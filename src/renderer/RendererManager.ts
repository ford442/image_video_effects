import { Renderer, RendererConfig } from './Renderer';
import { JSRenderer } from './JSRenderer';
import { WASMRenderer } from './WASMRenderer';

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
