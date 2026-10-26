/**
 * presentVariants.ts
 *
 * The two present paths besides the standard render-pass blit (#1512 Part A):
 *
 * - **HDR present.** When extended tone mapping is negotiated the canvas is an
 *   rgba16float display-p3 swapchain (canvas_configure.json optIn.hdrCanvas). The
 *   blit is re-specialised to that format, drops the 1.0 clamp, and takes a
 *   `PresentParams` uniform at group 1: paper white and peak, both relative to the
 *   SDR reference white (1.0 on an extended canvas).
 * - **Storage present.** With bgra8unorm-storage and a bgra8unorm canvas the present
 *   is one compute pass that writes the swapchain texture directly (optIn.storagePresent);
 *   the render pass is skipped.
 *
 * A running cue crossfade always presents through the SDR mix (presentHold.ts).
 */

import canvasConfigureContract from '../../contracts/canvas_configure.json';
import {
  GENERATIVE_STORAGE_PRESENT_WGSL,
  HDR_BLIT_WGSL,
  HDR_GENERATIVE_BLIT_WGSL,
  STORAGE_PRESENT_WGSL,
} from '../ShaderTemplates';

const PRESENT_DEFAULTS = canvasConfigureContract.optIn.hdrCanvas.presentParams;
const STORAGE_WORKGROUP = 8;

export interface HdrPresentSettings {
  /** Nits of scene white (1.0 in the working texture). */
  paperWhiteNits: number;
  /** Nits the brightest highlight rolls off towards. */
  peakNits: number;
}

export const DEFAULT_HDR_PRESENT: Readonly<HdrPresentSettings> = Object.freeze({
  paperWhiteNits: PRESENT_DEFAULTS.defaultPaperWhiteNits,
  peakNits: PRESENT_DEFAULTS.defaultPeakNits,
});

/** Clamp to a sane range: paper white 80–1000 nits, peak at least paper white, at most 10 000. */
export function normalizeHdrPresent(settings: Partial<HdrPresentSettings> = {}): HdrPresentSettings {
  const num = (v: unknown, fallback: number) => (typeof v === 'number' && Number.isFinite(v) ? v : fallback);
  const paperWhiteNits = Math.min(1000, Math.max(80, num(settings.paperWhiteNits, DEFAULT_HDR_PRESENT.paperWhiteNits)));
  const peakNits = Math.min(10000, Math.max(paperWhiteNits, num(settings.peakNits, DEFAULT_HDR_PRESENT.peakNits)));
  return { paperWhiteNits, peakNits };
}

/** `PresentParams` (ShaderTemplates HDR blit): [paperWhite, peak, pad, pad], relative to SDR white. */
export function hdrPresentUniform(settings: HdrPresentSettings): Float32Array<ArrayBuffer> {
  const ref = PRESENT_DEFAULTS.sdrReferenceNits;
  return new Float32Array([settings.paperWhiteNits / ref, settings.peakNits / ref, 0, 0]);
}

/** CPU twin of the WGSL `hdrShoulder` (tests): identity to 1.0, exponential roll-off to `peak`. */
export function hdrShoulder(x: number, peak: number): number {
  const h = Math.max(peak - 1, 0);
  if (h <= 0) return Math.min(x, 1);
  return x <= 1 ? x : 1 + h * (1 - Math.exp(-(x - 1) / h));
}

/** What `encodePresent` uses instead of the standard blit (null = the standard blit). */
export type PresentVariant =
  | {
      kind: 'hdr';
      standard: GPURenderPipeline;
      generative: GPURenderPipeline;
      /** Group 1: the PresentParams uniform. */
      bindGroup: GPUBindGroup;
    }
  | {
      kind: 'storage';
      /** One compute pass from `src` into the swapchain `target`; false = use the render pass. */
      encode(
        encoder: GPUCommandEncoder,
        src: GPUTexture,
        target: GPUTexture,
        generative: boolean,
        timestampWrites?: GPUComputePassTimestampWrites,
      ): boolean;
    };

/** HDR present pipelines and their uniform, per device and canvas format. */
export class HdrPresent {
  private device: GPUDevice | null = null;
  private format: GPUTextureFormat | null = null;
  private blitLayout: GPUBindGroupLayout | null = null;
  private variant: Extract<PresentVariant, { kind: 'hdr' }> | null = null;
  private buffer: GPUBuffer | null = null;
  private settings: HdrPresentSettings = { ...DEFAULT_HDR_PRESENT };

  setSettings(settings: Partial<HdrPresentSettings>): HdrPresentSettings {
    this.settings = normalizeHdrPresent({ ...this.settings, ...settings });
    if (this.device && this.buffer) this.device.queue.writeBuffer(this.buffer, 0, hdrPresentUniform(this.settings));
    return { ...this.settings };
  }

  getSettings(): HdrPresentSettings {
    return { ...this.settings };
  }

