import { Renderer, RendererConfig } from './Renderer';
import { JSRenderer } from './JSRenderer';
import { WASMRenderer } from './WASMRenderer';
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
    // Default to JS renderer
    return this.switchRenderer(false);
  }

  async switchRenderer(useWasm: boolean): Promise<boolean> {
    if (!this.canvas) return false;

    // Store video reference if exists
    const video = this.currentRenderer?.['video'] as HTMLVideoElement | undefined;

    // Destroy old renderer
    this.currentRenderer?.destroy();

    // Create new renderer
    const RendererClass = useWasm ? WASMRenderer : JSRenderer;
    const renderer = new RendererClass(this.config);

    const success = await renderer.init(this.canvas);

    if (success) {
      this.currentRenderer = renderer;
      this.metrics.isWASM = useWasm;

      // Restore video if was playing
      if (video) {
        renderer.setVideo(video);
      }

      // Start metrics collection
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
   * Load a shader into the WASM renderer by fetching its WGSL from the given URL.
   * No-op when the JS renderer is active.
   */
  async loadShader(id: string, url: string): Promise<boolean> {
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

  /** Switch to a previously loaded shader. No-op when the JS renderer is active. */
  setActiveShader(id: string): void {
    if (this.currentRenderer instanceof WASMRenderer) {
      this.currentRenderer.setActiveShader(id);
    }
  }

  addRipple(x: number, y: number): void {
    if (this.currentRenderer instanceof WASMRenderer) {
      this.currentRenderer.addRipple(x, y);
    }
  }

  clearRipples(): void {
    if (this.currentRenderer instanceof WASMRenderer) {
      this.currentRenderer.clearRipples();
    }
  }

  /** Load an image from URL into the WASM renderer's read texture. */
  async loadImageFromURL(url: string): Promise<void> {
    if (this.currentRenderer instanceof WASMRenderer) {
      return this.currentRenderer.loadImageFromURL(url);
    }
  }

  getMetrics(): RendererMetrics {
    return this.metrics;
  }

  isWASM(): boolean {
    return this.metrics.isWASM;
  }

  destroy(): void {
    this.currentRenderer?.destroy();
    this.currentRenderer = null;
  }
}

export default RendererManager;
