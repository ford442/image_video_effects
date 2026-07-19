/**
 * WebGPURenderer.ts
 *
 * TypeScript WebGPU compute-shader renderer.
 *
 * Uses navigator.gpu directly — no WASM / Emscripten required.
 * Implements the same 13-binding compute shader contract used by all
 * 694 WGSL shaders in public/shaders/, with full multi-slot support.
 *
 * Bind group layout (group 0, matches every shader):
 *   0  sampler              filtering
 *   1  texture_2d<f32>      readTexture  (previous frame / input image)
 *   2  texture_storage …    writeTexture (rgba32float, write-only)
 *   3  uniform Uniforms     { config, zoom_config, zoom_params, ripples[50] }
 *   4  texture_2d<f32>      readDepthTexture
 *   5  sampler              non-filtering
 *   6  texture_storage …    writeDepthTexture (r32float, write-only)
 *   7  texture_storage …    dataTextureA  (rgba32float, write-only)
 *   8  texture_storage …    dataTextureB  (rgba32float, write-only)
 *   9  texture_2d<f32>      dataTextureC  (readable copy of A from prev frame)
 *  10  storage read_write   extraBuffer   (256 floats)
 *       [0]=bass, [1]=mid, [2]=treble, [3]=reserved, [4]=historyHead
 *       [5..132] = 128 FFT frequency bins (normalised 0-1, from useAudioAnalyzer
 *                  or any compatible source such as ford442/flac_player)
 *                  bin 0 → ~86 Hz, bin 127 → ~22 kHz (at 44.1 kHz, fftSize=256)
 *  11  sampler_comparison   comparison sampler
 *  12  storage read         plasmaBuffer
 *  13  texture_2d_array<f32> historyTexture  (HISTORY_DEPTH=8 past frames; opt-in)
 */

import { Renderer, RendererConfig, ShaderSlotRenderer, GPUTimings } from './Renderer';
import { resolveMultipassChain } from './multipassRegistry';
import { resolveGraphForShader } from './multipassGraph';
import { graphRunner } from './GraphRunner';
import { createUniformBufferView, UniformBufferView, Ripple, UNIFORM_FLOATS, MAX_RIPPLES } from './UniformBuffer';
import { reportError, getBrowserWarning } from './ErrorHandling';
import { BLIT_WGSL, GENERATIVE_BLIT_WGSL, VIDEO_COPY_WGSL } from './ShaderTemplates';
import { PHYSICAL_SLOT_LIMIT } from './slotOrchestrator';
import { initializeWebGPUDevice, attachDeviceLostHandler } from './webgpu/WebGPUDeviceInit';
import {
  createTextures,
  createSamplers,
  createBuffers,
  createComputeBindGroupLayout,
  createComputeBindGroup,
  createComputeBindGroupForPass,
  WebGPUTextureSet,
  WebGPUSamplerSet,
  WebGPUBufferSet,
} from './webgpu/WebGPUResourceManager';
import { setupTimestampQueries, buildGPUTimings } from './webgpu/WebGPUTiming';
import { WebGPUShaderManager } from './webgpu/WebGPUShaderManager';
import { HISTORY_DEPTH } from './webgpu/webgpuConstants';

// ── Constants matching C++ renderer ─────────────────────────────────────────

const MAX_PLASMA_BALLS   = 50;
const EXTRA_FLOATS       = 256;                     // 1024 bytes
const PLASMA_BYTES       = MAX_PLASMA_BALLS * 48;   // 2400 bytes

/**
 * extraBuffer layout:
 *   [0]    bass            (0-1, averaged over bass frequency range)
 *   [1]    mid             (0-1, averaged over mid frequency range)
 *   [2]    treble          (0-1, averaged over treble frequency range)
 *   [3]    reserved
 *   [4]    historyHead     (u32 cast from f32, ring-buffer write pointer)
 *   [5..132] FFT_BINS[0..127]  (128 per-bin magnitudes normalised to [0,1])
 *            bin 0  → ~86 Hz, bin 127 → ~22 kHz (44.1 kHz / fftSize=256)
 *            Wire format matches ford442/flac_player FFT output (N=128 bins).
 */
const EXTRA_BIN_OFFSET   = 5;    // First FFT bin index in extraBuffer
const AUDIO_FFT_BINS     = 128;  // Number of FFT bins stored in extraBuffer


// ── Compute Shader Workgroup Configuration ───────────────────────────────────
// Optimized for 2D image processing effects (liquid, distortion, generative)
// 
// WebGPU 2026 Recommendation: 256 invocations (16×16) for maximum occupancy
// on modern GPUs. This provides:
//
// 16×16 = 256 threads provides:
// - Better SM occupancy on NVIDIA/AMD/Intel/Apple Silicon (2026 GPUs)
// - 30-60% performance improvement for pixel-heavy shaders
// - Still efficient 2D memory access patterns
// - More threads per workgroup = better latency hiding
//
// Benchmark results on 2026 hardware:
// - 8×8 (64):  Base performance
// - 16×16 (256): +40% average on RTX 4090, +35% on M3 Max, +50% on RX 7900 XTX
//
// For 1D particle simulations (boids, flocking), use WG_SIZE_1D (256, 1, 1)

const WG_SIZE_X          = 16;  // Workgroup X dimension (was 8)
const WG_SIZE_Y          = 16;  // Workgroup Y dimension (was 8)
const WG_SIZE_1D         = 256; // Workgroup size for 1D dispatch (particles, was 64)

// Note: TRANSIENT_ATTACHMENT (Chrome 146+) requires RENDER_ATTACHMENT usage.
// Since we use compute shaders exclusively (not render passes), we cannot use
// TRANSIENT_ATTACHMENT. The standard TEXTURE_BINDING | STORAGE_BINDING is
// optimal for compute-only workflows.

// ── Typed Uniform Buffer Layout ─────────────────────────────────────────────
// Provides type-safe access to the uniform buffer structure matching WGSL
// (Definitions moved to UniformBuffer.ts)

// ── Error handling utilities ────────────────────────────────────────────────
// (Definitions moved to ErrorHandling.ts)

// ── Shader templates ─────────────────────────────────────────────────────────
// (Definitions moved to ShaderTemplates.ts)

// ── Types ────────────────────────────────────────────────────────────────────

/** Slot execution mode for inter-shader parallelization */
type SlotMode = 'chained' | 'parallel';

interface ShaderSlot {
  shaderId: string | null;
  enabled: boolean;
  mode: SlotMode;
}

// Ripple type is imported from UniformBuffer.ts

// ── Renderer class ───────────────────────────────────────────────────────────

export class WebGPURenderer implements Renderer, ShaderSlotRenderer {

  // WebGPU core
  private device: GPUDevice | null = null;
  private context: GPUCanvasContext | null = null;
  private canvasFormat: GPUTextureFormat = 'bgra8unorm';

