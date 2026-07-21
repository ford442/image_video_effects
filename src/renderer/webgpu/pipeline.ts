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
import { BLIT_WGSL, GENERATIVE_BLIT_WGSL, SCALE_COPY_WGSL, VIDEO_COPY_WGSL } from '../ShaderTemplates';
import { resolveShaderUrl } from '../../utils/resolveShaderUrl';
import { fetchShaderWgsl } from '../../utils/fetchShaderWgsl';
import { HISTORY_DEPTH } from './webgpuConstants';
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

export class WebGPUShaderManager {
  private pipelines = new Map<string, GPUComputePipeline>();
  private pipelineHashes = new Map<string, string>();
  private workgroupSizes = new Map<string, { x: number; y: number }>();
  private bindingUsages = new Map<string, ShaderBindingUsage>();

  getPipeline(id: string): GPUComputePipeline | undefined {
    return this.pipelines.get(id);
  }

  hasPipeline(id: string): boolean {
    return this.pipelines.has(id);
  }

  getWorkgroupSize(id: string): { x: number; y: number } {
    return this.workgroupSizes.get(id) || { x: 8, y: 8 };
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

  clear(): void {
    this.pipelines.clear();
    this.pipelineHashes.clear();
    this.workgroupSizes.clear();
    this.bindingUsages.clear();
  }

  compile(
    device: GPUDevice,
    pipelineLayout: GPUPipelineLayout,
    id: string,
    wgsl: string,
  ): boolean {
    const ok = compileShader(
      device,
      pipelineLayout,
      id,
      wgsl,
      this.pipelines,
      this.pipelineHashes,
      this.workgroupSizes,
    );
    if (ok) {
      this.bindingUsages.set(id, analyzeShaderBindings(wgsl));
    }
    return ok;
  }

  async loadShader(
    device: GPUDevice | null,
    pipelineLayout: GPUPipelineLayout | null,
    supportsSubgroups: boolean,
    id: string,
    url: string,
  ): Promise<boolean> {
    if (!device || !pipelineLayout) return false;

    const resolvedUrl = resolveShaderUrl(url);

    if (supportsSubgroups && !id.endsWith('-sg') && resolvedUrl.endsWith('.wgsl')) {
      const sgUrl = resolvedUrl.replace(/\.wgsl$/, '-sg.wgsl');
      const sgWgsl = await fetchShaderWgsl(`${id}-sg`, sgUrl);
      if (sgWgsl) {
        const ok = this.compile(device, pipelineLayout, id, sgWgsl);
        if (ok) {
          if (process.env.NODE_ENV !== 'production') {
            console.log(`[WebGPU] "${id}": loaded subgroup variant (-sg.wgsl)`);
          }
          return true;
        }
      }
      if (process.env.NODE_ENV !== 'production') {
        console.log(`[WebGPU] "${id}": no -sg variant found, using base variant`);
      }
    }

    const wgsl = await fetchShaderWgsl(id, url);
    if (!wgsl) return false;
    return this.compile(device, pipelineLayout, id, wgsl);
  }
}

export function createComputeBindGroupLayout(
  device: GPUDevice,
  hasF32Filt: boolean,
): WebGPUComputeLayout {
  const fST: GPUTextureSampleType = hasF32Filt ? 'float' : 'unfilterable-float';
  const V = GPUShaderStage.COMPUTE;

  const bindGroupLayout = device.createBindGroupLayout({
    label: 'computeBGL',
    entries: [
      { binding: 0, visibility: V, sampler: { type: 'filtering' } },
      { binding: 1, visibility: V, texture: { sampleType: fST } },
      { binding: 2, visibility: V, storageTexture: { access: 'write-only', format: 'rgba32float' } },
      { binding: 3, visibility: V, buffer: { type: 'uniform' } },
      { binding: 4, visibility: V, texture: { sampleType: 'unfilterable-float' } },
      { binding: 5, visibility: V, sampler: { type: 'non-filtering' } },
      { binding: 6, visibility: V, storageTexture: { access: 'write-only', format: 'r32float' } },
      { binding: 7, visibility: V, storageTexture: { access: 'write-only', format: 'rgba32float' } },
      { binding: 8, visibility: V, storageTexture: { access: 'write-only', format: 'rgba32float' } },
      { binding: 9, visibility: V, texture: { sampleType: fST } },
      { binding: 10, visibility: V, buffer: { type: 'storage' } },
      { binding: 11, visibility: V, sampler: { type: 'comparison' } },
      { binding: 12, visibility: V, buffer: { type: 'read-only-storage' } },
      {
        binding: 13,
        visibility: V,
        texture: { sampleType: fST, viewDimension: '2d-array' },
      },
    ],
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
          arrayLayerCount: HISTORY_DEPTH,
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
    fragment: { module: scaleModule, entryPoint: 'fs', targets: [{ format: 'rgba32float' }] },
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
        targets: [{ format: 'rgba32float' }],
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

  readonly shaderManager = new WebGPUShaderManager();

  setupComputeLayout(device: GPUDevice, hasF32Filt: boolean): void {
    const layout = createComputeBindGroupLayout(device, hasF32Filt);
    this.bindGroupLayout = layout.bindGroupLayout;
    this.pipelineLayout = layout.pipelineLayout;
  }

  setupBlitPipelines(
    device: GPUDevice,
    canvasFormat: GPUTextureFormat,
    blitReadTex: GPUTexture,
  ): void {
    const blit = createBlitPipeline(device, canvasFormat, blitReadTex);
    this.blitPipeline = blit.blitPipeline;
    this.generativeBlitPipeline = blit.generativeBlitPipeline;
    this.scaleCopyPipeline = blit.scaleCopyPipeline;
    this.blitBindGroupLayout = blit.blitBindGroupLayout;
    this.blitBindGroup = blit.blitBindGroup;
    this.videoCopyPipeline = blit.videoCopyPipeline;
    this.videoCopyBindGroupLayout = blit.videoCopyBindGroupLayout;
    this.supportsExternalTexture = blit.supportsExternalTexture;
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
