/**
 * GpuChoresHost — shared pre-FX analysis on the renderer’s GPUDevice.
 *
 * Never calls requestAdapter / requestDevice. Requires a successful boot probe
 * (`window.webgpuProbe.ok`) before adopting GPU or CPU chore backends.
 */

import { downsample2d } from './downsample';
import { autoExposureFromHistogram } from './exposure';
import { lumaHistogramBt709 } from './histogram';
import { gpuComputeKillReason, isGpuComputeKillSwitchEnabled } from './killSwitch';
import { isWebGpuProbeOk, webGpuProbeFailureReason } from './probeGate';
import { buildLumaClassifyLut, lutU8Map } from './lut';
import { reduceF32FromHistogram, reduceF32Luma } from './reduce';
import {
  DOWNSAMPLE_WGSL,
  HISTOGRAM_WGSL,
  LUT_WGSL,
  REDUCE_WGSL,
} from './shaders';
import {
  createDefaultBreadcrumbs,
  GpuChoresAutoUniforms,
  GpuChoresBackend,
  GpuChoresBreadcrumbs,
  GpuChoresOp,
  HISTOGRAM_BINS,
  LUT_SIZE,
  NEUTRAL_AUTO_UNIFORMS,
  PREVIEW_SIZE,
} from './types';

const HIST_BYTES = HISTOGRAM_BINS * 4;
const REDUCE_BYTES = 16;
const CPU_CACHE_MAX = 128;
const GPU_PERIOD = 8;

export interface CpuSourceCache {
  rgba: Float32Array;
  width: number;
  height: number;
}

interface GpuResources {
  histBuf: GPUBuffer;
  histRead: [GPUBuffer, GPUBuffer];
  reduceBuf: GPUBuffer;
  reduceRead: [GPUBuffer, GPUBuffer];
  lutBuf: GPUBuffer;
  downsampleParams: GPUBuffer;
  reduceInitBuf: GPUBuffer;
  previewTex: GPUTexture;
  classifyTex: GPUTexture;
  histPipeline: GPUComputePipeline;
  reducePipeline: GPUComputePipeline;
  lutPipeline: GPUComputePipeline;
  downsamplePipeline: GPUComputePipeline;
  histLayout: GPUBindGroupLayout;
  reduceLayout: GPUBindGroupLayout;
  lutLayout: GPUBindGroupLayout;
  downsampleLayout: GPUBindGroupLayout;
}

function deviceCanCompile(device: GPUDevice): boolean {
  return (
    typeof device.createShaderModule === 'function' &&
    typeof device.createComputePipeline === 'function' &&
    typeof device.createBindGroupLayout === 'function' &&
    typeof device.createBuffer === 'function'
  );
}

export class GpuChoresHost {
  private device: GPUDevice | null = null;
  private gpu: GpuResources | null = null;
  private breadcrumbs: GpuChoresBreadcrumbs = createDefaultBreadcrumbs();
  private cpuSource: CpuSourceCache | null = null;
  private previewRgba: Float32Array | null = null;
  private classifyLut = buildLumaClassifyLut();
  private lastClassify: Uint8Array | null = null;
  private frameCounter = 0;
  private readSlot = 0;
  private mapPending = false;

  getBreadcrumbs(): GpuChoresBreadcrumbs {
    return { ...this.breadcrumbs, autoUniforms: { ...this.breadcrumbs.autoUniforms } };
  }

  getAutoUniforms(): GpuChoresAutoUniforms {
    return { ...this.breadcrumbs.autoUniforms };
  }

  getPreviewRgba(): Float32Array | null {
    return this.previewRgba;
  }

  getClassifyMap(): Uint8Array | null {
    return this.lastClassify;
  }

  /** Pooled preview texture (64×64). Bindable; not an effect target. */
  getPreviewTexture(): GPUTexture | null {
    return this.gpu?.previewTex ?? null;
  }

