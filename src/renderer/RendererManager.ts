import { Renderer, RendererConfig, GPUTimings } from './Renderer';
import { WASMRenderer } from './WASMRenderer';
import { WebGPURenderer } from './WebGPURenderer';
import { InputSource, RenderMode, ShaderEntry, SlotParams } from './types';
import { AdaptivePerformanceController } from './adaptivePerformance';
import {
  RendererType,
  getRendererTypeFromURL,
  performBackendSwitch,
  resolveInitBackendPreference,
  type RendererInitOptions,
  type WebGpuProbeHandoff,
} from './backendLifecycle';
import * as inputBridge from './inputSourceBridge';
import {
  PerformancePolicyState,
  RendererPerformanceStatus,
  applyPerformancePolicyToRenderer,
  applyQualityPolicy,
  applyResolutionScaleToRenderer,
  buildPerformanceStatus,
  createPerformancePolicyState,
  readResolutionScale,
  refreshFormatCapabilities,
  registerFp32Requirement,
  releaseFp32Requirement,
} from './performanceStatus';
import {
  ShaderLoadMeta,
  SLOT_COUNT,
  addRipple,
  clearRipples,
  firePlasmaOnBackend,
  loadShaderForBackend,
  loadShadersForBackend,
  reloadShaderOnBackend,
  resyncShaderStack,
  resolveShaderBackend,
  setActiveShader,
  setSlotMode,
  setSlotParams,
  setSlotShader,
  supportsShaderEffects as backendSupportsShaders,
  syncAllSlotParams,
  updateSlotParams,
} from './slotOrchestration';
import { DeviceFormatCapabilities } from '../config/formatPolicy';
import { RenderQualityMode } from '../config/performancePolicy';
import { buildRendererDiagnostics } from './rendererDiagnostics';
import type { RendererDiagnostics, RendererMetrics } from './rendererTypes';
import { adoptHandoffDeviceIfWebGpu, clearAdoptedRendererDevice, getAdoptedRendererDevice, releaseAdoptedDeviceIfLeavingWebGpu } from '../utils/adoptedGpuDevice';

export type { RendererType, RendererInitOptions, WebGpuProbeHandoff };
export { getRendererTypeFromURL };
export type { RendererPerformanceStatus, ShaderLoadMeta };
export type { RendererMetrics, RendererDiagnostics } from './rendererTypes';

export class RendererManager {
  private currentRenderer: Renderer | null = null;
  private currentType: RendererType | null = null;
  private lastFailedWasmRenderer: WASMRenderer | null = null;
  private readonly config: RendererConfig;
  private canvas: HTMLCanvasElement | null = null;
  private webGpuHandoff: WebGpuProbeHandoff | undefined;
  private metrics: RendererMetrics = { fps: 0, frameTime: 0, agentCount: 0, isWASM: false };
  private readonly onMetricsUpdate?: (metrics: RendererMetrics) => void;
  private readonly perfState: PerformancePolicyState = createPerformancePolicyState();
  private readonly adaptiveController: AdaptivePerformanceController;

  constructor(config: RendererConfig, onMetricsUpdate?: (metrics: RendererMetrics) => void) {
    this.config = config;
    this.onMetricsUpdate = onMetricsUpdate;
    this.adaptiveController = new AdaptivePerformanceController({
      getFps: () => this.getCurrentFPS(),
      getScale: () => this.perfState.resolutionScale,
      setScale: (scale) => applyResolutionScaleToRenderer(this.perfState, this.shaderRenderer(), scale),
    });
  }

  private shaderRenderer(): WebGPURenderer | WASMRenderer | null {
    const r = this.currentRenderer;
    return r instanceof WebGPURenderer || r instanceof WASMRenderer ? r : null;
  }

  private backend() {
    return resolveShaderBackend(this.currentRenderer);
  }

  private slotPolicy() {
    return {
      maxActiveSlots: this.perfState.performancePolicy.maxActiveSlots,
      preferNonDeepVariants: this.perfState.performancePolicy.preferNonDeepVariants,
    };
  }

  private slotCallbacks() {
    return {
      onFp32Required: (id: string) => {
        if (registerFp32Requirement(this.perfState, id)) {
          if (this.perfState.performancePolicy.colorFormat !== 'rgba32float') {
            console.warn(
              `[RendererManager] "${id}" requires rgba32float — pinning storage format to FP32 ` +
                `(quality mode stays "${this.perfState.qualityMode}")`,
            );
            this.applyQualityPolicy(this.perfState.qualityMode);
          }
        }
      },
    };
  }

