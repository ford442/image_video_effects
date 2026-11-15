/**
 * outputs.ts — stage outputs: one program, many canvases, one GPUDevice.
 *
 * The frame plan renders the program texture once (`blitReadTex`, the texture
 * the main canvas blit reads). Each attached output — a stage window's canvas,
 * transferred to whichever thread owns the device — gets its own
 * GPUCanvasContext configured on that same device and one small render pass
 * in the frame's single encoder (public/shaders/_output/corner_pin.wgsl):
 * corner pin, per-output colour and calibration test patterns. No second
 * device, no readback.
 *
 * Pacing: every output presents with the frame the main canvas presents. A
 * stage on a display with a different refresh rate still gets one new picture
 * per renderer frame (see docs/STAGE_OUTPUTS.md).
 */

import cornerPinWgsl from '../../../public/shaders/_output/corner_pin.wgsl?raw';
import {
  OUTPUT_UNIFORM_BYTES,
  OUTPUT_UNIFORM_FLOATS,
  outputInverse,
  packOutputUniform,
  sanitizeOutputConfig,
  type OutputConfig,
} from '../../output/outputConfig';

/** What a stage hands the renderer: a canvas whose control it no longer has. */
export interface OutputCanvas {
  width: number;
  height: number;
  getContext(contextId: 'webgpu'): GPUCanvasContext | null;
}

export interface OutputStatus {
  id: string;
  width: number;
  height: number;
  format: GPUTextureFormat;
  framesPresented: number;
  /** The corner pin could not be inverted (degenerate quad): the identity is shown. */
  singular: boolean;
  lastError?: string;
}

export interface AttachOutputResult {
  ok: boolean;
  format?: GPUTextureFormat;
  error?: string;
}

/** Hard cap: a show is a handful of projectors, not dozens of contexts. */
export const MAX_OUTPUTS = 8;
const MAX_OUTPUT_DIM = 8192;

interface OutputEntry {
  id: string;
  canvas: OutputCanvas;
  context: GPUCanvasContext;
  format: GPUTextureFormat;
  config: OutputConfig;
  uniform: GPUBuffer;
  uniformData: Float32Array<ArrayBuffer>;
  dirty: boolean;
  bindGroup: GPUBindGroup | null;
  bindGroupTex: GPUTexture | null;
  lastGenerative: boolean | null;
  framesPresented: number;
  singular: boolean;
  lastError?: string;
}

const clampDim = (v: number) => Math.max(1, Math.min(MAX_OUTPUT_DIM, Math.round(Number.isFinite(v) ? v : 1)));

export class OutputPresenter {
  private readonly outputs = new Map<string, OutputEntry>();
  private device: GPUDevice | null = null;
  private layout: GPUBindGroupLayout | null = null;
  private module: GPUShaderModule | null = null;
  private readonly pipelines = new Map<GPUTextureFormat, GPURenderPipeline>();

  get count(): number {
    return this.outputs.size;
  }

  has(id: string): boolean {
    return this.outputs.has(id);
  }

