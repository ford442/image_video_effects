/**
 * pipeline.ts
 *
 * Compute bind-group layout, blit pipelines, and shader load/cache.
 * Mirrors wasm_renderer/pipeline.cpp.
 */

import {
  analyzeShaderBindings,
  compileShader,
  CONSERVATIVE_BINDING_USAGE,
  createComputePipelineChecked,
  ShaderBindingUsage,
} from '../ShaderCompilation';
import { withValidationScope } from './validationScope';
import { DIRECT_PRESENT_FORMAT, toDirectPresentVariant } from './directPresent';
import { colorTextureSampleType, type InternalColorFormat } from '../../config/formatPolicy';
import bindGroup0Contract from '../../contracts/bind_group0.json';
import {
  BLIT_WGSL,
  GENERATIVE_BLIT_WGSL,
  HDR_BLIT_WGSL,
  HDR_GENERATIVE_BLIT_WGSL,
  SCALE_COPY_WGSL,
  VIDEO_COPY_WGSL,
} from '../ShaderTemplates';
import { DEFAULT_HDR_TONE_MAP, hdrToneMapUniform, type HdrToneMapSettings } from '../../services/hdrOutput';
import { fetchShaderWgsl } from '../../utils/fetchShaderWgsl';
import { chooseF16Variant, type F16Choice } from '../wgslF16';
import { rewriteWgslStorageFormats } from '../wgslFormatRewrite';
import { compileCheckWgsl } from './compileCheck';
import { HISTORY_DEPTH } from './webgpuConstants';
import { PIPELINE_CACHE_LIMIT, PipelineLru } from './pipelineCache';
import {
  checkSimRingLimits,
  createSimRingBindGroupLayout,
  createSimRingPipelineLayout,
  declaresBindGroup1,
  validateGroup1Declarations,
} from './simRing';
import {
  WebGPUBufferSet,
  WebGPUSamplerSet,
  WebGPUTextureSet,
} from './resources';

export interface WebGPUComputeLayout {
  bindGroupLayout: GPUBindGroupLayout;
  pipelineLayout: GPUPipelineLayout;
}

/** The present pass is HDR (keeps > 1.0, applies the tonemap) on this swapchain format. */
export function isHdrPresentFormat(format: GPUTextureFormat): boolean {
  return format === 'rgba16float';
}

/** Size of the present params uniform (vec4<f32>, ShaderTemplates HDR blit binding 1). */
export const PRESENT_PARAMS_BYTES = 16;

export interface WebGPUBlitResources {
  blitPipeline: GPURenderPipeline;
  generativeBlitPipeline: GPURenderPipeline;
  scaleCopyPipeline: GPURenderPipeline;
  blitBindGroupLayout: GPUBindGroupLayout;
  blitBindGroup: GPUBindGroup;
  videoCopyPipeline: GPURenderPipeline | null;
  videoCopyBindGroupLayout: GPUBindGroupLayout | null;
  supportsExternalTexture: boolean;
}

/** Group-1 layout provider; null when the device cannot host the sim ring. */
export type SimRingLayoutProvider = () => GPUPipelineLayout | null;

/** Which precision a shader compiled at: 'f32-fallback' = it asked for f16 and the half variant failed. */
export type ShaderPrecision = F16Choice | 'f32-fallback';

export class WebGPUShaderManager {
  private pipelines = new Map<string, GPUComputePipeline>();
  /** Recency of every cached pipeline; the single eviction authority (warm-up included). */
  private readonly lru = new PipelineLru();
  private cacheLimit = PIPELINE_CACHE_LIMIT;
  /** Ids bound to a slot (including graph chains): never evicted. */
  private boundIds: () => ReadonlySet<string> = () => new Set<string>();
  private simRingShaders = new Set<string>();
  private simRingLayoutProvider: SimRingLayoutProvider = () => null;
  private pipelineHashes = new Map<string, string>();
  private workgroupSizes = new Map<string, { x: number; y: number }>();
  private bindingUsages = new Map<string, ShaderBindingUsage>();
  private precisions = new Map<string, ShaderPrecision>();
  /** Compiled source per cached pipeline (after the precision choice): what a direct variant derives from. */
  private sources = new Map<string, string>();
  /** Direct-present variants (#1512): pipeline, or null when it cannot be built. */
  private directPipelines = new Map<string, GPUComputePipeline | null>();
  private directPending = new Set<string>();
  /** Bumped on clear(): an in-flight direct compile from before is dropped. */
  private directGeneration = 0;
  private colorFormat: InternalColorFormat = 'rgba32float';
  /** Device has shader-f16 and the half path is on: `// @requires f16` shaders compile half. */
  private shaderF16 = false;

