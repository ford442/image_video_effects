import { Renderer, RendererConfig, ShaderSlotRenderer } from './Renderer';
import * as WasmBridge from '../wasm/wasm_bridge.js';
import { reportError } from './ErrorHandling';
import { InputSource } from './types';

type SlotMode = 'chained' | 'parallel';

/**
 * Diagnostic information from the WASM renderer.
 */
export interface WASMDiagnostics {
  initialized: boolean;
  initAttempts: number;
  errorCount: number;
  lastErrorTime: string | null;
  fps: number;
  hasModule: boolean;
  adapterInfo: string;
  /** WebGPURenderer::InitStage of the last Initialize() attempt (0=None, 8=Ready). */
  failedStage: number;
  /** Human-readable reason for the last Initialize() failure, or '' if none. */
  lastInitError: string;
  /** InitStage name from C++ (e.g. 'Device', 'Surface'). */
  failedStageName: string;
  /** Bridge-layer load/init failures (from wasm_bridge.js getDiagnostics). */
  loadErrorCount: number;
  lastLoadError: string | null;
  initTime: string;
}

export class WASMRenderer implements Renderer, ShaderSlotRenderer {
  private config: RendererConfig;
  private video: HTMLVideoElement | null = null;
  private animationId: number | null = null;
  private startTime = 0;
  private mouseX = 0.5;
  private mouseY = 0.5;
  private mouseDown = false;
  private initialized = false;
  private inputSource: InputSource = 'image';

  // Offscreen canvas for extracting video/image pixel data
  private offscreenCanvas: HTMLCanvasElement | null = null;
  private offscreenCtx: CanvasRenderingContext2D | null = null;

  // Diagnostic tracking
  private lastErrorTime = 0;
  private errorCount = 0;
  private initAttempts = 0;
  private maxInitAttempts = 3;
  private consecutiveRenderErrors = 0;
  private maxRenderErrorsBeforeStopping = 10;
  private lastFrameDataUrl = '';
  private recording = false;

  constructor(config: RendererConfig) {
    this.config = config;
  }

  async init(canvas: HTMLCanvasElement): Promise<boolean> {
    this.initAttempts++;
    try {
      console.log(`[WASM] Init attempt ${this.initAttempts}/${this.maxInitAttempts}...`);
      
      const ok = await WasmBridge.initWasmRenderer(canvas);
      if (!ok) {
        const error = `WASM Renderer init failed (attempt ${this.initAttempts}/${this.maxInitAttempts}). ` +
                      `Common cause on Windows + Chrome/Edge: Dawn (C++) failed to acquire a WebGPU adapter. ` +
                      `See console for detailed C++ logs. Falling back to JS WebGPU renderer.`;
        console.error(`❌ ${error}`);
        reportError({
          type: 'wasm-init',
          message: error,
          recoverable: true
        });
        return false;
      }

      this.initialized = true;
      this.startTime = performance.now() / 1000;
      this.startRenderLoop();

      console.log('✅ WASM Renderer initialized successfully');
      return true;
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : String(err);
      console.error(`❌ WASM Renderer init error: ${errorMsg}`);
      reportError({
        type: 'wasm-init',
        message: `WASM initialization exception: ${errorMsg}`,
        recoverable: true
      });
      return false;
    }
  }

  /**
   * Get diagnostic information about the WASM renderer status.
   * Useful for debugging and verifying renderer health.
   */
  getDiagnostics(): WASMDiagnostics {
    const bridge = WasmBridge.getDiagnostics?.();

    return {
      initialized: this.initialized,
      initAttempts: this.initAttempts,
      errorCount: this.errorCount,
      lastErrorTime: this.lastErrorTime > 0 ? new Date(this.lastErrorTime).toISOString() : null,
      fps: WasmBridge.getFPS?.() ?? 0,
      hasModule: bridge?.hasModule ?? !!WasmBridge,
      adapterInfo: bridge?.adapterInfo ?? WasmBridge.getAdapterSummary?.() ?? '',
      failedStage: bridge?.failedStage ?? WasmBridge.getLastInitErrorStage?.() ?? 0,
      failedStageName: bridge?.failedStageName ?? 'None',
      lastInitError: bridge?.lastInitError ?? WasmBridge.getLastInitErrorMessage?.() ?? '',
      loadErrorCount: bridge?.loadErrorCount ?? 0,
      lastLoadError: bridge?.lastLoadError ?? null,
      initTime: bridge?.initTime ?? 'pending',
    };
  }