  /**
   * Adopt the renderer’s device. Must not request a second GPU device.
   */
  attach(device: GPUDevice | null, reasonIfMissing = 'no GPUDevice adopted'): void {
    this.releaseGpu();
    this.device = null;

    if (!isWebGpuProbeOk()) {
      this.setStatus(false, webGpuProbeFailureReason(), 'ts', null);
      return;
    }

    if (isGpuComputeKillSwitchEnabled()) {
      this.setStatus(false, gpuComputeKillReason(), 'ts', null);
      this.analyzeCpuCache();
      return;
    }

    if (!device) {
      this.setStatus(false, reasonIfMissing, 'ts', null);
      return;
    }

    if (!deviceCanCompile(device)) {
      this.setStatus(false, 'adopted device cannot compile compute', 'ts', null);
      this.device = device;
      return;
    }

    this.device = device;
    try {
      this.gpu = this.createGpu(device);
      this.setStatus(true, 'webgpu compute on adopted renderer device', 'webgpu', null);
    } catch (err) {
      this.gpu = null;
      const message = err instanceof Error ? err.message : String(err);
      this.setStatus(false, `webgpu chore pipeline failed: ${message}`, 'ts', null);
    }
  }

  detach(reason = 'detached'): void {
    this.releaseGpu();
    this.device = null;
    this.setStatus(false, reason, 'ts', this.breadcrumbs.lastOp);
  }

  destroy(): void {
    this.detach('destroyed');
    this.cpuSource = null;
    this.previewRgba = null;
    this.lastClassify = null;
  }

  /** Cache a CPU snapshot for TS fallback (image load / kill switch). */
  ingestRgba(rgba: ArrayLike<number>, width: number, height: number): void {
    if (!isWebGpuProbeOk() && !isGpuComputeKillSwitchEnabled()) return;
    this.cpuSource = shrinkCpuSource(rgba, width, height, CPU_CACHE_MAX);
    this.analyzeCpuCache();
  }

  ingestOffscreen(canvas: HTMLCanvasElement | null, ctx: CanvasRenderingContext2D | null): void {
    if (!canvas || !ctx) return;
    try {
      const image = ctx.getImageData(0, 0, canvas.width, canvas.height);
      const floats = new Float32Array(image.data.length);
      for (let i = 0; i < image.data.length; i++) floats[i] = image.data[i] / 255;
      this.ingestRgba(floats, canvas.width, canvas.height);
    } catch {
      // Offscreen may be tainted; GPU hist still runs when available.
    }
  }

  /**
   * Encode histogram / reduce / LUT / downsample on the pre-FX source.
   * Domain FX pipelines are not replaced.
   */
  encodePreFx(
    encoder: GPUCommandEncoder,
    source: GPUTexture,
    srcW: number,
    srcH: number,
  ): void {
    const gpu = this.gpu;
    const device = this.device;
    if (!gpu || !device || !this.breadcrumbs.gpuComputeAvailable) {
      if (isWebGpuProbeOk() && (isGpuComputeKillSwitchEnabled() || this.cpuSource)) {
        this.analyzeCpuCache();
      }
      return;
    }

    this.frameCounter += 1;
    if (this.frameCounter % GPU_PERIOD !== 1 && this.frameCounter !== 1) {
      this.encodeDownsampleAndLut(encoder, gpu, device, source, srcW, srcH);
      this.noteOp('downsample_2d', 'webgpu');
      return;
    }

    if (typeof encoder.clearBuffer === 'function') {
      encoder.clearBuffer(gpu.histBuf);
    }
    encoder.copyBufferToBuffer(gpu.reduceInitBuf, 0, gpu.reduceBuf, 0, REDUCE_BYTES);

    const histBg = device.createBindGroup({
      layout: gpu.histLayout,
      entries: [
        { binding: 0, resource: source.createView() },
        { binding: 1, resource: { buffer: gpu.histBuf } },
      ],
    });
    const histPass = encoder.beginComputePass({ label: 'gpu-chores-histogram' });
    histPass.setPipeline(gpu.histPipeline);
    histPass.setBindGroup(0, histBg);
    histPass.dispatchWorkgroups(Math.ceil(srcW / 8), Math.ceil(srcH / 8));
    histPass.end();

    const reduceBg = device.createBindGroup({
      layout: gpu.reduceLayout,
      entries: [
        { binding: 0, resource: source.createView() },
        { binding: 1, resource: { buffer: gpu.reduceBuf } },
      ],
    });
    const reducePass = encoder.beginComputePass({ label: 'gpu-chores-reduce' });
    reducePass.setPipeline(gpu.reducePipeline);
    reducePass.setBindGroup(0, reduceBg);
    reducePass.dispatchWorkgroups(Math.ceil((srcW * srcH) / 64));
    reducePass.end();

    this.encodeDownsampleAndLut(encoder, gpu, device, source, srcW, srcH);
    this.noteOp('luma_histogram_bt709', 'webgpu');
  }

