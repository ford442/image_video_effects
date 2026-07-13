/**
 * WebGPURenderer.ts — TypeScript WebGPU compute-shader renderer.
 *
 * Implements the 13-binding compute shader contract (see webgpuConstants.ts)
 * with full multi-slot support. Delegates to focused modules under ./webgpu/.
 */

import { IRenderer, RendererConfig, ShaderSlotRenderer, GPUTimings, WebGPUDiagnostics } from './Renderer';
import { Ripple, MAX_RIPPLES } from './UniformBuffer';
import { PHYSICAL_SLOT_LIMIT } from './slotOrchestrator';
import {
  AUDIO_FFT_BINS,
  ShaderSlot,
  SlotMode,
  WG_SIZE_1D,
  WG_SIZE_X,
  WG_SIZE_Y,
} from './webgpu/webgpuConstants';
import {
  createTextures,
  createSamplers,
  createBuffers,
  createComputeBindGroupLayout,
  createComputeBindGroup,
  createBlitPipeline,
  createTimestampQueries,
} from './webgpu/WebGPUResourceManager';
import {
  createMediaInputState,
  WebGPUMediaInputContext,
  WebGPUMediaInputState,
  loadImage as mediaLoadImage,
  updateVideoFrame as mediaUpdateVideoFrame,
  clearSourceTexture as mediaClearSourceTexture,
} from './webgpu/WebGPUMediaInput';
import { WebGPUShaderManager } from './webgpu/WebGPUShaderManager';
import {
  WebGPURenderLoop,
  computeScaledDimensions,
  createDefaultAudioFreqBins,
} from './webgpu/WebGPURenderLoop';
import { initializeWebGPUDevice, attachDeviceLostHandler } from './webgpu/WebGPUDeviceInit';
import { createRenderLoopState, WebGPURenderLoopHost } from './webgpu/webgpuLoopState';

export class WebGPURenderer implements IRenderer, ShaderSlotRenderer {

  device: GPUDevice | null = null;
  context: GPUCanvasContext | null = null;
  private canvasFormat: GPUTextureFormat = 'bgra8unorm';

  private sourceTex!: GPUTexture;
  private readTex!: GPUTexture;
  private writeTex!: GPUTexture;
  private dataTexA!: GPUTexture;
  private dataTexB!: GPUTexture;
  private dataTexC!: GPUTexture;
  private historyTex!: GPUTexture;
  private historyHead = 0;
  private depthRead!: GPUTexture;
  private depthWrite!: GPUTexture;
  private emptyTex!: GPUTexture;

  private filterSampler!: GPUSampler;
  private nearestSampler!: GPUSampler;
  private compSampler!: GPUSampler;

  private uniformBuf!: GPUBuffer;
  private extraBuf!: GPUBuffer;
  private plasmaBuf!: GPUBuffer;

  private bindGroupLayout!: GPUBindGroupLayout;
  private pipelineLayout!: GPUPipelineLayout;
  private computeBindGroup!: GPUBindGroup;

  private blitPipeline!: GPURenderPipeline;
  private generativeBlitPipeline!: GPURenderPipeline;
  private scaleCopyPipeline!: GPURenderPipeline;
  private blitBindGroupLayout!: GPUBindGroupLayout;
  private blitBindGroup!: GPUBindGroup;
  private blitReadTex!: GPUTexture;
  private lastBlitReadTex: GPUTexture | null = null;
  private lastBlitScaledW = 0;
  private lastBlitScaledH = 0;

  shaderManager = new WebGPUShaderManager();
  private renderLoop = new WebGPURenderLoop();
  private mediaState: WebGPUMediaInputState = createMediaInputState();
  private loopState = createRenderLoopState(this as unknown as WebGPURenderLoopHost);

  slots: ShaderSlot[] = Array.from({ length: PHYSICAL_SLOT_LIMIT }, () => ({
    shaderId: null, enabled: false, mode: 'chained' as SlotMode,
  }));

