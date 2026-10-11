import type { PassTiming } from './passTimings';
import type { InputSource } from './types';

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
  /** Smoothed per-pass GPU time, when timestamps resolved (#1314 WP-4). */
  passes?: PassTiming[];
}

/** Vsync-free throughput: N frames submitted back to back, timed to GPU idle (#1080). */
export interface UncappedBenchResult {
  frames: number;
  wallMs: number;
  msPerFrame: number;
}

/** A runtime GPUDevice loss in a TS WebGPU backend (page or render worker). */
export interface DeviceLossInfo {
  /** 'worker-died': the render worker crashed, taking its device with it (#1395). */
  kind: 'device-lost' | 'worker-died';
  /** GPUDeviceLostInfo.reason, 'simulated' for the test hook, or 'render worker crashed'. */
  reason: string;
  message: string;
  /** Date.now() when the loss was observed. */
  at: number;
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

// Base renderer interface
export interface Renderer {
  init(canvas: HTMLCanvasElement): Promise<boolean>;
  /** Backends without an internal loop render on demand; TS WebGPU drives its own rAF loop. */
  render?(): void;
  /** Resolves (when async) once the backend's GPU device is released. */
  destroy(): void | Promise<void>;

  /**
   * Optional: notified once when the backend stops rendering at runtime (not during init),
   * so RendererManager can fall back or surface the blocked-renderer overlay. The TS WebGPU
   * backends pass `info` when the stop was a GPUDevice loss (RendererManager recovers it).
   */
  setFatalErrorHandler?: (handler: (message: string, info?: DeviceLossInfo) => void) => void;

  // Video input
  setVideo(video: HTMLVideoElement | undefined): void;
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
  /** Bench only: pause the frame loop, render `frames` frames without rAF, time to GPU idle. */
  benchmarkUncapped?: (frames: number) => Promise<UncappedBenchResult | null>;
  /** Returns true when the GPU supports 16×16×4 (1024-invocation) workgroups. */
  getSupportsDeepWorkgroup?: () => boolean;

  // Added optionally implemented methods used by app
  setImageList?: (urls: string[]) => void;
  updateDepthMap?: (data: Float32Array, width: number, height: number) => void;
  getAvailableModes?: () => any[];
  loadImage?: (url: string) => Promise<string>;
  /** CPU-side photo/video still held after exclusive GPU teardown (#1206). */
  getCpuInputBitmap?: () => HTMLCanvasElement | HTMLImageElement | HTMLVideoElement | null;
  /** Upload an already-decoded canvas/image without a network re-fetch. */
  loadImageFromElement?: (
    element: HTMLCanvasElement | HTMLImageElement,
  ) => Promise<{ width: number; height: number } | null> | { width: number; height: number } | null;
  getFrameImage?: () => string;
  applyMask?: (maskType: string) => void;
  setMaskEnabled?: (enabled: boolean) => void;
  setRecording?: (isRecording: boolean) => void;
  setRecordingMode?: (mode: 'loop' | 'continuous') => void;
  // Capture / recording capabilities. Typed here so RendererManager never duck-types (#1395).
  /** Read the presented frame back as a data URL (the worker and WASM cannot read the page canvas). */
  refreshFrameImage?: () => Promise<string>;
  /** WASM: save a screenshot through the C++ readback. */
  takeScreenshot?: (filename?: string) => Promise<void>;
  /** WASM: record the canvas output internally. */
  startRecording?: (
    canvas: HTMLCanvasElement,
    options?: { durationMs?: number; frameRate?: number; videoBitsPerSecond?: number },
  ) => Promise<Blob>;
  stopRecording?: () => void;
  /** Swapchain accepted COPY_SRC at init (canvas → VideoFrame capture). */
  supportsCanvasCopySrc?: () => boolean;
  /** Reconfigure the swapchain with / without COPY_SRC; false when refused. */
  setCanvasCopySrc?: (enabled: boolean) => boolean;
  /** Render worker: the next presented frame as a transferred VideoFrame. */
  grabVideoFrame?: (timestampUs: number) => Promise<VideoFrame | null>;
  /** Optional: last audio analysis snapshot (WebGPU + WASM). */
  getAudioData?: () => { bass: number; mid: number; treble: number; freqBins: Float32Array };
  /** Optional: whether an internal recording flag is active (WASM). */
  isRecording?: () => boolean;
  loadShader?: (id: string, url: string) => Promise<boolean>;
  setActiveShader?: (id: string) => void;
  setSlotShader?: (index: number, id: string) => void;
  setSlotParams?: (slotIndex: number, p1: number, p2: number, p3: number, p4: number) => void;
  updateSlotParams?: (params: SlotZoomParamsUpdate, slotIndex?: number) => void;
  addRipple?: (x: number, y: number) => void;
  clearRipples?: () => void;

  /** Optional: Return current FPS for performance comparison (used by dual-FPS toggle). */
  getFPS?: () => number;

  /**
   * Exclusive WebGPU teardown for backend switches: destroy working textures,
   * device.destroy(), and await device.lost before the next requestDevice.
   */
  releaseExclusiveGpu?: () => Promise<void>;

  /** Optional: Reload a single shader from a remote URL without rebuilding the entire pipeline. */
  reloadShaderFromURL?: (id: string, url: string) => Promise<boolean>;
}

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

// Re-export error handling from ErrorHandling module for backward compatibility
export type { RendererError, ErrorHandler } from './ErrorHandling';
export { setRendererErrorHandler, reportError, getBrowserWarning, isWebGPUAvailable } from './ErrorHandling';