  afterSubmit(): void {
    const gpu = this.gpu;
    const device = this.device;
    if (!gpu || !device || !this.breadcrumbs.gpuComputeAvailable || this.mapPending) return;
    if (this.frameCounter % GPU_PERIOD !== 1 && this.frameCounter !== 1) return;

    const slot = this.readSlot;
    const encoder = device.createCommandEncoder({ label: 'gpu-chores-readback' });
    encoder.copyBufferToBuffer(gpu.histBuf, 0, gpu.histRead[slot], 0, HIST_BYTES);
    encoder.copyBufferToBuffer(gpu.reduceBuf, 0, gpu.reduceRead[slot], 0, REDUCE_BYTES);
    device.queue.submit([encoder.finish()]);

    this.mapPending = true;
    const histRead = gpu.histRead[slot];
    const reduceRead = gpu.reduceRead[slot];
    Promise.all([
      histRead.mapAsync(GPUMapMode.READ),
      reduceRead.mapAsync(GPUMapMode.READ),
    ])
      .then(() => {
        const histCopy = new Uint32Array(histRead.getMappedRange().slice(0));
        const reduceCopy = new Uint32Array(reduceRead.getMappedRange().slice(0));
        histRead.unmap();
        reduceRead.unmap();
        this.applyGpuReadback(histCopy, reduceCopy);
        this.readSlot = 1 - slot;
        this.mapPending = false;
      })
      .catch((err) => {
        try {
          histRead.unmap();
          reduceRead.unmap();
        } catch {
          /* already unmapped */
        }
        this.mapPending = false;
        this.setStatus(
          false,
          `webgpu readback failed: ${err instanceof Error ? err.message : String(err)}`,
          'ts',
          this.breadcrumbs.lastOp,
        );
        this.analyzeCpuCache();
      });
  }

  private encodeDownsampleAndLut(
    encoder: GPUCommandEncoder,
    gpu: GpuResources,
    device: GPUDevice,
    source: GPUTexture,
    srcW: number,
    srcH: number,
  ): void {
    const gain = this.breadcrumbs.autoUniforms.exposureGain;
    const params = new Float32Array(8);
    const u32 = new Uint32Array(params.buffer);
    u32[0] = srcW;
    u32[1] = srcH;
    u32[2] = PREVIEW_SIZE;
    u32[3] = PREVIEW_SIZE;
    params[4] = gain;
    device.queue.writeBuffer(gpu.downsampleParams, 0, params);

    const dsBg = device.createBindGroup({
      layout: gpu.downsampleLayout,
      entries: [
        { binding: 0, resource: source.createView() },
        { binding: 1, resource: gpu.previewTex.createView() },
        { binding: 2, resource: { buffer: gpu.downsampleParams } },
      ],
    });
    const dsPass = encoder.beginComputePass({ label: 'gpu-chores-downsample' });
    dsPass.setPipeline(gpu.downsamplePipeline);
    dsPass.setBindGroup(0, dsBg);
    dsPass.dispatchWorkgroups(Math.ceil(PREVIEW_SIZE / 8), Math.ceil(PREVIEW_SIZE / 8));
    dsPass.end();

    const lutBg = device.createBindGroup({
      layout: gpu.lutLayout,
      entries: [
        { binding: 0, resource: source.createView() },
        { binding: 1, resource: gpu.classifyTex.createView() },
        { binding: 2, resource: { buffer: gpu.lutBuf } },
      ],
    });
    const lutPass = encoder.beginComputePass({ label: 'gpu-chores-lut' });
    lutPass.setPipeline(gpu.lutPipeline);
    lutPass.setBindGroup(0, lutBg);
    lutPass.dispatchWorkgroups(Math.ceil(PREVIEW_SIZE / 8), Math.ceil(PREVIEW_SIZE / 8));
    lutPass.end();
  }

  private applyGpuReadback(histBins: Uint32Array, reduceRaw: Uint32Array): void {
    const pixelCount = histBins.reduce((s, v) => s + v, 0);
    const hist = { bins: histBins, pixelCount };
    const exposure = autoExposureFromHistogram(hist);
    const fromHist = reduceF32FromHistogram(hist);
    const count = reduceRaw[3] || 0;
    const reduce = count > 0
      ? {
          min: reduceRaw[0] / 65535,
          max: reduceRaw[1] / 65535,
          mean: reduceRaw[2] / 65535 / count,
        }
      : fromHist;
    this.breadcrumbs.autoUniforms = {
      lumaMin: reduce.min,
      lumaMax: reduce.max,
      lumaMean: exposure.lumaMean,
      exposureGain: exposure.gain,
      exposureEv: exposure.ev,
    };
    this.noteOp('auto_exposure', 'webgpu');
    if (this.cpuSource) {
      this.previewRgba = downsample2d(
        this.cpuSource.rgba,
        this.cpuSource.width,
        this.cpuSource.height,
        PREVIEW_SIZE,
        PREVIEW_SIZE,
        exposure.gain,
      );
    }
  }