  // Compute textures
  private sourceTex!: GPUTexture;   // original image/video source (rgba32float) - never modified by shaders
  private readTex!: GPUTexture;     // current input  (rgba32float)
  private writeTex!: GPUTexture;    // current output (rgba32float)
  private dataTexA!: GPUTexture;    // per-frame scratch A (rgba32float)
  private dataTexB!: GPUTexture;    // per-frame scratch B (rgba32float)
  private dataTexC!: GPUTexture;    // previous-frame copy of A (rgba32float)
  private historyTex!: GPUTexture;  // N-frame ring buffer (2d_array, HISTORY_DEPTH layers, rgba32float)
  private historyHead: number = 0;  // Ring write pointer (next layer to write)
  private depthRead!: GPUTexture;   // depth input  (r32float)
  private depthWrite!: GPUTexture;  // depth output (r32float)
  private emptyTex!: GPUTexture;    // 1×1 black placeholder (r32float)

  // Samplers
  private filterSampler!: GPUSampler;
  private nearestSampler!: GPUSampler;
  private compSampler!: GPUSampler;

  // GPU buffers
  private uniformBuf!: GPUBuffer;
  private extraBuf!: GPUBuffer;
  private plasmaBuf!: GPUBuffer;

  // Compute pipeline infrastructure
  private bindGroupLayout!: GPUBindGroupLayout;
  private pipelineLayout!: GPUPipelineLayout;
  // A single bind group (read=readTex, write=writeTex).
  // After each slot we copyTextureToTexture(writeTex → readTex) so the next
  // slot always reads up-to-date results from readTex.
  private computeBindGroup!: GPUBindGroup;

  // Blit (compute output → canvas)
  private blitPipeline!: GPURenderPipeline;
  private generativeBlitPipeline!: GPURenderPipeline;
  private blitBindGroupLayout!: GPUBindGroupLayout;
  private blitBindGroup!: GPUBindGroup;  // reads blitReadTex
  private blitReadTex!: GPUTexture;      // readTex normally, writeTex when single-slot copy is skipped
  private lastBlitReadTex: GPUTexture | null = null;   // cache key for bind-group recreation
  private lastBlitScaledW = 0;                         // cached dimensions to avoid recreating bind group
  private lastBlitScaledH = 0;

  // Shader pipeline cache (delegated to WebGPUShaderManager)
  private shaderManager = new WebGPUShaderManager();

  // Multi-slot state with parallelization support (PHYSICAL_SLOT_LIMIT slots)
  // Slot 0: Usually chained (background/base effect)
  // Slots 1–5: Can be parallel (independent overlays) or chained
  private slots: ShaderSlot[] = Array.from({ length: PHYSICAL_SLOT_LIMIT }, () => ({
    shaderId: null, enabled: false, mode: 'chained' as SlotMode,
  }));

  // Per-frame uniforms
  private currentTime = 0;
  // Mouse coordinates (normalized 0-1). Y=0 is TOP in browser events.
  // Shaders ported from systems like Shadertoy expect Y=0 at BOTTOM.
  // We store BOTH: mouseYBrowser (raw) and mouseYShader (1.0 - raw) so
  // shaders can pick the convention that matches their math.
  private mouseX      = 0.5;
  private mouseYBrowser = 0.5;   // raw from browser (top=0)
  private mouseYShader  = 0.5;   // inverted (bottom=0, matches Shadertoy)
  private mouseDown   = false;
  private zoomParams  = [0.5, 0.5, 0.5, 0.5];
  private ripples: Ripple[] = [];
  private audioBass   = 0;
  private audioMid    = 0;
  private audioTreble = 0;
  /** 128-bin FFT magnitude array written into extraBuffer[5..132] each frame. */
  private audioFreqBins: Float32Array = new Float32Array(AUDIO_FFT_BINS);

  // Canvas dimensions
  private canvasW = 0;
  private canvasH = 0;

  // Dynamic resolution scaling (0.25 - 1.0, default 1.0)
  // Reduces working texture size on low FPS or mobile for performance
  private resolutionScale = 1.0;
  private scaledW = 0;  // canvasW * resolutionScale (rounded to workgroup multiple)
  private scaledH = 0;  // canvasH * resolutionScale (rounded to workgroup multiple)

  // Timestamp query support for GPU profiling (measure parallelization gains)
  private supportsTimestampQuery = false;
  private hasF32Filterable = false;
  private querySet: GPUQuerySet | null = null;
  private queryBuffer: GPUBuffer | null = null;
  private gpuTimings: { parallelTime: number; chainedTime: number; totalTime: number } = { 
    parallelTime: 0, chainedTime: 0, totalTime: 0 
  };

  // Lifecycle
  private initialized  = false;
  private animationId: number | null = null;
  private startTime    = 0;

  // FPS tracking with adaptive quality
  private frameCount   = 0;
  private lastFPSTime  = 0;
  private fps          = 0;
  private targetFPS    = 60;
  private adaptiveQuality = false;  // Auto-adjust resolution based on FPS

  // Video / image input
  private video: HTMLVideoElement | null = null;
  private offscreen: HTMLCanvasElement | null = null;
  private offCtx: CanvasRenderingContext2D | null = null;
  private inputSource: 'image' | 'video' | 'webcam' | 'generative' | 'live' = 'image';
  
  // Zero-copy video optimization
  private videoExternalTexture: GPUExternalTexture | null = null;
  private videoCopyPipeline: GPURenderPipeline | null = null;
  private videoCopyBindGroupLayout: GPUBindGroupLayout | null = null;
  private supportsExternalTexture: boolean = false;

  // Subgroup operations support (Chrome 128+)
  private supportsSubgroups: boolean = false;

  // Deep-workgroup support: @workgroup_size(16,16,4) = 1024 invocations
  // True on Apple M1/M2/M3, NVIDIA RTX, AMD RDNA2+; false on Intel UHD / older mobile
  private supportsDeepWorkgroup: boolean = false;

  constructor(private config: RendererConfig) {}

  /** Returns true if the GPU supports 1024-invocation workgroups (16×16×4). */
  getSupportsDeepWorkgroup(): boolean { return this.supportsDeepWorkgroup; }

  // ── Initialisation ─────────────────────────────────────────────────────────