  /** Turn the f16 variant path on / off (#1512); recompiles on the next load. */
  setShaderF16(enabled: boolean): void {
    if (this.shaderF16 === enabled) return;
    this.shaderF16 = enabled;
    this.clear();
  }

  getShaderF16(): boolean {
    return this.shaderF16;
  }

  /** Precision each opted-in shader compiled at (absent: never compiled or not opted in). */
  getPrecisions(): Record<string, ShaderPrecision> {
    return Object.fromEntries([...this.precisions].filter(([, p]) => p !== 'not-requested'));
  }

  setColorFormat(format: InternalColorFormat): void {
    if (this.colorFormat === format) return;
    this.colorFormat = format;
    this.clear();
  }

  getColorFormat(): InternalColorFormat {
    return this.colorFormat;
  }

  getPipeline(id: string): GPUComputePipeline | undefined {
    const pipeline = this.pipelines.get(id);
    // Keeps a shader that was just switched away from as recent as the moment it stopped rendering.
    if (pipeline) this.lru.touch(id);
    return pipeline;
  }

  /** Slot-bound ids the LRU must keep. Defaults to none. */
  setBoundIdsProvider(provider: () => ReadonlySet<string>): void {
    this.boundIds = provider;
  }

  /** Test/tuning hook: the most pipelines kept before unbound ones are evicted. */
  setCacheLimit(limit: number): void {
    this.cacheLimit = Math.max(1, Math.floor(limit));
    this.trim(null);
  }

  /** Evict least recently used unbound pipelines beyond the cache limit. */
  private trim(justUsed: string | null): void {
    if (this.lru.size <= this.cacheLimit) return;
    const keep = new Set(this.boundIds());
    if (justUsed) keep.add(justUsed);
    for (const victim of this.lru.overflow(this.cacheLimit, keep)) this.evict(victim);
  }

  hasPipeline(id: string): boolean {
    return this.pipelines.has(id);
  }

  getWorkgroupSize(id: string): { x: number; y: number } {
    return this.workgroupSizes.get(id) || { x: 8, y: 8 };
  }

  setSimRingLayoutProvider(provider: SimRingLayoutProvider): void {
    this.simRingLayoutProvider = provider;
  }

  /** True when the cached pipeline for `id` was built against the group-1 layout. */
  usesSimRing(id: string): boolean {
    return this.simRingShaders.has(id);
  }

  getBindingUsage(id: string): ShaderBindingUsage {
    return this.bindingUsages.get(id) ?? CONSERVATIVE_BINDING_USAGE;
  }

  getCacheStats(): { cachedCount: number; cachedIds: string[] } {
    return {
      cachedCount: this.pipelines.size,
      cachedIds: Array.from(this.pipelines.keys()),
    };
  }

  /** Drop one cached pipeline. */
  evict(id: string): void {
    this.lru.remove(id);
    this.pipelines.delete(id);
    this.pipelineHashes.delete(id);
    this.workgroupSizes.delete(id);
    this.bindingUsages.delete(id);
    this.simRingShaders.delete(id);
    this.precisions.delete(id);
    this.sources.delete(id);
    this.directPipelines.delete(id);
  }

  clear(): void {
    this.lru.clear();
    this.pipelines.clear();
    this.pipelineHashes.clear();
    this.workgroupSizes.clear();
    this.bindingUsages.clear();
    this.simRingShaders.clear();
    this.precisions.clear();
    this.sources.clear();
    this.directPipelines.clear();
    this.directPending.clear();
    this.directGeneration++;
  }