  /** The HDR variant for this swapchain format (built once per device / format / blit layout). */
  get(device: GPUDevice, blitLayout: GPUBindGroupLayout, format: GPUTextureFormat): PresentVariant | null {
    if (this.variant && this.device === device && this.format === format && this.blitLayout === blitLayout) {
      return this.variant;
    }
    this.release();
    try {
      const paramsLayout = device.createBindGroupLayout({
        label: 'hdrPresentBGL',
        entries: [{ binding: 0, visibility: GPUShaderStage.FRAGMENT, buffer: { type: 'uniform' } }],
      });
      const layout = device.createPipelineLayout({ bindGroupLayouts: [blitLayout, paramsLayout] });
      const pipeline = (label: string, code: string) => {
        const module = device.createShaderModule({ label, code });
        return device.createRenderPipeline({
          label: `${label}-${format}`,
          layout,
          vertex: { module, entryPoint: 'vs' },
          fragment: { module, entryPoint: 'fs', targets: [{ format }] },
          primitive: { topology: 'triangle-list' },
        });
      };
      const buffer = device.createBuffer({
        label: 'hdrPresentParams',
        size: 16,
        usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
      });
      device.queue.writeBuffer(buffer, 0, hdrPresentUniform(this.settings));
      this.variant = {
        kind: 'hdr',
        standard: pipeline('hdrBlit', HDR_BLIT_WGSL),
        generative: pipeline('hdrGenerativeBlit', HDR_GENERATIVE_BLIT_WGSL),
        bindGroup: device.createBindGroup({
          label: 'hdrPresentBG',
          layout: paramsLayout,
          entries: [{ binding: 0, resource: { buffer } }],
        }),
      };
      this.buffer = buffer;
      this.device = device;
      this.format = format;
      this.blitLayout = blitLayout;
      return this.variant;
    } catch (e) {
      console.warn('[WebGPU] HDR present unavailable; presenting SDR:', e);
      this.release();
      return null;
    }
  }

  release(): void {
    this.buffer?.destroy();
    this.buffer = null;
    this.variant = null;
    this.device = null;
    this.format = null;
    this.blitLayout = null;
  }
}

/** The compute present into a bgra8unorm swapchain (needs the bgra8unorm-storage feature). */
export class StoragePresent {
  private device: GPUDevice | null = null;
  private layout: GPUBindGroupLayout | null = null;
  private pipelines: { standard: GPUComputePipeline; generative: GPUComputePipeline } | null = null;
  /** Present passes encoded since the device was adopted (diagnostics / tests). */
  presents = 0;

  constructor(private readonly deviceProvider: () => GPUDevice | null) {}

  readonly variant: PresentVariant = {
    kind: 'storage',
    encode: (encoder, src, target, generative, timestampWrites) =>
      this.encode(encoder, src, target, generative, timestampWrites),
  };

  private encode(
    encoder: GPUCommandEncoder,
    src: GPUTexture,
    target: GPUTexture,
    generative: boolean,
    timestampWrites?: GPUComputePassTimestampWrites,
  ): boolean {
    const device = this.deviceProvider();
    if (!device || target.format !== 'bgra8unorm') return false;
    const pipelines = this.ensure(device);
    if (!pipelines || !this.layout) return false;
    // The swapchain texture is new every frame: so is its bind group (as the blit's view is).
    const bindGroup = device.createBindGroup({
      label: 'storagePresentBG',
      layout: this.layout,
      entries: [
        { binding: 0, resource: src.createView() },
        { binding: 1, resource: target.createView() },
      ],
    });
    const pass = encoder.beginComputePass(
      timestampWrites ? { label: 'present', timestampWrites } : { label: 'present' },
    );
    pass.setPipeline(generative ? pipelines.generative : pipelines.standard);
    pass.setBindGroup(0, bindGroup);
    pass.dispatchWorkgroups(Math.ceil(target.width / STORAGE_WORKGROUP), Math.ceil(target.height / STORAGE_WORKGROUP), 1);
    pass.end();
    this.presents++;
    return true;
  }

  private ensure(device: GPUDevice): { standard: GPUComputePipeline; generative: GPUComputePipeline } | null {
    if (this.pipelines && this.device === device) return this.pipelines;
    this.release();
    try {
      const layout = device.createBindGroupLayout({
        label: 'storagePresentBGL',
        entries: [
          { binding: 0, visibility: GPUShaderStage.COMPUTE, texture: { sampleType: 'unfilterable-float' } },
          { binding: 1, visibility: GPUShaderStage.COMPUTE, storageTexture: { access: 'write-only', format: 'bgra8unorm' } },
        ],
      });
      const pipelineLayout = device.createPipelineLayout({ bindGroupLayouts: [layout] });
      const pipeline = (label: string, code: string) => device.createComputePipeline({
        label,
        layout: pipelineLayout,
        compute: { module: device.createShaderModule({ label, code }), entryPoint: 'main' },
      });
      this.pipelines = {
        standard: pipeline('storagePresent', STORAGE_PRESENT_WGSL),
        generative: pipeline('storagePresentGenerative', GENERATIVE_STORAGE_PRESENT_WGSL),
      };
      this.layout = layout;
      this.device = device;
      return this.pipelines;
    } catch (e) {
      console.warn('[WebGPU] storage present unavailable; using the render pass:', e);
      this.release();
      return null;
    }
  }

  release(): void {
    this.pipelines = null;
    this.layout = null;
    this.device = null;
    this.presents = 0;
  }
}