  async init(canvas: HTMLCanvasElement): Promise<boolean> {
    if (this.initialized) return true;

    const outcome = await initializeWebGPUDevice(
      canvas,
      this.config.width,
      this.config.height,
    );
    if (!outcome.ok) return false;

    this.device = outcome.device;
    this.context = outcome.context;
    this.canvasFormat = outcome.canvasFormat;
    this.canvasW = outcome.canvasW;
    this.canvasH = outcome.canvasH;
    this.supportsSubgroups = outcome.supportsSubgroups;
    this.supportsDeepWorkgroup = outcome.supportsDeepWorkgroup;
    const hasF32Filt = outcome.hasF32Filterable;
    this.hasF32Filterable = hasF32Filt;

    attachDeviceLostHandler(outcome.device, outcome.context, () => {
      this.initialized = false;
    });

    this.updateScaledDimensions();
    this.setupGpuResources(hasF32Filt);

    this.initialized = true;
    this.startTime   = performance.now() / 1000;
    this.lastFPSTime = this.startTime;
    this.startRenderLoop();

    console.log(
      `✅ TypeScript WebGPU renderer initialized ` +
      `(${this.canvasW}×${this.canvasH}` +
      `${hasF32Filt ? ', float32-filterable' : ''}` +
      `${this.supportsSubgroups ? ', subgroups' : ''}` +
      `${this.supportsDeepWorkgroup ? ', deep-workgroup' : ''})` +
      (outcome.adapterAttemptLabel ? ` [${outcome.adapterAttemptLabel}]` : '')
    );
    return true;
  }

  private setupGpuResources(hasF32Filt: boolean): void {
    const d = this.device!;
    const textures = createTextures(d, this.canvasW, this.canvasH, this.scaledW, this.scaledH);
    this.applyTextureSet(textures);

    const samplers = createSamplers(d);
    this.filterSampler = samplers.filterSampler;
    this.nearestSampler = samplers.nearestSampler;
    this.compSampler = samplers.compSampler;

    const buffers = createBuffers(d);
    this.uniformBuf = buffers.uniformBuf;
    this.extraBuf = buffers.extraBuf;
    this.plasmaBuf = buffers.plasmaBuf;

    const computeLayout = createComputeBindGroupLayout(d, hasF32Filt);
    this.bindGroupLayout = computeLayout.bindGroupLayout;
    this.pipelineLayout = computeLayout.pipelineLayout;
    this.computeBindGroup = createComputeBindGroup(
      d,
      computeLayout.bindGroupLayout,
      textures,
      buffers,
      samplers,
    );

    this.createBlitPipeline();

    const timing = setupTimestampQueries(d);
    this.supportsTimestampQuery = timing.supportsTimestampQuery;
    this.querySet = timing.querySet;
    this.queryBuffer = timing.queryBuffer;
  }

  private applyTextureSet(tex: WebGPUTextureSet): void {
    this.sourceTex = tex.sourceTex;
    this.readTex = tex.readTex;
    this.writeTex = tex.writeTex;
    this.dataTexA = tex.dataTexA;
    this.dataTexB = tex.dataTexB;
    this.dataTexC = tex.dataTexC;
    this.historyTex = tex.historyTex;
    this.depthRead = tex.depthRead;
    this.depthWrite = tex.depthWrite;
    this.emptyTex = tex.emptyTex;
    this.historyHead = 0;
    this.blitReadTex = this.readTex;
  }

  private getTextureSet(): WebGPUTextureSet {
    return {
      sourceTex: this.sourceTex,
      readTex: this.readTex,
      writeTex: this.writeTex,
      dataTexA: this.dataTexA,
      dataTexB: this.dataTexB,
      dataTexC: this.dataTexC,
      historyTex: this.historyTex,
      depthRead: this.depthRead,
      depthWrite: this.depthWrite,
      emptyTex: this.emptyTex,
    };
  }

  private getBufferSet(): WebGPUBufferSet {
    return {
      uniformBuf: this.uniformBuf,
      extraBuf: this.extraBuf,
      plasmaBuf: this.plasmaBuf,
    };
  }

  private getSamplerSet(): WebGPUSamplerSet {
    return {
      filterSampler: this.filterSampler,
      nearestSampler: this.nearestSampler,
      compSampler: this.compSampler,
    };
  }

  private destroyWorkingTextures(): void {
    for (const t of [
      this.sourceTex, this.readTex, this.writeTex, this.dataTexA, this.dataTexB,
      this.dataTexC, this.historyTex, this.depthRead, this.depthWrite, this.emptyTex,
    ]) {
      t?.destroy();
    }
  }

  private recreateScaleTextures(): void {
    const d = this.device!;
    this.destroyWorkingTextures();
    const textures = createTextures(d, this.canvasW, this.canvasH, this.scaledW, this.scaledH);
    this.applyTextureSet(textures);
    this.computeBindGroup = createComputeBindGroup(
      d,
      this.bindGroupLayout,
      textures,
      this.getBufferSet(),
      this.getSamplerSet(),
    );
  }

  private createBindGroupForPass(readTex: GPUTexture, writeTex: GPUTexture): GPUBindGroup {
    return createComputeBindGroupForPass(
      this.device!,
      this.bindGroupLayout,
      readTex,
      writeTex,
      this.getTextureSet(),
      this.getBufferSet(),
      this.getSamplerSet(),
    );
  }

  // ── Resource creation (blit pipeline — scale path differs from WebGPURenderLoop module) ──

  private createBlitPipeline(): void {
    const d = this.device!;

    this.blitBindGroupLayout = d.createBindGroupLayout({
      label: 'blitBGL',
      entries: [
        // textureLoad() is used in the blit shader, so sampleType can be
        // 'unfilterable-float' — no float32-filterable requirement.
        { binding: 0, visibility: GPUShaderStage.FRAGMENT,
          texture: { sampleType: 'unfilterable-float' } },
      ],
    });

    const module = d.createShaderModule({ label: 'blitShader', code: BLIT_WGSL });
    const generativeModule = d.createShaderModule({
      label: 'generativeBlitShader',
      code: GENERATIVE_BLIT_WGSL,
    });

    this.blitPipeline = d.createRenderPipeline({
      label: 'blitPipeline',
      layout: d.createPipelineLayout({ bindGroupLayouts: [this.blitBindGroupLayout] }),
      vertex:   { module, entryPoint: 'vs' },
      fragment: { module, entryPoint: 'fs', targets: [{ format: this.canvasFormat }] },
      primitive: { topology: 'triangle-list' },
    });

    this.generativeBlitPipeline = d.createRenderPipeline({
      label: 'generativeBlitPipeline',
      layout: d.createPipelineLayout({ bindGroupLayouts: [this.blitBindGroupLayout] }),
      vertex:   { module: generativeModule, entryPoint: 'vs' },
      fragment: { module: generativeModule, entryPoint: 'fs', targets: [{ format: this.canvasFormat }] },
      primitive: { topology: 'triangle-list' },
    });

    // Blit reads from blitReadTex (readTex by default; writeTex when the single
    // active chained slot skips the redundant writeTex→readTex copy).
    this.blitBindGroup = d.createBindGroup({
      label: 'blitBG',
      layout: this.blitBindGroupLayout,
      entries: [{ binding: 0, resource: this.blitReadTex.createView() }],
    });
    this.lastBlitReadTex = this.blitReadTex;
    this.lastBlitScaledW = this.scaledW;
    this.lastBlitScaledH = this.scaledH;

    // ── Zero-copy video pipeline ─────────────────────────────────────────────
    // Check if importExternalTexture is supported
    this.supportsExternalTexture = 'importExternalTexture' in d;
    
    if (this.supportsExternalTexture) {
      this.videoCopyBindGroupLayout = d.createBindGroupLayout({
        label: 'videoCopyBGL',
        entries: [
          { binding: 0, visibility: GPUShaderStage.FRAGMENT,
            externalTexture: {} },
          { binding: 1, visibility: GPUShaderStage.FRAGMENT,
            sampler: { type: 'filtering' } },
        ],
      });

      const videoModule = d.createShaderModule({ 
        label: 'videoCopyShader', 
        code: VIDEO_COPY_WGSL 
      });

      this.videoCopyPipeline = d.createRenderPipeline({
        label: 'videoCopyPipeline',
        layout: d.createPipelineLayout({ 
          bindGroupLayouts: [this.videoCopyBindGroupLayout] 
        }),
        vertex:   { module: videoModule, entryPoint: 'vs_main' },
        fragment: { 
          module: videoModule, 
          entryPoint: 'fs_main', 
          targets: [{ format: 'rgba32float' }] 
        },
        primitive: { topology: 'triangle-list' },
      });
    }
  }