  /**
   * Configure `canvas` on `device` and start presenting the program to it. An
   * existing output with the same id is replaced (a stage re-sends a fresh canvas
   * after a backend switch or device-loss recovery).
   */
  attach(
    device: GPUDevice,
    id: string,
    canvas: OutputCanvas,
    size: { width: number; height: number },
    config: unknown,
    format: GPUTextureFormat,
  ): AttachOutputResult {
    if (!this.outputs.has(id) && this.outputs.size >= MAX_OUTPUTS) {
      return { ok: false, error: `at most ${MAX_OUTPUTS} outputs` };
    }
    this.bindDevice(device);
    // The replaced output goes first: a re-sent canvas may share its context.
    this.detach(id);
    let context: GPUCanvasContext | null = null;
    try {
      context = canvas.getContext('webgpu');
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : String(e) };
    }
    if (!context) return { ok: false, error: 'output canvas has no webgpu context' };
    canvas.width = clampDim(size.width);
    canvas.height = clampDim(size.height);
    try {
      // A stage is SDR sRGB (projectors, LED processors); the operator's HDR / P3
      // negotiation stays on the main canvas.
      context.configure({ device, format, alphaMode: 'opaque', usage: GPUTextureUsage.RENDER_ATTACHMENT });
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : String(e) };
    }
    const uniform = device.createBuffer({
      label: `output:${id}`,
      size: OUTPUT_UNIFORM_BYTES,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });
    this.outputs.set(id, {
      id,
      canvas,
      context,
      format,
      config: sanitizeOutputConfig(config),
      uniform,
      uniformData: new Float32Array(OUTPUT_UNIFORM_FLOATS),
      dirty: true,
      bindGroup: null,
      bindGroupTex: null,
      lastGenerative: null,
      framesPresented: 0,
      singular: false,
    });
    return { ok: true, format };
  }

  detach(id: string): void {
    const entry = this.outputs.get(id);
    if (!entry) return;
    this.outputs.delete(id);
    try {
      entry.context.unconfigure();
    } catch {
      /* a canvas whose window closed may already be gone */
    }
    entry.uniform.destroy?.();
  }

  setConfig(id: string, config: unknown): void {
    const entry = this.outputs.get(id);
    if (!entry) return;
    entry.config = sanitizeOutputConfig(config);
    entry.dirty = true;
  }

  setSize(id: string, width: number, height: number): void {
    const entry = this.outputs.get(id);
    if (!entry) return;
    const w = clampDim(width);
    const h = clampDim(height);
    if (entry.canvas.width === w && entry.canvas.height === h) return;
    entry.canvas.width = w;
    entry.canvas.height = h;
    entry.dirty = true;
  }

  /**
   * One render pass per output, reading `programTex` (the frame's final picture).
   * Called inside the frame's encoder, after the main present.
   */
  encode(encoder: GPUCommandEncoder, programTex: GPUTexture, generative: boolean): void {
    const device = this.device;
    if (!device || this.outputs.size === 0) return;
    for (const entry of this.outputs.values()) {
      let target: GPUTexture;
      try {
        target = entry.context.getCurrentTexture();
      } catch (e) {
        entry.lastError = e instanceof Error ? e.message : String(e);
        continue;
      }
      const pipeline = this.pipelineFor(device, entry.format);
      if (!pipeline || !this.layout) continue;
      if (entry.dirty || entry.lastGenerative !== generative) {
        packOutputUniform(entry.config, {
          generative,
          width: entry.canvas.width,
          height: entry.canvas.height,
        }, entry.uniformData);
        entry.singular = !outputInverse(entry.config).valid;
        device.queue.writeBuffer(entry.uniform, 0, entry.uniformData);
        entry.dirty = false;
        entry.lastGenerative = generative;
      }
      if (!entry.bindGroup || entry.bindGroupTex !== programTex) {
        entry.bindGroup = device.createBindGroup({
          label: `outputBG:${entry.id}`,
          layout: this.layout,
          entries: [
            { binding: 0, resource: programTex.createView() },
            { binding: 1, resource: { buffer: entry.uniform } },
          ],
        });
        entry.bindGroupTex = programTex;
      }
      const pass = encoder.beginRenderPass({
        label: `output:${entry.id}`,
        colorAttachments: [{
          view: target.createView(),
          loadOp: 'clear',
          storeOp: 'store',
          clearValue: { r: 0, g: 0, b: 0, a: 1 },
        }],
      });
      pass.setPipeline(pipeline);
      pass.setBindGroup(0, entry.bindGroup);
      pass.draw(3);
      pass.end();
      entry.framesPresented++;
      delete entry.lastError;
    }
  }

  status(): OutputStatus[] {
    return [...this.outputs.values()].map((e) => ({
      id: e.id,
      width: e.canvas.width,
      height: e.canvas.height,
      format: e.format,
      framesPresented: e.framesPresented,
      singular: e.singular,
      ...(e.lastError ? { lastError: e.lastError } : {}),
    }));
  }

  /** Unconfigure every output (renderer teardown). The stages re-attach to the next backend. */
  releaseAll(): void {
    for (const id of [...this.outputs.keys()]) this.detach(id);
    this.pipelines.clear();
    this.layout = null;
    this.module = null;
    this.device = null;
  }

  private bindDevice(device: GPUDevice): void {
    if (this.device === device) return;
    // A different device: everything built for the old one is useless.
    for (const id of [...this.outputs.keys()]) this.detach(id);
    this.pipelines.clear();
    this.device = device;
    this.layout = device.createBindGroupLayout({
      label: 'outputBGL',
      entries: [
        { binding: 0, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: 'unfilterable-float' } },
        { binding: 1, visibility: GPUShaderStage.FRAGMENT, buffer: { type: 'uniform', minBindingSize: OUTPUT_UNIFORM_BYTES } },
      ],
    });
    this.module = device.createShaderModule({ label: 'outputCornerPin', code: cornerPinWgsl });
  }

  private pipelineFor(device: GPUDevice, format: GPUTextureFormat): GPURenderPipeline | null {
    const cached = this.pipelines.get(format);
    if (cached) return cached;
    if (!this.layout || !this.module) return null;
    const pipeline = device.createRenderPipeline({
      label: `outputPipeline:${format}`,
      layout: device.createPipelineLayout({ bindGroupLayouts: [this.layout] }),
      vertex: { module: this.module, entryPoint: 'vs' },
      fragment: { module: this.module, entryPoint: 'fs', targets: [{ format }] },
      primitive: { topology: 'triangle-list' },
    });
    this.pipelines.set(format, pipeline);
    return pipeline;
  }
}
