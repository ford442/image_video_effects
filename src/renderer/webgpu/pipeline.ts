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
  ShaderBindingUsage,
} from '../ShaderCompilation';
import type { InternalColorFormat } from '../../config/formatPolicy';
import bindGroup0Contract from '../../contracts/bind_group0.json';
import { BLIT_WGSL, GENERATIVE_BLIT_WGSL, SCALE_COPY_WGSL, VIDEO_COPY_WGSL } from '../ShaderTemplates';
import { fetchShaderWgsl } from '../../utils/fetchShaderWgsl';
import { applyF16Variant } from '../wgslF16';
import { HISTORY_DEPTH } from './webgpuConstants';
import { PIPELINE_CACHE_LIMIT, PipelineLru } from './pipelineCache';
import {
  checkSimRingLimits,
  createSimRingBindGroupLayout,
  createSimRingHashBindGroupLayout,
  createSimRingPipelineLayout,
  declaresBindGroup1,
  declaresSimHash,
  validateGroup1Declarations,
} from './simRing';
import { createSimHashBuildResources, type SimHashBuildResources } from './simHash';
import {
  WebGPUBufferSet,
  WebGPUSamplerSet,
  WebGPUTextureSet,
} from './resources';

export interface WebGPUComputeLayout {
  bindGroupLayout: GPUBindGroupLayout;
  pipelineLayout: GPUPipelineLayout;
}

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

/** Group-1 layout provider (`spatialHash`: the 4-binding layout); null when the device cannot host it. */
export type SimRingLayoutProvider = (spatialHash: boolean) => GPUPipelineLayout | null;

export class WebGPUShaderManager {
  private pipelines = new Map<string, GPUComputePipeline>();
  /** Recency of every cached pipeline; the single eviction authority (warm-up included). */
  private readonly lru = new PipelineLru();
  private cacheLimit = PIPELINE_CACHE_LIMIT;
  /** Ids bound to a slot (including graph chains): never evicted. */
  private boundIds: () => ReadonlySet<string> = () => new Set<string>();
  private simRingShaders = new Set<string>();
  private simHashShaders = new Set<string>();
  private simRingLayoutProvider: SimRingLayoutProvider = () => null;
  private pipelineHashes = new Map<string, string>();
  private workgroupSizes = new Map<string, { x: number; y: number }>();
  private bindingUsages = new Map<string, ShaderBindingUsage>();
  private colorFormat: InternalColorFormat = 'rgba32float';
  /** The device was granted shader-f16: `// @requires f16` shaders compile their f16 variant. */
  private shaderF16 = false;

  setShaderF16(enabled: boolean): void {
    if (this.shaderF16 === enabled) return;
    this.shaderF16 = enabled;
    this.clear();
  }

