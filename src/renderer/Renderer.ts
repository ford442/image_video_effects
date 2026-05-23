// Slot execution mode for inter-shader parallelization
type SlotMode = 'chained' | 'parallel';

// Base renderer interface
export interface Renderer {
  init(canvas: HTMLCanvasElement): Promise<boolean>;
  render(): void;
  destroy(): void;

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

  // Slot management with parallelization support
  setSlotMode?: (index: number, mode: SlotMode) => void;
  getSlotMode?: (index: number) => SlotMode | null;
  getSlotState?: (index: number) => { shaderId: string | null; enabled: boolean; mode: SlotMode } | null;
  getGPUTimings?: () => { parallelTime: number; chainedTime: number; totalTime: number; available: boolean };
  /** Returns true when the GPU supports 16×16×4 (1024-invocation) workgroups. */
  getSupportsDeepWorkgroup?: () => boolean;

  // Added optionally implemented methods used by app
  setImageList?: (urls: string[]) => void;
  updateDepthMap?: (data: Float32Array, width: number, height: number) => void;
  getAvailableModes?: () => any[];
  loadImage?: (url: string) => Promise<string>;
  getFrameImage?: () => string;
  applyMask?: (maskType: string) => void;
  setMaskEnabled?: (enabled: boolean) => void;
  setRecording?: (isRecording: boolean) => void;
  setRecordingMode?: (mode: 'loop' | 'continuous') => void;
  updateSlotParams?: (params: { zoomParam1?: number; zoomParam2?: number; zoomParam3?: number; zoomParam4?: number }) => void;
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
