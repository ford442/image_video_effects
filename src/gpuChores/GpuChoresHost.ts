/**
 * GpuChoresHost — shared pre-FX analysis on the renderer’s GPUDevice.
 *
 * Never calls requestAdapter / requestDevice. Requires a successful boot probe
 * (`window.webgpuProbe.ok`) before adopting GPU or CPU chore backends.
 */

import type { InternalColorFormat } from '../config/formatPolicy';
import { rewriteWgslStorageFormats } from '../renderer/wgslFormatRewrite';
import { downsample2d } from './downsample';
import { autoExposureFromHistogram, clampExposureGain } from './exposure';
import { lumaHistogramBt709 } from './histogram';
import { gpuComputeKillReason, isGpuComputeKillSwitchEnabled } from './killSwitch';
import { isWebGpuProbeOk, webGpuProbeFailureReason } from './probeGate';
import { buildLumaClassifyLut, lutU8Map, unpackClassifyRgba8 } from './lut';
import { rgbaFloatsToPngBase64 } from './pngEncode';
import { reduceF32FromHistogram, reduceF32Luma } from './reduce';
import {
  APPLY_GAIN_WGSL,
  DOWNSAMPLE_WGSL,
  HISTOGRAM_WGSL,
  LUT_WGSL,
  REDUCE_WGSL,
} from './shaders';
import { shouldEncodeSourceGain, sourceGainStatus } from './sourceNormalize';
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
  SourceGainStatus,
} from './types';