  /**
   * The direct-present variant of `id` (directPresent.ts): a pipeline, null when it
   * cannot be built, undefined while it was never requested or is compiling.
   */
  getDirectPipeline(id: string): GPUComputePipeline | null | undefined {
    return this.directPipelines.get(id);
  }

  /** Compile the direct variant in the background; frames use the blit until it is ready. */
  requestDirectPipeline(device: GPUDevice, layout: GPUPipelineLayout, id: string): void {
    if (this.directPipelines.has(id) || this.directPending.has(id)) return;
    const source = this.sources.get(id);
    if (!source || this.simRingShaders.has(id)) {
      this.directPipelines.set(id, null);
      return;
    }
    const generation = this.directGeneration;
    this.directPending.add(id);
    void this.compileDirect(device, layout, id, source).then((pipeline) => {
      if (generation !== this.directGeneration) return;
      this.directPending.delete(id);
      // Evicted meanwhile: a later load compiles it again.
      if (this.pipelines.has(id)) this.directPipelines.set(id, pipeline);
    });
  }

  /**
   * Never falls back to the pass-through shader (compileShader would): a direct
   * variant that does not compile is simply not used.
   */
  private async compileDirect(
    device: GPUDevice,
    layout: GPUPipelineLayout,
    id: string,
    source: string,
  ): Promise<GPUComputePipeline | null> {
    const variant = toDirectPresentVariant(source);
    if (!variant) return null;
    try {
      const code = rewriteWgslStorageFormats(variant, this.colorFormat);
      const moduleResult = await withValidationScope(device, () =>
        device.createShaderModule({ label: `${id}-direct`, code }),
      );
      const module = moduleResult.value;
      if (!module || moduleResult.threw || moduleResult.error) return null;
      const created = await createComputePipelineChecked(device, {
        label: `${id}-direct`,
        layout,
        compute: { module, entryPoint: 'main' },
      });
      if (!created.pipeline) console.warn(`[WebGPU] "${id}": direct-present variant failed — using the blit`, created.error);
      return created.pipeline;
    } catch (e) {
      console.warn(`[WebGPU] "${id}": direct-present variant threw — using the blit`, e);
      return null;
    }
  }

  /**
   * The source to compile: the half variant of a `// @requires f16` shader when
   * the device has shader-f16 and it compiles against the layout, else the f32
   * source unchanged (wgslF16.ts).
   */
  private async selectPrecision(
    device: GPUDevice,
    layout: GPUPipelineLayout,
    id: string,
    wgsl: string,
  ): Promise<{ source: string; precision: ShaderPrecision }> {
    const choice = chooseF16Variant(wgsl, this.shaderF16);
    if (choice.variant !== 'f16') return { source: choice.source, precision: choice.variant };
    try {
      const messages = await compileCheckWgsl(
        device, `${id}-f16`, rewriteWgslStorageFormats(choice.source, this.colorFormat), { layout },
      );
      if (!messages.some((m) => m.type === 'error')) return { source: choice.source, precision: 'f16' };
      console.warn(`[WebGPU] "${id}": f16 variant failed (${messages[0]?.message ?? 'unknown'}) — using f32`);
    } catch (e) {
      console.warn(`[WebGPU] "${id}": f16 variant check threw — using f32`, e);
    }
    return { source: wgsl, precision: 'f32-fallback' };
  }

  async compile(
    device: GPUDevice,
    pipelineLayout: GPUPipelineLayout,
    id: string,
    wgsl: string,
  ): Promise<boolean> {
    // Opt-in @group(1): only shaders that declare it get the two-layout pipeline.
    // Everything else keeps the single group-0 layout it has always used.
    let layout = pipelineLayout;
    const wantsSimRing = declaresBindGroup1(wgsl);
    if (wantsSimRing) {
      const errors = validateGroup1Declarations(wgsl);
      const simLayout = this.simRingLayoutProvider();
      if (errors.length > 0 || !simLayout) {
        console.warn(
          `[WebGPU] Shader "${id}" declares @group(1) but ` +
            (errors.length > 0
              ? `violates bind_group1.json: ${errors.join('; ')}`
              : 'this device cannot host the sim ring') +
            ' — skipped.',
        );
        return false;
      }
      layout = simLayout;
    }

    const { source, precision } = await this.selectPrecision(device, layout, id, wgsl);
    const ok = await compileShader(
      device,
      layout,
      id,
      source,
      this.pipelines,
      this.pipelineHashes,
      this.workgroupSizes,
      this.colorFormat,
    );
    if (ok) {
      this.precisions.set(id, precision);
      this.sources.set(id, source);
      this.directPipelines.delete(id);
      this.bindingUsages.set(id, analyzeShaderBindings(wgsl));
      if (wantsSimRing) this.simRingShaders.add(id);
      else this.simRingShaders.delete(id);
      this.lru.touch(id);
      this.trim(id);
    }
    return ok;
  }