  private loadShaderBound = (id: string, url: string, meta?: ShaderLoadMeta) =>
    loadShaderForBackend(this.backend(), this.slotPolicy(), this.slotCallbacks(), id, url, meta);

  async init(canvas: HTMLCanvasElement, options?: RendererInitOptions): Promise<boolean> {
    this.canvas = canvas;
    this.webGpuHandoff = options?.webGpuHandoff;
    const { preferredType } = resolveInitBackendPreference();

    if (preferredType === 'wasm') {
      console.log('🔧 WASM renderer explicitly requested via ?renderer=wasm');
      if (await this.switchRenderer('wasm')) {
        console.log('✅ Using C++ WASM renderer (experimental, forced via ?renderer=wasm)');
        return true;
      }
      console.warn('⚠️ WASM renderer requested but failed to initialise');
      return false;
    }
    if (preferredType === 'js') {
      console.log('🔧 Canvas2D renderer explicitly requested via ?renderer=js');
      return this.switchRenderer('js');
    }
    if (await this.switchRenderer('webgpu')) {
      console.log('✅ Using TypeScript WebGPU renderer (native navigator.gpu)');
      return true;
    }
    console.warn('⚠️ WebGPU unavailable — renderer blocked (no automatic Canvas2D fallback)');
    return false;
  }

  async switchRenderer(type: RendererType): Promise<boolean> {
    if (!this.canvas) return false;
    const handoff = type === 'webgpu' ? this.webGpuHandoff : undefined;
    releaseAdoptedDeviceIfLeavingWebGpu(this.currentType, type);
    const outcome = await performBackendSwitch({
      targetType: type,
      canvas: this.canvas,
      config: this.config,
      previousType: this.currentType,
      previousRenderer: this.currentRenderer,
      webGpuHandoff: handoff,
    });
    if (type === 'webgpu') this.webGpuHandoff = undefined;

    if (outcome.success) {
      adoptHandoffDeviceIfWebGpu(type, handoff);
      this.currentRenderer = outcome.renderer;
      this.currentType = outcome.type;
      this.canvas = outcome.canvas;
      this.metrics.isWASM = outcome.isWASM;
      this.lastFailedWasmRenderer = null;
      refreshFormatCapabilities(this.perfState, this.shaderRenderer());
      applyPerformancePolicyToRenderer(this.perfState, this.shaderRenderer(), this.adaptiveController);
      this.startMetricsCollection();
      return true;
    }

    if (outcome.failedWasmRenderer) this.lastFailedWasmRenderer = outcome.failedWasmRenderer;
    this.currentRenderer = outcome.renderer;
    this.currentType = outcome.type;
    this.metrics.isWASM = outcome.isWASM;

    if (outcome.restoreType) {
      console.warn(`[RendererManager] Restoring previous renderer '${outcome.restoreType}' after ${type} init failure`);
      if (!(await this.switchRenderer(outcome.restoreType))) {
        console.warn(`[RendererManager] Restore of '${outcome.restoreType}' failed — renderer blocked`);
      }
    } else {
      console.warn(`[RendererManager] switchRenderer('${type}') failed — keeping previous renderer`);
    }
    return false;
  }

  private startMetricsCollection(): void {
    const tick = () => {
      const fps = this.currentRenderer?.getFPS?.();
      if (typeof fps === 'number') this.metrics.fps = fps;
      this.onMetricsUpdate?.(this.metrics);
      requestAnimationFrame(tick);
    };
    tick();
  }

  setVideo(video: HTMLVideoElement): void { inputBridge.setVideo(this.currentRenderer, video); }
  updateVideoFrame(): void { inputBridge.updateVideoFrame(this.currentRenderer); }
  updateAudioData(bass: number, mid: number, treble: number): void { this.currentRenderer?.updateAudioData(bass, mid, treble); }
  updateAudioFrequencyBins(bins: Float32Array): void { this.currentRenderer?.updateAudioFrequencyBins?.(bins); }
  updateMouse(x: number, y: number): void { this.currentRenderer?.updateMouse(x, y); }