  currentTime = 0;
  mouseX = 0.5;
  private mouseYBrowser = 0.5;
  mouseYShader = 0.5;
  mouseDown = false;
  zoomParams = [0.5, 0.5, 0.5, 0.5];
  ripples: Ripple[] = [];
  audioBass = 0;
  audioMid = 0;
  audioTreble = 0;
  audioFreqBins: Float32Array = createDefaultAudioFreqBins();

  canvasW = 0;
  canvasH = 0;
  resolutionScale = 1.0;
  scaledW = 0;
  scaledH = 0;

  supportsTimestampQuery = false;
  private querySet: GPUQuerySet | null = null;
  private queryBuffer: GPUBuffer | null = null;
  gpuTimings = { parallelTime: 0, chainedTime: 0, totalTime: 0 };

  initialized = false;
  animationId: number | null = null;
  startTime = 0;

  frameCount = 0;
  lastFPSTime = 0;
  fps = 0;
  targetFPS = 60;
  adaptiveQuality = false;

  inputSource: 'image' | 'video' | 'webcam' | 'generative' | 'live' = 'image';
  videoCopyPipeline: GPURenderPipeline | null = null;
  videoCopyBindGroupLayout: GPUBindGroupLayout | null = null;
  private supportsExternalTexture = false;

  private supportsSubgroups = false;
  private supportsDeepWorkgroup = false;

  private lastInitError = '';
  private adapterSummary = '';
  private adapterAttemptLabel: string | null = null;

  constructor(private config: RendererConfig) {}

  get mediaVideo(): HTMLVideoElement | null { return this.mediaState.video; }

  getSupportsDeepWorkgroup(): boolean { return this.supportsDeepWorkgroup; }

  getDiagnostics(): WebGPUDiagnostics {
    return {
      initialized: this.initialized,
      lastInitError: this.lastInitError,
      adapterSummary: this.adapterSummary,
      adapterAttemptLabel: this.adapterAttemptLabel,
      supportsDeepWorkgroup: this.supportsDeepWorkgroup,
      supportsSubgroups: this.supportsSubgroups,
      fps: this.fps,
    };
  }

  async init(canvas: HTMLCanvasElement): Promise<boolean> {
    if (this.initialized) return true;

    const outcome = await initializeWebGPUDevice(canvas, this.config.width, this.config.height);
    if (!outcome.ok) {
      this.lastInitError = outcome.lastInitError;
      this.adapterSummary = outcome.adapterSummary;
      this.adapterAttemptLabel = outcome.adapterAttemptLabel;
      return false;
    }

    this.device = outcome.device;
    this.context = outcome.context;
    this.canvasFormat = outcome.canvasFormat;
    this.canvasW = outcome.canvasW;
    this.canvasH = outcome.canvasH;
    this.supportsSubgroups = outcome.supportsSubgroups;
    this.supportsDeepWorkgroup = outcome.supportsDeepWorkgroup;
    this.adapterSummary = outcome.adapterSummary;
    this.adapterAttemptLabel = outcome.adapterAttemptLabel;

    attachDeviceLostHandler(outcome.device, this.context, () => { this.initialized = false; });

    this.updateScaledDimensions();
    this.createGpuResources(outcome.hasF32Filterable);

    this.initialized = true;
    this.startTime = performance.now() / 1000;
    this.lastFPSTime = this.startTime;
    this.startRenderLoop();

    console.log(
      `✅ TypeScript WebGPU renderer initialized (${this.canvasW}×${this.canvasH}` +
      `${outcome.hasF32Filterable ? ', float32-filterable' : ''}` +
      `${this.supportsSubgroups ? ', subgroups' : ''}` +
      `${this.supportsDeepWorkgroup ? ', deep-workgroup' : ''})`,
    );
    return true;
  }