  async loadShader(
    device: GPUDevice | null,
    pipelineLayout: GPUPipelineLayout | null,
    id: string,
    url: string,
  ): Promise<boolean> {
    if (!device || !pipelineLayout) return false;

    const wgsl = await fetchShaderWgsl(id, url);
    if (!wgsl) return false;
    return this.compile(device, pipelineLayout, id, wgsl);
  }
}

type BindGroup0Kind = keyof typeof bindGroup0Contract.kinds;

/** One @group(0) layout entry from src/contracts/bind_group0.json (shared with C++). */
export function bindGroup0LayoutEntry(
  binding: { binding: number; kind: string },
  colorFormat: InternalColorFormat,
  hasF32Filt: boolean,
  /** Direct present (#1512): binding 2 is the bgra8unorm swapchain instead of the colour format. */
  outputFormat?: GPUTextureFormat,
): GPUBindGroupLayoutEntry {
  const spec = bindGroup0Contract.kinds[binding.kind as BindGroup0Kind] as {
    sampler?: GPUSamplerBindingType;
    texture?: { sampleType: string; viewDimension: GPUTextureViewDimension };
    storageTexture?: { access: GPUStorageTextureAccess; format: string };
    buffer?: GPUBufferBindingType;
  } | undefined;
  if (!spec) throw new Error(`bind_group0.json: unknown kind ${binding.kind}`);
  const base = { binding: binding.binding, visibility: GPUShaderStage.COMPUTE };
  if (spec.sampler) return { ...base, sampler: { type: spec.sampler } };
  if (spec.buffer) return { ...base, buffer: { type: spec.buffer } };
  if (spec.storageTexture) {
    const { access, format } = spec.storageTexture;
    const resolved = outputFormat && binding.binding === 2
      ? outputFormat
      : format === 'color-format' ? colorFormat : (format as GPUTextureFormat);
    return { ...base, storageTexture: { access, format: resolved } };
  }
  if (!spec.texture) throw new Error(`bind_group0.json: kind ${binding.kind} declares no resource`);
  const { sampleType, viewDimension } = spec.texture;
  return {
    ...base,
    texture: {
      // Keyed on the format, not just the feature: rgba16float is always filterable.
      sampleType: sampleType === 'color-format'
        ? colorTextureSampleType(colorFormat, hasF32Filt)
        : (sampleType as GPUTextureSampleType),
      ...(viewDimension === '2d' ? {} : { viewDimension }),
    },
  };
}

export function createComputeBindGroupLayout(
  device: GPUDevice,
  hasF32Filt: boolean,
  colorFormat: InternalColorFormat = 'rgba32float',
  outputFormat?: GPUTextureFormat,
): WebGPUComputeLayout {
  const label = outputFormat ? 'computeBGL-direct' : 'computeBGL';
  const bindGroupLayout = device.createBindGroupLayout({
    label,
    entries: bindGroup0Contract.bindings.map((b) => bindGroup0LayoutEntry(b, colorFormat, hasF32Filt, outputFormat)),
  });

  const pipelineLayout = device.createPipelineLayout({
    label: outputFormat ? 'computePL-direct' : 'computePL',
    bindGroupLayouts: [bindGroupLayout],
  });

  return { bindGroupLayout, pipelineLayout };
}

