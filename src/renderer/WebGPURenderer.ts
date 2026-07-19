/**
 * WebGPURenderer.ts
 *
 * Thin facade implementing IRenderer / ShaderSlotRenderer.
 * Delegates to webgpu/* modules (device, resources, pipeline, frame, audioDepth).
 */

import { Renderer, RendererConfig, ShaderSlotRenderer, GPUTimings } from './Renderer';
import { Ripple, MAX_RIPPLES } from './UniformBuffer';
import { PHYSICAL_SLOT_LIMIT } from './slotOrchestrator';
import { initializeWebGPUDevice, attachDeviceLostHandler } from './webgpu/device';
import { WebGPUResourcePool } from './webgpu/resources';
import { WebGPUPipelineModule, createComputeBindGroup } from './webgpu/pipeline';
import { setupTimestampQueries, buildGPUTimings } from './webgpu/WebGPUTiming';
import {
  createAudioDepthState,
  updateAudioData,
  updateAudioFrequencyBins,
  updateDepthMap,
  getAudioData,
} from './webgpu/audioDepth';
import {
  WebGPUFrameRenderer,
  createFrameState,
  createRendererFrameHost,
  computeScaledDimensions,
  WebGPUFrameState,
  RendererFrameDeps,
} from './webgpu/frame';
import {
  createMediaInputState,
  updateVideoFrame as mediaUpdateVideoFrame,
  loadImage as mediaLoadImage,
  clearSourceTexture,
  WebGPUMediaInputContext,
} from './webgpu/WebGPUMediaInput';
import { ShaderSlot, SlotMode, WG_SIZE_X, WG_SIZE_Y, WG_SIZE_1D } from './webgpu/webgpuConstants';

export class WebGPURenderer implements Renderer, ShaderSlotRenderer {
  private device: GPUDevice | null = null;
  private context: GPUCanvasContext | null = null;
  private canvasFormat: GPUTextureFormat = 'bgra8unorm';

  readonly resources = new WebGPUResourcePool();
  readonly pipeline = new WebGPUPipelineModule();
  private readonly frameRenderer = new WebGPUFrameRenderer();
  private readonly audioDepth = createAudioDepthState();
  private readonly mediaState = createMediaInputState();

  private computeBindGroup!: GPUBindGroup;
  private blitReadTex!: GPUTexture;
  private lastBlitReadTex: GPUTexture | null = null;
  private lastBlitScaledW = 0;
  private lastBlitScaledH = 0;

  private slots: ShaderSlot[] = Array.from({ length: PHYSICAL_SLOT_LIMIT }, () => ({
    shaderId: null, enabled: false, mode: 'chained' as SlotMode,
  }));

  private currentTime = 0;
  private mouseX = 0.5;
  private mouseYShader = 0.5;
  private mouseDown = false;
  private zoomParams = [0.5, 0.5, 0.5, 0.5];
  private ripples: Ripple[] = [];

  private canvasW = 0;
  private canvasH = 0;
  private resolutionScale = 1.0;
  private scaledW = 0;
  private scaledH = 0;

  private supportsTimestampQuery = false;
  private querySet: GPUQuerySet | null = null;
  private queryBuffer: GPUBuffer | null = null;
  private gpuTimings = { parallelTime: 0, chainedTime: 0, totalTime: 0 };

  private initialized = false;
  private animationId: number | null = null;
  private startTime = 0;
  private frameCount = 0;
  private lastFPSTime = 0;
  private fps = 0;
  private targetFPS = 60;
  private adaptiveQuality = false;
  maxPassesPerFrame = 12;

  private inputSource: 'image' | 'video' | 'webcam' | 'generative' | 'live' = 'image';
  private supportsSubgroups = false;
  private supportsDeepWorkgroup = false;

  private frameState?: WebGPUFrameState;

  constructor(private config: RendererConfig) {}

  getSupportsDeepWorkgroup(): boolean { return this.supportsDeepWorkgroup; }

