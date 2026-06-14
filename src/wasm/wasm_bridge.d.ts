/**
 * Pixelocity WASM Renderer TypeScript Definitions
 *
 * All named exports here correspond to functions in public/wasm/wasm_bridge.js
 * and their backing C++ exports in wasm_renderer/main.cpp.
 */

export function initWasmRenderer(canvas: HTMLCanvasElement): Promise<boolean>;
export function shutdownWasmRenderer(): void;
export function loadShader(id: string, wgslCode: string): boolean;
export function loadShaderFromURL(id: string, url: string): Promise<boolean>;
export function setActiveShader(id: string): void;

// Multi-slot shader API
export function setSlotShader(slotIndex: number, id: string): void;
export function setSlotParams(slotIndex: number, p1: number, p2: number, p3: number, p4: number): void;
export function setSlotMode(slotIndex: number, mode: 0 | 1 | 'chained' | 'parallel'): void;

export function updateUniforms(uniforms?: {
  time?: number;
  mouseX?: number;
  mouseY?: number;
  mouseDown?: boolean;
  zoom_params?: [number, number, number, number];
}): void;
export function updateMousePos(x: number, y: number): void;
export function setMouseDown(down: boolean): void;
export function updateAudioData(bass: number, mid: number, treble: number): void;
export function updateDepthMap(data: Float32Array, width: number, height: number): void;
export function setInputSource(
  source: number | 'none' | 'image' | 'video' | 'webcam' | 'generative' | 'live'
): void;
export function addRipple(x: number, y: number): void;
export function clearRipples(): void;
export function getFPS(): number;
export function getAdapterSummary(): string;
export function isInitialized(): boolean;
export function uploadImageData(rgbaPixels: Uint8Array | Uint8ClampedArray, width: number, height: number): void;
export function uploadVideoFrame(rgbaPixels: Uint8Array | Uint8ClampedArray, width: number, height: number): void;

// Canvas resizing
export function resizeCanvas(newWidth: number, newHeight: number): void;

// Frame capture / screenshots
export function captureFrame(): Promise<ImageData>;
export function takeScreenshot(filename?: string): Promise<void>;

// Video recording
export interface RecordingOptions {
  /** Auto-stop recording after this many milliseconds. 0 = no auto-stop. Default: 8000 */
  durationMs?: number;
  /** Target capture frame rate. Default: 60 */
  frameRate?: number;
  /** MediaRecorder video bit-rate in bps. Default: 8_000_000 (8 Mbps) */
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
  updateUniforms(uniforms?: {
    time?: number;
    mouseX?: number;
    mouseY?: number;
    mouseDown?: boolean;
    zoom_params?: [number, number, number, number];
  }): void;
  updateMousePos(x: number, y: number): void;
  setMouseDown(down: boolean): void;
  updateAudioData(bass: number, mid: number, treble: number): void;
  updateDepthMap(data: Float32Array, width: number, height: number): void;
  setInputSource(source: number | 'none' | 'image' | 'video' | 'webcam' | 'generative' | 'live'): void;
  addRipple(x: number, y: number): void;
  clearRipples(): void;
  getFPS(): number;
  getAdapterSummary(): string;
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
