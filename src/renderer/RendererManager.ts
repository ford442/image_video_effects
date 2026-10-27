import { Renderer, RendererConfig, GPUTimings, UncappedBenchResult, DeviceLossInfo } from './Renderer';
import type { WASMRenderer } from './WASMRenderer';
import { isWasmBackend } from './wasmBackend';
import type { WebGPURenderer } from './WebGPURenderer';
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
import { listRuntimeGraphs, setRuntimeGraph as setRuntimeGraphOverlay, type RuntimeSimRingRequest } from './runtimeGraphs';
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
import { defaultSlotLayer, normalizeSlotLayer, slotLayersEqual, type SlotLayer } from './layerState';
import { MAX_RIPPLES } from './UniformBuffer';
import type { HdrToneMapSettings } from '../services/hdrOutput';

/** Ripples older than this are not replayed after a device loss (every catalog ripple has faded). */
export const RIPPLE_REPLAY_MAX_AGE_S = 10;
import type { DisplayP3Result } from './webgpuBootProbe';

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
  /** Opt-in graph node scales of the lost backend (`${slot}:${nodeId}` → scale). */
  private pendingNodeScales: Record<string, number> = {};
  /**
   * Session state the manager replays onto every rebuilt TS backend (backend switch or
   * device-loss recovery): per-slot compositing, the last depth map, source auto-exposure.
   */
  private slotLayers: SlotLayer[] = Array.from({ length: PHYSICAL_SLOT_LIMIT }, () => defaultSlotLayer());
  /** Chained/parallel as last set through the manager (a backend switch starts all-chained). */
  private slotModes: Array<'chained' | 'parallel'> = Array.from({ length: PHYSICAL_SLOT_LIMIT }, () => 'chained');
  private lastDepthMap: { data: Float32Array; width: number; height: number } | null = null;
  private sourceAutoExposure: boolean | null = null;
  private hdrToneMap: HdrToneMapSettings | null = null;
  /** Ripples added since the last clear (performance.now() stamps), for device-loss replay. */
  private rippleLog: Array<{ x: number; y: number; at: number }> = [];
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
    return isWebGpuBackend(r) || isWasmBackend(r) ? r : null;
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
    // A worker-owned canvas forces the old backend out before the new one inits, so
    // performBackendSwitch sees no previous renderer to keep or restore; remember it here.
    let releasedType: RendererType | null = null;
    // Read the CPU-side still before a transferred-canvas release drops the renderer.
    const cpuBitmap = inputBridge.readCpuInputBitmap(this.currentRenderer);
    if (this.acquireFreshCanvas && (transferred || changingType)) {
      if (transferred && this.currentRenderer) {
        await releaseRendererGpu(this.currentRenderer);
        releasedType = this.currentType;
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
      // Keep a failed WASM attempt's diagnostics across the restore switch.
      if (type === 'wasm') this.lastFailedWasmRenderer = null;
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
        // Before the stack: a slot may hold the Graph Lab draft, which a new worker has never seen.
        if (type === 'webgpu') this.reseedRuntimeGraphs();
        if (this.lastShaderStack) {
          await this.resyncShaderStack(this.lastShaderStack);
        }
        this.replaySessionExtras();
      }
      return true;
    }

    if (outcome.failedWasmRenderer) this.lastFailedWasmRenderer = outcome.failedWasmRenderer;
    this.currentRenderer = outcome.renderer;
    this.currentType = outcome.type;
    this.metrics.isWASM = outcome.isWASM;

    const restoreType =
      outcome.restoreType ?? (outcome.renderer === null && releasedType !== type ? releasedType : null);
    if (restoreType && options.restoreOnFailure !== false) {
      console.warn(`[RendererManager] Restoring previous renderer '${restoreType}' after ${type} init failure`);
      if (!(await this.switchRenderer(restoreType))) {
        console.warn(`[RendererManager] Restore of '${restoreType}' failed — renderer blocked`);
      }
    } else {
      console.warn(`[RendererManager] switchRenderer('${type}') failed — keeping previous renderer`);
    }
    return false;
  }

  /**
   * Re-send the page's runtime graphs (the Graph Lab draft) to a freshly built TS backend. The
   * page's overlay survives a backend switch, but a render worker's realm starts empty.
   */
  /**
   * Slot modes, compositor layers, the depth map and source auto-exposure live in the
   * manager, so any rebuilt backend (device-loss recovery included) gets them back (#1512).
   * Layers and auto-exposure are TS-only; WASM always composites as replace.
   */
  private replaySessionExtras(): void {
    const backend = this.backend();
    this.slotModes.forEach((mode, i) => {
      if (mode === 'parallel') setSlotMode(backend, i, mode);
    });
    if (this.lastDepthMap) {
      const { data, width, height } = this.lastDepthMap;
      inputBridge.updateDepthMap(this.currentRenderer, data, width, height);
    }
    const r = this.shaderRenderer();
    if (!isWebGpuBackend(r)) return;
    this.slotLayers.forEach((layer, i) => {
      if (!slotLayersEqual(layer, defaultSlotLayer())) r.setSlotLayer?.(i, layer);
    });
    if (this.sourceAutoExposure !== null) r.setSourceAutoExposure?.(this.sourceAutoExposure);
    if (this.hdrToneMap) r.setHdrToneMap?.(this.hdrToneMap);
  }

  private reseedRuntimeGraphs(): void {
    const r = this.shaderRenderer();
    if (!isWebGpuBackend(r)) return;
    for (const { id, graph, simRing } of listRuntimeGraphs()) r.setRuntimeGraph(id, graph, simRing);
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
      this.pendingNodeScales = captured.nodeScales;
      // The lost backend's modes are what was rendering; the switch replays them from the mirror.
      captured.slotModes.forEach((mode, i) => {
        this.slotModes[i] = mode;
      });
      captured.layers.forEach((layer, i) => {
        if (layer) this.slotLayers[i] = layer;
      });
    }
    // Ages are taken at the loss, so each ripple resumes where it froze, not after the rebuild.
    const lostAt = performance.now();
    const ok = await this.switchRenderer('webgpu', { restoreOnFailure: false });
    if (!ok || this.destroyed) return false;
    const r = this.shaderRenderer();
    if (isWebGpuBackend(r)) {
      r.restoreNodeScales?.(this.pendingNodeScales);
      const ripples = this.replayableRipples(lostAt);
      if (ripples.length > 0) r.restoreRipples?.(ripples);
    }
    this.pendingNodeScales = {};
    return true;
  }

  /** [x, y, ageSeconds] for each logged ripple still young enough to be visible. */
  private replayableRipples(now: number): Array<[number, number, number]> {
    return this.rippleLog
      .map(({ x, y, at }): [number, number, number] => [x, y, Math.max(0, (now - at) / 1000)])
      .filter(([, , age]) => age < RIPPLE_REPLAY_MAX_AGE_S);
  }

  /**
   * What the lost backend was rendering: its slot state (the ground truth, whoever set it),
   * shader URLs as they were loaded, and the host session's slot params. Null when there is
   * no backend left to read (a retry after a failed attempt reuses the earlier capture).
   */
  private captureLiveStack(): {
    stack: ShaderStackSnapshot;
    slotModes: Array<'chained' | 'parallel'>;
    layers: Array<SlotLayer | null>;
    nodeScales: Record<string, number>;
  } | null {
    const r = this.currentRenderer;
    if (!r) return null;
    const session = this.getSessionState?.() ?? null;
    const slots = Array.from({ length: PHYSICAL_SLOT_LIMIT }, (_, i) => r.getSlotState?.(i) ?? null);
    // Optional calls: capture runs on a backend that just died, and must never throw here.
    const nodeScales = isWebGpuBackend(r) ? r.getNodeScales?.() ?? {} : {};
    if (!slots.some(Boolean)) {
      return session
        ? { stack: { ...session, inputSource: this.lastInputSource }, slotModes: [], layers: [], nodeScales }
        : null;
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
      layers: slots.map((slot) => (slot?.layer ? normalizeSlotLayer(slot.layer) : null)),
      nodeScales,
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
  setSlotMode(index: number, mode: 'chained' | 'parallel'): void {
    if (index >= 0 && index < PHYSICAL_SLOT_LIMIT) this.slotModes[index] = mode;
    setSlotMode(this.backend(), index, mode);
  }
  /** Per-slot compositing (#1512). Kept here too, so a rebuilt backend gets it back. */
  setSlotLayer(index: number, layer: SlotLayer): void {
    if (index < 0 || index >= PHYSICAL_SLOT_LIMIT) return;
    const next = normalizeSlotLayer(layer);
    this.slotLayers[index] = next;
    const r = this.shaderRenderer();
    if (isWebGpuBackend(r)) r.setSlotLayer?.(index, next);
  }
  getSlotLayer(index: number): SlotLayer | null {
    const r = this.shaderRenderer();
    const fromBackend = isWebGpuBackend(r) ? r.getSlotLayer?.(index) ?? null : null;
    const layer = fromBackend ?? this.slotLayers[index];
    return layer ? { ...layer, mask: { ...layer.mask } } : null;
  }
  setInputSource(source: InputSource): void {
    this.lastInputSource = source;
    inputBridge.setInputSource(this.currentRenderer, source);
  }
  getInputSource(): InputSource | null {
    return inputBridge.getInputSource(this.currentRenderer) ?? this.lastInputSource;
  }
  addRipple(x: number, y: number): void {
    this.rippleLog.push({ x, y, at: performance.now() });
    if (this.rippleLog.length > MAX_RIPPLES) this.rippleLog.shift();
    addRipple(this.backend(), x, y);
  }
  addRipplePoint(x: number, y: number): void { this.addRipple(x, y); }
  clearRipples(): void {
    this.rippleLog = [];
    clearRipples(this.backend());
  }
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
    // A copy: callers may reuse their array, and the worker path transfers its own.
    this.lastDepthMap = { data: data.slice(), width, height };
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
  /**
   * Live Display P3 toggle. Null when the active backend has no TS canvas to
   * reconfigure (WASM / Canvas2D — the color opt-in is TS-first, Tier B freeze).
   */
  async setDisplayP3(enabled: boolean, isHdr: boolean): Promise<DisplayP3Result | null> {
    const r = this.currentRenderer as {
      setDisplayP3?: (e: boolean, hdr: boolean) => Promise<DisplayP3Result | null>;
    } | null;
    return (await r?.setDisplayP3?.(enabled, isHdr)) ?? null;
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
  /** The `// @requires f16` half path (TS WebGPU). Recompiles on the next shader load. */
  setShaderF16Enabled(enabled: boolean): void {
    const r = this.shaderRenderer();
    if (isWebGpuBackend(r)) r.setShaderF16Enabled?.(enabled);
  }
  /** Direct-to-swapchain present (TS WebGPU, bgra8unorm-storage) on / off. */
  setDirectPresentEnabled(enabled: boolean): void {
    const r = this.shaderRenderer();
    if (isWebGpuBackend(r)) r.setDirectPresentEnabled?.(enabled);
  }
  getShaderPrecisionInfo(): import('./WebGPURenderer').ShaderPrecisionInfo | null {
    const r = this.shaderRenderer();
    return isWebGpuBackend(r) ? r.getShaderPrecisionInfo?.() ?? null : null;
  }
  /** HDR canvas tonemap (paper white / peak nits); used only while the canvas is HDR. */
  setHdrToneMap(settings: HdrToneMapSettings): void {
    this.hdrToneMap = { ...settings };
    const r = this.shaderRenderer();
    if (isWebGpuBackend(r)) r.setHdrToneMap?.(settings);
  }
  setSourceAutoExposure(enabled: boolean): void {
    this.sourceAutoExposure = enabled;
    const r = this.shaderRenderer();
    if (r && 'setSourceAutoExposure' in r) {
      (r as WebGPUBackendApi).setSourceAutoExposure(enabled);
    }
  }
  /** Smoothed per-pass GPU ms from the TS or C++ profiler (empty until timestamps resolve, or on JS). */
  getPassTimings(): PassTiming[] {
    const r = this.shaderRenderer();
    if (isWebGpuBackend(r)) return r.getPassTimings();
    if (isWasmBackend(r)) return r.getPassTimings();
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
   * `simRing` sizes the group-1 ring when one of the graph's group-1 entries next
   * compiles; entries that do not declare @group(1) never get it bound.
   * Returns false when the active backend cannot run graphs.
   */
  setRuntimeGraph(id: string, graph: MultipassGraphDef | null, simRing: RuntimeSimRingRequest | null = null): boolean {
    const r = this.shaderRenderer();
    if (!isWebGpuBackend(r)) return false;
    setRuntimeGraphOverlay(id, graph, simRing);
    r.setRuntimeGraph(id, graph, simRing);
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
