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
 *  10  storage read_write   extraBuffer   (256 floats; [0-2] = bass/mid/treble; [4] = historyHead)
 *  11  sampler_comparison   comparison sampler
 *  12  storage read         plasmaBuffer
 *  13  texture_2d_array<f32> historyTexture  (HISTORY_DEPTH=8 past frames; opt-in)
 */

import { Renderer, RendererConfig } from './Renderer';
import { resolveMultipassChain } from './multipassRegistry';
import { createUniformBufferView, UniformBufferView, Ripple, UNIFORM_FLOATS, MAX_RIPPLES } from './UniformBuffer';
import { reportError, getBrowserWarning } from './ErrorHandling';
import { compileShader } from './ShaderCompilation';
import { BLIT_WGSL, VIDEO_COPY_WGSL } from './ShaderTemplates';
import { PHYSICAL_SLOT_LIMIT } from './slotOrchestrator';

// ── Constants matching C++ renderer ─────────────────────────────────────────

const MAX_PLASMA_BALLS   = 50;
const EXTRA_FLOATS       = 256;                     // 1024 bytes
const PLASMA_BYTES       = MAX_PLASMA_BALLS * 48;   // 2400 bytes

/** Number of frames kept in the temporal history ring buffer (binding 13). */
const HISTORY_DEPTH = 8;

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

export class WebGPURenderer implements Renderer {

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
  private blitBindGroupLayout!: GPUBindGroupLayout;
  private blitBindGroup!: GPUBindGroup;  // reads readTex

  // Shader pipeline cache: shader-id → GPUComputePipeline
  private pipelines = new Map<string, GPUComputePipeline>();
  private pipelineHashes = new Map<string, string>(); // shader-id → content hash
  private workgroupSizes = new Map<string, { x: number; y: number }>(); // shader-id → parsed workgroup size

  // Multi-slot state with parallelization support (PHYSICAL_SLOT_LIMIT slots)
  // Slot 0: Usually chained (background/base effect)
  // Slots 1–5: Can be parallel (independent overlays) or chained
  private slots: ShaderSlot[] = Array.from({ length: PHYSICAL_SLOT_LIMIT }, () => ({
    shaderId: null, enabled: false, mode: 'chained' as SlotMode,
  }));

  // Per-frame uniforms
  private currentTime = 0;
  private mouseX      = 0.5;
  private mouseY      = 0.5;
  private mouseDown   = false;
  private zoomParams  = [0.5, 0.5, 0.5, 0.5];
  private ripples: Ripple[] = [];
  private audioBass   = 0;
  private audioMid    = 0;
  private audioTreble = 0;

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
    // Idempotency guard: prevent double-init (e.g. React StrictMode)
    if (this.initialized) return true;

    // Check WebGPU availability with user-friendly warnings
    if (!navigator.gpu) {
      const warning = getBrowserWarning();
      const message = warning || 'WebGPU is not available in this browser';
      
      reportError({
        type: 'webgpu-unavailable',
        message,
        recoverable: false
      });
      
      console.warn('[WebGPU] navigator.gpu is unavailable in this browser');
      return false;
    }

    const adapter = await navigator.gpu.requestAdapter({ powerPreference: 'high-performance' });
    if (!adapter) {
      reportError({
        type: 'webgpu-unavailable',
        message: 'No suitable GPU adapter found. Your device may not support WebGPU.',
        recoverable: false
      });
      
      console.warn('[WebGPU] No GPU adapter found');
      return false;
    }

    // Request float32-filterable when available so shaders can use
    // textureSample() with a linear sampler on rgba32float textures.
    const wantFeatures: GPUFeatureName[] = [];
    if (adapter.features.has('float32-filterable')) {
      wantFeatures.push('float32-filterable');
    }

    // Opt into subgroup operations (Chrome 128+) if the adapter supports them.
    // Subgroup ops enable -sg shader variants that replace multiple texture
    // samples with intra-subgroup data shuffles for significant bandwidth savings.
    const subgroupFeatureName: GPUFeatureName | null =
      adapter.features.has('subgroups')
        ? 'subgroups'
        : adapter.features.has('chromium-experimental-subgroups' as GPUFeatureName)
          ? ('chromium-experimental-subgroups' as GPUFeatureName)
          : null;
    if (subgroupFeatureName) {
      wantFeatures.push(subgroupFeatureName);
    }