  private createGpuResources(hasF32Filt: boolean): void {
    const d = this.device!;
    const textures = createTextures(d, this.canvasW, this.canvasH, this.scaledW, this.scaledH);
    Object.assign(this, textures);

    const samplers = createSamplers(d);
    this.filterSampler = samplers.filterSampler;
    this.nearestSampler = samplers.nearestSampler;
    this.compSampler = samplers.compSampler;

    const buffers = createBuffers(d);
    this.uniformBuf = buffers.uniformBuf;
    this.extraBuf = buffers.extraBuf;
    this.plasmaBuf = buffers.plasmaBuf;

    const computeLayout = createComputeBindGroupLayout(d, hasF32Filt);
    this.bindGroupLayout = computeLayout.bindGroupLayout;
    this.pipelineLayout = computeLayout.pipelineLayout;

    this.historyHead = 0;
    this.blitReadTex = this.readTex;
    this.computeBindGroup = createComputeBindGroup(d, this.bindGroupLayout, textures, buffers, samplers);

    const blit = createBlitPipeline(d, this.canvasFormat, this.blitReadTex, this.scaledW, this.scaledH);
    this.blitPipeline = blit.blitPipeline;
    this.generativeBlitPipeline = blit.generativeBlitPipeline;
    this.scaleCopyPipeline = blit.scaleCopyPipeline;
    this.blitBindGroupLayout = blit.blitBindGroupLayout;
    this.blitBindGroup = blit.blitBindGroup;
    this.videoCopyPipeline = blit.videoCopyPipeline;
    this.videoCopyBindGroupLayout = blit.videoCopyBindGroupLayout;
    this.supportsExternalTexture = blit.supportsExternalTexture;
    this.lastBlitReadTex = this.blitReadTex;
    this.lastBlitScaledW = this.scaledW;
    this.lastBlitScaledH = this.scaledH;

    const ts = createTimestampQueries(d);
    this.supportsTimestampQuery = ts.supportsTimestampQuery;
    this.querySet = ts.querySet;
    this.queryBuffer = ts.queryBuffer;
  }

  private getMediaContext(): WebGPUMediaInputContext {
    return {
      device: this.device,
      sourceTex: this.sourceTex,
      readTex: this.readTex,
      canvasW: this.canvasW,
      canvasH: this.canvasH,
      filterSampler: this.filterSampler,
      supportsExternalTexture: this.supportsExternalTexture,
      videoCopyPipeline: this.videoCopyPipeline,
      videoCopyBindGroupLayout: this.videoCopyBindGroupLayout,
    };
  }

  private startRenderLoop(): void {
    const loop = () => {
      if (!this.initialized) return;
      this.loopState.currentTime = performance.now() / 1000 - this.startTime;
      this.renderLoop.renderFrame(this.loopState);
      this.animationId = requestAnimationFrame(loop);
    };
    loop();
  }

  updateVideoFrame = (): void => {
    mediaUpdateVideoFrame(this.getMediaContext(), this.mediaState);
  };

  adaptQualityIfNeeded = (): void => {
    if (!this.adaptiveQuality) return;
    const ratio = this.fps / this.targetFPS;
    if (ratio < 0.7 && this.resolutionScale > 0.25) {
      this.setResolutionScale(this.resolutionScale - 0.125);
      console.log(`[WebGPU] FPS low (${this.fps}), reducing resolution to ${this.resolutionScale}`);
    } else if (ratio > 0.95 && this.resolutionScale < 1.0) {
      this.setResolutionScale(this.resolutionScale + 0.0625);
      console.log(`[WebGPU] FPS good (${this.fps}), increasing resolution to ${this.resolutionScale}`);
    }
  };

  getGPUTimings(): GPUTimings {
    return this.renderLoop.getGPUTimings(this.loopState);
  }

  applyTestRenderState(state: {
    time?: number; mouseX?: number; mouseY?: number;
    bass?: number; mid?: number; treble?: number;
  }): void {
    if (state.time !== undefined) this.currentTime = state.time;
    if (state.mouseX !== undefined) this.mouseX = state.mouseX;
    if (state.mouseY !== undefined) {
      this.mouseYBrowser = state.mouseY;
      this.mouseYShader = 1.0 - state.mouseY;
    }
    if (state.bass !== undefined) {
      this.updateAudioData(state.bass, state.mid ?? 0, state.treble ?? 0);
    }
    this.renderLoop.renderFrame(this.loopState);
  }

  async loadShader(id: string, url: string): Promise<boolean> {
    return this.shaderManager.loadShader(this.device, this.pipelineLayout, this.supportsSubgroups, id, url);
  }