  async init(canvas: HTMLCanvasElement): Promise<boolean> {
    if (this.initialized) return true;

    const outcome = await initializeWebGPUDevice(canvas, this.config.width, this.config.height);
    if (!outcome.ok) return false;

    this.device = outcome.device;
    this.context = outcome.context;
    this.canvasFormat = outcome.canvasFormat;
    this.canvasW = outcome.canvasW;
    this.canvasH = outcome.canvasH;
    this.supportsSubgroups = outcome.supportsSubgroups;
    this.supportsDeepWorkgroup = outcome.supportsDeepWorkgroup;

    attachDeviceLostHandler(outcome.device, outcome.context, () => {
      this.initialized = false;
    });

    this.updateScaledDimensions();
    this.setupGpuResources(outcome.hasF32Filterable);

    this.frameState = createFrameState(createRendererFrameHost(this as unknown as RendererFrameDeps));
    this.initialized = true;
    this.startTime = performance.now() / 1000;
    this.lastFPSTime = this.startTime;
    this.frameRenderer.startRenderLoop(this.frameState);

    console.log(
      `✅ TypeScript WebGPU renderer initialized (${this.canvasW}×${this.canvasH}` +
      `${outcome.hasF32Filterable ? ', float32-filterable' : ''}` +
      `${this.supportsSubgroups ? ', subgroups' : ''}` +
      `${this.supportsDeepWorkgroup ? ', deep-workgroup' : ''})` +
      (outcome.adapterAttemptLabel ? ` [${outcome.adapterAttemptLabel}]` : ''),
    );
    return true;
  }

  private setupGpuResources(hasF32Filt: boolean): void {
    const d = this.device!;
    this.pipeline.setupComputeLayout(d, hasF32Filt);
    this.resources.setup(d, this.canvasW, this.canvasH, this.scaledW, this.scaledH);
    this.computeBindGroup = createComputeBindGroup(
      d,
      this.pipeline.bindGroupLayout,
      this.resources.getTextureSet(),
      this.resources.getBufferSet(),
      this.resources.getSamplerSet(),
    );
    this.blitReadTex = this.resources.blitReadTex;
    this.pipeline.setupBlitPipelines(d, this.canvasFormat, this.blitReadTex);
    this.lastBlitReadTex = this.blitReadTex;
    this.lastBlitScaledW = this.scaledW;
    this.lastBlitScaledH = this.scaledH;

    const timing = setupTimestampQueries(d);
    this.supportsTimestampQuery = timing.supportsTimestampQuery;
    this.querySet = timing.querySet;
    this.queryBuffer = timing.queryBuffer;
  }

  private getMediaContext(): WebGPUMediaInputContext {
    return {
      device: this.device,
      sourceTex: this.resources.sourceTex,
      readTex: this.resources.readTex,
      canvasW: this.canvasW,
      canvasH: this.canvasH,
      filterSampler: this.resources.filterSampler,
      supportsExternalTexture: this.pipeline.supportsExternalTexture,
      videoCopyPipeline: this.pipeline.videoCopyPipeline,
      videoCopyBindGroupLayout: this.pipeline.videoCopyBindGroupLayout,
    };
  }

  getGPUTimings(): GPUTimings {
    return buildGPUTimings(this.gpuTimings, this.supportsTimestampQuery);
  }

  applyTestRenderState(state: {
    time?: number; mouseX?: number; mouseY?: number;
    bass?: number; mid?: number; treble?: number;
  }): void {
    if (state.time !== undefined) this.currentTime = state.time;
    if (state.mouseX !== undefined) this.mouseX = state.mouseX;
    if (state.mouseY !== undefined) this.mouseYShader = state.mouseY;
    if (state.bass !== undefined) updateAudioData(this.audioDepth, state.bass, state.mid ?? 0, state.treble ?? 0);
    this.frameRenderer.renderFrame(this.frameState!);
  }

