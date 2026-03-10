import { Renderer, RendererConfig } from './Renderer';

// WASM module type
interface PixelocityWASM {
  _initWasmRenderer: (width: number, height: number, agentCount: number) => void;
  _updateVideoFrame: (ctx: number) => void;
  _updateAudioData: (bass: number, mid: number, treble: number) => void;
  _updateMousePos: (x: number, y: number) => void;
  _toggleRenderer: (useWasm: number) => void;
}

export class WASMRenderer implements Renderer {
  private module: PixelocityWASM | null = null;
  private canvas: HTMLCanvasElement | null = null;
  private config: RendererConfig;
  private video: HTMLVideoElement | null = null;
  private glContext: WebGLRenderingContext | null = null;

  constructor(config: RendererConfig) {
    this.config = config;
  }

  async init(canvas: HTMLCanvasElement): Promise<boolean> {
    this.canvas = canvas;

    try {
      // Load WASM module
      const wasm = await import('/wasm/pixelocity_wasm.js');
      await wasm.default();
      this.module = wasm as unknown as PixelocityWASM;

      // Initialize renderer
      this.module._initWasmRenderer(
        this.config.width,
        this.config.height,
        this.config.agentCount
      );

      // Create GL context for video texture
      this.glContext = canvas.getContext('webgl2', {
        alpha: false,
        premultipliedAlpha: false,
      });

      console.log('✅ WASM Renderer initialized');
      return true;
    } catch (err) {
      console.error('❌ WASM init failed:', err);
      return false;
    }
  }

  setVideo(video: HTMLVideoElement): void {
    this.video = video;
  }

  updateVideoFrame(): void {
    if (!this.module || !this.video || !this.glContext) return;

    // Import video frame to WebGL texture
    // This is a simplified version - actual implementation would use
    // emscripten_webgpu_import_external_texture
    const gl = this.glContext;

    // Create/update texture from video
    const texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, this.video);

    // Pass to WASM
    // Note: Actual implementation needs WebGPU external texture
  }

  updateAudioData(bass: number, mid: number, treble: number): void {
    if (!this.module) return;
    this.module._updateAudioData(bass, mid, treble);
  }

  updateMouse(x: number, y: number): void {
    if (!this.module) return;
    this.module._updateMousePos(x, y);
  }

  setParam(name: string, value: number): void {
    // Parameters are set via uniforms in the WASM renderer
    // This would need additional WASM exports for each parameter
  }

  render(): void {
    // Rendering is handled by the WASM main loop
    // We just update inputs here
    if (this.video && this.video.readyState >= 2) {
      this.updateVideoFrame();
    }
  }

  destroy(): void {
    if (this.module) {
      this.module._toggleRenderer(0);
      this.module = null;
    }
    this.glContext = null;
  }
}
