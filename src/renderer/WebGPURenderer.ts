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
 *  10  storage read_write   extraBuffer   (256 floats; [0-2] = bass/mid/treble)
 *  11  sampler_comparison   comparison sampler
 *  12  storage read         plasmaBuffer
 */

import { Renderer, RendererConfig } from './Renderer';

// ── Constants matching C++ renderer ─────────────────────────────────────────

const MAX_RIPPLES        = 50;
const MAX_PLASMA_BALLS   = 50;
const UNIFORM_FLOATS     = 12 + MAX_RIPPLES * 4;   // 212 floats = 848 bytes
const EXTRA_FLOATS       = 256;                     // 1024 bytes
const PLASMA_BYTES       = MAX_PLASMA_BALLS * 48;   // 2400 bytes

// ── Error handling utilities ────────────────────────────────────────────────

export interface RendererError {
  type: 'webgpu-unavailable' | 'shader-compile' | 'media-load' | 'device-lost';
  message: string;
  recoverable: boolean;
}

export type ErrorHandler = (error: RendererError) => void;

// Default error handler that logs to console
let globalErrorHandler: ErrorHandler = (error) => {
  console.error(`[WebGPU Renderer] ${error.type}: ${error.message}`);
};

export function setRendererErrorHandler(handler: ErrorHandler) {
  globalErrorHandler = handler;
}

// Browser detection for WebGPU warnings
function getBrowserWarning(): string | null {
  const ua = navigator.userAgent.toLowerCase();
  
  // Safari check (all versions as of 2026)
  if (ua.includes('safari') && !ua.includes('chrome') && !ua.includes('chromium')) {
    return 'Safari does not support WebGPU. Please use Chrome, Edge, or Firefox Nightly.';
  }
  
  // iOS check
  if (/iphone|ipad|ipod/.test(ua)) {
    return 'WebGPU is not available on iOS. Please use a desktop browser.';
  }
  
  // Older browser check
  if (!navigator.gpu) {
    return 'Your browser does not support WebGPU. Please update to the latest Chrome, Edge, or Firefox.';
  }
  
  return null;
}

// ── Fallback compute shader ──────────────────────────────────────────────────
// Simple pass-through shader used when the requested shader fails to compile

const FALLBACK_WGSL = /* wgsl */`
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(textureDimensions(readTexture));
    let uv = vec2<f32>(global_id.xy) / resolution;
    
    // Simple pass-through with slight color boost to indicate fallback
    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    
    // Add a subtle red tint to indicate fallback mode
    let fallbackColor = vec4<f32>(
        min(color.r * 1.1, 1.0),
        color.g * 0.9,
        color.b * 0.9,
        color.a
    );
    
    textureStore(writeTexture, global_id.xy, fallbackColor);
}
`;

// ── Full-screen blit shader ──────────────────────────────────────────────────
// Renders the final rgba32float compute output to the canvas.
// Uses textureLoad (no sampler) to avoid float32-filterable requirement at blit.
// Applies simple gamma correction (linear → sRGB).

const BLIT_WGSL = /* wgsl */`
struct VSOut {
  @builtin(position) pos : vec4f,
  @location(0)       uv  : vec2f,
}

@vertex
fn vs(@builtin(vertex_index) idx: u32) -> VSOut {
  // Full-screen triangle
  var p = array<vec2f,3>(
    vec2f(-1.0, -1.0),
    vec2f( 3.0, -1.0),
    vec2f(-1.0,  3.0),
  );
  var out: VSOut;
  out.pos = vec4f(p[idx], 0.0, 1.0);
  // NDC → UV:  x [-1,1]→[0,1],  y [-1,1]→[1,0]  (flip Y for texture convention)
  out.uv  = p[idx] * vec2f(0.5, -0.5) + vec2f(0.5);
  return out;
}

@group(0) @binding(0) var src: texture_2d<f32>;

@fragment
fn fs(in: VSOut) -> @location(0) vec4f {
  let dim   = vec2i(textureDimensions(src));
  let coord = clamp(vec2i(in.uv * vec2f(dim)), vec2i(0), dim - 1);
  let c     = textureLoad(src, coord, 0);
  // Gamma encode: linear → sRGB (γ = 2.2 approximation)
  let rgb   = pow(clamp(c.rgb, vec3f(0.0), vec3f(1.0)), vec3f(1.0 / 2.2));
  return vec4f(rgb, 1.0);
}
`;

// ── Types ────────────────────────────────────────────────────────────────────

interface ShaderSlot {
  shaderId: string | null;
  enabled: boolean;
}

interface Ripple {
  x: number;
  y: number;
  startTime: number;
}