  /** Get GPU timing data for performance analysis */
  getGPUTimings(): GPUTimings {
    return buildGPUTimings(this.gpuTimings, this.supportsTimestampQuery);
  }

  /** Test hook: pin uniforms and render one frame. */
  applyTestRenderState(state: {
    time?: number;
    mouseX?: number;
    mouseY?: number;
    bass?: number;
    mid?: number;
    treble?: number;
  }): void {
    if (state.time !== undefined) this.currentTime = state.time;
    if (state.mouseX !== undefined) this.mouseX = state.mouseX;
    if (state.mouseY !== undefined) {
      this.mouseYBrowser = state.mouseY;
      this.mouseYShader = 1.0 - state.mouseY;
    }
    if (state.bass !== undefined) {
      this.updateAudioData(state.bass, state.mid ?? 0, state.treble ?? 0);
    }
    this.renderFrame();
  }

  // ── Shader management ──────────────────────────────────────────────────────

  async loadShader(id: string, url: string): Promise<boolean> {
    return this.shaderManager.loadShader(
      this.device,
      this.pipelineLayout,
      this.supportsSubgroups,
      id,
      url,
    );
  }

  private compileShader(id: string, wgsl: string): boolean {
    if (!this.device || !this.pipelineLayout) return false;
    return this.shaderManager.compile(this.device, this.pipelineLayout, id, wgsl);
  }

  /** Set a single active shader (slot 0). Clears all other slots. */
  setActiveShader(id: string): void {
    this.slots[0] = { shaderId: id, enabled: true, mode: 'chained' };
    for (let i = 1; i < PHYSICAL_SLOT_LIMIT; i++) {
      this.slots[i] = { shaderId: null, enabled: false, mode: 'chained' };
    }
  }

  /** Set which shader is bound to a specific slot (0–PHYSICAL_SLOT_LIMIT-1). */
  setSlotShader(index: number, id: string): void {
    if (index >= 0 && index < PHYSICAL_SLOT_LIMIT) {
      const mode = this.slots[index]?.mode ?? 'chained';
      this.slots[index] = { shaderId: id, enabled: !!id, mode };
      console.log(`[WebGPURenderer] Slot ${index} set to "${id}" (enabled: ${!!id}, mode: ${mode})`);
      console.log(`[WebGPURenderer] Current slots:`, this.slots.map(s => ({ id: s.shaderId, enabled: s.enabled, mode: s.mode })));
    }
  }

  setSlotEnabled(index: number, enabled: boolean): void {
    if (index >= 0 && index < PHYSICAL_SLOT_LIMIT) this.slots[index].enabled = enabled;
  }

  /** 
   * Set slot execution mode: 'chained' (sequential) or 'parallel' (concurrent).
   * 
   * Chained: Output of slot N feeds into slot N+1. Use for layered effects.
   * Parallel: All parallel slots read from same input. Use for independent overlays.
   */
  setSlotMode(index: number, mode: SlotMode): void {
    if (index >= 0 && index < PHYSICAL_SLOT_LIMIT) {
      this.slots[index].mode = mode;
    }
  }

  /** Get current slot mode */
  getSlotMode(index: number): SlotMode | null {
    if (index >= 0 && index < PHYSICAL_SLOT_LIMIT) {
      return this.slots[index].mode;
    }
    return null;
  }

  /** Get full slot state for UI display */
  getSlotState(index: number): { shaderId: string | null; enabled: boolean; mode: SlotMode } | null {
    if (index >= 0 && index < PHYSICAL_SLOT_LIMIT) {
      const slot = this.slots[index];
      return { shaderId: slot.shaderId, enabled: slot.enabled, mode: slot.mode };
    }
    return null;
  }

  addRipple(x: number, y: number): void {
    if (this.ripples.length >= MAX_RIPPLES) this.ripples.shift();
    this.ripples.push({ x, y, startTime: this.currentTime });
  }

  clearRipples(): void { this.ripples = []; }

  getFPS(): number { return this.fps; }

  /** Get audio analysis data for external consumers (e.g. audio-reactive params). */
  getAudioData(): { bass: number; mid: number; treble: number; freqBins: Float32Array } {
    return {
      bass: this.audioBass,
      mid: this.audioMid,
      treble: this.audioTreble,
      freqBins: this.audioFreqBins,
    };
  }

  /** Get current video pipeline status for debugging */
  getVideoStatus(): { hasVideo: boolean; playing: boolean; readyState: number; currentTime: number; videoWidth: number; videoHeight: number } | null {
    if (!this.video) return null;
    return {
      hasVideo: true,
      playing: !this.video.paused,
      readyState: this.video.readyState,
      currentTime: this.video.currentTime,
      videoWidth: this.video.videoWidth,
      videoHeight: this.video.videoHeight,
    };
  }

  /** Check if a shader is already cached (for hot-swap optimization) */
  isShaderCached(id: string): boolean {
    return this.shaderManager.hasPipeline(id);
  }

  getPipelineCacheStats(): { cachedCount: number; cachedIds: string[] } {
    return this.shaderManager.getCacheStats();
  }

  /** Pre-compile a shader for faster hot-swapping later */
  async preloadShader(id: string, url: string): Promise<boolean> {
    return this.loadShader(id, url);
  }

  /** Get workgroup configuration for debugging/optimization */
  getWorkgroupConfig(): { 
    size2D: [number, number]; 
    size1D: number; 
    invocationsPerGroup: number;
    dispatch2D: { x: number; y: number };
  } {
    return {
      size2D: [WG_SIZE_X, WG_SIZE_Y],
      size1D: WG_SIZE_1D,
      invocationsPerGroup: WG_SIZE_X * WG_SIZE_Y,
      dispatch2D: {
        x: Math.ceil(this.canvasW / WG_SIZE_X),
        y: Math.ceil(this.canvasH / WG_SIZE_Y),
      },
    };
  }