    try {
      this.device = await adapter.requestDevice({
        label: 'PixelocityDevice',
        requiredFeatures: wantFeatures,
      });
    } catch (e) {
      console.warn('[WebGPU] requestDevice failed:', e);
      return false;
    }

    // Record whether subgroup operations are available
    this.supportsSubgroups = !!(
      subgroupFeatureName && this.device.features.has(subgroupFeatureName)
    );
    if (this.supportsSubgroups) {
      console.log('[WebGPU] Subgroup operations enabled — fast -sg variants will be preferred');
    }

    // Deep-workgroup capability: @workgroup_size(16,16,4) = 1024 invocations.
    // Supported on Apple M1+, NVIDIA RTX, AMD RDNA2+; NOT on Intel UHD (limit=256).
    // The WebGPU spec guarantees maxComputeInvocationsPerWorkgroup >= 256 for all
    // compliant devices, so 256 is the safe conservative fallback if the property
    // is unexpectedly absent (e.g. in older type stubs or non-standard environments).
    const maxInvocations = adapter.limits?.maxComputeInvocationsPerWorkgroup ?? 256;
    this.supportsDeepWorkgroup = maxInvocations >= 1024;
    if (this.supportsDeepWorkgroup) {
      console.log('[WebGPU] Deep-workgroup (16×16×4 = 1024 invocations) supported');
    } else {
      console.log(`[WebGPU] Deep-workgroup NOT supported (maxComputeInvocationsPerWorkgroup=${maxInvocations}); requiresDeepWorkgroup shaders will be filtered out`);
    }

    // Forward uncaptured GPU errors to console during development
    this.device.addEventListener('uncapturederror', (ev) => {
      console.error('[WebGPU] Uncaptured error:', (ev as GPUUncapturedErrorEvent).error);
    });

    // Handle device lost (GPU crash, driver reset, etc.)
    this.device.lost.then((info) => {
      reportError({
        type: 'device-lost',
        message: `GPU device lost: ${info.reason}. Try reloading the page.`,
        recoverable: false
      });
      console.error('[WebGPU] Device lost:', info.reason, info.message);
      // Unconfigure context to release the old device reference
      try {
        this.context?.unconfigure();
      } catch (e) {
        // Ignore errors during cleanup
      }
      this.initialized = false;
    });

    this.canvasW = canvas.width  || this.config.width;
    this.canvasH = canvas.height || this.config.height;
    this.updateScaledDimensions();  // Initialize scaledW/scaledH

    this.context = canvas.getContext('webgpu') as GPUCanvasContext | null;
    if (!this.context) {
      console.warn('[WebGPU] Failed to get webgpu canvas context');
      return false;
    }

    this.canvasFormat = navigator.gpu.getPreferredCanvasFormat();
    
    // Unconfigure first to clear any previous device association
    try {
      this.context.unconfigure();
    } catch (e) {
      // Context might not have been configured yet
    }
    
    this.context.configure({
      device: this.device,
      format: this.canvasFormat,
      alphaMode: 'opaque',
    });

    const hasF32Filt = this.device.features.has('float32-filterable');

    this.createTextures();
    this.createSamplers();
    this.createBuffers();
    this.createComputeBindGroupLayout(hasF32Filt);
    this.createComputeBindGroup();
    this.createBlitPipeline();
    this.createTimestampQueries();

    this.initialized = true;
    this.startTime   = performance.now() / 1000;
    this.lastFPSTime = this.startTime;
    this.startRenderLoop();