// ── Renderer class ───────────────────────────────────────────────────────────

export class WebGPURenderer implements Renderer {

  // WebGPU core
  private device: GPUDevice | null = null;
  private context: GPUCanvasContext | null = null;
  private canvasFormat: GPUTextureFormat = 'bgra8unorm';

  // Compute textures
  private sourceTex!: GPUTexture;  // original image/video source (rgba32float) - never modified by shaders
  private readTex!: GPUTexture;    // current input  (rgba32float)
  private writeTex!: GPUTexture;   // current output (rgba32float)
  private dataTexA!: GPUTexture;   // per-frame scratch A (rgba32float)
  private dataTexB!: GPUTexture;   // per-frame scratch B (rgba32float)
  private dataTexC!: GPUTexture;   // previous-frame copy of A (rgba32float)
  private depthRead!: GPUTexture;  // depth input  (r32float)
  private depthWrite!: GPUTexture; // depth output (r32float)
  private emptyTex!: GPUTexture;   // 1×1 black placeholder (r32float)

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

  // Multi-slot state (3 independent shader passes chained together)
  private slots: ShaderSlot[] = [
    { shaderId: null, enabled: false },
    { shaderId: null, enabled: false },
    { shaderId: null, enabled: false },
  ];

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

  // Lifecycle
  private initialized  = false;
  private animationId: number | null = null;
  private startTime    = 0;

  // FPS tracking
  private frameCount   = 0;
  private lastFPSTime  = 0;
  private fps          = 0;

  // Video / image input
  private video: HTMLVideoElement | null = null;
  private offscreen: HTMLCanvasElement | null = null;
  private offCtx: CanvasRenderingContext2D | null = null;

  constructor(private config: RendererConfig) {}

  // ── Initialisation ─────────────────────────────────────────────────────────