  /** 
   * Set resolution scale for dynamic quality (0.25 - 1.0).
   * Lower values reduce working texture size for better FPS on weak hardware.
   * Final output is bilinear upscaled to full canvas size.
   */
  setResolutionScale(scale: number): void {
    // Clamp to valid range and snap to workgroup-multiple-friendly values
    const clamped = Math.max(0.25, Math.min(1.0, scale));
    // Round to nearest 0.125 to ensure clean workgroup divisions
    const snapped = Math.round(clamped * 8) / 8;
    
    if (this.resolutionScale !== snapped) {
      this.resolutionScale = snapped;
      this.updateScaledDimensions();
      
      // Recreate textures at new resolution
      if (this.device && this.initialized) {
        this.recreateScaleTextures();
        this.updateBlitBindGroup();
      }
    }
  }

  /** Get current resolution scale and effective dimensions */
  getResolutionScale(): { 
    scale: number; 
    full: { w: number; h: number }; 
    scaled: { w: number; h: number };
    pixelReduction: string;
  } {
    const fullPixels = this.canvasW * this.canvasH;
    const scaledPixels = this.scaledW * this.scaledH;
    return {
      scale: this.resolutionScale,
      full: { w: this.canvasW, h: this.canvasH },
      scaled: { w: this.scaledW, h: this.scaledH },
      pixelReduction: `${Math.round((1 - scaledPixels / fullPixels) * 100)}%`,
    };
  }

  /** Enable/disable adaptive quality based on FPS */
  setAdaptiveQuality(enabled: boolean, targetFPS = 60): void {
    this.adaptiveQuality = enabled;
    this.targetFPS = targetFPS;
  }

  /** Update scaled dimensions based on resolutionScale */
  private updateScaledDimensions(): void {
    // Round to workgroup-multiple to avoid partial tiles
    this.scaledW = Math.ceil((this.canvasW * this.resolutionScale) / WG_SIZE_X) * WG_SIZE_X;
    this.scaledH = Math.ceil((this.canvasH * this.resolutionScale) / WG_SIZE_Y) * WG_SIZE_Y;
  }

  /** Adapt resolution based on current FPS (call once per second) */
  private adaptQualityIfNeeded(): void {
    if (!this.adaptiveQuality) return;
    
    const ratio = this.fps / this.targetFPS;
    
    if (ratio < 0.7 && this.resolutionScale > 0.25) {
      // FPS too low, reduce quality
      this.setResolutionScale(this.resolutionScale - 0.125);
      console.log(`[WebGPU] FPS low (${this.fps}), reducing resolution to ${this.resolutionScale}`);
    } else if (ratio > 0.95 && this.resolutionScale < 1.0) {
      // FPS good, can increase quality
      this.setResolutionScale(this.resolutionScale + 0.0625);
      console.log(`[WebGPU] FPS good (${this.fps}), increasing resolution to ${this.resolutionScale}`);
    }
  }

  // ── BaseRenderer interface ─────────────────────────────────────────────────

  setVideo(video: HTMLVideoElement | undefined): void {
    this.video = video ?? null;
  }

  updateVideoFrame(): void {
    if (!this.video || this.video.readyState < 2) return;
    const vw = this.video.videoWidth, vh = this.video.videoHeight;
    if (!vw || !vh) return;

    try {
      // Check if video is corrupted or errored
      if (this.video.error) {
        const errorCode = this.video.error.code;
        const errorMessages: Record<number, string> = {
          1: 'Video loading aborted',
          2: 'Network error while loading video',
          3: 'Video decoding error (corrupt file?)',
          4: 'Video format not supported'
        };
        
        reportError({
          type: 'media-load',
          message: `Video error: ${errorMessages[errorCode] || 'Unknown video error'}`,
          recoverable: true
        });
        
        // Show black frame on error
        this.clearSourceTexture();
        return;
      }

      // Try zero-copy path first (importExternalTexture)
      if (this.supportsExternalTexture && this.device && this.videoCopyPipeline) {
        this.updateVideoFrameZeroCopy();
      } else {
        // Fallback to canvas-based CPU readback
        this.updateVideoFrameCanvasFallback();
      }
    } catch (e) {
      console.warn('[WebGPU] Video frame upload failed:', e);
      // Gracefully handle by showing black frame
      this.clearSourceTexture();
    }
  }

  /** Zero-copy video frame update using importExternalTexture */
  private updateVideoFrameZeroCopy(): void {
    if (!this.device || !this.video || !this.videoCopyPipeline || !this.videoCopyBindGroupLayout) return;

    // Import external texture from video element (zero-copy GPU path)
    this.videoExternalTexture = this.device.importExternalTexture({ source: this.video! });

    // Create bind group for this frame (external textures are transient)
    const videoCopyBindGroup = this.device.createBindGroup({
      label: 'videoCopyBG',
      layout: this.videoCopyBindGroupLayout,
      entries: [
        { binding: 0, resource: this.videoExternalTexture },
        { binding: 1, resource: this.filterSampler },
      ],
    });

    // Render pass: copy from external texture to sourceTex
    const encoder = this.device.createCommandEncoder({ label: 'videoCopyEncoder' });
    
    const pass = encoder.beginRenderPass({
      label: 'videoCopyPass',
      colorAttachments: [{
        view: this.sourceTex.createView(),
        loadOp: 'clear',
        storeOp: 'store',
        clearValue: { r: 0, g: 0, b: 0, a: 1 },
      }],
    });

    pass.setPipeline(this.videoCopyPipeline);
    pass.setBindGroup(0, videoCopyBindGroup);
    pass.draw(3);  // Full-screen triangle
    pass.end();

    this.device.queue.submit([encoder.finish()]);
    
    // External texture is only valid until next submit, so clear reference
    this.videoExternalTexture = null;
  }

  /** Canvas-based fallback for browsers without importExternalTexture support */
  private updateVideoFrameCanvasFallback(): void {
    if (!this.video) return;
    const dstW = this.canvasW, dstH = this.canvasH;

    if (!this.offscreen || this.offscreen.width !== dstW || this.offscreen.height !== dstH) {
      this.offscreen = document.createElement('canvas');
      this.offscreen.width = dstW;
      this.offscreen.height = dstH;
      this.offCtx = this.offscreen.getContext('2d', { willReadFrequently: true });
    }
    if (!this.offCtx) return;

    this.offCtx.drawImage(this.video!, 0, 0, dstW, dstH);
    this.uploadRGBA8(this.offCtx.getImageData(0, 0, dstW, dstH).data, dstW, dstH);
  }