  setActiveShader(id: string): void {
    this.slots[0] = { shaderId: id, enabled: true, mode: 'chained' };
    for (let i = 1; i < PHYSICAL_SLOT_LIMIT; i++) {
      this.slots[i] = { shaderId: null, enabled: false, mode: 'chained' };
    }
  }

  setSlotShader(index: number, id: string): void {
    if (index >= 0 && index < PHYSICAL_SLOT_LIMIT) {
      const mode = this.slots[index]?.mode ?? 'chained';
      this.slots[index] = { shaderId: id, enabled: !!id, mode };
      if (process.env.NODE_ENV === 'development') {
        console.log(`[WebGPURenderer] Slot ${index} set to "${id}" (enabled: ${!!id}, mode: ${mode})`);
        console.log(`[WebGPURenderer] Current slots:`, this.slots.map(s => ({ id: s.shaderId, enabled: s.enabled, mode: s.mode })));
      }
    }
  }

  setSlotEnabled(index: number, enabled: boolean): void {
    if (index >= 0 && index < PHYSICAL_SLOT_LIMIT) this.slots[index].enabled = enabled;
  }

  setSlotMode(index: number, mode: SlotMode): void {
    if (index >= 0 && index < PHYSICAL_SLOT_LIMIT) this.slots[index].mode = mode;
  }

  getSlotMode(index: number): SlotMode | null {
    return index >= 0 && index < PHYSICAL_SLOT_LIMIT ? this.slots[index].mode : null;
  }

  getSlotState(index: number): { shaderId: string | null; enabled: boolean; mode: SlotMode } | null {
    if (index < 0 || index >= PHYSICAL_SLOT_LIMIT) return null;
    const slot = this.slots[index];
    return { shaderId: slot.shaderId, enabled: slot.enabled, mode: slot.mode };
  }

  addRipple(x: number, y: number): void {
    if (this.ripples.length >= MAX_RIPPLES) this.ripples.shift();
    this.ripples.push({ x, y, startTime: this.currentTime });
  }

  clearRipples(): void { this.ripples = []; }
  getFPS(): number { return this.fps; }

  getAudioData(): { bass: number; mid: number; treble: number; freqBins: Float32Array } {
    return { bass: this.audioBass, mid: this.audioMid, treble: this.audioTreble, freqBins: this.audioFreqBins };
  }

  getVideoStatus(): { hasVideo: boolean; playing: boolean; readyState: number; currentTime: number; videoWidth: number; videoHeight: number } | null {
    const video = this.mediaState.video;
    if (!video) return null;
    return {
      hasVideo: true, playing: !video.paused, readyState: video.readyState,
      currentTime: video.currentTime, videoWidth: video.videoWidth, videoHeight: video.videoHeight,
    };
  }

  isShaderCached(id: string): boolean { return this.shaderManager.hasPipeline(id); }
  getPipelineCacheStats() { return this.shaderManager.getCacheStats(); }

  async preloadShader(id: string, url: string): Promise<boolean> {
    return this.shaderManager.preloadShader(this.device, this.pipelineLayout, this.supportsSubgroups, id, url);
  }

  getWorkgroupConfig() {
    return {
      size2D: [WG_SIZE_X, WG_SIZE_Y] as [number, number],
      size1D: WG_SIZE_1D,
      invocationsPerGroup: WG_SIZE_X * WG_SIZE_Y,
      dispatch2D: { x: Math.ceil(this.canvasW / WG_SIZE_X), y: Math.ceil(this.canvasH / WG_SIZE_Y) },
    };
  }

  setResolutionScale(scale: number): void {
    const snapped = Math.round(Math.max(0.25, Math.min(1.0, scale)) * 8) / 8;
    if (this.resolutionScale === snapped) return;
    this.resolutionScale = snapped;
    this.updateScaledDimensions();
    if (this.device && this.initialized) {
      this.createGpuResources(this.device.features.has('float32-filterable'));
    }
  }