export function createComputeBindGroup(
  device: GPUDevice,
  layout: GPUBindGroupLayout,
  textures: WebGPUTextureSet,
  buffers: WebGPUBufferSet,
  samplers: WebGPUSamplerSet,
): GPUBindGroup {
  return createComputeBindGroupForPass(
    device,
    layout,
    textures.readTex,
    textures.writeTex,
    textures,
    buffers,
    samplers,
  );
}

export interface GraphRoleTextureBindings {
  read: GPUTexture;
  color: GPUTexture;
  dataA: GPUTexture;
  dataB: GPUTexture;
  dataC: GPUTexture;
}

/** Bind group with explicit role textures (graph runner / multipass handoff). */
export function createComputeBindGroupForRoles(
  device: GPUDevice,
  layout: GPUBindGroupLayout,
  roles: GraphRoleTextureBindings,
  textures: WebGPUTextureSet,
  buffers: WebGPUBufferSet,
  samplers: WebGPUSamplerSet,
): GPUBindGroup {
  return device.createBindGroup({
    label: 'computeBG-graph',
    layout,
    entries: [
      { binding: 0, resource: samplers.filterSampler },
      { binding: 1, resource: roles.read.createView() },
      { binding: 2, resource: roles.color.createView() },
      { binding: 3, resource: { buffer: buffers.uniformBuf } },
      { binding: 4, resource: textures.depthRead.createView() },
      { binding: 5, resource: samplers.nearestSampler },
      { binding: 6, resource: textures.depthWrite.createView() },
      { binding: 7, resource: textures.dataTexA.createView() },
      { binding: 8, resource: textures.dataTexB.createView() },
      { binding: 9, resource: textures.dataTexC.createView() },
      { binding: 10, resource: { buffer: buffers.extraBuf } },
      { binding: 11, resource: samplers.compSampler },
      { binding: 12, resource: { buffer: buffers.plasmaBuf } },
      {
        binding: 13,
        resource: textures.historyTex.createView({
          dimension: '2d-array',
          baseArrayLayer: 0,
          arrayLayerCount: textures.historyLayers ?? HISTORY_DEPTH,
        }),
      },
    ],
  });
}

/** Bind group with explicit read/write textures (legacy two-texture handoff). */
export function createComputeBindGroupForPass(
  device: GPUDevice,
  layout: GPUBindGroupLayout,
  readTex: GPUTexture,
  writeTex: GPUTexture,
  textures: WebGPUTextureSet,
  buffers: WebGPUBufferSet,
  samplers: WebGPUSamplerSet,
): GPUBindGroup {
  return createComputeBindGroupForRoles(
    device,
    layout,
    {
      read: readTex,
      color: writeTex,
      dataA: textures.dataTexA,
      dataB: textures.dataTexB,
      dataC: textures.dataTexC,
    },
    textures,
    buffers,
    samplers,
  );
}

/**
 * Present + input-scale pipelines. On an rgba16float canvas (HDR, #1512) the
 * present shaders are the HDR variants; the layout is the same on every format:
 * binding 0 the texture, binding 1 the present params uniform (unused on SDR).
 */