  getShaderF16(): boolean {
    return this.shaderF16;
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

  /** True when the cached pipeline for `id` was built against the 4-binding (simHash) group-1 layout. */
  usesSimHash(id: string): boolean {
    return this.simHashShaders.has(id);
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
    this.simHashShaders.delete(id);
  }

  clear(): void {
    this.lru.clear();
    this.pipelines.clear();
    this.pipelineHashes.clear();
    this.workgroupSizes.clear();
    this.bindingUsages.clear();
    this.simRingShaders.clear();
    this.simHashShaders.clear();
  }

  async compile(
    device: GPUDevice,
    pipelineLayout: GPUPipelineLayout,
    id: string,
    source: string,
  ): Promise<boolean> {
    // f16 variant first (#1512): everything below sees exactly what the GPU compiles.
    const wgsl = applyF16Variant(source, this.shaderF16);
    // Opt-in @group(1): only shaders that declare it get the two-layout pipeline.
    // Everything else keeps the single group-0 layout it has always used.
    let layout = pipelineLayout;
    const wantsSimRing = declaresBindGroup1(wgsl);
    // Opt-in within the opt-in: binding 3 selects the second, 4-binding group-1 layout.
    const wantsSimHash = wantsSimRing && declaresSimHash(wgsl);
    if (wantsSimRing) {
      const errors = validateGroup1Declarations(wgsl);
      const simLayout = this.simRingLayoutProvider(wantsSimHash);
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

    const ok = await compileShader(
      device,
      layout,
      id,
      wgsl,
      this.pipelines,
      this.pipelineHashes,
      this.workgroupSizes,
      this.colorFormat,
    );
    if (ok) {
      this.bindingUsages.set(id, analyzeShaderBindings(wgsl));
      if (wantsSimRing) this.simRingShaders.add(id);
      else this.simRingShaders.delete(id);
      if (wantsSimHash) this.simHashShaders.add(id);
      else this.simHashShaders.delete(id);
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

/** One @group(0) layout entry from src/contracts/bind_group0.json (shared with the C++ header). */
function bindGroup0Entry(
  binding: number,
  kind: BindGroup0Kind,
  visibility: GPUShaderStageFlags,
  colorSample: GPUTextureSampleType,
  colorFormat: InternalColorFormat,
): GPUBindGroupLayoutEntry {
  switch (kind) {
    case 'filteringSampler': return { binding, visibility, sampler: { type: 'filtering' } };
    case 'nonFilteringSampler': return { binding, visibility, sampler: { type: 'non-filtering' } };
    case 'comparisonSampler': return { binding, visibility, sampler: { type: 'comparison' } };
    case 'sampledColor': return { binding, visibility, texture: { sampleType: colorSample } };
    case 'sampledColorArray':
      return { binding, visibility, texture: { sampleType: colorSample, viewDimension: '2d-array' } };
    case 'sampledDepth': return { binding, visibility, texture: { sampleType: 'unfilterable-float' } };
    case 'storageColor':
      return { binding, visibility, storageTexture: { access: 'write-only', format: colorFormat } };
    case 'storageDepth':
      return { binding, visibility, storageTexture: { access: 'write-only', format: 'r32float' } };
    case 'uniformBuffer': return { binding, visibility, buffer: { type: 'uniform' } };
    case 'storageBuffer': return { binding, visibility, buffer: { type: 'storage' } };
    case 'readOnlyStorageBuffer': return { binding, visibility, buffer: { type: 'read-only-storage' } };
  }
}

/**
 * Sample type for the internal-colour bindings (1, 9, 13). Keyed on the texture format, not the
 * device feature alone: rgba16float is always filterable, so pairing it with the filtering
 * `u_sampler` is legal even without `float32-filterable`. Only rgba32float needs the feature.
 */
export function colorSampleType(
  colorFormat: InternalColorFormat,
  hasF32Filt: boolean,
): GPUTextureSampleType {
  if (colorFormat === 'rgba32float' && !hasF32Filt) return 'unfilterable-float';
  return 'float';
}

export function createComputeBindGroupLayout(
  device: GPUDevice,
  hasF32Filt: boolean,
  colorFormat: InternalColorFormat = 'rgba32float',
): WebGPUComputeLayout {
  const fST = colorSampleType(colorFormat, hasF32Filt);
  const V = GPUShaderStage.COMPUTE;

  const bindGroupLayout = device.createBindGroupLayout({
    label: 'computeBGL',
    entries: bindGroup0Contract.bindings.map(({ binding, kind }) =>
      bindGroup0Entry(binding, kind as BindGroup0Kind, V, fST, colorFormat),
    ),
  });

  const pipelineLayout = device.createPipelineLayout({
    label: 'computePL',
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

export function createBlitPipeline(
  device: GPUDevice,
  canvasFormat: GPUTextureFormat,
  blitReadTex: GPUTexture,
  internalColorFormat: InternalColorFormat = 'rgba32float',
): WebGPUBlitResources {
  const blitBindGroupLayout = device.createBindGroupLayout({
    label: 'blitBGL',
    entries: [
      {
        binding: 0,
        visibility: GPUShaderStage.FRAGMENT,
        texture: { sampleType: 'unfilterable-float' },
      },
    ],
  });

  const module = device.createShaderModule({ label: 'blitShader', code: BLIT_WGSL });
  const generativeModule = device.createShaderModule({
    label: 'generativeBlitShader',
    code: GENERATIVE_BLIT_WGSL,
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

  const blitBindGroup = device.createBindGroup({
    label: 'blitBG',
    layout: blitBindGroupLayout,
    entries: [{ binding: 0, resource: blitReadTex.createView() }],
  });

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

export function createBlitBindGroup(
  device: GPUDevice,
  layout: GPUBindGroupLayout,
  blitReadTex: GPUTexture,
): GPUBindGroup {
  return device.createBindGroup({
    label: 'blitBG',
    layout,
    entries: [{ binding: 0, resource: blitReadTex.createView() }],
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
  private hasF32Filterable = false;
  private canvasFormat: GPUTextureFormat = 'bgra8unorm';
  private blitReadTex!: GPUTexture;

  /** Group-1 sim-ring layouts; created lazily, null when the device lacks the limits. */
  simRingBindGroupLayout: GPUBindGroupLayout | null = null;
  private simRingPipelineLayout: GPUPipelineLayout | null = null;
  /** The second group-1 layout (bindings 0–3), only built once a simHash shader compiles. */
  simRingHashBindGroupLayout: GPUBindGroupLayout | null = null;
  private simRingHashPipelineLayout: GPUPipelineLayout | null = null;
  private simHashBuild: SimHashBuildResources | null = null;
  private simRingDevice: GPUDevice | null = null;

  readonly shaderManager = new WebGPUShaderManager();

  constructor() {
    this.shaderManager.setSimRingLayoutProvider((spatialHash) => this.getSimRingPipelineLayout(spatialHash));
  }

  setupComputeLayout(
    device: GPUDevice,
    hasF32Filt: boolean,
    colorFormat: InternalColorFormat = 'rgba32float',
  ): void {
    this.hasF32Filterable = hasF32Filt;
    this.colorFormat = colorFormat;
    this.shaderManager.setColorFormat(colorFormat);
    const layout = createComputeBindGroupLayout(device, hasF32Filt, colorFormat);
    this.bindGroupLayout = layout.bindGroupLayout;
    this.pipelineLayout = layout.pipelineLayout;
    // Group 0 changed → any group-1 pipeline layout built on it is stale.
    this.simRingDevice = device;
    this.simRingBindGroupLayout = null;
    this.simRingPipelineLayout = null;
    this.simRingHashBindGroupLayout = null;
    this.simRingHashPipelineLayout = null;
    this.simHashBuild = null;
  }

  /**
   * [group 0, group 1] pipeline layout for sim-ring shaders. Built on first use
   * so non-sim sessions never create it; the group-1 limits are checked against
   * device.limits here instead of being added to catalog-wide requiredLimits.
   */
  getSimRingPipelineLayout(spatialHash = false): GPUPipelineLayout | null {
    const cached = spatialHash ? this.simRingHashPipelineLayout : this.simRingPipelineLayout;
    if (cached) return cached;
    const device = this.simRingDevice;
    if (!device || !this.bindGroupLayout) return null;
    // The one extra storage buffer of simHash is checked here, never added to catalog-wide limits.
    const check = checkSimRingLimits(device.limits as never, spatialHash);
    if (!check.ok) {
      console.warn(`[WebGPU] sim ring${spatialHash ? ' spatial hash' : ''} unavailable:`, check.failures.join('; '));
      return null;
    }
    // A hash ring still binds the base layout for its nodes that do not declare simHash.
    if (!this.simRingBindGroupLayout) {
      this.simRingBindGroupLayout = createSimRingBindGroupLayout(device);
      this.simRingPipelineLayout = createSimRingPipelineLayout(
        device,
        this.bindGroupLayout,
        this.simRingBindGroupLayout,
      );
    }
    if (!spatialHash) return this.simRingPipelineLayout;
    this.simRingHashBindGroupLayout = createSimRingHashBindGroupLayout(device);
    this.simRingHashPipelineLayout = createSimRingPipelineLayout(
      device,
      this.bindGroupLayout,
      this.simRingHashBindGroupLayout,
    );
    return this.simRingHashPipelineLayout;
  }

  /**
   * The planner's scatter pass (simHash.ts) and its bind group layout; built on
   * first use so sessions without a simHash shader never compile it.
   */
  getSimHashBuildResources(): SimHashBuildResources | null {
    if (this.simHashBuild) return this.simHashBuild;
    const device = this.simRingDevice;
    if (!device) return null;
    this.simHashBuild = createSimHashBuildResources(device);
    return this.simHashBuild;
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
    const blit = createBlitPipeline(device, canvasFormat, blitReadTex, colorFormat);
    this.blitPipeline = blit.blitPipeline;
    this.generativeBlitPipeline = blit.generativeBlitPipeline;
    this.scaleCopyPipeline = blit.scaleCopyPipeline;
    this.blitBindGroupLayout = blit.blitBindGroupLayout;
    this.blitBindGroup = blit.blitBindGroup;
    this.videoCopyPipeline = blit.videoCopyPipeline;
    this.videoCopyBindGroupLayout = blit.videoCopyBindGroupLayout;
    this.supportsExternalTexture = blit.supportsExternalTexture;
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
  }
}
