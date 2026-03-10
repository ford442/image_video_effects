/**
 * Pixelocity WASM Renderer TypeScript Definitions
 */

export function initWasmRenderer(canvas: HTMLCanvasElement): Promise<boolean>;
export function shutdownWasmRenderer(): void;
export function loadShader(id: string, wgslCode: string): boolean;
export function loadShaderFromURL(id: string, url: string): Promise<boolean>;
export function setActiveShader(id: string): void;
export function updateUniforms(uniforms: {
  time?: number;
  mouseX?: number;
  mouseY?: number;
  mouseDown?: boolean;
  zoomParams?: [number, number, number, number];
}): void;
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
  updateUniforms(uniforms: {
    time?: number;
    mouseX?: number;
    mouseY?: number;
    mouseDown?: boolean;
    zoomParams?: [number, number, number, number];
  }): void;
  addRipple(x: number, y: number): void;
  clearRipples(): void;
  getFPS(): number;
  isInitialized(): boolean;
  uploadImageData(rgbaPixels: Uint8Array | Uint8ClampedArray, width: number, height: number): void;
  uploadVideoFrame(rgbaPixels: Uint8Array | Uint8ClampedArray, width: number, height: number): void;
}

declare const wasmRenderer: WasmRenderer;
export default wasmRenderer;