  /**
   * Fetch a WGSL shader from url and compile it under the given id.
   * Must be called before setActiveShader().
   */
  async loadShader(id: string, url: string): Promise<boolean> {
    return WasmBridge.loadShaderFromURL(id, url);
  }

  /** Switch to a previously loaded shader (legacy single-shader API). */
  setActiveShader(id: string): void {
    WasmBridge.setActiveShader(id);
  }

  /** Assign a loaded shader to a slot (0-2). */
  setSlotShader(slotIndex: number, id: string): void {
    WasmBridge.setSlotShader(slotIndex, id);
  }

  /** Set per-slot zoom parameters. */
  setSlotParams(slotIndex: number, p1: number, p2: number, p3: number, p4: number): void {
    WasmBridge.setSlotParams(slotIndex, p1, p2, p3, p4);
  }

  /**
   * Update zoom parameters for a specific slot from a SlotParams object.
   * Partial updates preserve unspecified params (matches TS WebGPURenderer).
   */
  updateSlotParams(
    params: { zoomParam1?: number; zoomParam2?: number; zoomParam3?: number; zoomParam4?: number },
    slotIndex = 0
  ): void {
    WasmBridge.updateSlotParams(slotIndex, params);
  }

  /** Set slot execution mode: 'chained' (default) or 'parallel'. */
  setSlotMode(slotIndex: number, mode: 'chained' | 'parallel'): void {
    WasmBridge.setSlotMode(slotIndex, mode);
  }

  /** Upload a depth map from the AI model (Float32Array, one float per pixel). */
  updateDepthMap(data: Float32Array, width: number, height: number): void {
    WasmBridge.updateDepthMap(data, width, height);
  }

  /** Set the active input source for generative / procedural shaders. */
  setInputSource(source: InputSource): void {
    this.inputSource = source;
    WasmBridge.setInputSource(source);
  }

  /** True when the current mode feeds live video frames into the C++ read texture. */
  private usesVideoInput(): boolean {
    return this.inputSource === 'video'
      || this.inputSource === 'webcam'
      || this.inputSource === 'live';
  }