  setParam(name: string, value: number): void {
    this.currentRenderer?.setParam(name, value);
    if (name === 'agentCount') this.metrics.agentCount = Math.floor(value);
  }

  supportsShaderEffects(): boolean { return backendSupportsShaders(this.currentRenderer); }
  async loadShader(id: string, url: string, meta?: ShaderLoadMeta): Promise<boolean> {
    return this.loadShaderBound(id, url, meta);
  }
  async loadShaders(shaders: ShaderEntry[]): Promise<void> {
    return loadShadersForBackend(this.backend(), this.slotPolicy(), this.slotCallbacks(), shaders, this.loadShaderBound);
  }
  setActiveShader(id: string): void { setActiveShader(this.backend(), id); }
  setSlotShader(index: number, id: string): void { setSlotShader(this.backend(), this.slotPolicy(), index, id); }
  setSlotParams(slotIndex: number, p1: number, p2: number, p3: number, p4: number): void {
    setSlotParams(this.backend(), slotIndex, p1, p2, p3, p4);
  }
  updateSlotParams(params: import('./Renderer').SlotZoomParamsUpdate, slotIndex = 0): void {
    updateSlotParams(this.backend(), params, slotIndex);
  }
  syncAllSlotParams(slotParams: SlotParams[], maxSlots = SLOT_COUNT): void {
    syncAllSlotParams(this.backend(), slotParams, maxSlots);
  }
  async resyncShaderStack(options: {
    modes: RenderMode[];
    slotParams: SlotParams[];
    resolveShader: (shaderId: string) => ShaderEntry | undefined;
    inputSource?: InputSource;
  }): Promise<void> {
    return resyncShaderStack(
      this.backend(),
      this.slotPolicy(),
      this.slotCallbacks(),
      this.loadShaderBound,
      (source) => this.setInputSource(source),
      options,
    );
  }
  setSlotMode(index: number, mode: 'chained' | 'parallel'): void { setSlotMode(this.backend(), index, mode); }
  setInputSource(source: InputSource): void { inputBridge.setInputSource(this.currentRenderer, source); }
  getInputSource(): InputSource | null { return inputBridge.getInputSource(this.currentRenderer); }
  addRipple(x: number, y: number): void { addRipple(this.backend(), x, y); }
  addRipplePoint(x: number, y: number): void { this.addRipple(x, y); }
  clearRipples(): void { clearRipples(this.backend()); }
  async loadImage(url: string): Promise<string> { return inputBridge.loadImage(this.currentRenderer, url); }
  async loadImageFromURL(url: string): Promise<void> { await this.loadImage(url); }
  getAvailableModes(): ShaderEntry[] { return inputBridge.getAvailableModes(this.currentRenderer); }
  setImageList(urls: string[]): void { inputBridge.setImageList(this.currentRenderer, urls); }
  updateDepthMap(data: Float32Array, width: number, height: number): void {
    inputBridge.updateDepthMap(this.currentRenderer, data, width, height);
  }
  getSupportsDeepWorkgroup(): boolean { return this.currentRenderer?.getSupportsDeepWorkgroup?.() ?? false; }
  getFormatCapabilities(): DeviceFormatCapabilities { return this.perfState.formatCapabilities; }
  getSlotState(index: number) { return this.currentRenderer?.getSlotState?.(index) ?? null; }
  getGPUTimings(): GPUTimings {
    return this.currentRenderer?.getGPUTimings?.() ?? {
      parallelTime: 0, chainedTime: 0, totalTime: 0, available: false, timingSource: 'unavailable',
    };
  }
  firePlasma(x: number, y: number, vx: number, vy: number): void {
    firePlasmaOnBackend(this.currentRenderer, this.backend(), x, y, vx, vy);
  }
  async reloadShader(id: string, url: string): Promise<boolean> {
    return reloadShaderOnBackend(this.currentRenderer, this.backend(), id, url);
  }
  applyTestRenderState(state: Parameters<NonNullable<WebGPURenderer['applyTestRenderState']>>[0]): void {
    (this.currentRenderer as WebGPURenderer | null)?.applyTestRenderState?.(state);
  }
  getFrameImage(): string { return this.currentRenderer?.getFrameImage?.() ?? ''; }
  async refreshFrameImage(): Promise<string> {
    const r = this.currentRenderer as { refreshFrameImage?: () => Promise<string> } | null;
    if (r?.refreshFrameImage) return r.refreshFrameImage();
    return this.canvas ? this.canvas.toDataURL('image/png') : '';
  }
  async takeScreenshot(filename = 'screenshot.png'): Promise<void> {
    const r = this.currentRenderer as { takeScreenshot?: (f?: string) => Promise<void> } | null;
    if (r?.takeScreenshot) return r.takeScreenshot(filename);
    const dataUrl = await this.refreshFrameImage();
    if (!dataUrl) throw new Error('[RendererManager] Screenshot unavailable — no frame source');
    const a = document.createElement('a');
    a.href = dataUrl;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
  }
  setRecording(isRecording: boolean): void { this.currentRenderer?.setRecording?.(isRecording); }
  setRecordingMode(mode: 'loop' | 'continuous'): void { this.currentRenderer?.setRecordingMode?.(mode); }
  usesInternalRecording(): boolean { return this.isWASM(); }
  startRecording(canvas: HTMLCanvasElement, options?: { durationMs?: number; frameRate?: number; videoBitsPerSecond?: number }): Promise<Blob> {
    const r = this.currentRenderer as { startRecording?: typeof RendererManager.prototype.startRecording } | null;
    if (r?.startRecording) return r.startRecording(canvas, options);
    return Promise.reject(new Error('[RendererManager] startRecording not supported for active backend'));
  }
  stopRendererRecording(): void {
    (this.currentRenderer as { stopRecording?: () => void } | null)?.stopRecording?.();
  }
  getMetrics(): RendererMetrics { return this.metrics; }
  isWASM(): boolean { return this.metrics.isWASM; }
  getActiveRendererType(): RendererType {
    if (this.currentType) return this.currentType;
    if (this.metrics.isWASM) return 'wasm';
    if (this.backend()) return 'webgpu';
    return 'js';
  }
  getDevice(): GPUDevice | null {
    return this.getActiveRendererType() === 'webgpu' ? getAdoptedRendererDevice() : null;
  }
  getDiagnostics(): RendererDiagnostics {
    return buildRendererDiagnostics(
      this.getActiveRendererType(),
      this.metrics,
      this.currentRenderer,
      this.lastFailedWasmRenderer,
    );
  }
  render(..._args: unknown[]): void { if (this.metrics.isWASM) this.updateVideoFrame(); }
  getCurrentFPS(): number { return this.metrics.fps || 0; }
  setRenderQuality(mode: RenderQualityMode, hints?: { supportsDeepWorkgroup?: boolean; formatCaps?: DeviceFormatCapabilities }): void {
    this.applyQualityPolicy(mode, hints);
  }
  private applyQualityPolicy(mode: RenderQualityMode, hints?: { supportsDeepWorkgroup?: boolean; formatCaps?: DeviceFormatCapabilities }): void {
    applyQualityPolicy(this.perfState, mode, hints, () => this.getSupportsDeepWorkgroup());
    applyPerformancePolicyToRenderer(this.perfState, this.shaderRenderer(), this.adaptiveController);
  }
  releaseFp32Requirement(id: string): void {
    if (!releaseFp32Requirement(this.perfState, id)) return;
    if (this.perfState.fp32Pin.pinned) this.applyQualityPolicy(this.perfState.qualityMode);
  }
  getRenderQualityMode(): RenderQualityMode { return this.perfState.qualityMode; }
  getMaxActiveSlots(): number { return this.perfState.performancePolicy.maxActiveSlots; }
  getPerformanceStatus(): RendererPerformanceStatus {
    return buildPerformanceStatus(
      this.perfState,
      this.getActiveRendererType(),
      () => this.getCurrentFPS(),
      readResolutionScale(this.perfState, this.config, this.shaderRenderer()),
    );
  }
  getAudioData() {
    return (this.currentRenderer as { getAudioData?: () => { bass: number; mid: number; treble: number; freqBins: Float32Array } } | null)
      ?.getAudioData?.() ?? null;
  }
  isRecording(): boolean { return this.currentRenderer?.isRecording?.() ?? false; }
  destroy(): void {
    this.adaptiveController.stop();
    this.currentRenderer?.destroy();
    this.currentRenderer = null;
    this.currentType = null;
    this.metrics.isWASM = false;
    clearAdoptedRendererDevice();
  }
}
export default RendererManager;
