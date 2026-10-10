import { Renderer, RendererConfig, GPUTimings, UncappedBenchResult, DeviceLossInfo } from './Renderer';
import { WASMRenderer } from './WASMRenderer';
import { WebGPURenderer } from './WebGPURenderer';
import { InputSource, RenderMode, ShaderEntry, SlotParams } from './types';
import { AdaptivePerformanceController } from './adaptivePerformance';
import {
  RendererType,
  getRendererTypeFromURL,
  performBackendSwitch,
  releaseRendererGpu,
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
  framePassBudgetFor,
  readResolutionScale,
  refreshFormatCapabilities,
  registerFp32Requirement,
  releaseFp32Requirement,
} from './performanceStatus';
import { isCanvasTransferred, WorkerWebGPUBackend } from './worker/WorkerWebGPUBackend';
import { isWebGpuBackend, type WebGPUBackendApi } from './webgpuBackendApi';
import type { PassTiming } from './passTimings';
import type { MultipassGraphDef } from './multipassGraph';
import { setRuntimeGraph as setRuntimeGraphOverlay } from './runtimeGraphs';
import {
  ShaderLoadMeta,
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
import { getDeviceGeneration, getRendererDevice, isRendererDeviceLive } from './deviceRegistry';
import { getLiveDeviceCount } from './webgpuBootProbe';
import { DeviceRecoveryController, type DeviceRecoveryStatus } from './deviceRecovery';
import { PHYSICAL_SLOT_LIMIT } from './slotOrchestrator';

export type { RendererType, RendererInitOptions, WebGpuProbeHandoff };
export { getRendererTypeFromURL };
export type { RendererPerformanceStatus, ShaderLoadMeta };
export type { RendererMetrics, RendererDiagnostics } from './rendererTypes';
export type { DeviceRecoveryStatus } from './deviceRecovery';

/** The live session a recovered backend replays (same shape as resyncShaderStack's input). */
export interface ShaderStackSnapshot {
  modes: RenderMode[];
  slotParams: SlotParams[];
  resolveShader: (shaderId: string) => ShaderEntry | undefined;
  inputSource?: InputSource;
}

/** switchRenderer knobs. */
export interface SwitchRendererOptions {
  /** On failure, re-init the previous backend type (default true). Recovery passes false. */
  restoreOnFailure?: boolean;
}

/** Optional RendererManager callbacks. */
export interface RendererManagerOptions {
  /**
   * The active backend stopped at runtime and no fallback backend could take over.
   * The renderer is blocked; the host should surface the WebGPU-required overlay.
   */
  onBackendFailure?: (failedType: RendererType, message: string) => void;
  /**
   * Swap in a new <canvas> and resolve with it. Needed once the render worker
   * owns the current canvas (#1314): switching to WASM / Canvas2D, or retrying
   * on the page after a worker failure.
   */
  acquireFreshCanvas?: () => Promise<HTMLCanvasElement>;
  /** The live shader stack, replayed onto the backend rebuilt after a GPUDevice loss. */
  getSessionState?: () => ShaderStackSnapshot | null;
  /** Device-loss recovery state changes (lost → recovering → idle | failed). */
  onDeviceRecovery?: (status: DeviceRecoveryStatus) => void;
}

export class RendererManager {
  private currentRenderer: Renderer | null = null;
  private currentType: RendererType | null = null;
  private lastFailedWasmRenderer: WASMRenderer | null = null;
  private lastImageUrl: string | null = null;
  private lastInputSource: InputSource = 'image';
  private lastShaderStack: ShaderStackSnapshot | null = null;
  private readonly getSessionState?: RendererManagerOptions['getSessionState'];
  private readonly deviceRecovery: DeviceRecoveryController;
  /** Chained/parallel per slot, captured from the lost backend and re-applied after recovery. */
  private pendingSlotModes: Array<'chained' | 'parallel'> = [];
  private readonly config: RendererConfig;
  private canvas: HTMLCanvasElement | null = null;
  private webGpuHandoff: WebGpuProbeHandoff | undefined;
  private metrics: RendererMetrics = { fps: 0, frameTime: 0, agentCount: 0, isWASM: false };
  private readonly onMetricsUpdate?: (metrics: RendererMetrics) => void;
  private readonly onBackendFailure?: RendererManagerOptions['onBackendFailure'];
  private readonly acquireFreshCanvas?: RendererManagerOptions['acquireFreshCanvas'];
  /** 'main' after the render worker failed for this manager (#1314). */
  private renderThreadOverride: 'main' | 'worker' | null = null;
  private metricsRafId: number | null = null;
  private destroyed = false;
  private readonly perfState: PerformancePolicyState = createPerformancePolicyState();
  private readonly adaptiveController: AdaptivePerformanceController;

  constructor(
    config: RendererConfig,
    onMetricsUpdate?: (metrics: RendererMetrics) => void,
    options: RendererManagerOptions = {},
  ) {
    this.config = config;
    this.onMetricsUpdate = onMetricsUpdate;
    this.onBackendFailure = options.onBackendFailure;
    this.acquireFreshCanvas = options.acquireFreshCanvas;
    this.getSessionState = options.getSessionState;
    this.deviceRecovery = new DeviceRecoveryController({
      recover: () => this.reinitAfterDeviceLoss(),
      describeFailure: () => (typeof window !== 'undefined' ? window.webgpuProbe?.lastError ?? null : null),
      onStatus: options.onDeviceRecovery,
      onFailed: (message) => {
        if (!this.destroyed) this.onBackendFailure?.('webgpu', message);
      },
    });
    this.adaptiveController = new AdaptivePerformanceController({
      getFps: () => this.getCurrentFPS(),
      getScale: () => this.perfState.resolutionScale,
      setScale: (scale) => applyResolutionScaleToRenderer(this.perfState, this.shaderRenderer(), scale),
      // #1314: shrink one expensive opt-in graph node before the whole canvas.
      getPassTimings: () => this.getPassTimings(),
      getScalableNodes: () => {
        const r = this.shaderRenderer();
        return isWebGpuBackend(r) ? r.getScalableNodes() : [];
      },
      setNodeScale: (slot, nodeId, scale) => {
        this.setNodeScale(slot, nodeId, scale);
      },
    });
  }

  private shaderRenderer(): WebGPUBackendApi | WASMRenderer | null {
    const r = this.currentRenderer;
    return isWebGpuBackend(r) || r instanceof WASMRenderer ? r : null;
  }

  private backend() {
    return resolveShaderBackend(this.currentRenderer);
  }

  /** Test-mode only: lift the quality slot cap (SwiftShader reports no deep workgroups → 1 slot). */
  private slotCapOverride: number | null = null;

  overrideSlotCapForTests(cap: number | null): void {
    this.slotCapOverride = cap;
    const r = this.shaderRenderer();
    if (isWebGpuBackend(r)) {
      r.setFramePassBudget(framePassBudgetFor(this.perfState.performancePolicy, cap));
    }
  }

  /**
   * Test-mode only: pin the internal resolution scale (adaptive quality off).
   * Each change reallocates the working textures, so feedback state starts from zero.
   */
  setResolutionScaleForTests(scale: number): void {
    applyResolutionScaleToRenderer(this.perfState, this.shaderRenderer(), scale);
  }

  private slotPolicy() {
    return {
      maxActiveSlots: this.slotCapOverride ?? this.perfState.performancePolicy.maxActiveSlots,
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

  /** Where each loaded shader came from, so a rebuilt backend can load the same WGSL. */
  private readonly shaderSources = new Map<string, { url: string; meta?: ShaderLoadMeta }>();

  private loadShaderBound = (id: string, url: string, meta?: ShaderLoadMeta) => {
    this.shaderSources.set(id, { url, meta });
    return loadShaderForBackend(this.backend(), this.slotPolicy(), this.slotCallbacks(), id, url, meta);
  };

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
    if (isCanvasTransferred(this.canvas) && this.acquireFreshCanvas && this.renderThreadOverride !== 'main') {
      // The worker took the canvas but could not render (probe / init failed there):
      // one retry on the page with a fresh canvas before giving up.
      console.warn('[RendererManager] Render worker failed after taking the canvas — retrying on the page');
      this.renderThreadOverride = 'main';
      if (await this.switchRenderer('webgpu')) return true;
    }
    console.warn('⚠️ WebGPU unavailable — renderer blocked (no automatic Canvas2D fallback)');
    return false;
  }

  async switchRenderer(type: RendererType, options: SwitchRendererOptions = {}): Promise<boolean> {
    if (!this.canvas) return false;
    // A canvas is bound to its first context type ('webgpu' or '2d') and, once
    // the render worker took it (#1314), to the worker. Switching backend type
    // therefore starts on a fresh <canvas> whenever the host can provide one.
    const transferred = isCanvasTransferred(this.canvas);
    const changingType = this.currentType !== null && this.currentType !== type;
    if (transferred && !this.acquireFreshCanvas) {
      console.warn(
        `[RendererManager] switchRenderer('${type}') refused: the canvas belongs to the render worker ` +
          '(reload with ?renderer=main to switch backends)',
      );
      return false;
    }
    // Read the CPU-side still before a transferred-canvas release drops the renderer.
    const cpuBitmap = inputBridge.readCpuInputBitmap(this.currentRenderer);
    if (this.acquireFreshCanvas && (transferred || changingType)) {
      if (transferred && this.currentRenderer) {
        await releaseRendererGpu(this.currentRenderer);
        this.currentRenderer = null;
        this.currentType = null;
      }
      this.canvas = await this.acquireFreshCanvas();
    }
    const handoff = type === 'webgpu' ? this.webGpuHandoff : undefined;
    if (type === 'wasm') {
      console.warn(
        '[RendererManager] Exclusive JS→WASM switch: hard-reload if this tab already allocated a 2048² historyTex (~512MB) before a second device',
      );
    }
    const outcome = await performBackendSwitch({
      targetType: type,
      renderThread: this.renderThreadOverride ?? undefined,
      canvas: this.canvas,
      config: this.config,
      previousType: this.currentType,
      previousRenderer: this.currentRenderer,
      webGpuHandoff: handoff,
    });
    if (type === 'webgpu') this.webGpuHandoff = undefined;

    if (outcome.success) {
      this.currentRenderer = outcome.renderer;
      this.currentType = outcome.type;
      this.canvas = outcome.canvas;
      this.metrics.isWASM = outcome.isWASM;
      this.lastFailedWasmRenderer = null;
      refreshFormatCapabilities(this.perfState, this.shaderRenderer());
      applyPerformancePolicyToRenderer(this.perfState, this.shaderRenderer(), this.adaptiveController);
      this.installFatalErrorHandler(outcome.renderer, outcome.type);
      this.startMetricsCollection();
      if (type === 'wasm' || type === 'webgpu') {
        await inputBridge.rebindMediaAfterBackendSwitch(this.currentRenderer, {
          inputSource: this.lastInputSource,
          imageUrl: this.lastImageUrl,
          bitmap: cpuBitmap,
          presentCanvas: this.canvas,
          logUpload: type === 'wasm',
        });
        if (this.lastShaderStack) {
          await this.resyncShaderStack(this.lastShaderStack);
        }
      }
      return true;
    }

    if (outcome.failedWasmRenderer) this.lastFailedWasmRenderer = outcome.failedWasmRenderer;
    this.currentRenderer = outcome.renderer;
    this.currentType = outcome.type;
    this.metrics.isWASM = outcome.isWASM;

    if (outcome.restoreType && options.restoreOnFailure !== false) {
      console.warn(`[RendererManager] Restoring previous renderer '${outcome.restoreType}' after ${type} init failure`);
      if (!(await this.switchRenderer(outcome.restoreType))) {
        console.warn(`[RendererManager] Restore of '${outcome.restoreType}' failed — renderer blocked`);
      }
    } else {
      console.warn(`[RendererManager] switchRenderer('${type}') failed — keeping previous renderer`);
    }
    return false;
  }

  /**
   * A backend that stops at runtime (e.g. the WASM loop after repeated errors) falls back to
   * the TS WebGPU renderer; if that also fails the host is told the renderer is blocked.
   */
  private installFatalErrorHandler(renderer: Renderer | null, type: RendererType | null): void {
    if (!renderer?.setFatalErrorHandler || !type) return;
    renderer.setFatalErrorHandler((message, info) => {
      if (this.destroyed || this.currentRenderer !== renderer) return;
      if (type === 'webgpu' && (info?.kind === 'device-lost' || info?.kind === 'worker-died')) {
        this.handleDeviceLoss(info);
        return;
      }
      void this.handleBackendFailure(type, message);
    });
  }

  /**
   * A TS WebGPU backend lost its GPUDevice at runtime, or its render worker crashed:
   * recover it (never fall back). The backend already cleared the device registry.
   */
  private handleDeviceLoss(info: DeviceLossInfo): void {
    console.warn(`[RendererManager] GPU device lost (${info.reason}) — rebuilding the WebGPU renderer`);
    this.stopMetricsCollection();
    this.deviceRecovery.handleLoss(info);
  }

  /**
   * Rebuild the TS WebGPU backend after a device loss (or retry a failed rebuild). Resolves
   * true when it renders again with the session's shader stack, params and still image.
   */
  recoverFromDeviceLoss(): Promise<boolean> {
    return this.deviceRecovery.retry();
  }

  getDeviceRecoveryStatus(): DeviceRecoveryStatus {
    return this.deviceRecovery.getStatus();
  }

  /** Test hook (?testMode=1 via __pixelocity__): lose the TS WebGPU device on purpose. */
  simulateDeviceLoss(): boolean {
    const r = this.currentRenderer;
    return isWebGpuBackend(r) ? r.simulateDeviceLoss() : false;
  }

  /** Test hook (?testMode=1 via __pixelocity__): crash the render worker (worker mode only). */
  simulateWorkerCrash(): boolean {
    const r = this.currentRenderer;
    return r instanceof WorkerWebGPUBackend ? r.simulateWorkerCrash() : false;
  }

  /**
   * webgpu → webgpu switch: releases the dead backend (worker: dispose + terminate, then a
   * fresh canvas and a new worker), reruns the boot probe in the new backend's init, then
   * replays media + the live shader stack. No other device is requested and no other
   * backend type is tried.
   */
  private async reinitAfterDeviceLoss(): Promise<boolean> {
    if (this.destroyed) return false;
    // A failed attempt released the dead backend: keep replaying what was captured from it.
    const captured = this.captureLiveStack();
    if (captured) {
      this.lastShaderStack = captured.stack;
      this.pendingSlotModes = captured.slotModes;
    }
    const ok = await this.switchRenderer('webgpu', { restoreOnFailure: false });
    if (!ok || this.destroyed) return false;
    this.pendingSlotModes.forEach((mode, i) => {
      if (mode === 'parallel') this.setSlotMode(i, mode);
    });
    this.pendingSlotModes = [];
    return true;
  }

  /**
   * What the lost backend was rendering: its slot state (the ground truth, whoever set it),
   * shader URLs as they were loaded, and the host session's slot params. Null when there is
   * no backend left to read (a retry after a failed attempt reuses the earlier capture).
   */
  private captureLiveStack(): { stack: ShaderStackSnapshot; slotModes: Array<'chained' | 'parallel'> } | null {
    const r = this.currentRenderer;
    if (!r) return null;
    const session = this.getSessionState?.() ?? null;
    const slots = Array.from({ length: PHYSICAL_SLOT_LIMIT }, (_, i) => r.getSlotState?.(i) ?? null);
    if (!slots.some(Boolean)) {
      return session ? { stack: { ...session, inputSource: this.lastInputSource }, slotModes: [] } : null;
    }
    const resolveShader = (id: string): ShaderEntry | undefined => {
      const source = this.shaderSources.get(id);
      if (source) return { id, name: id, url: source.url, category: 'image', ...source.meta } as ShaderEntry;
      return session?.resolveShader(id);
    };
    return {
      stack: {
        modes: slots.map((slot) => (slot?.enabled && slot.shaderId ? slot.shaderId : 'none') as RenderMode),
        slotParams: session?.slotParams ?? [],
        resolveShader,
        inputSource: this.lastInputSource,
      },
      slotModes: slots.map((slot) => slot?.mode ?? 'chained'),
    };
  }

  private async handleBackendFailure(type: RendererType, message: string): Promise<void> {
    console.warn(`[RendererManager] ${type} backend stopped: ${message}`);
    if (type !== 'webgpu' && (await this.switchRenderer('webgpu'))) {
      console.warn('[RendererManager] Fell back to the TypeScript WebGPU renderer');
      return;
    }
    if (this.destroyed) return;
    this.onBackendFailure?.(type, message);
  }

  private refreshFps(): void {
    const fps = this.currentRenderer?.getFPS?.();
    if (typeof fps === 'number') this.metrics.fps = fps;
  }

  /** At most one metrics loop, and none when nobody listens (FPS is read lazily instead). */
  private startMetricsCollection(): void {
    this.stopMetricsCollection();
    if (!this.onMetricsUpdate) return;
    const tick = () => {
      this.refreshFps();
      this.onMetricsUpdate?.(this.metrics);
      this.metricsRafId = requestAnimationFrame(tick);
    };
    tick();
  }

  private stopMetricsCollection(): void {
    if (this.metricsRafId !== null) {
      cancelAnimationFrame(this.metricsRafId);
      this.metricsRafId = null;
    }
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
  syncAllSlotParams(slotParams: SlotParams[], maxSlots = PHYSICAL_SLOT_LIMIT): void {
    syncAllSlotParams(this.backend(), slotParams, maxSlots);
  }
  async resyncShaderStack(options: {
    modes: RenderMode[];
    slotParams: SlotParams[];
    resolveShader: (shaderId: string) => ShaderEntry | undefined;
    inputSource?: InputSource;
  }): Promise<void> {
    this.lastShaderStack = options;
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
  setInputSource(source: InputSource): void {
    this.lastInputSource = source;
    inputBridge.setInputSource(this.currentRenderer, source);
  }
  getInputSource(): InputSource | null {
    return inputBridge.getInputSource(this.currentRenderer) ?? this.lastInputSource;
  }
  addRipple(x: number, y: number): void { addRipple(this.backend(), x, y); }
  addRipplePoint(x: number, y: number): void { this.addRipple(x, y); }
  clearRipples(): void { clearRipples(this.backend()); }
  async loadImage(url: string): Promise<string> {
    this.lastImageUrl = url;
    const resolved = await inputBridge.loadImage(this.currentRenderer, url);
    if (resolved) this.lastImageUrl = resolved;
    return resolved;
  }
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
    const meta = this.shaderSources.get(id)?.meta;
    this.shaderSources.set(id, { url, meta });
    return reloadShaderOnBackend(this.currentRenderer, this.backend(), id, url);
  }
  applyTestRenderState(state: Parameters<NonNullable<WebGPURenderer['applyTestRenderState']>>[0]): void {
    (isWebGpuBackend(this.currentRenderer) ? this.currentRenderer : null)?.applyTestRenderState(state);
  }
  getFrameImage(): string { return this.currentRenderer?.getFrameImage?.() ?? ''; }
  async refreshFrameImage(): Promise<string> {
    const r = this.currentRenderer;
    if (r?.refreshFrameImage) return r.refreshFrameImage();
    return this.canvas ? this.canvas.toDataURL('image/png') : '';
  }
  async takeScreenshot(filename = 'screenshot.png'): Promise<void> {
    const r = this.currentRenderer;
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
    const r = this.currentRenderer;
    if (r?.startRecording) return r.startRecording(canvas, options);
    return Promise.reject(new Error('[RendererManager] startRecording not supported for active backend'));
  }
  /** Canvas → VideoFrame capture is usable (swapchain accepts COPY_SRC; TS boot probe or C++ init probe). */
  supportsCanvasFrameCapture(): boolean {
    return !!this.currentRenderer?.supportsCanvasCopySrc?.();
  }
  /**
   * Render worker (#1314): a function returning a VideoFrame of the next
   * presented frame, taken in the worker and transferred. Null when the
   * backend renders on the page (record from the canvas instead).
   */
  getWorkerFrameGrabber(): ((timestampUs: number) => Promise<VideoFrame | null>) | null {
    const r = this.currentRenderer;
    if (!isWebGpuBackend(r) || r.renderThread !== 'worker') return null;
    return r.grabVideoFrame?.bind(r) ?? null;
  }
  /** Where the TS backend renders (main page or render worker); null for WASM / Canvas2D. */
  getRenderThread(): 'main' | 'worker' | null {
    const r = this.currentRenderer;
    return isWebGpuBackend(r) ? r.renderThread : null;
  }
  setCanvasCopySrc(enabled: boolean): boolean {
    return this.currentRenderer?.setCanvasCopySrc?.(enabled) ?? false;
  }
  stopRendererRecording(): void {
    this.currentRenderer?.stopRecording?.();
  }
  getMetrics(): RendererMetrics {
    this.refreshFps();
    return this.metrics;
  }
  isWASM(): boolean { return this.metrics.isWASM; }
  getActiveRendererType(): RendererType {
    if (this.currentType) return this.currentType;
    if (this.metrics.isWASM) return 'wasm';
    if (this.backend()) return 'webgpu';
    return 'js';
  }
  /** The renderer's page-thread device (null in worker mode, on WASM / Canvas2D, or while lost). */
  getDevice(): GPUDevice | null {
    return getRendererDevice();
  }
  getDiagnostics(): RendererDiagnostics {
    this.refreshFps();
    return {
      ...buildRendererDiagnostics(
        this.getActiveRendererType(),
        this.metrics,
        this.currentRenderer,
        this.lastFailedWasmRenderer,
      ),
      deviceRecovery: this.deviceRecovery.getStatus(),
      deviceGeneration: getDeviceGeneration(),
      liveGpuDevices: this.getLiveGpuDevices(),
    };
  }

  /** GPUDevices alive on this page and in the current render worker (1 while rendering). */
  getLiveGpuDevices(): number {
    const r = this.currentRenderer;
    return getLiveDeviceCount() + (r instanceof WorkerWebGPUBackend ? r.getLiveGpuDevices() : 0);
  }
  /** Per-frame host tick: uploads video frames on WASM (TS WebGPU drives its own loop). */
  render(): void { if (this.metrics.isWASM) this.updateVideoFrame(); }
  getCurrentFPS(): number {
    this.refreshFps();
    return this.metrics.fps || 0;
  }
  setRenderQuality(mode: RenderQualityMode, hints?: { supportsDeepWorkgroup?: boolean; formatCaps?: DeviceFormatCapabilities }): void {
    this.applyQualityPolicy(mode, hints);
  }
  setSourceAutoExposure(enabled: boolean): void {
    const r = this.shaderRenderer();
    if (r && 'setSourceAutoExposure' in r) {
      (r as WebGPUBackendApi).setSourceAutoExposure(enabled);
    }
  }
  /** Smoothed per-pass GPU ms from the TS or C++ profiler (empty until timestamps resolve, or on JS). */
  getPassTimings(): PassTiming[] {
    const r = this.shaderRenderer();
    if (isWebGpuBackend(r)) return r.getPassTimings();
    if (r instanceof WASMRenderer) return r.getPassTimings();
    return [];
  }
  /** Bench only (#1080): vsync-free ms/frame from the active TS or C++ backend. */
  async benchmarkUncapped(frames: number): Promise<UncappedBenchResult | null> {
    return (await this.shaderRenderer()?.benchmarkUncapped?.(frames)) ?? null;
  }
  /**
   * Register (or, with `null`, drop) a runtime Tier C graph under `id` — the Graph
   * Lab draft (TS WebGPU only; WASM stays frozen). The main-thread overlay is set
   * even when the renderer runs in the worker, because shader loading and badges
   * resolve graphs on this thread; the backend call then reaches the worker's copy.
   * Pass a fresh graph object per edit: plans are memoised per object.
   * Returns false when the active backend cannot run graphs.
   */
  setRuntimeGraph(id: string, graph: MultipassGraphDef | null): boolean {
    const r = this.shaderRenderer();
    if (!isWebGpuBackend(r)) return false;
    setRuntimeGraphOverlay(id, graph);
    r.setRuntimeGraph(id, graph);
    return true;
  }
  /** Run an opt-in graph node below full size (TS WebGPU only). Returns the scale in effect. */
  setNodeScale(slot: number, nodeId: string, scale: number): number {
    const r = this.shaderRenderer();
    return isWebGpuBackend(r) ? r.setNodeScale(slot, nodeId, scale) : 1;
  }
  /**
   * True while a TS backend holds a device, on this thread or in the render worker
   * (where getDevice() is null), and while a lost one is being rebuilt. Lets depth
   * estimation stay off WebGPU instead of opening a second device in the gap.
   */
  isGpuDeviceActive(): boolean {
    const recovery = this.deviceRecovery.getStatus().state;
    return isRendererDeviceLive() || recovery === 'lost' || recovery === 'recovering';
  }
  /** True when the TS backend already holds a compiled pipeline for `id`. */
  isShaderCached(id: string): boolean {
    const r = this.shaderRenderer();
    return isWebGpuBackend(r) ? r.isShaderCached(id) : false;
  }
  /** Pre-compile pipelines the user is about to pick (TS WebGPU only; no-op elsewhere). */
  warmShaders(entries: Array<{ id: string; url: string }>): void {
    const r = this.shaderRenderer();
    if (isWebGpuBackend(r)) r.warmShaders(entries);
  }
  async captureThumbnailPng(outSize: number): Promise<string | null> {
    const r = this.shaderRenderer();
    if (r && 'captureChoresThumbnailPng' in r) {
      return (r as WebGPUBackendApi).captureChoresThumbnailPng(outSize);
    }
    return null;
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
    const shader = this.shaderRenderer();
    const historyLayers =
      isWebGpuBackend(shader) ? shader.getHistoryLayers() : undefined;
    const workingSizeCap =
      isWebGpuBackend(shader) ? shader.getWorkingSizeCap() : undefined;
    return buildPerformanceStatus(
      this.perfState,
      this.getActiveRendererType(),
      () => this.getCurrentFPS(),
      readResolutionScale(this.perfState, this.config, shader),
      { historyLayers, workingSizeCap },
    );
  }
  getAudioData() {
    return this.currentRenderer?.getAudioData?.() ?? null;
  }
  isRecording(): boolean { return this.currentRenderer?.isRecording?.() ?? false; }
  /** Resolves once the backend has released its GPU device (safe to re-probe after). */
  async destroy(): Promise<void> {
    this.destroyed = true;
    this.deviceRecovery.dispose();
    // A recovery mid-switch may still create a backend: release that one, not a stale handle.
    await this.deviceRecovery.whenSettled();
    this.stopMetricsCollection();
    this.adaptiveController.stop();
    const renderer = this.currentRenderer;
    this.currentRenderer = null;
    this.currentType = null;
    this.metrics.isWASM = false;
    if (renderer) await releaseRendererGpu(renderer);
  }
}
export default RendererManager;