export function createBlitPipeline(
  device: GPUDevice,
  canvasFormat: GPUTextureFormat,
  blitReadTex: GPUTexture,
  internalColorFormat: InternalColorFormat = 'rgba32float',
  presentParams: GPUBuffer | null = null,
): WebGPUBlitResources {
  const blitBindGroupLayout = device.createBindGroupLayout({
    label: 'blitBGL',
    entries: [
      {
        binding: 0,
        visibility: GPUShaderStage.FRAGMENT,
        texture: { sampleType: 'unfilterable-float' },
      },
      {
        binding: 1,
        visibility: GPUShaderStage.FRAGMENT,
        buffer: { type: 'uniform', minBindingSize: PRESENT_PARAMS_BYTES },
      },
    ],
  });

  const hdr = isHdrPresentFormat(canvasFormat);
  const module = device.createShaderModule({ label: hdr ? 'hdrBlitShader' : 'blitShader', code: hdr ? HDR_BLIT_WGSL : BLIT_WGSL });
  const generativeModule = device.createShaderModule({
    label: hdr ? 'hdrGenerativeBlitShader' : 'generativeBlitShader',
    code: hdr ? HDR_GENERATIVE_BLIT_WGSL : GENERATIVE_BLIT_WGSL,
  });

  const blitPipeline = device.createRenderPipeline({
    label: 'blitPipeline',
    layout: device.createPipelineLayout({ bindGroupLayouts: [blitBindGroupLayout] }),
    vertex: { module, entryPoint: 'vs' },
    fragment: { module, entryPoint: 'fs', targets: [{ format: canvasFormat }] },
    primitive: { topology: 'triangle-list' },
  });

  const generativeBlitPipeline = device.createRenderPipeline({
    label: 'generativeBlitPipeline',
    layout: device.createPipelineLayout({ bindGroupLayouts: [blitBindGroupLayout] }),
    vertex: { module: generativeModule, entryPoint: 'vs' },
    fragment: {
      module: generativeModule,
      entryPoint: 'fs',
      targets: [{ format: canvasFormat }],
    },
    primitive: { topology: 'triangle-list' },
  });

  const params = presentParams ?? createPresentParamsBuffer(device);
  const blitBindGroup = createBlitBindGroup(device, blitBindGroupLayout, blitReadTex, params);

  const scaleModule = device.createShaderModule({
    label: 'scaleCopyShader',
    code: SCALE_COPY_WGSL,
  });
  const scaleCopyPipeline = device.createRenderPipeline({
    label: 'scaleCopyPipeline',
    layout: device.createPipelineLayout({ bindGroupLayouts: [blitBindGroupLayout] }),
    vertex: { module: scaleModule, entryPoint: 'vs' },
    fragment: { module: scaleModule, entryPoint: 'fs', targets: [{ format: internalColorFormat }] },
    primitive: { topology: 'triangle-list' },
  });

  const supportsExternalTexture = 'importExternalTexture' in device;
  let videoCopyPipeline: GPURenderPipeline | null = null;
  let videoCopyBindGroupLayout: GPUBindGroupLayout | null = null;

  if (supportsExternalTexture) {
    videoCopyBindGroupLayout = device.createBindGroupLayout({
      label: 'videoCopyBGL',
      entries: [
        { binding: 0, visibility: GPUShaderStage.FRAGMENT, externalTexture: {} },
        { binding: 1, visibility: GPUShaderStage.FRAGMENT, sampler: { type: 'filtering' } },
      ],
    });

    const videoModule = device.createShaderModule({
      label: 'videoCopyShader',
      code: VIDEO_COPY_WGSL,
    });

    videoCopyPipeline = device.createRenderPipeline({
      label: 'videoCopyPipeline',
      layout: device.createPipelineLayout({
        bindGroupLayouts: [videoCopyBindGroupLayout],
      }),
      vertex: { module: videoModule, entryPoint: 'vs_main' },
      fragment: {
        module: videoModule,
        entryPoint: 'fs_main',
        targets: [{ format: internalColorFormat }],
      },
      primitive: { topology: 'triangle-list' },
    });
  }

  return {
    blitPipeline,
    generativeBlitPipeline,
    scaleCopyPipeline,
    blitBindGroupLayout,
    blitBindGroup,
    videoCopyPipeline,
    videoCopyBindGroupLayout,
    supportsExternalTexture,
  };
}

export function createPresentParamsBuffer(device: GPUDevice, settings: HdrToneMapSettings = DEFAULT_HDR_TONE_MAP): GPUBuffer {
  const buffer = device.createBuffer({
    label: 'presentParams',
    size: PRESENT_PARAMS_BYTES,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });
  device.queue.writeBuffer(buffer, 0, hdrToneMapUniform(settings));
  return buffer;
}

export function createBlitBindGroup(
  device: GPUDevice,
  layout: GPUBindGroupLayout,
  blitReadTex: GPUTexture,
  presentParams: GPUBuffer,
): GPUBindGroup {
  return device.createBindGroup({
    label: 'blitBG',
    layout,
    entries: [
      { binding: 0, resource: blitReadTex.createView() },
      { binding: 1, resource: { buffer: presentParams } },
    ],
  });
}