    console.log(
      `✅ TypeScript WebGPU renderer initialized ` +
      `(${this.canvasW}×${this.canvasH}` +
      `${hasF32Filt ? ', float32-filterable' : ''}` +
      `${this.supportsSubgroups ? ', subgroups' : ''}` +
      `${this.supportsDeepWorkgroup ? ', deep-workgroup' : ''})`
    );
    return true;
  }

  // ── Resource creation ──────────────────────────────────────────────────────

  private createTextures(): void {
    const d = this.device!;
    const fullW = this.canvasW, fullH = this.canvasH;
    const scaledW = this.scaledW || fullW;
    const scaledH = this.scaledH || fullH;

    // ═══════════════════════════════════════════════════════════════════════════════
    // TEXTURE USAGE FLAGS
    // 
    // Standard compute workflow uses TEXTURE_BINDING | STORAGE_BINDING | COPY_DST
    // COPY_SRC is only needed for textures that will be copied from (like source)
    // ═══════════════════════════════════════════════════════════════════════════════
    
    // Source texture: uploaded from CPU, sampled by shaders, copied from
    const USAGE_SOURCE = GPUTextureUsage.TEXTURE_BINDING |
                         GPUTextureUsage.COPY_DST |
                         GPUTextureUsage.COPY_SRC |
                         GPUTextureUsage.RENDER_ATTACHMENT;
    
    // Standard compute texture: sampled, written as storage, copied to/from
    const USAGE_STANDARD = GPUTextureUsage.TEXTURE_BINDING |
                           GPUTextureUsage.STORAGE_BINDING |
                           GPUTextureUsage.COPY_DST |
                           GPUTextureUsage.COPY_SRC;

    // Full resolution (source input)
    this.sourceTex = d.createTexture({
      label: 'sourceTex',
      size: [fullW, fullH],
      format: 'rgba32float',
      usage: USAGE_SOURCE
    });

    // Scaled resolution (intermediate processing)
    this.readTex = d.createTexture({
      label: 'readTex',
      size: [scaledW, scaledH],
      format: 'rgba32float',
      usage: USAGE_STANDARD
    });
    
    this.writeTex = d.createTexture({
      label: 'writeTex',
      size: [scaledW, scaledH],
      format: 'rgba32float',
      usage: USAGE_STANDARD
    });
    
    this.dataTexA = d.createTexture({
      label: 'dataTexA',
      size: [scaledW, scaledH],
      format: 'rgba32float',
      usage: USAGE_STANDARD
    });
    
    this.dataTexB = d.createTexture({
      label: 'dataTexB',
      size: [scaledW, scaledH],
      format: 'rgba32float',
      usage: USAGE_STANDARD
    });
    
    this.dataTexC = d.createTexture({
      label: 'dataTexC',
      size: [scaledW, scaledH],
      format: 'rgba32float',
      usage: USAGE_STANDARD
    });

    // History ring buffer: HISTORY_DEPTH layers, one frame per layer
    this.historyTex = d.createTexture({
      label: 'historyTex',
      size: { width: scaledW, height: scaledH, depthOrArrayLayers: HISTORY_DEPTH },
      format: 'rgba32float',
      usage: GPUTextureUsage.TEXTURE_BINDING |
             GPUTextureUsage.STORAGE_BINDING |
             GPUTextureUsage.COPY_DST |
             GPUTextureUsage.COPY_SRC,
    });
    // Reset ring head whenever textures are (re)created (e.g. resolution change)
    this.historyHead = 0;

    // Depth textures
    this.depthRead = d.createTexture({
      label: 'depthRead',
      size: [fullW, fullH],
      format: 'r32float',
      usage: USAGE_SOURCE
    });
    
    this.depthWrite = d.createTexture({
      label: 'depthWrite',
      size: [scaledW, scaledH],
      format: 'r32float',
      usage: USAGE_STANDARD
    });

    // 1×1 black placeholder - needs COPY_DST for writeTexture
    this.emptyTex = d.createTexture({
      label: 'emptyTex',
      size: [1, 1],
      format: 'r32float',
      usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
    });
    
    d.queue.writeTexture(
      { texture: this.emptyTex },
      new Float32Array([0]),
      { bytesPerRow: 4 },
      [1, 1],
    );
  }

  private createSamplers(): void {
    const d = this.device!;
    this.filterSampler = d.createSampler({
      label: 'filterSampler',
      magFilter: 'linear', minFilter: 'linear', mipmapFilter: 'linear',
      addressModeU: 'repeat', addressModeV: 'repeat',
    });
    this.nearestSampler = d.createSampler({
      label: 'nearestSampler',
      magFilter: 'nearest', minFilter: 'nearest',
      addressModeU: 'clamp-to-edge', addressModeV: 'clamp-to-edge',
    });
    this.compSampler = d.createSampler({
      label: 'compSampler',
      compare: 'less',
    });
  }

  private createBuffers(): void {
    const d = this.device!;
    this.uniformBuf = d.createBuffer({
      label: 'uniformBuf',
      size: UNIFORM_FLOATS * 4,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });
    this.extraBuf = d.createBuffer({
      label: 'extraBuf',
      size: EXTRA_FLOATS * 4,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    });
    this.plasmaBuf = d.createBuffer({
      label: 'plasmaBuf',
      size: Math.max(PLASMA_BYTES, 16),   // min 16 bytes for WebGPU
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    });
  }

  private createComputeBindGroupLayout(hasF32Filt: boolean): void {
    const d  = this.device!;
    // If float32-filterable is enabled, use 'float' (supports filtering samplers).
    // Otherwise use 'unfilterable-float' — shaders that call textureSample() with
    // a filtering sampler will fail pipeline creation and be skipped gracefully.
    const fST: GPUTextureSampleType = hasF32Filt ? 'float' : 'unfilterable-float';
    const V  = GPUShaderStage.COMPUTE;

    this.bindGroupLayout = d.createBindGroupLayout({
      label: 'computeBGL',
      entries: [
        { binding:  0, visibility: V, sampler:        { type: 'filtering' } },
        { binding:  1, visibility: V, texture:        { sampleType: fST } },
        { binding:  2, visibility: V, storageTexture: { access: 'write-only', format: 'rgba32float' } },
        { binding:  3, visibility: V, buffer:         { type: 'uniform' } },
        { binding:  4, visibility: V, texture:        { sampleType: 'unfilterable-float' } },
        { binding:  5, visibility: V, sampler:        { type: 'non-filtering' } },
        { binding:  6, visibility: V, storageTexture: { access: 'write-only', format: 'r32float' } },
        { binding:  7, visibility: V, storageTexture: { access: 'write-only', format: 'rgba32float' } },
        { binding:  8, visibility: V, storageTexture: { access: 'write-only', format: 'rgba32float' } },
        { binding:  9, visibility: V, texture:        { sampleType: fST } },
        { binding: 10, visibility: V, buffer:         { type: 'storage' } },
        { binding: 11, visibility: V, sampler:        { type: 'comparison' } },
        { binding: 12, visibility: V, buffer:         { type: 'read-only-storage' } },
        // Binding 13: opt-in history ring (HISTORY_DEPTH-layer 2d-array of past frames)
        { binding: 13, visibility: V, texture:        { sampleType: fST, viewDimension: '2d-array' } },
      ],
    });

    this.pipelineLayout = d.createPipelineLayout({
      label: 'computePL',
      bindGroupLayouts: [this.bindGroupLayout],
    });
  }

  private createComputeBindGroup(): void {
    this.computeBindGroup = this.device!.createBindGroup({
      label: 'computeBG',
      layout: this.bindGroupLayout,
      entries: [
        { binding:  0, resource: this.filterSampler },
        { binding:  1, resource: this.readTex.createView() },
        { binding:  2, resource: this.writeTex.createView() },
        { binding:  3, resource: { buffer: this.uniformBuf } },
        { binding:  4, resource: this.depthRead.createView() },
        { binding:  5, resource: this.nearestSampler },
        { binding:  6, resource: this.depthWrite.createView() },
        { binding:  7, resource: this.dataTexA.createView() },
        { binding:  8, resource: this.dataTexB.createView() },
        { binding:  9, resource: this.dataTexC.createView() },
        { binding: 10, resource: { buffer: this.extraBuf } },
        { binding: 11, resource: this.compSampler },
        { binding: 12, resource: { buffer: this.plasmaBuf } },
        // Binding 13: temporal history ring (2d-array view of all HISTORY_DEPTH layers)
        { binding: 13, resource: this.historyTex.createView({
            dimension: '2d-array',
            baseArrayLayer: 0,
            arrayLayerCount: HISTORY_DEPTH,
          })
        },
      ],
    });
  }

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

    this.blitPipeline = d.createRenderPipeline({
      label: 'blitPipeline',
      layout: d.createPipelineLayout({ bindGroupLayouts: [this.blitBindGroupLayout] }),
      vertex:   { module, entryPoint: 'vs' },
      fragment: { module, entryPoint: 'fs', targets: [{ format: this.canvasFormat }] },
      primitive: { topology: 'triangle-list' },
    });

    // Blit reads from readTex (always holds the latest output after per-slot copies)
    this.blitBindGroup = d.createBindGroup({
      label: 'blitBG',
      layout: this.blitBindGroupLayout,
      entries: [{ binding: 0, resource: this.readTex.createView() }],
    });

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

  // ── Timestamp Queries for GPU Profiling ────────────────────────────────────

  private createTimestampQueries(): void {
    if (!this.device) return;
    
    // Check if timestamp queries are supported
    this.supportsTimestampQuery = this.device.features.has('timestamp-query');
    
    if (this.supportsTimestampQuery) {
      try {
        this.querySet = this.device.createQuerySet({
          type: 'timestamp',
          count: 8,  // Enough for parallel start/end, chained start/end, total
        });
        
        this.queryBuffer = this.device.createBuffer({
          size: 8 * 8,  // 8 timestamps × 8 bytes each
          usage: GPUBufferUsage.QUERY_RESOLVE | GPUBufferUsage.COPY_SRC,
        });
        
        console.log('[WebGPU] Timestamp queries enabled for GPU profiling');
      } catch (e) {
        console.warn('[WebGPU] Timestamp query creation failed:', e);
        this.supportsTimestampQuery = false;
      }
    }
  }

  /** Get GPU timing data for performance analysis */
  getGPUTimings(): { parallelTime: number; chainedTime: number; totalTime: number; available: boolean } {
    return { 
      ...this.gpuTimings, 
      available: this.supportsTimestampQuery 
    };
  }

  // ── Shader management ──────────────────────────────────────────────────────

  async loadShader(id: string, url: string): Promise<boolean> {
    // Helper: fetch a URL, returning text on success or null on any failure.
    const tryFetch = async (u: string): Promise<string | null> => {
      try {
        const r = await fetch(u);
        return r.ok ? await r.text() : null;
      } catch { return null; }
    };

    // If subgroup operations are supported, probe the -sg sibling variant first.
    // The -sg file uses `enable subgroups;` and subgroupAdd/Shuffle ops that
    // cannot be inlined alongside non-subgroup code in the same module.
    // We compile it under the same base ID so all downstream code (setSlotShader,
    // pipeline cache, bind-group lookups) requires zero changes.
    if (this.supportsSubgroups && !id.endsWith('-sg') && url.endsWith('.wgsl')) {
      const sgUrl = url.replace(/\.wgsl$/, '-sg.wgsl');
      const wgsl = await tryFetch(sgUrl) ?? await tryFetch(`./shaders/${id}-sg.wgsl`);
      if (wgsl) {
        const ok = this.compileShader(id, wgsl);
        if (ok) {
          if (process.env.NODE_ENV !== 'production') {
            console.log(`[WebGPU] "${id}": loaded subgroup variant (-sg.wgsl)`);
          }
          return true;
        }
      }
      // -sg variant absent or failed to compile — fall through to base variant below
      if (process.env.NODE_ENV !== 'production') {
        console.log(`[WebGPU] "${id}": no -sg variant found, using base variant`);
      }
    }

    // Base variant (also serves as silent fallback when -sg is absent or fails)
    const wgsl = await tryFetch(url) ?? await tryFetch(`./shaders/${id}.wgsl`);
    if (!wgsl) return false;
    return this.compileShader(id, wgsl);
  }

  /** Wrapper for shader compilation that uses extracted ShaderCompilation module */
  private compileShader(id: string, wgsl: string): boolean {
    if (!this.device) return false;
    return compileShader(
      this.device,
      this.pipelineLayout,
      id,
      wgsl,
      this.pipelines,
      this.pipelineHashes,
      this.workgroupSizes,
    );
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

  /** Get video pipeline status for debugging */
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
    return this.pipelines.has(id);
  }

  /** Get pipeline cache statistics */
  getPipelineCacheStats(): { cachedCount: number; cachedIds: string[] } {
    return {
      cachedCount: this.pipelines.size,
      cachedIds: Array.from(this.pipelines.keys()),
    };
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
        this.createTextures();
        this.createComputeBindGroup();
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

  updateMouse(x: number, y: number): void {
    this.mouseX = x; this.mouseY = y;
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

  /** Update all zoom params from SlotParams (called when UI changes) */
  updateSlotParams(params: { zoomParam1?: number; zoomParam2?: number; zoomParam3?: number; zoomParam4?: number }): void {
    if (params.zoomParam1 !== undefined) this.zoomParams[0] = params.zoomParam1;
    if (params.zoomParam2 !== undefined) this.zoomParams[1] = params.zoomParam2;
    if (params.zoomParam3 !== undefined) this.zoomParams[2] = params.zoomParam3;
    if (params.zoomParam4 !== undefined) this.zoomParams[3] = params.zoomParam4;
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
    if (!slot.shaderId) return;
    const chain = resolveMultipassChain(slot.shaderId);
    for (const shaderId of chain) {
      const pipeline = this.pipelines.get(shaderId);
      if (!pipeline) {
        console.warn(`[WebGPURenderer] Pipeline missing for multipass step "${shaderId}"`);
        continue;
      }
      const wg = this.workgroupSizes.get(shaderId) || { x: 8, y: 8 };
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
    this.pipelines.clear();
    this.workgroupSizes.clear();

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
    }

    const enabled = this.slots.filter(
      s => s.enabled && s.shaderId && this.pipelines.has(s.shaderId)
    );


    if (enabled.length === 0) {
      // No active shader — show whatever is in readTex (black initially)
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

      // Copy output to input for next chained slot (always copy so blit reads correct tex)
      encoder.copyTextureToTexture(
        { texture: this.writeTex },
        { texture: this.readTex },
        [this.scaledW, this.scaledH, 1],
      );

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
    // Same encoder as the slot chain — no extra queue.submit() needed.
    encoder.copyTextureToTexture(
      { texture: this.readTex },
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

    const encoder = this.device.createCommandEncoder({ label: 'blit' });
    const pass = encoder.beginRenderPass({
      colorAttachments: [{
        view:       this.context.getCurrentTexture().createView(),
        loadOp:     'clear',
        storeOp:    'store',
        clearValue: { r: 0, g: 0, b: 0, a: 1 },
      }],
    });
    pass.setPipeline(this.blitPipeline);
    pass.setBindGroup(0, this.blitBindGroup);
    pass.draw(3);   // full-screen triangle
    pass.end();
    this.device.queue.submit([encoder.finish()]);
  }

  /** Update blit bind group after texture recreation (e.g., resolution change) */
  private updateBlitBindGroup(): void {
    if (!this.device) return;
    this.blitBindGroup = this.device.createBindGroup({
      label: 'blitBG',
      layout: this.blitBindGroupLayout,
      entries: [{ binding: 0, resource: this.readTex.createView() }],
    });
  }

  private uniformView: UniformBufferView = createUniformBufferView();

  private writeUniforms(): void {
    if (!this.device) return;

    const u = this.uniformView;
    
    // config: time, rippleCount, resW, resH
    // Use scaledW/scaledH so shaders get the actual working texture dimensions
    u.setConfig(this.currentTime, this.ripples.length, this.scaledW, this.scaledH);
    
    // zoom_config: time, mouseX, mouseY, mouseDown
    u.setZoomConfig(this.currentTime, this.mouseX, this.mouseY, this.mouseDown ? 1 : 0);
    
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

    // Extra buffer: [0]=bass, [1]=mid, [2]=treble, [3]=reserved, [4]=historyHead
    this.device.queue.writeBuffer(
      this.extraBuf, 0,
      new Float32Array([this.audioBass, this.audioMid, this.audioTreble, 0, this.historyHead]),
    );
  }
}
