import { Renderer, RendererConfig } from './Renderer';
import { JSRenderer } from './JSRenderer';
import { WASMRenderer, WASMDiagnostics } from './WASMRenderer';
import { WebGPURenderer } from './WebGPURenderer';
import { ShaderEntry } from './types';

export interface RendererMetrics {
  fps: number;
  frameTime: number;
  agentCount: number;
  isWASM: boolean;
}

export interface RendererDiagnostics {
  rendererType: RendererType;
  metrics: RendererMetrics;
  timestamp: string;
  wasm?: WASMDiagnostics;
  webgpu?: Record<string, any>;
}

/** Supported renderer backend identifiers. */
export type RendererType = 'webgpu' | 'wasm' | 'js';

/**
 * Read the preferred renderer type from the URL query string.
 *
 * Supported values for the `renderer` parameter:
 *   - `wasm`   → C++ Emscripten WASM renderer
 *   - `webgpu` → TypeScript native WebGPU renderer (default)
 *   - `js`     → Canvas 2D fallback (no shaders)
 *
 * Example: `http://localhost:3000/?renderer=wasm`
 */
export function getRendererTypeFromURL(): RendererType | null {
  try {
    const params = new URLSearchParams(window.location.search);
    const value = params.get('renderer');
    if (value === 'wasm' || value === 'webgpu' || value === 'js') {
      return value as RendererType;
    }
  } catch {
    // Not in a browser context (e.g. tests)
  }
  return null;
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

    // Honour an explicit renderer preference from the URL query string
    // (e.g. ?renderer=wasm) so the WASM path can be tested without code changes.
    const urlPreference = getRendererTypeFromURL();

    if (urlPreference === 'wasm') {
      console.log('🔧 WASM renderer explicitly requested via ?renderer=wasm');
      const wasmSuccess = await this.switchRenderer('wasm');
      if (wasmSuccess) {
        console.log('✅ Using C++ WASM renderer (forced via ?renderer=wasm)');
        return true;
      }
      // Fall through to the normal priority order on failure
      console.warn('⚠️ WASM renderer requested but failed to initialise — falling back to TypeScript WebGPU');
    }

    if (urlPreference === 'js') {
      console.log('🔧 Canvas2D renderer explicitly requested via ?renderer=js');
      return this.switchRenderer('js');
    }

    // 1. Try native TypeScript WebGPU renderer (no WASM / Emscripten required)
    if (urlPreference !== 'wasm') {
      const gpuSuccess = await this.switchRenderer('webgpu');
      if (gpuSuccess) {
        console.log('✅ Using TypeScript WebGPU renderer (native navigator.gpu)');
        return true;
      }
    }

    // 2. Canvas2D fallback — no shader effects, but app stays functional.
    // WASM renderer is NOT an automatic fallback; use switchRenderer('wasm') explicitly
    // or pass ?renderer=wasm in the URL to opt in.
    console.warn('⚠️ WebGPU unavailable — falling back to Canvas2D (shaders disabled)');
    return this.switchRenderer('js');
  }

  async switchRenderer(type: RendererType): Promise<boolean> {
    if (!this.canvas) return false;

    // Preserve video reference across renderer switches
    const video = (this.currentRenderer as any)?.['video'] as HTMLVideoElement | undefined;

    // Destroy the old renderer only after the new one is ready, so we don't
    // leave the app without a renderer if initialization fails.
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
      this.currentRenderer?.destroy();
      this.currentRenderer = renderer;
      this.metrics.isWASM  = type === 'wasm';

      if (video) renderer.setVideo(video);
      this.startMetricsCollection();
    } else {
      // If initialization failed, discard the new renderer.
      // The previous renderer (if any) is still active.
      console.warn(`[RendererManager] switchRenderer('${type}') failed — keeping previous renderer`);
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

  updateAudioFrequencyBins(bins: Float32Array): void {
    this.currentRenderer?.updateAudioFrequencyBins?.(bins);
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

  /** Assign a shader to a specific slot (0-2) without clearing other slots. */
  setSlotShader(index: number, id: string): void {
    if (this.currentRenderer instanceof WebGPURenderer) {
      this.currentRenderer.setSlotShader(index, id);
    } else if (this.currentRenderer instanceof WASMRenderer) {
      this.currentRenderer.setSlotShader(index, id);
    }
  }

  /** Update zoom params for a slot (called when UI sliders change). */
  updateSlotParams(
    params: { zoomParam1?: number; zoomParam2?: number; zoomParam3?: number; zoomParam4?: number },
    slotIndex?: number
  ): void {
    if (this.currentRenderer instanceof WebGPURenderer) {
      this.currentRenderer.updateSlotParams(params);
    } else if (this.currentRenderer instanceof WASMRenderer) {
      this.currentRenderer.updateSlotParams(params, slotIndex);
    }
  }

  /** Set slot execution mode ('chained' | 'parallel'). */
  setSlotMode(index: number, mode: 'chained' | 'parallel'): void {
    if (this.currentRenderer instanceof WebGPURenderer) {
      this.currentRenderer.setSlotMode(index, mode);
    } else if (this.currentRenderer instanceof WASMRenderer) {
      this.currentRenderer.setSlotMode(index, mode);
    }
  }

  /** Set the active input source (generative, image, video, webcam, or live). */
  setInputSource(source: 'image' | 'video' | 'webcam' | 'generative' | 'live'): void {
    if (this.currentRenderer instanceof WebGPURenderer) {
      this.currentRenderer.setInputSource(source);
    } else if (this.currentRenderer instanceof WASMRenderer) {
      this.currentRenderer.setInputSource(source);
    } else if (this.currentRenderer instanceof JSRenderer) {
      this.currentRenderer.setInputSource(source);
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

  /** Forward a list of image URLs to the active renderer (e.g. for slideshow mode). */
  setImageList(urls: string[]): void {
    if (this.currentRenderer?.setImageList) {
      this.currentRenderer.setImageList(urls);
    }
  }

  /** Forward a depth map to the active renderer. */
  updateDepthMap(data: Float32Array, width: number, height: number): void {
    if (this.currentRenderer?.updateDepthMap) {
      this.currentRenderer.updateDepthMap(data, width, height);
    }
  }

  /** Forwards deep-workgroup capability query to the active renderer. */
  getSupportsDeepWorkgroup(): boolean {
    return this.currentRenderer?.getSupportsDeepWorkgroup?.() ?? false;
  }

  getMetrics(): RendererMetrics {
    return this.metrics;
  }

  isWASM(): boolean {
    return this.metrics.isWASM;
  }

  /**
   * Returns the type identifier of the currently active renderer backend.
   * Useful for UI components that need to display or react to the active renderer.
   */
  getActiveRendererType(): RendererType {
    if (this.currentRenderer instanceof WASMRenderer) return 'wasm';
    if (this.currentRenderer instanceof WebGPURenderer) return 'webgpu';
    return 'js';
  }

  /**
   * Get diagnostic information about the currently active renderer.
   * Useful for debugging, testing, and monitoring renderer health.
   */
  getDiagnostics(): RendererDiagnostics {
    const rendererType = this.getActiveRendererType();
    const baseDiagnostics: RendererDiagnostics = {
      rendererType,
      metrics: this.metrics,
      timestamp: new Date().toISOString(),
    };

    // Get renderer-specific diagnostics
    if (this.currentRenderer instanceof WASMRenderer) {
      return {
        ...baseDiagnostics,
        wasm: (this.currentRenderer as WASMRenderer).getDiagnostics(),
      };
    }

    if (this.currentRenderer instanceof WebGPURenderer) {
      return {
        ...baseDiagnostics,
        webgpu: {
          initialized: (this.currentRenderer as any).initialized ?? false,
          fps: (this.currentRenderer as any).getFPS?.() ?? 0,
        },
      };
    }

    return baseDiagnostics;
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