const HIST_BYTES = HISTOGRAM_BINS * 4;
const REDUCE_BYTES = 16;
const CPU_CACHE_MAX = 128;
const GPU_PERIOD = 8;
const CLASSIFY_BYTES_PER_PIXEL = 4;
const CLASSIFY_BYTES_PER_ROW = Math.ceil((PREVIEW_SIZE * CLASSIFY_BYTES_PER_PIXEL) / 256) * 256;
const CLASSIFY_READ_BYTES = CLASSIFY_BYTES_PER_ROW * PREVIEW_SIZE;

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
  classifyRead: [GPUBuffer, GPUBuffer];
  lutBuf: GPUBuffer;
  downsampleParams: GPUBuffer;
  gainParams: GPUBuffer;
  reduceInitBuf: GPUBuffer;
  previewTex: GPUTexture;
  classifyTex: GPUTexture;
  histPipeline: GPUComputePipeline;
  reducePipeline: GPUComputePipeline;
  lutPipeline: GPUComputePipeline;
  downsamplePipeline: GPUComputePipeline;
  gainPipeline: GPUComputePipeline;
  histLayout: GPUBindGroupLayout;
  reduceLayout: GPUBindGroupLayout;
  lutLayout: GPUBindGroupLayout;
  downsampleLayout: GPUBindGroupLayout;
  gainLayout: GPUBindGroupLayout;
  colorFormat: InternalColorFormat;
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
  private classifyWidth = 0;
  private classifyHeight = 0;
  private frameCounter = 0;
  private readSlot = 0;
  private mapPending = false;
  private sourceNormalizeEnabled = false;
  private physicsPinned = false;
  private colorFormat: InternalColorFormat = 'rgba32float';

  getBreadcrumbs(): GpuChoresBreadcrumbs {
    return {
      ...this.breadcrumbs,
      autoUniforms: { ...this.breadcrumbs.autoUniforms },
      sourceGain: this.currentSourceGainStatus(),
      classifyPreview: this.lastClassify
        ? {
            width: this.classifyWidth,
            height: this.classifyHeight,
            bands: Array.from(this.lastClassify),
          }
        : null,
    };
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

  getClassifySize(): { width: number; height: number } {
    return { width: this.classifyWidth, height: this.classifyHeight };
  }

  /** Pooled preview texture (64×64). Bindable; not an effect target. */
  getPreviewTexture(): GPUTexture | null {
    return this.gpu?.previewTex ?? null;
  }

  getClassifyTexture(): GPUTexture | null {
    return this.gpu?.classifyTex ?? null;
  }

  setSourceNormalizeEnabled(enabled: boolean): void {
    this.sourceNormalizeEnabled = enabled;
    this.breadcrumbs.sourceGain = this.currentSourceGainStatus();
  }

  isSourceNormalizeEnabled(): boolean {
    return this.sourceNormalizeEnabled;
  }

  setPhysicsPinned(pinned: boolean): void {
    this.physicsPinned = pinned;
    this.breadcrumbs.sourceGain = this.currentSourceGainStatus();
  }

  setColorFormat(format: InternalColorFormat): void {
    if (this.colorFormat === format) return;
    this.colorFormat = format;
    if (this.device && this.gpu && this.breadcrumbs.gpuComputeAvailable) {
      try {
        this.rebuildGainPipeline(this.device, this.gpu, format);
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        this.setStatus(false, `webgpu gain pipeline failed: ${message}`, 'ts', this.breadcrumbs.lastOp);
      }
    }
  }

  /**
   * Adopt the renderer’s device. Must not request a second GPU device.
   */
  attach(
    device: GPUDevice | null,
    reasonIfMissing = 'no GPUDevice adopted',
    colorFormat: InternalColorFormat = 'rgba32float',
  ): void {
    this.releaseGpu();
    this.device = null;
    this.colorFormat = colorFormat;

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
      this.gpu = this.createGpu(device, colorFormat);
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
    this.classifyWidth = 0;
    this.classifyHeight = 0;
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
   * Optional apply_gain_2d writes dest then copies back onto source (readTex).
   */
  encodePreFx(
    encoder: GPUCommandEncoder,
    source: GPUTexture,
    srcW: number,
    srcH: number,
    dest?: GPUTexture | null,
  ): void {
    const gpu = this.gpu;
    const device = this.device;
    if (!gpu || !device || !this.breadcrumbs.gpuComputeAvailable) {
      if (isWebGpuProbeOk() && (isGpuComputeKillSwitchEnabled() || this.cpuSource)) {
        this.analyzeCpuCache();
      }
      this.breadcrumbs.sourceGain = this.currentSourceGainStatus();
      return;
    }

    this.frameCounter += 1;
    if (this.frameCounter % GPU_PERIOD !== 1 && this.frameCounter !== 1) {
      this.encodeDownsampleAndLut(encoder, gpu, device, source, srcW, srcH);
      this.encodeSourceGain(encoder, gpu, device, source, dest ?? null, srcW, srcH);
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
    this.encodeSourceGain(encoder, gpu, device, source, dest ?? null, srcW, srcH);
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
    encoder.copyTextureToBuffer(
      { texture: gpu.classifyTex },
      { buffer: gpu.classifyRead[slot], bytesPerRow: CLASSIFY_BYTES_PER_ROW, rowsPerImage: PREVIEW_SIZE },
      [PREVIEW_SIZE, PREVIEW_SIZE, 1],
    );
    device.queue.submit([encoder.finish()]);

    this.mapPending = true;
    const histRead = gpu.histRead[slot];
    const reduceRead = gpu.reduceRead[slot];
    const classifyRead = gpu.classifyRead[slot];
    Promise.all([
      histRead.mapAsync(GPUMapMode.READ),
      reduceRead.mapAsync(GPUMapMode.READ),
      classifyRead.mapAsync(GPUMapMode.READ),
    ])
      .then(() => {
        const histCopy = new Uint32Array(histRead.getMappedRange().slice(0));
        const reduceCopy = new Uint32Array(reduceRead.getMappedRange().slice(0));
        const classifyPacked = new Uint8Array(classifyRead.getMappedRange().slice(0));
        histRead.unmap();
        reduceRead.unmap();
        classifyRead.unmap();
        this.applyGpuReadback(histCopy, reduceCopy, classifyPacked);
        this.readSlot = 1 - slot;
        this.mapPending = false;
      })
      .catch((err) => {
        try {
          histRead.unmap();
          reduceRead.unmap();
          classifyRead.unmap();
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

  /**
   * One-shot downsample of a presented texture for thumbnail capture.
   * Returns PNG base64 without the data-URL prefix, or null if chores are idle.
   */
  async captureDownsampledPng(
    source: GPUTexture,
    srcW: number,
    srcH: number,
    destSize: number,
  ): Promise<string | null> {
    const gpu = this.gpu;
    const device = this.device;
    if (!gpu || !device || !this.breadcrumbs.gpuComputeAvailable) return null;
    const size = Math.max(1, Math.floor(destSize));
    const dest = device.createTexture({
      label: 'chores-thumb-ds',
      size: [size, size],
      format: 'rgba16float',
      usage: GPUTextureUsage.STORAGE_BINDING | GPUTextureUsage.COPY_SRC,
    });
    const bytesPerPixel = 8;
    const bytesPerRow = Math.ceil((size * bytesPerPixel) / 256) * 256;
    const readBuf = device.createBuffer({
      label: 'chores-thumb-read',
      size: bytesPerRow * size,
      usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ,
    });
    try {
      const encoder = device.createCommandEncoder({ label: 'gpu-chores-thumb-ds' });
      this.encodeDownsampleTo(encoder, gpu, device, source, srcW, srcH, dest, size, size, 1);
      encoder.copyTextureToBuffer(
        { texture: dest },
        { buffer: readBuf, bytesPerRow, rowsPerImage: size },
        [size, size, 1],
      );
      device.queue.submit([encoder.finish()]);
      await readBuf.mapAsync(GPUMapMode.READ);
      const packed = new Uint8Array(readBuf.getMappedRange().slice(0));
      readBuf.unmap();
      const floats = rgba16BufferToRgba32(packed, size, size, bytesPerRow);
      this.noteOp('downsample_2d', 'webgpu');
      return rgbaFloatsToPngBase64(floats, size, size);
    } catch {
      return null;
    } finally {
      dest.destroy();
      readBuf.destroy();
    }
  }

  encodeSourceGainForTest(
    encoder: GPUCommandEncoder,
    source: GPUTexture,
    dest: GPUTexture,
    srcW: number,
    srcH: number,
  ): boolean {
    const gpu = this.gpu;
    const device = this.device;
    if (!gpu || !device) return false;
    return this.encodeSourceGain(encoder, gpu, device, source, dest, srcW, srcH);
  }

  private encodeSourceGain(
    encoder: GPUCommandEncoder,
    gpu: GpuResources,
    device: GPUDevice,
    source: GPUTexture,
    dest: GPUTexture | null,
    srcW: number,
    srcH: number,
  ): boolean {
    const kill = isGpuComputeKillSwitchEnabled();
    const gate = {
      toggleOn: this.sourceNormalizeEnabled,
      gpuComputeAvailable: this.breadcrumbs.gpuComputeAvailable,
      physicsPinned: this.physicsPinned,
      killSwitch: kill,
    };
    this.breadcrumbs.sourceGain = sourceGainStatus(gate);
    if (!dest || !shouldEncodeSourceGain(gate)) return false;

    const gain = clampExposureGain(this.breadcrumbs.autoUniforms.exposureGain);
    const params = new Float32Array([gain, 0, 0, 0]);
    device.queue.writeBuffer(gpu.gainParams, 0, params);

    const bg = device.createBindGroup({
      layout: gpu.gainLayout,
      entries: [
        { binding: 0, resource: source.createView() },
        { binding: 1, resource: dest.createView() },
        { binding: 2, resource: { buffer: gpu.gainParams } },
      ],
    });
    const pass = encoder.beginComputePass({ label: 'gpu-chores-apply-gain' });
    pass.setPipeline(gpu.gainPipeline);
    pass.setBindGroup(0, bg);
    pass.dispatchWorkgroups(Math.ceil(srcW / 8), Math.ceil(srcH / 8));
    pass.end();
    encoder.copyTextureToTexture({ texture: dest }, { texture: source }, [srcW, srcH, 1]);
    this.noteOp('apply_gain_2d', 'webgpu');
    return true;
  }

  private currentSourceGainStatus(): SourceGainStatus {
    return sourceGainStatus({
      toggleOn: this.sourceNormalizeEnabled,
      gpuComputeAvailable: this.breadcrumbs.gpuComputeAvailable,
      physicsPinned: this.physicsPinned,
      killSwitch: isGpuComputeKillSwitchEnabled(),
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
    this.encodeDownsampleTo(
      encoder,
      gpu,
      device,
      source,
      srcW,
      srcH,
      gpu.previewTex,
      PREVIEW_SIZE,
      PREVIEW_SIZE,
      this.breadcrumbs.autoUniforms.exposureGain,
    );

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

  private encodeDownsampleTo(
    encoder: GPUCommandEncoder,
    gpu: GpuResources,
    device: GPUDevice,
    source: GPUTexture,
    srcW: number,
    srcH: number,
    dest: GPUTexture,
    destW: number,
    destH: number,
    gain: number,
  ): void {
    const params = new Float32Array(8);
    const u32 = new Uint32Array(params.buffer);
    u32[0] = srcW;
    u32[1] = srcH;
    u32[2] = destW;
    u32[3] = destH;
    params[4] = clampExposureGain(gain);
    device.queue.writeBuffer(gpu.downsampleParams, 0, params);

    const dsBg = device.createBindGroup({
      layout: gpu.downsampleLayout,
      entries: [
        { binding: 0, resource: source.createView() },
        { binding: 1, resource: dest.createView() },
        { binding: 2, resource: { buffer: gpu.downsampleParams } },
      ],
    });
    const dsPass = encoder.beginComputePass({ label: 'gpu-chores-downsample' });
    dsPass.setPipeline(gpu.downsamplePipeline);
    dsPass.setBindGroup(0, dsBg);
    dsPass.dispatchWorkgroups(Math.ceil(destW / 8), Math.ceil(destH / 8));
    dsPass.end();
  }

  private applyGpuReadback(
    histBins: Uint32Array,
    reduceRaw: Uint32Array,
    classifyPacked?: Uint8Array,
  ): void {
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
    if (classifyPacked) {
      this.lastClassify = unpackClassifyRgba8(
        classifyPacked,
        PREVIEW_SIZE,
        PREVIEW_SIZE,
        CLASSIFY_BYTES_PER_ROW,
      );
      this.classifyWidth = PREVIEW_SIZE;
      this.classifyHeight = PREVIEW_SIZE;
    }
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
      this.classifyWidth = 0;
      this.classifyHeight = 0;
      if (!this.breadcrumbs.gpuComputeAvailable) {
        this.breadcrumbs.autoUniforms = { ...NEUTRAL_AUTO_UNIFORMS };
      }
      return;
    }
    const hist = lumaHistogramBt709(src.rgba, src.width, src.height);
    const reduce = reduceF32Luma(src.rgba, src.width, src.height);
    const exposure = autoExposureFromHistogram(hist);
    this.lastClassify = lutU8Map(src.rgba, src.width, src.height, this.classifyLut);
    this.classifyWidth = src.width;
    this.classifyHeight = src.height;
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

  private createGpu(device: GPUDevice, colorFormat: InternalColorFormat): GpuResources {
    const histModule = device.createShaderModule({ label: 'chores-hist', code: HISTOGRAM_WGSL });
    const reduceModule = device.createShaderModule({ label: 'chores-reduce', code: REDUCE_WGSL });
    const lutModule = device.createShaderModule({ label: 'chores-lut', code: LUT_WGSL });
    const dsModule = device.createShaderModule({ label: 'chores-downsample', code: DOWNSAMPLE_WGSL });
    const gainWgsl = rewriteWgslStorageFormats(APPLY_GAIN_WGSL, colorFormat);
    const gainModule = device.createShaderModule({ label: 'chores-apply-gain', code: gainWgsl });

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
    const gainLayout = device.createBindGroupLayout({
      entries: [
        { binding: 0, visibility: GPUShaderStage.COMPUTE, texture: { sampleType: 'unfilterable-float' } },
        { binding: 1, visibility: GPUShaderStage.COMPUTE, storageTexture: { access: 'write-only', format: colorFormat } },
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
    const gainPipeline = device.createComputePipeline({
      layout: device.createPipelineLayout({ bindGroupLayouts: [gainLayout] }),
      compute: { module: gainModule, entryPoint: 'main' },
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
    const classifyRead: [GPUBuffer, GPUBuffer] = [
      device.createBuffer({ label: 'chores-classify-read-0', size: CLASSIFY_READ_BYTES, usage: mapRead }),
      device.createBuffer({ label: 'chores-classify-read-1', size: CLASSIFY_READ_BYTES, usage: mapRead }),
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
    const gainParams = device.createBuffer({
      label: 'chores-gain-params',
      size: 16,
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
      classifyRead,
      lutBuf,
      downsampleParams,
      gainParams,
      reduceInitBuf,
      previewTex,
      classifyTex,
      histPipeline,
      reducePipeline,
      lutPipeline,
      downsamplePipeline,
      gainPipeline,
      histLayout,
      reduceLayout,
      lutLayout,
      downsampleLayout,
      gainLayout,
      colorFormat,
    };
  }

  private rebuildGainPipeline(
    device: GPUDevice,
    gpu: GpuResources,
    colorFormat: InternalColorFormat,
  ): void {
    const gainWgsl = rewriteWgslStorageFormats(APPLY_GAIN_WGSL, colorFormat);
    const gainModule = device.createShaderModule({ label: 'chores-apply-gain', code: gainWgsl });
    gpu.gainLayout = device.createBindGroupLayout({
      entries: [
        { binding: 0, visibility: GPUShaderStage.COMPUTE, texture: { sampleType: 'unfilterable-float' } },
        { binding: 1, visibility: GPUShaderStage.COMPUTE, storageTexture: { access: 'write-only', format: colorFormat } },
        { binding: 2, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'uniform' } },
      ],
    });
    gpu.gainPipeline = device.createComputePipeline({
      layout: device.createPipelineLayout({ bindGroupLayouts: [gpu.gainLayout] }),
      compute: { module: gainModule, entryPoint: 'main' },
    });
    gpu.colorFormat = colorFormat;
    this.colorFormat = colorFormat;
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
    gpu.classifyRead[0].destroy();
    gpu.classifyRead[1].destroy();
    gpu.lutBuf.destroy();
    gpu.downsampleParams.destroy();
    gpu.gainParams.destroy();
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
    this.breadcrumbs.sourceGain = this.currentSourceGainStatus();
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

/** Unpack tightly-or-padded rgba16float buffer into linear f32 RGBA. */
export function rgba16BufferToRgba32(
  packed: Uint8Array,
  width: number,
  height: number,
  bytesPerRow: number,
): Float32Array {
  const out = new Float32Array(width * height * 4);
  const row = new Uint16Array(width * 4);
  for (let y = 0; y < height; y++) {
    const offset = y * bytesPerRow;
    const view = new DataView(packed.buffer, packed.byteOffset + offset, width * 8);
    for (let i = 0; i < width * 4; i++) {
      row[i] = view.getUint16(i * 2, true);
    }
    for (let x = 0; x < width; x++) {
      const di = (y * width + x) * 4;
      out[di] = float16ToFloat32(row[x * 4]);
      out[di + 1] = float16ToFloat32(row[x * 4 + 1]);
      out[di + 2] = float16ToFloat32(row[x * 4 + 2]);
      out[di + 3] = float16ToFloat32(row[x * 4 + 3]);
    }
  }
  return out;
}

function float16ToFloat32(u16: number): number {
  const sign = (u16 & 0x8000) >> 15;
  const exp = (u16 & 0x7c00) >> 10;
  const frac = u16 & 0x03ff;
  if (exp === 0) {
    if (frac === 0) return sign ? -0 : 0;
    return (sign ? -1 : 1) * Math.pow(2, -14) * (frac / 1024);
  }
  if (exp === 31) {
    return frac ? Number.NaN : (sign ? -Infinity : Infinity);
  }
  return (sign ? -1 : 1) * Math.pow(2, exp - 15) * (1 + frac / 1024);
}