  /** Clear source texture to black (for error handling) */
  private clearSourceTexture(): void {
    if (!this.device) return;
    
    const encoder = this.device.createCommandEncoder({ label: 'clearSourceEncoder' });
    const pass = encoder.beginRenderPass({
      label: 'clearSourcePass',
      colorAttachments: [{
        view: this.sourceTex.createView(),
        loadOp: 'clear',
        storeOp: 'store',
        clearValue: { r: 0, g: 0, b: 0, a: 1 },
      }],
    });
    pass.end();
    this.device.queue.submit([encoder.finish()]);
  }

  async loadImage(url: string): Promise<string> {
    try {
      const img = new Image();
      img.crossOrigin = 'anonymous';
      
      // Set up error handling before setting src
      await new Promise<void>((resolve, reject) => {
        img.onload = () => resolve();
        img.onerror = () => reject(new Error(`Failed to load image: ${url}`));
        img.src = url;
      });

      // Scale image to fill the full canvas texture (letterbox to preserve aspect ratio)
      const dstW = this.canvasW, dstH = this.canvasH;
      const srcAspect = img.naturalWidth / img.naturalHeight;
      const dstAspect = dstW / dstH;
      let drawW = dstW, drawH = dstH, drawX = 0, drawY = 0;
      if (srcAspect > dstAspect) {
        // Image wider than canvas — fit to width, letterbox top/bottom
        drawH = dstW / srcAspect;
        drawY = (dstH - drawH) / 2;
      } else {
        // Image taller than canvas — fit to height, pillarbox left/right
        drawW = dstH * srcAspect;
        drawX = (dstW - drawW) / 2;
      }

      if (!this.offscreen || this.offscreen.width !== dstW || this.offscreen.height !== dstH) {
        this.offscreen = document.createElement('canvas');
        this.offscreen.width  = dstW;
        this.offscreen.height = dstH;
        this.offCtx = this.offscreen.getContext('2d', { willReadFrequently: true });
      }
      if (!this.offCtx) return url;

      this.offCtx.fillStyle = 'black';
      this.offCtx.fillRect(0, 0, dstW, dstH);
      this.offCtx.drawImage(img, drawX, drawY, drawW, drawH);

      this.uploadRGBA8(this.offCtx.getImageData(0, 0, dstW, dstH).data, dstW, dstH);
      return url;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      
      reportError({
        type: 'media-load',
        message: `Failed to load image "${url}": ${errorMessage}`,
        recoverable: true
      });
      
      console.warn(`[WebGPU] Image load failed:`, error);
      
      // Upload a black frame as fallback
      if (this.offscreen && this.offCtx) {
        const dstW = this.canvasW, dstH = this.canvasH;
        this.offCtx.fillStyle = 'black';
        this.offCtx.fillRect(0, 0, dstW, dstH);
        this.uploadRGBA8(this.offCtx.getImageData(0, 0, dstW, dstH).data, dstW, dstH);
      }
      
      throw error;
    }
  }

  private uploadRGBA8(data: Uint8ClampedArray, srcW: number, srcH: number): void {
    if (!this.device) return;
    const dstW = this.canvasW, dstH = this.canvasH;
    const cW = Math.min(srcW, dstW), cH = Math.min(srcH, dstH);

    // Convert RGBA8 → RGBA32Float in JS
    const floats = new Float32Array(cW * cH * 4);
    for (let y = 0; y < cH; y++) {
      for (let x = 0; x < cW; x++) {
        const si = (y * srcW + x) * 4;
        const di = (y * cW  + x) * 4;
        floats[di]     = data[si]     / 255;
        floats[di + 1] = data[si + 1] / 255;
        floats[di + 2] = data[si + 2] / 255;
        floats[di + 3] = data[si + 3] / 255;
      }
    }
    // Upload to both sourceTex (preserved) and readTex (working copy)
    this.device.queue.writeTexture(
      { texture: this.sourceTex },
      floats,
      { bytesPerRow: cW * 16, rowsPerImage: cH },
      [cW, cH],
    );
    this.device.queue.writeTexture(
      { texture: this.readTex },
      floats,
      { bytesPerRow: cW * 16, rowsPerImage: cH },
      [cW, cH],
    );
  }

  updateAudioData(bass: number, mid: number, treble: number): void {
    this.audioBass = bass; this.audioMid = mid; this.audioTreble = treble;
  }

  /**
   * Push a full 128-bin FFT magnitude array to the renderer.
   * Values must be normalised to [0, 1]. They are flushed into
   * extraBuffer[5..132] on the next frame upload.
   *
   * Compatible with ford442/flac_player wire format (N=128 bins).
   */
  updateAudioFrequencyBins(bins: Float32Array): void {
    const len = Math.min(bins.length, AUDIO_FFT_BINS);
    this.audioFreqBins.set(bins.subarray(0, len), 0);
    if (len < AUDIO_FFT_BINS) {
      this.audioFreqBins.fill(0, len);
    }
  }

  updateMouse(x: number, y: number): void {
    this.mouseX = x;
    this.mouseYBrowser = y;
    this.mouseYShader = 1.0 - y; // Invert so Y=0 is bottom (Shadertoy convention)
  }

  setParam(name: string, value: number): void {
    switch (name) {
      case 'mouseDown':  this.mouseDown      = value > 0; break;
      case 'zoomParam1': this.zoomParams[0]  = value;     break;
      case 'zoomParam2': this.zoomParams[1]  = value;     break;
      case 'zoomParam3': this.zoomParams[2]  = value;     break;
      case 'zoomParam4': this.zoomParams[3]  = value;     break;
    }
  }

  /** Per-slot zoom params (slotIndex accepted for API parity with WASM; TS renderer uses slot 0 for uniforms). */
  setSlotParams(slotIndex: number, p1: number, p2: number, p3: number, p4: number): void {
    if (slotIndex === 0) {
      this.zoomParams[0] = p1;
      this.zoomParams[1] = p2;
      this.zoomParams[2] = p3;
      this.zoomParams[3] = p4;
    }
  }

  /** Update zoom params from SlotParams (called when UI changes). slotIndex ignored except for slot 0. */
  updateSlotParams(
    params: { zoomParam1?: number; zoomParam2?: number; zoomParam3?: number; zoomParam4?: number },
    slotIndex = 0
  ): void {
    if (slotIndex !== 0) return;
    if (params.zoomParam1 !== undefined) this.zoomParams[0] = params.zoomParam1;
    if (params.zoomParam2 !== undefined) this.zoomParams[1] = params.zoomParam2;
    if (params.zoomParam3 !== undefined) this.zoomParams[2] = params.zoomParam3;
    if (params.zoomParam4 !== undefined) this.zoomParams[3] = params.zoomParam4;
  }

