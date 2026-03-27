/** Type declarations for the Emscripten WASM bridge (wasm_bridge.js). */

export function initWasmRenderer(canvasElement: HTMLCanvasElement): Promise<boolean>;
export function shutdownWasmRenderer(): void;

export function loadShader(id: string, wgslCode: string): boolean;
export function loadShaderFromURL(id: string, url: string): Promise<boolean>;
export function setActiveShader(id: string): void;

export function addRipple(x: number, y: number): void;
export function clearRipples(): void;
export function getFPS(): number;
export function isInitialized(): boolean;

export function uploadImageData(rgbaPixels: Uint8Array | Uint8ClampedArray, width: number, height: number): void;
export function uploadVideoFrame(rgbaPixels: Uint8Array | Uint8ClampedArray, width: number, height: number): void;

export function updateMousePos(x: number, y: number): void;
export function updateAudioData(bass: number, mid: number, treble: number): void;
export function updateUniforms(uniforms: {
  time?: number;
  mouseX?: number;
  mouseY?: number;
  mouseDown?: boolean;
  zoom_params?: number[];
}): void;

declare const wasmBridge: {
  initWasmRenderer: typeof initWasmRenderer;
  shutdownWasmRenderer: typeof shutdownWasmRenderer;
  loadShader: typeof loadShader;
  loadShaderFromURL: typeof loadShaderFromURL;
  setActiveShader: typeof setActiveShader;
  updateUniforms: typeof updateUniforms;
  updateMousePos: typeof updateMousePos;
  updateAudioData: typeof updateAudioData;
  addRipple: typeof addRipple;
  clearRipples: typeof clearRipples;
  getFPS: typeof getFPS;
  isInitialized: typeof isInitialized;
  uploadImageData: typeof uploadImageData;
  uploadVideoFrame: typeof uploadVideoFrame;
};

export default wasmBridge;