  private analyzeCpuCache(): void {
    const src = this.cpuSource;
    if (!src) {
      this.previewRgba = null;
      this.lastClassify = null;
      if (!this.breadcrumbs.gpuComputeAvailable) {
        this.breadcrumbs.autoUniforms = { ...NEUTRAL_AUTO_UNIFORMS };
      }
      return;
    }
    const hist = lumaHistogramBt709(src.rgba, src.width, src.height);
    const reduce = reduceF32Luma(src.rgba, src.width, src.height);
    const exposure = autoExposureFromHistogram(hist);
    this.lastClassify = lutU8Map(src.rgba, src.width, src.height, this.classifyLut);
    this.previewRgba = downsample2d(
      src.rgba,
      src.width,
      src.height,
      PREVIEW_SIZE,
      PREVIEW_SIZE,
      exposure.gain,
    );
    this.breadcrumbs.autoUniforms = {
      lumaMin: reduce.min,
      lumaMax: reduce.max,
      lumaMean: exposure.lumaMean,
      exposureGain: exposure.gain,
      exposureEv: exposure.ev,
    };
    const backend: GpuChoresBackend = this.breadcrumbs.gpuComputeAvailable ? 'webgpu' : 'ts';
    this.noteOp('auto_exposure', backend);
  }

  private createGpu(device: GPUDevice): GpuResources {
    const histModule = device.createShaderModule({ label: 'chores-hist', code: HISTOGRAM_WGSL });
    const reduceModule = device.createShaderModule({ label: 'chores-reduce', code: REDUCE_WGSL });
    const lutModule = device.createShaderModule({ label: 'chores-lut', code: LUT_WGSL });
    const dsModule = device.createShaderModule({ label: 'chores-downsample', code: DOWNSAMPLE_WGSL });

    const histLayout = device.createBindGroupLayout({
      entries: [
        { binding: 0, visibility: GPUShaderStage.COMPUTE, texture: { sampleType: 'unfilterable-float' } },
        { binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } },
      ],
    });
    const reduceLayout = device.createBindGroupLayout({
      entries: [
        { binding: 0, visibility: GPUShaderStage.COMPUTE, texture: { sampleType: 'unfilterable-float' } },
        { binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } },
      ],
    });
    const lutLayout = device.createBindGroupLayout({
      entries: [
        { binding: 0, visibility: GPUShaderStage.COMPUTE, texture: { sampleType: 'unfilterable-float' } },
        { binding: 1, visibility: GPUShaderStage.COMPUTE, storageTexture: { access: 'write-only', format: 'rgba8unorm' } },
        { binding: 2, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
      ],
    });
    const downsampleLayout = device.createBindGroupLayout({
      entries: [
        { binding: 0, visibility: GPUShaderStage.COMPUTE, texture: { sampleType: 'unfilterable-float' } },
        { binding: 1, visibility: GPUShaderStage.COMPUTE, storageTexture: { access: 'write-only', format: 'rgba16float' } },
        { binding: 2, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'uniform' } },
      ],
    });

    const histPipeline = device.createComputePipeline({
      layout: device.createPipelineLayout({ bindGroupLayouts: [histLayout] }),
      compute: { module: histModule, entryPoint: 'main' },
    });
    const reducePipeline = device.createComputePipeline({
      layout: device.createPipelineLayout({ bindGroupLayouts: [reduceLayout] }),
      compute: { module: reduceModule, entryPoint: 'main' },
    });
    const lutPipeline = device.createComputePipeline({
      layout: device.createPipelineLayout({ bindGroupLayouts: [lutLayout] }),
      compute: { module: lutModule, entryPoint: 'main' },
    });
    const downsamplePipeline = device.createComputePipeline({
      layout: device.createPipelineLayout({ bindGroupLayouts: [downsampleLayout] }),
      compute: { module: dsModule, entryPoint: 'main' },
    });

    const storage = GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST;
    const mapRead = GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST;
    const histBuf = device.createBuffer({ label: 'chores-hist', size: HIST_BYTES, usage: storage });
    const histRead: [GPUBuffer, GPUBuffer] = [
      device.createBuffer({ label: 'chores-hist-read-0', size: HIST_BYTES, usage: mapRead }),
      device.createBuffer({ label: 'chores-hist-read-1', size: HIST_BYTES, usage: mapRead }),
    ];
    const reduceBuf = device.createBuffer({ label: 'chores-reduce', size: REDUCE_BYTES, usage: storage });
    const reduceRead: [GPUBuffer, GPUBuffer] = [
      device.createBuffer({ label: 'chores-reduce-read-0', size: REDUCE_BYTES, usage: mapRead }),
      device.createBuffer({ label: 'chores-reduce-read-1', size: REDUCE_BYTES, usage: mapRead }),
    ];
    const lutU32 = new Uint32Array(LUT_SIZE);
    for (let i = 0; i < LUT_SIZE; i++) lutU32[i] = this.classifyLut[i];
    const lutBuf = device.createBuffer({
      label: 'chores-lut',
      size: LUT_SIZE * 4,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    });
    device.queue.writeBuffer(lutBuf, 0, lutU32);
    const downsampleParams = device.createBuffer({
      label: 'chores-downsample-params',
      size: 32,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });
    const reduceInitBuf = device.createBuffer({
      label: 'chores-reduce-init',
      size: REDUCE_BYTES,
      usage: GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST,
    });
    device.queue.writeBuffer(reduceInitBuf, 0, new Uint32Array([0xffffffff, 0, 0, 0]));

    const previewTex = device.createTexture({
      label: 'chores-preview',
      size: [PREVIEW_SIZE, PREVIEW_SIZE],
      format: 'rgba16float',
      usage: GPUTextureUsage.STORAGE_BINDING | GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_SRC,
    });
    const classifyTex = device.createTexture({
      label: 'chores-classify',
      size: [PREVIEW_SIZE, PREVIEW_SIZE],
      format: 'rgba8unorm',
      usage: GPUTextureUsage.STORAGE_BINDING | GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_SRC,
    });

    return {
      histBuf,
      histRead,
      reduceBuf,
      reduceRead,
      lutBuf,
      downsampleParams,
      reduceInitBuf,
      previewTex,
      classifyTex,
      histPipeline,
      reducePipeline,
      lutPipeline,
      downsamplePipeline,
      histLayout,
      reduceLayout,
      lutLayout,
      downsampleLayout,
    };
  }

  private releaseGpu(): void {
    const gpu = this.gpu;
    this.gpu = null;
    this.mapPending = false;
    if (!gpu) return;
    gpu.histBuf.destroy();
    gpu.histRead[0].destroy();
    gpu.histRead[1].destroy();
    gpu.reduceBuf.destroy();
    gpu.reduceRead[0].destroy();
    gpu.reduceRead[1].destroy();
    gpu.lutBuf.destroy();
    gpu.downsampleParams.destroy();
    gpu.reduceInitBuf.destroy();
    gpu.previewTex.destroy();
    gpu.classifyTex.destroy();
  }

  private setStatus(
    available: boolean,
    reason: string,
    backend: GpuChoresBackend,
    lastOp: GpuChoresOp | null,
  ): void {
    this.breadcrumbs.gpuComputeAvailable = available;
    this.breadcrumbs.reason = reason;
    this.breadcrumbs.backend = backend;
    this.breadcrumbs.lastOp = lastOp;
  }

  private noteOp(op: GpuChoresOp, backend: GpuChoresBackend): void {
    this.breadcrumbs.lastOp = op;
    this.breadcrumbs.backend = backend;
  }
}

export function shrinkCpuSource(
  rgba: ArrayLike<number>,
  width: number,
  height: number,
  maxDim: number,
): CpuSourceCache {
  const pixelCount = Math.max(0, width * height);
  if (width <= maxDim && height <= maxDim) {
    const copy = new Float32Array(pixelCount * 4);
    for (let i = 0; i < copy.length; i++) copy[i] = rgba[i] ?? 0;
    return { rgba: copy, width, height };
  }
  const scale = maxDim / Math.max(width, height);
  const w = Math.max(1, Math.round(width * scale));
  const h = Math.max(1, Math.round(height * scale));
  return { rgba: downsample2d(rgba, width, height, w, h, 1), width: w, height: h };
}