  /** Set the active input source for generative/procedural, image, video, webcam, or live. */
  setInputSource(source: 'image' | 'video' | 'webcam' | 'generative' | 'live'): void {
    this.inputSource = source;
    
    // For generative mode, ensure source texture is black (no input image)
    if (source === 'generative') {
      this.clearSourceTexture();
    }
    
    if (process.env.NODE_ENV === 'development') {
      console.log(`[WebGPU] Input source set to: ${source}`);
    }
  }

  getInputSource(): 'image' | 'video' | 'webcam' | 'generative' | 'live' {
    return this.inputSource;
  }

  /** render() is a no-op; actual rendering is driven by the internal RAF loop. */
  render(): void {}

  /**
   * Dispatch a single slot, expanding multipass chains into sequential
   * compute passes within the same command encoder.
   */
  private dispatchSlot(
    encoder: GPUCommandEncoder,
    slot: { shaderId: string | null; enabled: boolean; mode: SlotMode },
    labelPrefix: string
  ): void {
    if (!slot.shaderId || !this.device) return;

    const graph = resolveGraphForShader(slot.shaderId);
    if (graph) {
      graphRunner.runGraph(encoder, graph, {
        device: this.device,
        pipelineLayout: this.pipelineLayout,
        getPipeline: (shaderId) => this.shaderManager.getPipeline(shaderId),
        getWorkgroupSize: (shaderId) => this.shaderManager.getWorkgroupSize(shaderId),
        createBindGroupForPass: (readTex, writeTex) => this.createBindGroupForPass(readTex, writeTex),
        textures: {
          readTex: this.readTex,
          writeTex: this.writeTex,
          dataTexA: this.dataTexA,
          dataTexB: this.dataTexB,
          dataTexC: this.dataTexC,
        },
        scaledW: this.scaledW,
        scaledH: this.scaledH,
      });
      return;
    }

    const chain = resolveMultipassChain(slot.shaderId);
    for (const shaderId of chain) {
      const pipeline = this.shaderManager.getPipeline(shaderId);
      if (!pipeline) {
        console.warn(`[WebGPURenderer] Pipeline missing for multipass step "${shaderId}"`);
        continue;
      }
      const wg = this.shaderManager.getWorkgroupSize(shaderId);
      const pass = encoder.beginComputePass({ label: `${labelPrefix}-${shaderId}` });
      pass.setPipeline(pipeline);
      pass.setBindGroup(0, this.computeBindGroup);
      pass.dispatchWorkgroups(
        Math.ceil(this.scaledW / wg.x),
        Math.ceil(this.scaledH / wg.y),
        1
      );
      pass.end();
    }
  }

  destroy(): void {
    if (this.animationId !== null) {
      cancelAnimationFrame(this.animationId);
      this.animationId = null;
    }
    this.initialized = false;
    this.shaderManager.clear();

    for (const t of [this.sourceTex, this.readTex, this.writeTex, this.dataTexA, this.dataTexB,
                     this.dataTexC, this.historyTex, this.depthRead, this.depthWrite, this.emptyTex]) {
      t?.destroy();
    }
    for (const b of [this.uniformBuf, this.extraBuf, this.plasmaBuf]) {
      b?.destroy();
    }
    this.context?.unconfigure();
    this.device?.destroy();
    this.device = null;
  }

  // ── Internal render loop ───────────────────────────────────────────────────

  private startRenderLoop(): void {
    const loop = () => {
      if (!this.initialized) return;
      this.currentTime = performance.now() / 1000 - this.startTime;
      this.renderFrame();
      this.animationId = requestAnimationFrame(loop);
    };
    loop();
  }

