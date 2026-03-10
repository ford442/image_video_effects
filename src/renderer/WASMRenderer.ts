import { BaseRenderer as Renderer, RendererConfig } from './BaseRenderer';
import * as WasmBridge from '../../wasm_renderer/wasm_bridge.js';

export class WASMRenderer implements Renderer {
  private config: RendererConfig;
  private video: HTMLVideoElement | null = null;
  private animationId: number | null = null;
  private startTime = 0;
  private mouseX = 0.5;
  private mouseY = 0.5;
  private mouseDown = false;
  private initialized = false;

  constructor(config: RendererConfig) {
    this.config = config;
  }

  async init(canvas: HTMLCanvasElement): Promise<boolean> {
    try {
      const ok = await WasmBridge.initWasmRenderer(canvas);
      if (!ok) {
        console.error('❌ WASM Renderer init failed');
        return false;
      }
      this.initialized = true;
      this.startTime = performance.now() / 1000;
      this.startRenderLoop();
      console.log('✅ WASM Renderer initialized');
      return true;
    } catch (err) {
      console.error('❌ WASM Renderer init error:', err);
      return false;
    }
  }

  /**
   * Fetch a WGSL shader from url and compile it under the given id.
   * Must be called before setActiveShader().
   */
  async loadShader(id: string, url: string): Promise<boolean> {
    return WasmBridge.loadShaderFromURL(id, url);
  }

  /** Switch to a previously loaded shader. */
  setActiveShader(id: string): void {
    WasmBridge.setActiveShader(id);
  }

  addRipple(x: number, y: number): void {
    WasmBridge.addRipple(x, y);
  }

  clearRipples(): void {
    WasmBridge.clearRipples();
  }

  getFPS(): number {
    return WasmBridge.getFPS();
  }

  // ── BaseRenderer interface ────────────────────────────────────────────────

  setVideo(video: HTMLVideoElement): void {
    this.video = video;
  }

  updateVideoFrame(): void {
    // C++ LoadImage / video texture upload not yet implemented in renderer.cpp.
    // When it is, upload this.video pixel data here via a new WASM export.
  }

  updateAudioData(_bass: number, _mid: number, _treble: number): void {
    // No C++ audio export yet.
  }

  updateMouse(x: number, y: number): void {
    this.mouseX = x;
    this.mouseY = y;
    WasmBridge.updateUniforms({ mouseX: x, mouseY: y, mouseDown: this.mouseDown });
  }

  setParam(name: string, value: number): void {
    if (name === 'mouseDown') {
      this.mouseDown = value > 0;
      WasmBridge.updateUniforms({ mouseDown: this.mouseDown });
    }
  }

  render(): void {
    // Rendering is driven by the internal animation loop.
  }

  destroy(): void {
    if (this.animationId !== null) {
      cancelAnimationFrame(this.animationId);
      this.animationId = null;
    }
    WasmBridge.shutdownWasmRenderer();
    this.initialized = false;
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  private startRenderLoop(): void {
    const loop = () => {
      if (!this.initialized) return;
      const time = performance.now() / 1000 - this.startTime;
      WasmBridge.updateUniforms({
        time,
        mouseX: this.mouseX,
        mouseY: this.mouseY,
        mouseDown: this.mouseDown,
      });
      this.animationId = requestAnimationFrame(loop);
    };
    loop();
  }
}
