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
}

declare const wasmRenderer: WasmRenderer;
export default wasmRenderer;