/** Holds compute layout, blit pipelines, and the shader cache. */
export class WebGPUPipelineModule {
  bindGroupLayout!: GPUBindGroupLayout;
  pipelineLayout!: GPUPipelineLayout;
  blitPipeline!: GPURenderPipeline;
  generativeBlitPipeline!: GPURenderPipeline;
  scaleCopyPipeline!: GPURenderPipeline;
  blitBindGroupLayout!: GPUBindGroupLayout;
  blitBindGroup!: GPUBindGroup;
  videoCopyPipeline: GPURenderPipeline | null = null;
  videoCopyBindGroupLayout: GPUBindGroupLayout | null = null;
  supportsExternalTexture = false;
  colorFormat: InternalColorFormat = 'rgba32float';
  /** Present params uniform (HDR tonemap); bound on every format, read only by the HDR blit. */
  presentParamsBuf: GPUBuffer | null = null;
  private presentParamsDevice: GPUDevice | null = null;
  private hdrToneMap: HdrToneMapSettings = { ...DEFAULT_HDR_TONE_MAP };
  private hasF32Filterable = false;
  private canvasFormat: GPUTextureFormat = 'bgra8unorm';
  private blitReadTex!: GPUTexture;

  /** Direct present (#1512): group 0 with binding 2 = bgra8unorm swapchain; built on first use. */
  private directLayout: WebGPUComputeLayout | null = null;
  private directLayoutDevice: GPUDevice | null = null;

  /** Group-1 sim-ring layouts; created lazily, null when the device lacks the limits. */
  simRingBindGroupLayout: GPUBindGroupLayout | null = null;
  private simRingPipelineLayout: GPUPipelineLayout | null = null;
  private simRingDevice: GPUDevice | null = null;

  readonly shaderManager = new WebGPUShaderManager();

  constructor() {
    this.shaderManager.setSimRingLayoutProvider(() => this.getSimRingPipelineLayout());
  }

  setupComputeLayout(
    device: GPUDevice,
    hasF32Filt: boolean,
    colorFormat: InternalColorFormat = 'rgba32float',
  ): void {
    this.hasF32Filterable = hasF32Filt;
    this.colorFormat = colorFormat;
    this.shaderManager.setColorFormat(colorFormat);
    this.directLayout = null;
    const layout = createComputeBindGroupLayout(device, hasF32Filt, colorFormat);
    this.bindGroupLayout = layout.bindGroupLayout;
    this.pipelineLayout = layout.pipelineLayout;
    // Group 0 changed → any group-1 pipeline layout built on it is stale.
    this.simRingDevice = device;
    this.simRingBindGroupLayout = null;
    this.simRingPipelineLayout = null;
  }

  /**
   * [group 0, group 1] pipeline layout for sim-ring shaders. Built on first use
   * so non-sim sessions never create it; the group-1 limits are checked against
   * device.limits here instead of being added to catalog-wide requiredLimits.
   */
  getSimRingPipelineLayout(): GPUPipelineLayout | null {
    if (this.simRingPipelineLayout) return this.simRingPipelineLayout;
    const device = this.simRingDevice;
    if (!device || !this.bindGroupLayout) return null;
    const check = checkSimRingLimits(device.limits as never);
    if (!check.ok) {
      console.warn('[WebGPU] sim ring unavailable:', check.failures.join('; '));
      return null;
    }
    this.simRingBindGroupLayout = createSimRingBindGroupLayout(device);
    this.simRingPipelineLayout = createSimRingPipelineLayout(
      device,
      this.bindGroupLayout,
      this.simRingBindGroupLayout,
    );
    return this.simRingPipelineLayout;
  }

  setupBlitPipelines(
    device: GPUDevice,
    canvasFormat: GPUTextureFormat,
    blitReadTex: GPUTexture,
    colorFormat: InternalColorFormat = this.colorFormat,
  ): void {
    this.canvasFormat = canvasFormat;
    this.blitReadTex = blitReadTex;
    this.colorFormat = colorFormat;
    if (!this.presentParamsBuf || this.presentParamsDevice !== device) {
      this.presentParamsBuf = createPresentParamsBuffer(device, this.hdrToneMap);
      this.presentParamsDevice = device;
    }
    const blit = createBlitPipeline(device, canvasFormat, blitReadTex, colorFormat, this.presentParamsBuf);
    this.blitPipeline = blit.blitPipeline;
    this.generativeBlitPipeline = blit.generativeBlitPipeline;
    this.scaleCopyPipeline = blit.scaleCopyPipeline;
    this.blitBindGroupLayout = blit.blitBindGroupLayout;
    this.blitBindGroup = blit.blitBindGroup;
    this.videoCopyPipeline = blit.videoCopyPipeline;
    this.videoCopyBindGroupLayout = blit.videoCopyBindGroupLayout;
    this.supportsExternalTexture = blit.supportsExternalTexture;
  }

