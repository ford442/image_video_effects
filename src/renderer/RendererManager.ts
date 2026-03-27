import { Renderer, RendererConfig } from './Renderer';
import { JSRenderer } from './JSRenderer';
import { WASMRenderer } from './WASMRenderer';
import { WebGPURenderer } from './WebGPURenderer';
import { ShaderEntry } from './types';

export interface RendererMetrics {
  fps: number;
  frameTime: number;
  agentCount: number;
  isWASM: boolean;
}

export class RendererManager {
  private currentRenderer: Renderer | null = null;
  private config: RendererConfig;
  private canvas: HTMLCanvasElement | null = null;
  private metrics: RendererMetrics = {
    fps: 0,
    frameTime: 0,
    agentCount: 0,
    isWASM: false,
  };
  private onMetricsUpdate?: (metrics: RendererMetrics) => void;

  constructor(config: RendererConfig, onMetricsUpdate?: (metrics: RendererMetrics) => void) {
    this.config = config;
    this.onMetricsUpdate = onMetricsUpdate;
  }

  async init(canvas: HTMLCanvasElement): Promise<boolean> {
    this.canvas = canvas;

    // 1. Try native TypeScript WebGPU renderer (no WASM / Emscripten required)
    const gpuSuccess = await this.switchRenderer('webgpu');
    if (gpuSuccess) {
      console.log('✅ Using TypeScript WebGPU renderer (native navigator.gpu)');
      return true;
    }

    // 2. Try compiled WASM renderer (requires a real Emscripten binary)
    const wasmSuccess = await this.switchRenderer('wasm');
    if (wasmSuccess) {
      console.log('✅ Using WASM renderer with shader support');
      return true;
    }

    // 3. Canvas2D fallback — no shader effects, but app stays functional
    console.warn('⚠️ WebGPU and WASM unavailable — falling back to Canvas2D (shaders disabled)');
    return this.switchRenderer('js');
  }

  async switchRenderer(type: 'webgpu' | 'wasm' | 'js'): Promise<boolean> {
    if (!this.canvas) return false;

    // Preserve video reference across renderer switches
    const video = (this.currentRenderer as any)?.['video'] as HTMLVideoElement | undefined;

    this.currentRenderer?.destroy();

    let renderer: Renderer;
    if (type === 'webgpu') {
      renderer = new WebGPURenderer(this.config);
    } else if (type === 'wasm') {
      renderer = new WASMRenderer(this.config);
    } else {
      renderer = new JSRenderer(this.config);
    }

    const success = await renderer.init(this.canvas);

    if (success) {
      this.currentRenderer = renderer;
      this.metrics.isWASM  = type === 'wasm';

      if (video) renderer.setVideo(video);
      this.startMetricsCollection();
    }

    return success;
  }

  private startMetricsCollection(): void {
    // In a real implementation, the renderers would expose getMetrics()
    // For now, we'll use simulated/placeholder metrics
    const updateMetrics = () => {
      // This would come from the renderer in a full implementation
      this.onMetricsUpdate?.(this.metrics);
      requestAnimationFrame(updateMetrics);
    };
    updateMetrics();
  }

  setVideo(video: HTMLVideoElement): void {
    this.currentRenderer?.setVideo(video);
  }

  updateVideoFrame(): void {
    this.currentRenderer?.updateVideoFrame();
  }

  updateAudioData(bass: number, mid: number, treble: number): void {
    this.currentRenderer?.updateAudioData(bass, mid, treble);
  }

  updateMouse(x: number, y: number): void {
    this.currentRenderer?.updateMouse(x, y);
  }

  setParam(name: string, value: number): void {
    this.currentRenderer?.setParam(name, value);

    if (name === 'agentCount') {
      this.metrics.agentCount = Math.floor(value);
    }
  }

  /**
   * Load a shader by fetching its WGSL from the given URL.
   * Works with both the TypeScript WebGPU renderer and the WASM renderer.
   * No-op when the Canvas2D fallback is active.
   */
  async loadShader(id: string, url: string): Promise<boolean> {
    if (this.currentRenderer instanceof WebGPURenderer) {
      return this.currentRenderer.loadShader(id, url);
    }
    if (this.currentRenderer instanceof WASMRenderer) {
      return this.currentRenderer.loadShader(id, url);
    }
    return false;
  }

  /**
   * Load all shaders from a shader list into the WASM renderer.
   * Shaders are loaded concurrently.
   */
  async loadShaders(shaders: ShaderEntry[]): Promise<void> {
    await Promise.all(shaders.map(s => this.loadShader(s.id, s.url)));
  }

  /** Switch to a previously loaded shader. No-op with Canvas2D fallback. */
  setActiveShader(id: string): void {
    if (this.currentRenderer instanceof WebGPURenderer) {
      this.currentRenderer.setActiveShader(id);
    } else if (this.currentRenderer instanceof WASMRenderer) {
      this.currentRenderer.setActiveShader(id);
    }
  }

  addRipple(x: number, y: number): void {
    if (this.currentRenderer instanceof WebGPURenderer) {
      this.currentRenderer.addRipple(x, y);
    } else if (this.currentRenderer instanceof WASMRenderer) {
      this.currentRenderer.addRipple(x, y);
    }
  }

  clearRipples(): void {
    if (this.currentRenderer instanceof WebGPURenderer) {
      this.currentRenderer.clearRipples();
    } else if (this.currentRenderer instanceof WASMRenderer) {
      this.currentRenderer.clearRipples();
    }
  }

  /** Load an image by URL into the active renderer's read texture. */
  async loadImage(url: string): Promise<string> {
    if (this.currentRenderer instanceof WebGPURenderer) {
      return this.currentRenderer.loadImage(url);
    }
    if (this.currentRenderer instanceof WASMRenderer) {
      await this.currentRenderer.loadImageFromURL(url);
      return url;
    }
    if (this.currentRenderer && 'loadImage' in this.currentRenderer) {
      return (this.currentRenderer as any).loadImage(url);
    }
    return url;
  }

  /** @deprecated Use loadImage() */
  async loadImageFromURL(url: string): Promise<void> {
    await this.loadImage(url);
  }


  getAvailableModes(): any[] {
    if (this.currentRenderer && 'getAvailableModes' in this.currentRenderer) {
      return (this.currentRenderer as any).getAvailableModes();
    }
    return [];
  }

  getMetrics(): RendererMetrics {
    return this.metrics;
  }

  isWASM(): boolean {
    return this.metrics.isWASM;
  }

  /**
   * Render method called by WebGPUCanvas animation loop.
   * The actual rendering is handled internally by the active renderer's own loop.
   * This method exists to satisfy the interface expected by WebGPUCanvas.
   */
  render(..._args: any[]): void {
    // Rendering is handled internally by JSRenderer/WASMRenderer's own animation loops
    // This method prevents "render is not a function" errors from WebGPUCanvas
  }

  destroy(): void {
    this.currentRenderer?.destroy();
    this.currentRenderer = null;
  }
}

export default RendererManager;