  getResolutionScale() {
    const fullPixels = this.canvasW * this.canvasH;
    const scaledPixels = this.scaledW * this.scaledH;
    return {
      scale: this.resolutionScale,
      full: { w: this.canvasW, h: this.canvasH },
      scaled: { w: this.scaledW, h: this.scaledH },
      pixelReduction: `${Math.round((1 - scaledPixels / fullPixels) * 100)}%`,
    };
  }

  setAdaptiveQuality(enabled: boolean, targetFPS = 60): void {
    this.adaptiveQuality = enabled;
    this.targetFPS = targetFPS;
  }

  private updateScaledDimensions(): void {
    const dims = computeScaledDimensions(this.canvasW, this.canvasH, this.resolutionScale);
    this.scaledW = dims.scaledW;
    this.scaledH = dims.scaledH;
  }

  setVideo(video: HTMLVideoElement | undefined): void { this.mediaState.video = video ?? null; }
  getVideo(): HTMLVideoElement | null { return this.mediaState.video; }

  async loadImage(url: string): Promise<string> {
    return mediaLoadImage(this.getMediaContext(), this.mediaState, url);
  }

  updateAudioData(bass: number, mid: number, treble: number): void {
    this.audioBass = bass; this.audioMid = mid; this.audioTreble = treble;
  }

  updateAudioFrequencyBins(bins: Float32Array): void {
    const len = Math.min(bins.length, AUDIO_FFT_BINS);
    this.audioFreqBins.set(bins.subarray(0, len), 0);
    if (len < AUDIO_FFT_BINS) this.audioFreqBins.fill(0, len);
  }

  updateMouse(x: number, y: number): void {
    this.mouseX = x;
    this.mouseYBrowser = y;
    this.mouseYShader = 1.0 - y;
  }

  setParam(name: string, value: number): void {
    switch (name) {
      case 'mouseDown': this.mouseDown = value > 0; break;
      case 'zoomParam1': this.zoomParams[0] = value; break;
      case 'zoomParam2': this.zoomParams[1] = value; break;
      case 'zoomParam3': this.zoomParams[2] = value; break;
      case 'zoomParam4': this.zoomParams[3] = value; break;
    }
  }

  setSlotParams(slotIndex: number, p1: number, p2: number, p3: number, p4: number): void {
    if (slotIndex === 0) {
      this.zoomParams[0] = p1; this.zoomParams[1] = p2;
      this.zoomParams[2] = p3; this.zoomParams[3] = p4;
    }
  }

  updateSlotParams(
    params: { zoomParam1?: number; zoomParam2?: number; zoomParam3?: number; zoomParam4?: number },
    slotIndex = 0,
  ): void {
    if (slotIndex !== 0) return;
    if (params.zoomParam1 !== undefined) this.zoomParams[0] = params.zoomParam1;
    if (params.zoomParam2 !== undefined) this.zoomParams[1] = params.zoomParam2;
    if (params.zoomParam3 !== undefined) this.zoomParams[2] = params.zoomParam3;
    if (params.zoomParam4 !== undefined) this.zoomParams[3] = params.zoomParam4;
  }

  setInputSource(source: 'image' | 'video' | 'webcam' | 'generative' | 'live'): void {
    this.inputSource = source;
    if (source === 'generative') mediaClearSourceTexture(this.getMediaContext());
    if (process.env.NODE_ENV === 'development') {
      console.log(`[WebGPU] Input source set to: ${source}`);
    }
  }

  getInputSource() { return this.inputSource; }
  render(): void {}

  destroy(): void {
    if (this.animationId !== null) {
      cancelAnimationFrame(this.animationId);
      this.animationId = null;
    }
    this.initialized = false;
    this.shaderManager.clear();
    for (const t of [this.sourceTex, this.readTex, this.writeTex, this.dataTexA, this.dataTexB,
                     this.dataTexC, this.historyTex, this.depthRead, this.depthWrite, this.emptyTex]) {
      t?.destroy();
    }
    for (const b of [this.uniformBuf, this.extraBuf, this.plasmaBuf]) {
      b?.destroy();
    }
    this.context?.unconfigure();
    this.device?.destroy();
    this.device = null;
  }
}