  /** The direct-present group-0 layout (dataA/B/history unchanged; binding 2 = swapchain). */
  getDirectLayout(device: GPUDevice): WebGPUComputeLayout {
    if (!this.directLayout || this.directLayoutDevice !== device) {
      this.directLayout = createComputeBindGroupLayout(device, this.hasF32Filterable, this.colorFormat, DIRECT_PRESENT_FORMAT);
      this.directLayoutDevice = device;
    }
    return this.directLayout;
  }

  /** Per-frame group 0 for a direct-present pass: binding 2 is this frame's swapchain texture. */
  createDirectBindGroup(
    device: GPUDevice,
    swapchain: GPUTexture,
    textures: WebGPUTextureSet,
    buffers: WebGPUBufferSet,
    samplers: WebGPUSamplerSet,
  ): GPUBindGroup {
    return createComputeBindGroupForRoles(
      device,
      this.getDirectLayout(device).bindGroupLayout,
      { read: textures.readTex, color: swapchain, dataA: textures.dataTexA, dataB: textures.dataTexB, dataC: textures.dataTexC },
      textures,
      buffers,
      samplers,
    );
  }

  /** Re-specialise the present pipelines for a renegotiated swapchain format (HDR on / off). */
  setCanvasFormat(device: GPUDevice, canvasFormat: GPUTextureFormat): void {
    if (this.canvasFormat === canvasFormat || !this.blitReadTex) {
      this.canvasFormat = canvasFormat;
      return;
    }
    this.setupBlitPipelines(device, canvasFormat, this.blitReadTex, this.colorFormat);
  }

  getCanvasFormat(): GPUTextureFormat {
    return this.canvasFormat;
  }

  /** Paper white / peak for the HDR present; takes effect at the next present. */
  setHdrToneMap(device: GPUDevice | null, settings: HdrToneMapSettings): void {
    this.hdrToneMap = { ...settings };
    if (device && this.presentParamsBuf && this.presentParamsDevice === device) {
      device.queue.writeBuffer(this.presentParamsBuf, 0, hdrToneMapUniform(settings));
    }
  }

  setColorFormat(device: GPUDevice, colorFormat: InternalColorFormat): void {
    if (this.colorFormat === colorFormat) return;
    this.setupComputeLayout(device, this.hasF32Filterable, colorFormat);
    if (this.blitReadTex) {
      this.setupBlitPipelines(device, this.canvasFormat, this.blitReadTex, colorFormat);
    }
  }

  createBindGroupForPass(
    device: GPUDevice,
    readTex: GPUTexture,
    writeTex: GPUTexture,
    textures: WebGPUTextureSet,
    buffers: WebGPUBufferSet,
    samplers: WebGPUSamplerSet,
  ): GPUBindGroup {
    return createComputeBindGroupForPass(
      device,
      this.bindGroupLayout,
      readTex,
      writeTex,
      textures,
      buffers,
      samplers,
    );
  }

  createBindGroupForRoles(
    device: GPUDevice,
    roles: GraphRoleTextureBindings,
    textures: WebGPUTextureSet,
    buffers: WebGPUBufferSet,
    samplers: WebGPUSamplerSet,
  ): GPUBindGroup {
    return createComputeBindGroupForRoles(
      device,
      this.bindGroupLayout,
      roles,
      textures,
      buffers,
      samplers,
    );
  }

  clear(): void {
    this.shaderManager.clear();
    this.directLayout = null;
    this.directLayoutDevice = null;
    this.presentParamsBuf?.destroy();
    this.presentParamsBuf = null;
    this.presentParamsDevice = null;
  }
}
