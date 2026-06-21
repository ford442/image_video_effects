import { Renderer, RendererConfig, ShaderSlotRenderer, SlotZoomParamsUpdate } from './Renderer';
import { JSRenderer } from './JSRenderer';
import { WASMRenderer, WASMDiagnostics } from './WASMRenderer';
import { WebGPURenderer } from './WebGPURenderer';
import { InputSource, RenderMode, ShaderEntry, SlotParams } from './types';

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
  // Retained even when switchRenderer('wasm') fails and falls back, so
  // getDiagnostics().wasm can still surface *why* WASM init failed
  // (e.g. surface-creation/adapter-limits errors recorded in adapterInfo).
  private lastFailedWasmRenderer: WASMRenderer | null = null;
  private config: RendererConfig;
  private canvas: HTMLCanvasElement | null = null;
  private metrics: RendererMetrics = {
    fps: 0,
    frameTime: 0,
    agentCount: 0,
    isWASM: false,
  };
  private onMetricsUpdate?: (metrics: RendererMetrics) => void;

  /** Max shader slots shared by WebGPU and WASM backends. */
  private static readonly SLOT_COUNT = 3;

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
    const gpuSuccess = await this.switchRenderer('webgpu');
    if (gpuSuccess) {
      console.log('✅ Using TypeScript WebGPU renderer (native navigator.gpu)');
      return true;
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
      if (type === 'wasm') this.lastFailedWasmRenderer = null;

      if (video) renderer.setVideo(video);
      this.startMetricsCollection();
    } else {
      // If initialization failed, discard the new renderer.
      // The previous renderer (if any) is still active.
      console.warn(`[RendererManager] switchRenderer('${type}') failed — keeping previous renderer`);
      if (renderer instanceof WASMRenderer) {
        this.lastFailedWasmRenderer = renderer;
      }
    }

    return success;
  }

  private startMetricsCollection(): void {
    const updateMetrics = () => {
      // Pull real FPS from the active renderer when available
      const renderer = this.currentRenderer as any;
      if (renderer && typeof renderer.getFPS === 'function') {
        this.metrics.fps = renderer.getFPS() || 0;
      }
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

  /** True when the active backend supports WGSL shader slots (WebGPU or WASM). */
  supportsShaderEffects(): boolean {
    return this.getShaderBackend() !== null;
  }

  /** Returns the shader-capable backend, or null for Canvas2D fallback. */
  private getShaderBackend(): ShaderSlotRenderer | null {
    const r = this.currentRenderer;
    if (!r || r instanceof JSRenderer) return null;
    const candidate = r as ShaderSlotRenderer;
    if (
      typeof candidate.loadShader === 'function' &&
      typeof candidate.setSlotShader === 'function' &&
      typeof candidate.updateSlotParams === 'function'
    ) {
      return candidate;
    }
    return null;
  }

  /**
   * Load a shader by fetching its WGSL from the given URL.
   * Works with both the TypeScript WebGPU renderer and the WASM renderer.
   * No-op when the Canvas2D fallback is active.
   */
  async loadShader(id: string, url: string): Promise<boolean> {
    const backend = this.getShaderBackend();
    if (!backend) return false;
    try {
      return await backend.loadShader(id, url);
    } catch (err) {
      console.warn(`[RendererManager] loadShader("${id}") failed:`, err);
      return false;
    }
  }

  /**
   * Load all shaders from a shader list into the active shader backend.
   * Shaders are loaded concurrently. Skips entries when Canvas2D is active.
   */
  async loadShaders(shaders: ShaderEntry[]): Promise<void> {
    if (!this.supportsShaderEffects()) return;
    const results = await Promise.allSettled(
      shaders.map(s => this.loadShader(s.id, s.url))
    );
    const failed = results.filter(r => r.status === 'rejected' || (r.status === 'fulfilled' && !r.value)).length;
    if (failed > 0) {
      console.warn(`[RendererManager] loadShaders: ${failed}/${shaders.length} shader(s) failed`);
    }
  }

  /** Switch to a previously loaded shader. No-op with Canvas2D fallback. */
  setActiveShader(id: string): void {
    this.getShaderBackend()?.setActiveShader(id);
  }

  /** Assign a shader to a specific slot (0-2) without clearing other slots. */
  setSlotShader(index: number, id: string): void {
    this.getShaderBackend()?.setSlotShader(index, id);
  }

  /**
   * Update zoom params for one slot using the per-param form (WASM bridge API).
   * Falls back to aggregate updateSlotParams when the backend has no setSlotParams.
   */
  setSlotParams(slotIndex: number, p1: number, p2: number, p3: number, p4: number): void {
    const backend = this.getShaderBackend();
    if (!backend) return;
    if (backend.setSlotParams) {
      backend.setSlotParams(slotIndex, p1, p2, p3, p4);
    } else {
      backend.updateSlotParams(
        { zoomParam1: p1, zoomParam2: p2, zoomParam3: p3, zoomParam4: p4 },
        slotIndex
      );
    }
  }

  /** Update zoom params for a slot (aggregate form from UI sliders). */
  updateSlotParams(params: SlotZoomParamsUpdate, slotIndex = 0): void {
    this.getShaderBackend()?.updateSlotParams(params, slotIndex);
  }

  /** Push all slot slider values to the active shader backend (required for WASM multi-slot). */
  syncAllSlotParams(slotParams: SlotParams[], maxSlots = RendererManager.SLOT_COUNT): void {
    if (!this.supportsShaderEffects() || slotParams.length === 0) return;
    const count = Math.min(maxSlots, slotParams.length);
    for (let i = 0; i < count; i++) {
      const p = slotParams[i];
      this.updateSlotParams(
        {
          zoomParam1: p.zoomParam1,
          zoomParam2: p.zoomParam2,
          zoomParam3: p.zoomParam3,
          zoomParam4: p.zoomParam4,
        },
        i
      );
    }
  }

  /**
   * Re-load and re-bind the current shader stack after a renderer backend switch.
   * Ensures WASM receives the same slot shaders + params the UI already selected.
   */
  async resyncShaderStack(options: {
    modes: RenderMode[];
    slotParams: SlotParams[];
    resolveShader: (shaderId: string) => ShaderEntry | undefined;
    inputSource?: InputSource;
  }): Promise<void> {
    if (!this.supportsShaderEffects()) return;

    if (options.inputSource) {
      this.setInputSource(options.inputSource);
    }

    for (let i = 0; i < Math.min(RendererManager.SLOT_COUNT, options.modes.length); i++) {
      const mode = options.modes[i];
      if (!mode || mode === 'none') {
        this.setSlotShader(i, '');
        continue;
      }

      const entry = options.resolveShader(mode);
      if (!entry) {
        console.warn(`[RendererManager] resyncShaderStack: no entry for "${mode}" on slot ${i}`);
        continue;
      }

      const ok = await this.loadShader(entry.id, entry.url);
      if (ok) {
        this.setSlotShader(i, entry.id);
      } else {
        console.warn(`[RendererManager] resyncShaderStack: failed to load "${entry.id}" for slot ${i}`);
      }
    }

    this.syncAllSlotParams(options.slotParams);
  }

  /** Set slot execution mode ('chained' | 'parallel'). */
  setSlotMode(index: number, mode: 'chained' | 'parallel'): void {
    this.getShaderBackend()?.setSlotMode(index, mode);
  }

  /** Set the active input source (generative, image, video, webcam, or live). */
  setInputSource(source: InputSource): void {
    this.currentRenderer?.setInputSource?.(source);
  }

  /** Returns the active input source when the backend exposes it (WASM). */
  getInputSource(): InputSource | null {
    if (this.currentRenderer instanceof WASMRenderer) {
      return this.currentRenderer.getInputSource();
    }
    return null;
  }

  addRipple(x: number, y: number): void {
    this.getShaderBackend()?.addRipple(x, y);
  }

  /** Alias used by WebGPUCanvas mouse handlers (forwards to addRipple). */
  addRipplePoint(x: number, y: number): void {
    this.addRipple(x, y);
  }

  clearRipples(): void {
    this.getShaderBackend()?.clearRipples();
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

  getSlotState(index: number): { shaderId: string | null; enabled: boolean; mode: 'chained' | 'parallel' } | null {
    return this.currentRenderer?.getSlotState?.(index) ?? null;
  }

  getGPUTimings(): { parallelTime: number; chainedTime: number; totalTime: number; available: boolean } {
    return this.currentRenderer?.getGPUTimings?.() ?? {
      parallelTime: 0,
      chainedTime: 0,
      totalTime: 0,
      available: false,
    };
  }

  getFrameImage(): string {
    return this.currentRenderer?.getFrameImage?.() ?? '';
  }

  /** Capture current frame from WASM renderer (no-op for other backends unless implemented). */
  async refreshFrameImage(): Promise<string> {
    const r = this.currentRenderer as WASMRenderer | null;
    if (r && typeof (r as WASMRenderer).refreshFrameImage === 'function') {
      return (r as WASMRenderer).refreshFrameImage();
    }
    return '';
  }

  setRecording(isRecording: boolean): void {
    this.currentRenderer?.setRecording?.(isRecording);
  }

  setRecordingMode(mode: 'loop' | 'continuous'): void {
    this.currentRenderer?.setRecordingMode?.(mode);
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
        ...(this.lastFailedWasmRenderer
          ? { wasm: this.lastFailedWasmRenderer.getDiagnostics() }
          : {}),
      };
    }

    if (this.lastFailedWasmRenderer) {
      return {
        ...baseDiagnostics,
        wasm: this.lastFailedWasmRenderer.getDiagnostics(),
      };
    }

    return baseDiagnostics;
  }

  /**
   * Render method called by WebGPUCanvas animation loop.
   * WebGPU renderer drives its own loop; WASM uploads video frames here then renders internally.
   */
  render(..._args: unknown[]): void {
    if (this.metrics.isWASM) {
      this.updateVideoFrame();
    }
  }

  /** Get latest FPS from the active renderer (real measured value). */
  getCurrentFPS(): number {
    return this.metrics.fps || 0;
  }

  /** Get audio analysis data from the active renderer (WebGPU only). */
  getAudioData(): { bass: number; mid: number; treble: number; freqBins: Float32Array } | null {
    if (this.currentRenderer instanceof WebGPURenderer) {
      return this.currentRenderer.getAudioData();
    }
    return null;
  }

  destroy(): void {
    this.currentRenderer?.destroy();
    this.currentRenderer = null;
  }
}

export default RendererManager;