  async loadShader(id: string, url: string): Promise<boolean> {
    return this.pipeline.shaderManager.loadShader(
      this.device, this.pipeline.pipelineLayout, this.supportsSubgroups, id, url,
    );
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
  getAudioData() { return getAudioData(this.audioDepth); }

  getVideoStatus() {
    const v = this.mediaState.video;
    if (!v) return null;
    return {
      hasVideo: true, playing: !v.paused, readyState: v.readyState,
      currentTime: v.currentTime, videoWidth: v.videoWidth, videoHeight: v.videoHeight,
    };
  }

  isShaderCached(id: string): boolean { return this.pipeline.shaderManager.hasPipeline(id); }
  getPipelineCacheStats() { return this.pipeline.shaderManager.getCacheStats(); }
  async preloadShader(id: string, url: string): Promise<boolean> { return this.loadShader(id, url); }

  getWorkgroupConfig() {
    return {
      size2D: [WG_SIZE_X, WG_SIZE_Y] as [number, number],
      size1D: WG_SIZE_1D,
      invocationsPerGroup: WG_SIZE_X * WG_SIZE_Y,
      dispatch2D: {
        x: Math.ceil(this.canvasW / WG_SIZE_X),
        y: Math.ceil(this.canvasH / WG_SIZE_Y),
      },
    };
  }

  setResolutionScale(scale: number): void {
    const snapped = Math.round(Math.max(0.25, Math.min(1.0, scale)) * 8) / 8;
    if (this.resolutionScale === snapped) return;
    this.resolutionScale = snapped;
    this.updateScaledDimensions();
    if (this.device && this.initialized) {
      this.resources.recreateScaleTextures(this.device, this.canvasW, this.canvasH, this.scaledW, this.scaledH);
      this.computeBindGroup = createComputeBindGroup(
        this.device, this.pipeline.bindGroupLayout,
        this.resources.getTextureSet(), this.resources.getBufferSet(), this.resources.getSamplerSet(),
      );
      this.blitReadTex = this.resources.blitReadTex;
      this.lastBlitReadTex = null;
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

  private adaptQualityIfNeeded(): void {
    if (!this.adaptiveQuality) return;
    const ratio = this.fps / this.targetFPS;
    if (ratio < 0.7 && this.resolutionScale > 0.25) {
      this.setResolutionScale(this.resolutionScale - 0.125);
    } else if (ratio > 0.95 && this.resolutionScale < 1.0) {
      this.setResolutionScale(this.resolutionScale + 0.0625);
    }
  }

  setVideo(video: HTMLVideoElement | undefined): void {
    this.mediaState.video = video ?? null;
  }

  get mediaVideo(): HTMLVideoElement | null {
    return this.mediaState.video;
  }

  updateVideoFrame(): void {
    mediaUpdateVideoFrame(this.getMediaContext(), this.mediaState);
  }

  async loadImage(url: string): Promise<string> {
    return mediaLoadImage(this.getMediaContext(), this.mediaState, url);
  }

  updateAudioData(bass: number, mid: number, treble: number): void {
    updateAudioData(this.audioDepth, bass, mid, treble);
  }

  updateAudioFrequencyBins(bins: Float32Array): void {
    updateAudioFrequencyBins(this.audioDepth, bins);
  }

  updateDepthMap(data: Float32Array, width: number, height: number): void {
    if (!this.device) return;
    updateDepthMap(this.device, this.resources.depthRead, data, width, height, this.canvasW, this.canvasH);
  }

  /** Canvas-normalized mouse Y (0 = top, 1 = bottom) — matches WASM + WGSL_BUILTINS mouse_uv. */
  updateMouse(x: number, y: number): void {
    this.mouseX = x;
    this.mouseYShader = y;
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
      this.zoomParams = [p1, p2, p3, p4];
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
    if (source === 'generative') clearSourceTexture(this.getMediaContext());
  }

  getInputSource() { return this.inputSource; }
  render(): void {}

  setMaxPassesPerFrame(cap: number): void {
    this.maxPassesPerFrame = cap;
    if (this.frameState) {
      this.frameState.maxPassesPerFrame = cap;
    }
  }

  destroy(): void {
    if (this.frameState) this.frameRenderer.stopRenderLoop(this.frameState);
    this.initialized = false;
    this.pipeline.clear();
    this.resources.destroyWorkingTextures();
    this.resources.destroyBuffers();
    this.context?.unconfigure();
    this.device?.destroy();
    this.device = null;
  }
}
