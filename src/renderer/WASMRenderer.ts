import { BaseRenderer as Renderer, RendererConfig } from './BaseRenderer';
import * as WasmBridge from '../wasm/wasm_bridge.js';

export class WASMRenderer implements Renderer {
  private config: RendererConfig;
  private video: HTMLVideoElement | null = null;
  private animationId: number | null = null;
  private startTime = 0;
  private mouseX = 0.5;
  private mouseY = 0.5;
  private mouseDown = false;
  private initialized = false;

  // Offscreen canvas for extracting video/image pixel data
  private offscreenCanvas: HTMLCanvasElement | null = null;
  private offscreenCtx: CanvasRenderingContext2D | null = null;

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
    if (!this.video || this.video.readyState < 2) return;

    const w = this.video.videoWidth;
    const h = this.video.videoHeight;

    if (w === 0 || h === 0) return;

    // Lazily create / resize the offscreen canvas
    if (!this.offscreenCanvas || this.offscreenCanvas.width !== w || this.offscreenCanvas.height !== h) {
      this.offscreenCanvas = document.createElement('canvas');
      this.offscreenCanvas.width = w;
      this.offscreenCanvas.height = h;
      this.offscreenCtx = this.offscreenCanvas.getContext('2d', { willReadFrequently: true });
    }

    if (!this.offscreenCtx) return;

    this.offscreenCtx.drawImage(this.video, 0, 0, w, h);
    const imageData = this.offscreenCtx.getImageData(0, 0, w, h);
    WasmBridge.uploadVideoFrame(imageData.data, w, h);
  }

  /**
   * Load an image from a URL into the C++ renderer's read texture.
   */
  async loadImageFromURL(url: string): Promise<void> {
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.src = url;
    await img.decode();

    const w = img.naturalWidth;
    const h = img.naturalHeight;

    if (!this.offscreenCanvas || this.offscreenCanvas.width !== w || this.offscreenCanvas.height !== h) {
      this.offscreenCanvas = document.createElement('canvas');
      this.offscreenCanvas.width = w;
      this.offscreenCanvas.height = h;
      this.offscreenCtx = this.offscreenCanvas.getContext('2d', { willReadFrequently: true });
    }

    if (!this.offscreenCtx) return;

    this.offscreenCtx.drawImage(img, 0, 0, w, h);
    const imageData = this.offscreenCtx.getImageData(0, 0, w, h);
    WasmBridge.uploadImageData(imageData.data, w, h);
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
    this.offscreenCanvas = null;
    this.offscreenCtx = null;
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
