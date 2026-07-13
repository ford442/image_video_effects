import type { InputSource, ShaderEntry } from './types';

// Slot execution mode for inter-shader parallelization
type SlotMode = 'chained' | 'parallel';

/** Aggregate zoom-param update (UI slider form). */
export type SlotZoomParamsUpdate = {
  zoomParam1?: number;
  zoomParam2?: number;
  zoomParam3?: number;
  zoomParam4?: number;
};

/** How getGPUTimings() values were produced. */
export type GPUTimingSource = 'gpu-timestamp' | 'wall-clock' | 'unavailable';

export interface GPUTimings {
  parallelTime: number;
  chainedTime: number;
  totalTime: number;
  /** True when GPU timestamp queries produced the numbers (TS WebGPU only). */
  available: boolean;
  /** Wall-clock timings may be present even when available is false (WASM path). */
  timingSource: GPUTimingSource;
}

/** Diagnostic information from the WASM renderer. */
export interface WASMDiagnostics {
  initialized: boolean;
  initAttempts: number;
  errorCount: number;
  lastErrorTime: string | null;
  fps: number;
  hasModule: boolean;
  adapterInfo: string;
  /** WebGPURenderer::InitStage of the last Initialize() attempt (0=None, 8=Ready). */
  failedStage: number;
  /** Human-readable reason for the last Initialize() failure, or '' if none. */
  lastInitError: string;
  /** InitStage name from C++ (e.g. 'Device', 'Surface'). */
  failedStageName: string;
  /** Bridge-layer load/init failures (from wasm_bridge.js getDiagnostics). */
  loadErrorCount: number;
  lastLoadError: string | null;
  initTime: string;
}

/** Diagnostic snapshot from the TypeScript WebGPU renderer. */
export interface WebGPUDiagnostics {
  initialized: boolean;
  lastInitError: string;
  adapterSummary: string;
  adapterAttemptLabel: string | null;
  supportsDeepWorkgroup: boolean;
  supportsSubgroups: boolean;
  fps: number;
}

export type RendererDiagnosticsSnapshot = WASMDiagnostics | WebGPUDiagnostics;

export interface RendererTestState {
  time?: number;
  mouseX?: number;
  mouseY?: number;
  mouseDown?: boolean;
  bass?: number;
  mid?: number;
  treble?: number;
}

export interface RecordingOptions {
  durationMs?: number;
  frameRate?: number;
  videoBitsPerSecond?: number;
}

export interface RendererAudioData {
  bass: number;
  mid: number;
  treble: number;
  freqBins: Float32Array;
}

/** Shader-slot backends (WebGPU + WASM). Canvas2D does not implement these. */
export interface ShaderSlotRenderer {
  loadShader(id: string, url: string): Promise<boolean>;
  setActiveShader(id: string): void;
  setSlotShader(index: number, id: string): void;
  setSlotParams?(slotIndex: number, p1: number, p2: number, p3: number, p4: number): void;
  updateSlotParams(params: SlotZoomParamsUpdate, slotIndex?: number): void;
  setSlotMode(index: number, mode: SlotMode): void;
  addRipple(x: number, y: number): void;
  clearRipples(): void;
}

/**
 * Canonical renderer contract implemented by WebGPURenderer, WASMRenderer, and JSRenderer.
 * Optional methods are backend-specific extensions; RendererManager forwards when present.
 */
export interface IRenderer {
  init(canvas: HTMLCanvasElement): Promise<boolean>;
  render(): void;
  destroy(): void;

  // Video input
  setVideo(video: HTMLVideoElement | undefined): void;
  getVideo?(): HTMLVideoElement | null;
  updateVideoFrame(): void;

  // Audio input
  updateAudioData(bass: number, mid: number, treble: number): void;
  /**
   * Push a full N-bin FFT magnitude array from the audio source (e.g. flac_player).
   * Values should be normalised to [0, 1]. Bins are written into
   * extraBuffer[5 .. 5+N-1] so that WGSL shaders can access them as:
   *   extraBuffer[5 + binIndex]
   * N should be ≤ 251 (EXTRA_FLOATS=256 minus the first 5 reserved slots).
   * The canonical size used by useAudioAnalyzer is 128.
   */
  updateAudioFrequencyBins?(bins: Float32Array): void;

  // Mouse input
  updateMouse(x: number, y: number): void;

  // Parameters
  setParam(name: string, value: number): void;

  // Input source selection (for generative/procedural, image, video, webcam, or live)
  setInputSource?: (source: InputSource) => void;
  getInputSource?: () => InputSource;

  // Slot management with parallelization support
  setSlotMode?: (index: number, mode: SlotMode) => void;
  getSlotMode?: (index: number) => SlotMode | null;
  getSlotState?: (index: number) => { shaderId: string | null; enabled: boolean; mode: SlotMode } | null;
  getGPUTimings?: () => GPUTimings;
  /** Returns true when the GPU supports 16×16×4 (1024-invocation) workgroups. */
  getSupportsDeepWorkgroup?: () => boolean;

  setImageList?: (urls: string[]) => void;
  updateDepthMap?: (data: Float32Array, width: number, height: number) => void;
  getAvailableModes?: () => ShaderEntry[];
  loadImage?: (url: string) => Promise<string>;
  loadImageFromURL?: (url: string) => Promise<void>;
  getFrameImage?: () => string;
  refreshFrameImage?: () => Promise<string>;
  applyMask?: (maskType: string) => void;
  setMaskEnabled?: (enabled: boolean) => void;
  setRecording?: (isRecording: boolean) => void;
  setRecordingMode?: (mode: 'loop' | 'continuous') => void;
  getAudioData?: () => RendererAudioData;
  isRecording?: () => boolean;
  loadShader?: (id: string, url: string) => Promise<boolean>;
  setActiveShader?: (id: string) => void;
  setSlotShader?: (index: number, id: string) => void;
  setSlotParams?: (slotIndex: number, p1: number, p2: number, p3: number, p4: number) => void;
  updateSlotParams?: (params: SlotZoomParamsUpdate, slotIndex?: number) => void;
  addRipple?: (x: number, y: number) => void;
  clearRipples?: () => void;
  getFPS?: () => number;
  reloadShaderFromURL?: (id: string, url: string) => Promise<boolean>;
  firePlasma?: (x: number, y: number, vx: number, vy: number) => void;
  applyTestRenderState?: (state: RendererTestState) => void;
  takeScreenshot?: (filename?: string) => Promise<void>;
  startRecording?: (
    canvas: HTMLCanvasElement,
    options?: RecordingOptions
  ) => Promise<Blob>;
  stopRecording?: () => void;
  getDiagnostics?: () => RendererDiagnosticsSnapshot;
}

/** @deprecated Use IRenderer — kept for existing imports. */
export type Renderer = IRenderer;

export interface RendererConfig {
  width: number;
  height: number;
  agentCount: number;
}

export const DEFAULT_CONFIG: RendererConfig = {
  width: 1920,
  height: 1080,
  agentCount: 50000,
};

// Re-export error handling from ErrorHandling module for backward compatibility
export type { RendererError, ErrorHandler } from './ErrorHandling';
export { setRendererErrorHandler, reportError, getBrowserWarning, isWebGPUAvailable } from './ErrorHandling';