  getInputSource(): InputSource {
    return this.inputSource;
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

  // ── Phase 2: Canvas resizing ──────────────────────────────────────────────

  /**
   * Resize the rendering canvas and recreate all size-dependent GPU resources.
   * Call this when the display canvas dimensions change.
   */
  resizeCanvas(newWidth: number, newHeight: number): void {
    WasmBridge.resizeCanvas(newWidth, newHeight);
  }

  // ── Phase 2: Screenshot capture ───────────────────────────────────────────

  /**
   * Capture the current rendered frame as an ImageData (RGBA8).
   * Asynchronous: triggers a GPU→CPU readback and resolves when complete.
   */
  captureFrame(): Promise<ImageData> {
    return WasmBridge.captureFrame();
  }

  /**
   * Take a screenshot and download it as a PNG file.
   * @param filename - Optional filename (default: 'screenshot.png').
   */
  takeScreenshot(filename?: string): Promise<void> {
    return WasmBridge.takeScreenshot(filename);
  }

  // ── Phase 2: Video recording ──────────────────────────────────────────────

  /**
   * Start recording the canvas output.
   * @param canvasElement - The canvas to record.
   * @param options       - Optional recording parameters (durationMs, frameRate, etc.).
   * @returns Promise that resolves with the recorded Blob when recording stops.
   */
  startRecording(
    canvasElement: HTMLCanvasElement,
    options?: { durationMs?: number; frameRate?: number; videoBitsPerSecond?: number }
  ): Promise<Blob> {
    return WasmBridge.startRecording(canvasElement, options);
  }

  /** Stop an in-progress recording immediately. */
  stopRecording(): void {
    WasmBridge.stopRecording();
  }

  /**
   * Record for `durationMs` milliseconds and automatically download the WebM.
   */
  recordAndDownload(
    canvasElement: HTMLCanvasElement,
    durationMs?: number,
    filename?: string
  ): Promise<void> {
    return WasmBridge.recordAndDownload(canvasElement, durationMs, filename);
  }

  // ── Renderer interface ─────────────────────────────────────────────────

  setVideo(video: HTMLVideoElement): void {
    this.video = video;
  }

  updateVideoFrame(): void {
    if (!this.usesVideoInput()) return;
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

  updateAudioData(bass: number, mid: number, treble: number): void {
    WasmBridge.updateAudioData(bass, mid, treble);
  }

  updateAudioFrequencyBins(bins: Float32Array): void {
    WasmBridge.updateAudioFrequencyBins(bins);
  }

  getSupportsDeepWorkgroup(): boolean {
    return WasmBridge.getSupportsDeepWorkgroup();
  }

  getSlotState(index: number): { shaderId: string | null; enabled: boolean; mode: SlotMode } | null {
    if (index < 0 || index > 2) return null;
    return WasmBridge.getSlotState(index);
  }

  getGPUTimings(): { parallelTime: number; chainedTime: number; totalTime: number; available: boolean } {
    return WasmBridge.getGPUTimings();
  }

  async reloadShaderFromURL(id: string, url: string): Promise<boolean> {
    return WasmBridge.reloadShaderFromURL(id, url);
  }

  /** Test hook: pin uniforms and render one WASM frame. */
  applyTestRenderState(state: {
    time?: number;
    mouseX?: number;
    mouseY?: number;
    mouseDown?: boolean;
    bass?: number;
    mid?: number;
    treble?: number;
  }): void {
    if (state.mouseX !== undefined) this.mouseX = state.mouseX;
    if (state.mouseY !== undefined) this.mouseY = state.mouseY;
    if (state.mouseDown !== undefined) this.mouseDown = state.mouseDown;
    if (state.bass !== undefined) {
      WasmBridge.updateAudioData(state.bass, state.mid ?? 0, state.treble ?? 0);
    }
    WasmBridge.updateUniforms({
      ...(state.time !== undefined ? { time: state.time } : {}),
      mouseX: this.mouseX,
      mouseY: this.mouseY,
      mouseDown: this.mouseDown,
    });
  }

  /** Returns the last captured frame as a PNG data URL, or '' if none yet. */
  getFrameImage(): string {
    return this.lastFrameDataUrl;
  }

  /** Capture the current frame and cache it for getFrameImage(). */
  async refreshFrameImage(): Promise<string> {
    this.lastFrameDataUrl = await WasmBridge.captureFrameDataUrl();
    return this.lastFrameDataUrl;
  }

  setRecording(isRecording: boolean): void {
    this.recording = isRecording;
    WasmBridge.setRecording(isRecording);
  }

  setRecordingMode(_mode: 'loop' | 'continuous'): void {
    // WASM path uses MediaRecorder; mode is handled at the App layer.
  }

  updateMouse(x: number, y: number): void {
    this.mouseX = x;
    this.mouseY = y;
    WasmBridge.updateMousePos(x, y);
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
      try {
        WasmBridge.updateUniforms({
          time,
          mouseX: this.mouseX,
          mouseY: this.mouseY,
          mouseDown: this.mouseDown,
        });
        // Reset error counter on success
        this.consecutiveRenderErrors = 0;
      } catch (err) {
        this.errorCount++;
        this.consecutiveRenderErrors++;
        this.lastErrorTime = Date.now();
        
        // Only log the first error and every 10th error to avoid console spam
        if (this.consecutiveRenderErrors === 1 || this.consecutiveRenderErrors % 10 === 0) {
          console.error('[WASM] Error during render loop update (attempt', this.consecutiveRenderErrors, '):', err);
        }
        
        // Stop the render loop after too many consecutive errors
        if (this.consecutiveRenderErrors >= this.maxRenderErrorsBeforeStopping) {
          console.error('[WASM] Stopping render loop after', this.maxRenderErrorsBeforeStopping, 'consecutive errors');
          this.initialized = false;
          return;
        }
      }

      this.animationId = requestAnimationFrame(loop);
    };

    loop();
  }
}