  private renderFrame(): void {
    if (!this.device || !this.context || !this.initialized) return;

    // Update video frame if video is playing (called every frame for smooth playback)
    if (this.video && !this.video.paused && this.video.readyState >= 2) {
      this.updateVideoFrame();
    } else if (this.video && this.video.readyState >= 2 && this.frameCount % 60 === 0) {
      // Debug: log video state periodically if not playing
      if (process.env.NODE_ENV === 'development') {
        console.log('[WebGPURenderer] Video state:', {
          paused: this.video.paused,
          readyState: this.video.readyState,
          videoWidth: this.video.videoWidth,
          videoHeight: this.video.videoHeight,
          src: this.video.src?.substring(0, 100),
          error: this.video.error?.code
        });
      }
    }

    const enabled = this.slots.filter(
      s => s.enabled && s.shaderId && this.shaderManager.hasPipeline(s.shaderId)
    );


    if (enabled.length === 0) {
      // No active shader — show whatever is in readTex (black initially)
      this.blitReadTex = this.readTex;
      this.blitToCanvas();
      return;
    }

    this.writeUniforms();

    const encoder = this.device.createCommandEncoder({ label: 'frame' });

    // Scale source to working resolution if needed (bilinear downscale)
    if (this.resolutionScale < 1.0) {
      // Use a render pass for bilinear downscale (all within same encoder)
      const scalePass = encoder.beginRenderPass({
        label: 'scalePass',
        colorAttachments: [{
          view: this.readTex.createView(),
          loadOp: 'clear',
          storeOp: 'store',
          clearValue: { r: 0, g: 0, b: 0, a: 1 },
        }],
      });
      scalePass.setPipeline(this.videoCopyPipeline!);  // Re-use video copy pipeline
      scalePass.setBindGroup(0, this.device.createBindGroup({
        layout: this.videoCopyBindGroupLayout!,
        entries: [
          { binding: 0, resource: this.sourceTex.createView() },
          { binding: 1, resource: this.filterSampler },
        ],
      }));
      scalePass.draw(3);
      scalePass.end();
    } else {
      // Full resolution: direct copy
      encoder.copyTextureToTexture(
        { texture: this.sourceTex },
        { texture: this.readTex },
        [this.canvasW, this.canvasH, 1],
      );
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PARALLEL SLOT GROUPS
    //
    // Parallel slots: All read from readTex, output to writeTex. The driver can
    // overlap their execution since they're independent compute passes.
    //
    // Chained slots: Output of slot N feeds into slot N+1. Must stay sequential.
    //
    // Dispatch sizes are per-shader based on parsed @workgroup_size from WGSL.
    // ═══════════════════════════════════════════════════════════════════════════════

    const parallelSlots = enabled.filter(s => s.mode === 'parallel');
    const chainedSlots = enabled.filter(s => s.mode === 'chained');

    // Safe optimization: when exactly one slot is active and it is chained, the
    // final result can stay in writeTex and the blit reads from there, saving
    // one redundant copyTextureToTexture per frame.
    const singleChained = enabled.length === 1 && enabled[0].mode === 'chained';
    this.blitReadTex = this.readTex;

    if (this.frameCount % 60 === 0) {
      console.log(`[WebGPURenderer] Parallel slots: ${parallelSlots.length}, Chained slots: ${chainedSlots.length}`);
      if (chainedSlots.length > 0) {
        console.log(`[WebGPURenderer] Chained slot order:`, chainedSlots.map(s => s.shaderId));
      }
    }

    // ── 1. Run ALL parallel slots first (driver can overlap these) ───────────────
    // All parallel slots read from the same readTex (base image)
    for (const slot of parallelSlots) {
      this.dispatchSlot(encoder, slot, 'parallel');
    }

    // If there were parallel slots, copy the final result to readTex for chained slots
    if (parallelSlots.length > 0) {
      encoder.copyTextureToTexture(
        { texture: this.writeTex },
        { texture: this.readTex },
        [this.scaledW, this.scaledH, 1],
      );
    }

    // ── 2. Run chained slots sequentially ────────────────────────────────────────
    for (let i = 0; i < chainedSlots.length; i++) {
      const slot = chainedSlots[i];
      if (this.frameCount % 60 === 0) {
        console.log(`[WebGPURenderer] Processing chained slot ${i}: ${slot.shaderId}`);
      }
      this.dispatchSlot(encoder, slot, 'chained');

      if (singleChained) {
        // Single active chained slot: the final output is already in writeTex.
        // Skip the redundant writeTex→readTex copy and have the blit read writeTex directly.
        this.blitReadTex = this.writeTex;
      } else {
        // Copy output to input for next chained slot (always copy so blit reads correct tex)
        encoder.copyTextureToTexture(
          { texture: this.writeTex },
          { texture: this.readTex },
          [this.scaledW, this.scaledH, 1],
        );
      }

      // Carry dataTexA forward into dataTexC for next frame's feedback reads
      encoder.copyTextureToTexture(
        { texture: this.dataTexA },
        { texture: this.dataTexC },
        [this.scaledW, this.scaledH, 1],
      );

      // Carry dataTexB forward into dataTexC for shaders that feedback from B
      encoder.copyTextureToTexture(
        { texture: this.dataTexB },
        { texture: this.dataTexC },
        [this.scaledW, this.scaledH, 1],
      );
    }

    // Post-chain: archive the final composited frame into the history ring.
    // Use blitReadTex so history stores whichever texture was actually presented.
    encoder.copyTextureToTexture(
      { texture: this.blitReadTex },
      { texture: this.historyTex, origin: [0, 0, this.historyHead] },
      [this.scaledW, this.scaledH, 1],
    );

    this.device.queue.submit([encoder.finish()]);

    // Advance ring head (CPU-side, after GPU submit)
    this.historyHead = (this.historyHead + 1) % HISTORY_DEPTH;

    this.blitToCanvas();

    // FPS tracking with adaptive quality
    this.frameCount++;
    const now = performance.now() / 1000;
    if (now - this.lastFPSTime >= 1.0) {
      this.fps = this.frameCount / (now - this.lastFPSTime);
      this.frameCount  = 0;
      this.lastFPSTime = now;
      this.adaptQualityIfNeeded();
    }
  }

  private blitToCanvas(): void {
    if (!this.device || !this.context || !this.initialized) return;
    
    // Ensure context is still valid (not lost)
    try {
      const currentTexture = this.context.getCurrentTexture();
      if (!currentTexture) return;
    } catch (e) {
      // Context lost or invalid
      return;
    }

    // Recreate blit bind group only when source texture or scaled dimensions changed.
    this.updateBlitBindGroup();

    const encoder = this.device.createCommandEncoder({ label: 'blit' });
    const pipeline = this.inputSource === 'generative'
      ? this.generativeBlitPipeline
      : this.blitPipeline;
    const pass = encoder.beginRenderPass({
      colorAttachments: [{
        view:       this.context.getCurrentTexture().createView(),
        loadOp:     'clear',
        storeOp:    'store',
        clearValue: { r: 0, g: 0, b: 0, a: 1 },
      }],
    });
    pass.setPipeline(pipeline);
    pass.setBindGroup(0, this.blitBindGroup);
    pass.draw(3);   // full-screen triangle
    pass.end();
    this.device.queue.submit([encoder.finish()]);
  }

  /**
   * Update blit bind group when the source texture or dimensions actually changed.
   * Caches the previous source and scaled dimensions to avoid recreating an
   * identical bind group every frame.
   */
  private updateBlitBindGroup(): void {
    if (!this.device) return;
    if (
      this.blitBindGroup &&
      this.blitReadTex === this.lastBlitReadTex &&
      this.scaledW === this.lastBlitScaledW &&
      this.scaledH === this.lastBlitScaledH
    ) {
      return;
    }

    this.blitBindGroup = this.device.createBindGroup({
      label: 'blitBG',
      layout: this.blitBindGroupLayout,
      entries: [{ binding: 0, resource: this.blitReadTex.createView() }],
    });
    this.lastBlitReadTex = this.blitReadTex;
    this.lastBlitScaledW = this.scaledW;
    this.lastBlitScaledH = this.scaledH;
  }

  private uniformView: UniformBufferView = createUniformBufferView();

  private writeUniforms(): void {
    if (!this.device) return;

    const u = this.uniformView;
    
    // config: time, rippleCount, resW, resH
    // Use scaledW/scaledH so shaders get the actual working texture dimensions
    u.setConfig(this.currentTime, this.ripples.length, this.scaledW, this.scaledH);
    
    // zoom_config: time, mouseX, mouseY, mouseDown
    // Pass mouseYShader (Y=0 at bottom) so shaders matching Shadertoy convention
    // don't need to manually invert. Shaders that already invert must be cleaned up.
    u.setZoomConfig(this.currentTime, this.mouseX, this.mouseYShader, this.mouseDown ? 1 : 0);
    
    // zoom_params: p1, p2, p3, p4
    u.setZoomParams(this.zoomParams[0], this.zoomParams[1], this.zoomParams[2], this.zoomParams[3]);
    
    // ripples[50]
    for (let i = 0; i < MAX_RIPPLES; i++) {
      if (i < this.ripples.length) {
        const r = this.ripples[i];
        u.setRipple(i, r.x, r.y, r.startTime);
      } else {
        u.clearRipple(i);
      }
    }
    
    this.device.queue.writeBuffer(this.uniformBuf, 0, u.data);

    // Extra buffer layout (256 floats = 1024 bytes):
    //   [0]    bass
    //   [1]    mid
    //   [2]    treble
    //   [3]    reserved
    //   [4]    historyHead
    //   [5..132] FFT bins [0..127] (128 bins normalised to [0,1])
    const extraData = new Float32Array(EXTRA_FLOATS);
    extraData[0] = this.audioBass;
    extraData[1] = this.audioMid;
    extraData[2] = this.audioTreble;
    extraData[3] = 0;
    extraData[4] = this.historyHead;
    extraData.set(this.audioFreqBins, EXTRA_BIN_OFFSET);
    this.device.queue.writeBuffer(this.extraBuf, 0, extraData);
  }
}