  async init(canvas: HTMLCanvasElement): Promise<boolean> {
    // Check WebGPU availability with user-friendly warnings
    if (!navigator.gpu) {
      const warning = getBrowserWarning();
      const message = warning || 'WebGPU is not available in this browser';
      
      globalErrorHandler({
        type: 'webgpu-unavailable',
        message,
        recoverable: false
      });
      
      console.warn('[WebGPU] navigator.gpu is unavailable in this browser');
      return false;
    }

    const adapter = await navigator.gpu.requestAdapter({ powerPreference: 'high-performance' });
    if (!adapter) {
      globalErrorHandler({
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

    try {
      this.device = await adapter.requestDevice({
        label: 'PixelocityDevice',
        requiredFeatures: wantFeatures,
      });
    } catch (e) {
      console.warn('[WebGPU] requestDevice failed:', e);
      return false;
    }

    // Forward uncaptured GPU errors to console during development
    this.device.addEventListener('uncapturederror', (ev) => {
      console.error('[WebGPU] Uncaptured error:', (ev as GPUUncapturedErrorEvent).error);
    });

    // Handle device lost (GPU crash, driver reset, etc.)
    this.device.lost.then((info) => {
      globalErrorHandler({
        type: 'device-lost',
        message: `GPU device lost: ${info.reason}. Try reloading the page.`,
        recoverable: false
      });
      console.error('[WebGPU] Device lost:', info.reason, info.message);
      this.initialized = false;
    });

    this.canvasW = canvas.width  || this.config.width;
    this.canvasH = canvas.height || this.config.height;

    this.context = canvas.getContext('webgpu') as GPUCanvasContext | null;
    if (!this.context) {
      console.warn('[WebGPU] Failed to get webgpu canvas context');
      return false;
    }

    this.canvasFormat = navigator.gpu.getPreferredCanvasFormat();
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

    this.initialized = true;
    this.startTime   = performance.now() / 1000;
    this.lastFPSTime = this.startTime;
    this.startRenderLoop();

    console.log(
      `✅ TypeScript WebGPU renderer initialized ` +
      `(${this.canvasW}×${this.canvasH}` +
      `${hasF32Filt ? ', float32-filterable' : ''})`
    );
    return true;
  }

  // ── Resource creation ──────────────────────────────────────────────────────

  private createTextures(): void {
    const d = this.device!;
    const w = this.canvasW, h = this.canvasH;

    const ALL = GPUTextureUsage.TEXTURE_BINDING  |
                GPUTextureUsage.STORAGE_BINDING  |
                GPUTextureUsage.COPY_SRC         |
                GPUTextureUsage.COPY_DST;

    const mkF32  = (label: string) => d.createTexture({ label, size: [w, h], format: 'rgba32float', usage: ALL });
    const mkR32  = (label: string) => d.createTexture({ label, size: [w, h], format: 'r32float',    usage: ALL });

    this.sourceTex = mkF32('sourceTex');  // Original image/video source (never modified)
    this.readTex   = mkF32('readTex');
    this.writeTex  = mkF32('writeTex');
    this.dataTexA  = mkF32('dataTexA');
    this.dataTexB  = mkF32('dataTexB');
    this.dataTexC  = mkF32('dataTexC');
    this.depthRead  = mkR32('depthRead');
    this.depthWrite = mkR32('depthWrite');

    // 1×1 black placeholder (r32float)
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
  }

  // ── Shader management ──────────────────────────────────────────────────────

  async loadShader(id: string, url: string): Promise<boolean> {
    try {
      const res = await fetch(url);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return this.compileShader(id, await res.text());
    } catch {
      // Fallback to local shaders/<id>.wgsl (relative path works for subdirectory deployments)
      try {
        const res = await fetch(`./shaders/${id}.wgsl`);
        if (!res.ok) return false;
        return this.compileShader(id, await res.text());
      } catch {
        return false;
      }
    }
  }

  private compileShader(id: string, wgsl: string): boolean {
    if (!this.device) return false;
    
    // Try to compile the requested shader
    try {
      const module = this.device.createShaderModule({ label: id, code: wgsl });
      
      // Check for compilation errors using compilationInfo
      module.getCompilationInfo().then(info => {
        const errors = info.messages.filter(m => m.type === 'error');
        if (errors.length > 0) {
          console.warn(`[WebGPU] Shader '${id}' compilation warnings:`, errors);
        }
      });
      
      const pipeline = this.device.createComputePipeline({
        label: id,
        layout: this.pipelineLayout,
        compute: { module, entryPoint: 'main' },
      });
      
      this.pipelines.set(id, pipeline);
      return true;
    } catch (e) {
      console.warn(`[WebGPU] Shader compile failed (${id}):`, e);
      
      // Report error through handler
      globalErrorHandler({
        type: 'shader-compile',
        message: `Shader "${id}" failed to compile. Using fallback pass-through shader.`,
        recoverable: true
      });
      
      // Try to use fallback shader
      try {
        const fallbackModule = this.device.createShaderModule({ 
          label: `${id}-fallback`, 
          code: FALLBACK_WGSL 
        });
        const fallbackPipeline = this.device.createComputePipeline({
          label: `${id}-fallback`,
          layout: this.pipelineLayout,
          compute: { module: fallbackModule, entryPoint: 'main' },
        });
        this.pipelines.set(id, fallbackPipeline);
        console.log(`[WebGPU] Using fallback shader for '${id}'`);
        return true;
      } catch (fallbackError) {
        console.error(`[WebGPU] Fallback shader also failed:`, fallbackError);
        return false;
      }
    }
  }

  /** Set a single active shader (slot 0). Clears slots 1 and 2. */
  setActiveShader(id: string): void {
    this.slots[0] = { shaderId: id, enabled: true };
    this.slots[1] = { shaderId: null, enabled: false };
    this.slots[2] = { shaderId: null, enabled: false };
  }

  /** Set which shader is bound to a specific slot (0-2). */
  setSlotShader(index: number, id: string): void {
    if (index >= 0 && index < 3) {
      this.slots[index] = { shaderId: id, enabled: !!id };
    }
  }

  setSlotEnabled(index: number, enabled: boolean): void {
    if (index >= 0 && index < 3) this.slots[index].enabled = enabled;
  }

  addRipple(x: number, y: number): void {
    if (this.ripples.length >= MAX_RIPPLES) this.ripples.shift();
    this.ripples.push({ x, y, startTime: this.currentTime });
  }

  clearRipples(): void { this.ripples = []; }

  getFPS(): number { return this.fps; }

  // ── BaseRenderer interface ─────────────────────────────────────────────────

  setVideo(video: HTMLVideoElement | undefined): void {
    this.video = video ?? null;
  }

  updateVideoFrame(): void {
    if (!this.video || this.video.readyState < 2) return;
    const vw = this.video.videoWidth, vh = this.video.videoHeight;
    if (!vw || !vh) return;

    const dstW = this.canvasW, dstH = this.canvasH;

    if (!this.offscreen || this.offscreen.width !== dstW || this.offscreen.height !== dstH) {
      this.offscreen = document.createElement('canvas');
      this.offscreen.width = dstW;
      this.offscreen.height = dstH;
      this.offCtx = this.offscreen.getContext('2d', { willReadFrequently: true });
    }
    if (!this.offCtx) return;

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
        
        globalErrorHandler({
          type: 'media-load',
          message: `Video error: ${errorMessages[errorCode] || 'Unknown video error'}`,
          recoverable: true
        });
        
        // Show black frame on error
        this.offCtx.fillStyle = 'black';
        this.offCtx.fillRect(0, 0, dstW, dstH);
        this.uploadRGBA8(this.offCtx.getImageData(0, 0, dstW, dstH).data, dstW, dstH);
        return;
      }

      this.offCtx.drawImage(this.video, 0, 0, dstW, dstH);
      this.uploadRGBA8(this.offCtx.getImageData(0, 0, dstW, dstH).data, dstW, dstH);
    } catch (e) {
      console.warn('[WebGPU] Video frame upload failed:', e);
      
      // Gracefully handle by showing black frame
      this.offCtx.fillStyle = 'black';
      this.offCtx.fillRect(0, 0, dstW, dstH);
      
      try {
        this.uploadRGBA8(this.offCtx.getImageData(0, 0, dstW, dstH).data, dstW, dstH);
      } catch (uploadError) {
        // Silent fail - don't crash the render loop
      }
    }
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
      
      globalErrorHandler({
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

  destroy(): void {
    if (this.animationId !== null) {
      cancelAnimationFrame(this.animationId);
      this.animationId = null;
    }
    this.initialized = false;
    this.pipelines.clear();

    for (const t of [this.readTex, this.writeTex, this.dataTexA, this.dataTexB,
                     this.dataTexC, this.depthRead, this.depthWrite, this.emptyTex]) {
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
    if (!this.device || !this.context) return;

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

    // Restore source image to readTex before processing (prevents feedback fade-to-black)
    encoder.copyTextureToTexture(
      { texture: this.sourceTex },
      { texture: this.readTex },
      [this.canvasW, this.canvasH, 1],
    );
    const wgX = Math.ceil(this.canvasW / 8);
    const wgY = Math.ceil(this.canvasH / 8);

    for (const slot of enabled) {
      const pipeline = this.pipelines.get(slot.shaderId!)!;

      const pass = encoder.beginComputePass({ label: slot.shaderId! });
      pass.setPipeline(pipeline);
      pass.setBindGroup(0, this.computeBindGroup);
      pass.dispatchWorkgroups(wgX, wgY, 1);
      pass.end();

      // Ping-pong: copy writeTex → readTex so next slot (or blit) reads this output
      encoder.copyTextureToTexture(
        { texture: this.writeTex },
        { texture: this.readTex },
        [this.canvasW, this.canvasH, 1],
      );

      // Carry dataTexA forward into dataTexC for next frame's feedback reads
      encoder.copyTextureToTexture(
        { texture: this.dataTexA },
        { texture: this.dataTexC },
        [this.canvasW, this.canvasH, 1],
      );
    }

    this.device.queue.submit([encoder.finish()]);
    this.blitToCanvas();

    // FPS
    this.frameCount++;
    const now = performance.now() / 1000;
    if (now - this.lastFPSTime >= 1.0) {
      this.fps = this.frameCount / (now - this.lastFPSTime);
      this.frameCount  = 0;
      this.lastFPSTime = now;
    }
  }

  private blitToCanvas(): void {
    if (!this.device || !this.context) return;

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

  private writeUniforms(): void {
    if (!this.device) return;

    const u = new Float32Array(UNIFORM_FLOATS);
    // config: time, rippleCount, resW, resH
    u[0] = this.currentTime;
    u[1] = this.ripples.length;
    u[2] = this.canvasW;
    u[3] = this.canvasH;
    // zoom_config: time, mouseX, mouseY, mouseDown
    u[4] = this.currentTime;
    u[5] = this.mouseX;
    u[6] = this.mouseY;
    u[7] = this.mouseDown ? 1 : 0;
    // zoom_params
    u[8]  = this.zoomParams[0];
    u[9]  = this.zoomParams[1];
    u[10] = this.zoomParams[2];
    u[11] = this.zoomParams[3];
    // ripples[50]
    for (let i = 0; i < MAX_RIPPLES; i++) {
      const b = 12 + i * 4;
      if (i < this.ripples.length) {
        u[b]     = this.ripples[i].x;
        u[b + 1] = this.ripples[i].y;
        u[b + 2] = this.ripples[i].startTime;
        u[b + 3] = 0;
      }
    }
    this.device.queue.writeBuffer(this.uniformBuf, 0, u);

    // First 3 floats of extraBuf carry audio (bass, mid, treble)
    this.device.queue.writeBuffer(
      this.extraBuf, 0,
      new Float32Array([this.audioBass, this.audioMid, this.audioTreble]),
    );
  }
}
