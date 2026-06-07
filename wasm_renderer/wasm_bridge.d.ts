/**
 * Pixelocity WASM Renderer TypeScript Definitions
 */

export function initWasmRenderer(canvas: HTMLCanvasElement): Promise<boolean>;
export function shutdownWasmRenderer(): void;
export function loadShader(id: string, wgslCode: string): boolean;
export function loadShaderFromURL(id: string, url: string): Promise<boolean>;
export function setActiveShader(id: string): void;

// Multi-slot shader API (Phase 1)
export function setSlotShader(slotIndex: number, id: string): void;
export function setSlotParams(slotIndex: number, p1: number, p2: number, p3: number, p4: number): void;
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
export function updateDepthMap(data: Float32Array, width: number, height: number): void;
export function setInputSource(
  source: number | 'none' | 'image' | 'video' | 'webcam' | 'generative'
): void;
export function addRipple(x: number, y: number): void;
export function clearRipples(): void;
export function getFPS(): number;
export function isInitialized(): boolean;
export function uploadImageData(rgbaPixels: Uint8Array | Uint8ClampedArray, width: number, height: number): void;
export function uploadVideoFrame(rgbaPixels: Uint8Array | Uint8ClampedArray, width: number, height: number): void;

// ─── Phase 2: Canvas resizing ────────────────────────────────────────────────

/**
 * Resize the rendering canvas and recreate all size-dependent GPU resources.
 * Call this whenever the display canvas dimensions change.
 */
export function resizeCanvas(newWidth: number, newHeight: number): void;

// ─── Phase 2: Frame capture / screenshots ────────────────────────────────────

/**
 * Capture the current rendered frame as an ImageData object (RGBA8).
 * The capture is asynchronous (GPU readback); the Promise resolves when the
 * pixel data is available.
 */
export function captureFrame(): Promise<ImageData>;

/**
 * Take a screenshot of the current frame and trigger a PNG download.
 * @param filename - Optional download filename (default: 'screenshot.png').
 */
export function takeScreenshot(filename?: string): Promise<void>;

// ─── Phase 2: Video recording ────────────────────────────────────────────────

export interface RecordingOptions {
  /** Auto-stop recording after this many milliseconds. 0 = no auto-stop. Default: 8000 */
  durationMs?: number;
  /** Target capture frame rate. Default: 60 */
  frameRate?: number;
  /** MediaRecorder video bit-rate in bps. Default: 8_000_000 (8 Mbps) */
  videoBitsPerSecond?: number;
}

/**
 * Start recording the canvas output to a WebM video using the browser's
 * MediaRecorder API.  Resolves with the recorded Blob when recording stops.
 *
 * @param canvasElement - The HTMLCanvasElement to capture.
 * @param options       - Optional recording parameters.
 */
export function startRecording(
  canvasElement: HTMLCanvasElement,
  options?: RecordingOptions
): Promise<Blob>;

/**
 * Stop an in-progress recording immediately.
 * If no recording is in progress this is a no-op.
 */
export function stopRecording(): void;

/**
 * Record the canvas for `durationMs` milliseconds, then automatically
 * download the resulting WebM file.
 */
export function recordAndDownload(
  canvasElement: HTMLCanvasElement,
  durationMs?: number,
  filename?: string
): Promise<void>;

// ─────────────────────────────────────────────────────────────────────────────

export interface WasmRenderer {
  initWasmRenderer(canvas: HTMLCanvasElement): Promise<boolean>;
  shutdownWasmRenderer(): void;
  loadShader(id: string, wgslCode: string): boolean;
  loadShaderFromURL(id: string, url: string): Promise<boolean>;
  setActiveShader(id: string): void;
  setSlotShader(slotIndex: number, id: string): void;
  setSlotParams(slotIndex: number, p1: number, p2: number, p3: number, p4: number): void;
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
  updateDepthMap(data: Float32Array, width: number, height: number): void;
  setInputSource(source: number | 'none' | 'image' | 'video' | 'webcam' | 'generative'): void;
  addRipple(x: number, y: number): void;
  clearRipples(): void;
  getFPS(): number;
  isInitialized(): boolean;
  uploadImageData(rgbaPixels: Uint8Array | Uint8ClampedArray, width: number, height: number): void;
  uploadVideoFrame(rgbaPixels: Uint8Array | Uint8ClampedArray, width: number, height: number): void;
  // Phase 2
  resizeCanvas(newWidth: number, newHeight: number): void;
  captureFrame(): Promise<ImageData>;
  takeScreenshot(filename?: string): Promise<void>;
  startRecording(canvasElement: HTMLCanvasElement, options?: RecordingOptions): Promise<Blob>;
  stopRecording(): void;
  recordAndDownload(canvasElement: HTMLCanvasElement, durationMs?: number, filename?: string): Promise<void>;
}

declare const wasmRenderer: WasmRenderer;
export default wasmRenderer;
