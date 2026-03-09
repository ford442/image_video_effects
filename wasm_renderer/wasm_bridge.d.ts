/**
 * Pixelocity WASM Renderer TypeScript Definitions
 */

export interface WasmRenderer {
  /**
   * Initialize the WASM renderer
   */
  initWasmRenderer(canvas: HTMLCanvasElement): Promise<boolean>;

  /**
   * Shutdown the WASM renderer
   */
  shutdownWasmRenderer(): void;

  /**
   * Load a WGSL shader
   */
  loadShader(id: string, wgslCode: string): boolean;

  /**
   * Load a shader from a URL
   */
  loadShaderFromURL(id: string, url: string): Promise<boolean>;

  /**
   * Set the active shader for rendering
   */
  setActiveShader(id: string): void;

  /**
   * Update uniform values
   */
  updateUniforms(uniforms: {
    time?: number;
    mouseX?: number;
    mouseY?: number;
    mouseDown?: boolean;
    zoomParams?: [number, number, number, number];
  }): void;

  /**
   * Add a ripple effect at the given position
   */
  addRipple(x: number, y: number): void;

  /**
   * Clear all ripples
   */
  clearRipples(): void;

  /**
   * Get current FPS
   */
  getFPS(): number;

  /**
   * Check if renderer is initialized
   */
  isInitialized(): boolean;
}

// Default export
declare const wasmRenderer: WasmRenderer;
export default wasmRenderer;
