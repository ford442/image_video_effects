/**
 * Pixelocity WASM Renderer TypeScript Definitions
 */

/** Diagnostic snapshot from the JS bridge layer (load/init tracking). */
export interface WasmBridgeDiagnostics {
  initialized: boolean;
  hasModule: boolean;
  hasCanvas: boolean;
  moduleHasCCall: boolean;
  canvasResolution: string;
  loadErrorCount: number;
  lastLoadError: string | null;
  initTime: string;
  loadPath: string;
  /** WebGPURenderer::InitStage from C++ (0=None, 8=Ready). */
  failedStage: number;
  failedStageName: string;
  /** Human-readable C++ init failure message. */
  lastInitError: string;
  /** Adapter/device/limits summary from C++ CreateDevice(). */
  adapterInfo: string;
}

export interface GPUTimings {
  parallelTime: number;
  chainedTime: number;
  totalTime: number;
  available: boolean;
}

export interface SlotState {
  shaderId: string | null;
  enabled: boolean;
  mode: 'chained' | 'parallel';
}

export interface SlotZoomParamsUpdate {
  zoomParam1?: number;
  zoomParam2?: number;
  zoomParam3?: number;
  zoomParam4?: number;
}

export function getDiagnostics(): WasmBridgeDiagnostics;

export function initWasmRenderer(canvas: HTMLCanvasElement): Promise<boolean>;
export function shutdownWasmRenderer(): void;
export function loadShader(id: string, wgslCode: string): boolean;
export function loadShaderFromURL(id: string, url: string): Promise<boolean>;
export function setActiveShader(id: string): void;

// Multi-slot shader API
export function setSlotShader(slotIndex: number, id: string): void;
export function setSlotParams(slotIndex: number, p1: number, p2: number, p3: number, p4: number): void;
export function updateSlotParams(slotIndex: number, params: SlotZoomParamsUpdate): void;
export function setSlotMode(slotIndex: number, mode: 0 | 1 | 'chained' | 'parallel'): void;

export function updateUniforms(uniforms: {
  time?: number;
  mouseX?: number;
  mouseY?: number;
  mouseDown?: boolean;
  zoom_params?: [number, number, number, number];
}): void;
export function updateMousePos(x: number, y: number): void;
export function updateAudioData(bass: number, mid: number, treble: number): void;
export function updateAudioFrequencyBins(bins: Float32Array): void;
export function updateDepthMap(data: Float32Array, width: number, height: number): void;
export function setInputSource(
  source: number | 'none' | 'image' | 'video' | 'webcam' | 'generative' | 'live'
): void;
export function addRipple(x: number, y: number): void;
export function clearRipples(): void;
export function getFPS(): number;
export function getSupportsDeepWorkgroup(): boolean;
export function getSlotState(slotIndex: number): SlotState;
export function getGPUTimings(): GPUTimings;
export function setRecording(recording: boolean): void;
export function isRecordingActive(): boolean;
export function getAdapterSummary(): string;
export function getLastInitErrorStage(): number;
export function getLastInitErrorMessage(): string;
export function isInitialized(): boolean;
export function uploadImageData(rgbaPixels: Uint8Array | Uint8ClampedArray, width: number, height: number): void;
export function uploadVideoFrame(rgbaPixels: Uint8Array | Uint8ClampedArray, width: number, height: number): void;

export function resizeCanvas(newWidth: number, newHeight: number): void;
export function captureFrame(): Promise<ImageData>;
export function captureFrameDataUrl(): Promise<string>;
export function takeScreenshot(filename?: string): Promise<void>;

export interface RecordingOptions {
  durationMs?: number;
  frameRate?: number;
  videoBitsPerSecond?: number;
}

export function startRecording(
  canvasElement: HTMLCanvasElement,
  options?: RecordingOptions
): Promise<Blob>;
export function stopRecording(): void;
export function recordAndDownload(
  canvasElement: HTMLCanvasElement,
  durationMs?: number,
  filename?: string
): Promise<void>;

export interface WasmRenderer {
  getDiagnostics(): WasmBridgeDiagnostics;
  initWasmRenderer(canvas: HTMLCanvasElement): Promise<boolean>;
  shutdownWasmRenderer(): void;
  loadShader(id: string, wgslCode: string): boolean;
  loadShaderFromURL(id: string, url: string): Promise<boolean>;
  setActiveShader(id: string): void;
  setSlotShader(slotIndex: number, id: string): void;
  setSlotParams(slotIndex: number, p1: number, p2: number, p3: number, p4: number): void;
  updateSlotParams(slotIndex: number, params: SlotZoomParamsUpdate): void;
  setSlotMode(slotIndex: number, mode: 0 | 1 | 'chained' | 'parallel'): void;
  updateUniforms(uniforms: {
    time?: number;
    mouseX?: number;
    mouseY?: number;
    mouseDown?: boolean;
    zoom_params?: [number, number, number, number];
  }): void;
  updateMousePos(x: number, y: number): void;
  updateAudioData(bass: number, mid: number, treble: number): void;
  updateAudioFrequencyBins(bins: Float32Array): void;
  updateDepthMap(data: Float32Array, width: number, height: number): void;
  setInputSource(source: number | 'none' | 'image' | 'video' | 'webcam' | 'generative' | 'live'): void;
  addRipple(x: number, y: number): void;
  clearRipples(): void;
  getFPS(): number;
  getSupportsDeepWorkgroup(): boolean;
  getSlotState(slotIndex: number): SlotState;
  getGPUTimings(): GPUTimings;
  setRecording(recording: boolean): void;
  isRecordingActive(): boolean;
  captureFrameDataUrl(): Promise<string>;
  getAdapterSummary(): string;
  getLastInitErrorStage(): number;
  getLastInitErrorMessage(): string;
  isInitialized(): boolean;
  uploadImageData(rgbaPixels: Uint8Array | Uint8ClampedArray, width: number, height: number): void;
  uploadVideoFrame(rgbaPixels: Uint8Array | Uint8ClampedArray, width: number, height: number): void;
  resizeCanvas(newWidth: number, newHeight: number): void;
  captureFrame(): Promise<ImageData>;
  takeScreenshot(filename?: string): Promise<void>;
  startRecording(canvasElement: HTMLCanvasElement, options?: RecordingOptions): Promise<Blob>;
  stopRecording(): void;
  recordAndDownload(canvasElement: HTMLCanvasElement, durationMs?: number, filename?: string): Promise<void>;
}

declare const wasmRenderer: WasmRenderer;
export default wasmRenderer;
