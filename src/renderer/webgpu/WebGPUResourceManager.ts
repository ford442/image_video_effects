/**
 * WebGPUResourceManager.ts
 *
 * GPU resource creation for the TypeScript WebGPU renderer.
 */

import { BLIT_WGSL, GENERATIVE_BLIT_WGSL, VIDEO_COPY_WGSL } from '../ShaderTemplates';
import { UNIFORM_FLOATS } from '../UniformBuffer';
import {
  EXTRA_FLOATS,
  HISTORY_DEPTH,
  PLASMA_BYTES,
} from './webgpuConstants';

export interface WebGPUTextureSet {
  sourceTex: GPUTexture;
  readTex: GPUTexture;
  writeTex: GPUTexture;
  dataTexA: GPUTexture;
  dataTexB: GPUTexture;
  dataTexC: GPUTexture;
  historyTex: GPUTexture;
  depthRead: GPUTexture;
  depthWrite: GPUTexture;
  emptyTex: GPUTexture;
}

export interface WebGPUSamplerSet {
  filterSampler: GPUSampler;
  nearestSampler: GPUSampler;
  compSampler: GPUSampler;
}

export interface WebGPUBufferSet {
  uniformBuf: GPUBuffer;
  extraBuf: GPUBuffer;
  plasmaBuf: GPUBuffer;
}

export interface WebGPUComputeLayout {
  bindGroupLayout: GPUBindGroupLayout;
  pipelineLayout: GPUPipelineLayout;
}

export interface WebGPUBlitResources {
  blitPipeline: GPURenderPipeline;
  generativeBlitPipeline: GPURenderPipeline;
  blitBindGroupLayout: GPUBindGroupLayout;
  blitBindGroup: GPUBindGroup;
  videoCopyPipeline: GPURenderPipeline | null;
  videoCopyBindGroupLayout: GPUBindGroupLayout | null;
  supportsExternalTexture: boolean;
}

export interface WebGPUTimestampQueries {
  supportsTimestampQuery: boolean;
  querySet: GPUQuerySet | null;
  queryBuffer: GPUBuffer | null;
}

export function createTextures(
  device: GPUDevice,
  canvasW: number,
  canvasH: number,
  scaledW: number,
  scaledH: number,
): WebGPUTextureSet {
  const fullW = canvasW;
  const fullH = canvasH;
  const sw = scaledW || fullW;
  const sh = scaledH || fullH;

  const USAGE_SOURCE =
    GPUTextureUsage.TEXTURE_BINDING |
    GPUTextureUsage.COPY_DST |
    GPUTextureUsage.COPY_SRC |
    GPUTextureUsage.RENDER_ATTACHMENT;

  const USAGE_STANDARD =
    GPUTextureUsage.TEXTURE_BINDING |
    GPUTextureUsage.STORAGE_BINDING |
    GPUTextureUsage.COPY_DST |
    GPUTextureUsage.COPY_SRC;

  const sourceTex = device.createTexture({
    label: 'sourceTex',
    size: [fullW, fullH],
    format: 'rgba32float',
    usage: USAGE_SOURCE,
  });

  const readTex = device.createTexture({
    label: 'readTex',
    size: [sw, sh],
    format: 'rgba32float',
    usage: USAGE_STANDARD,
  });

  const writeTex = device.createTexture({
    label: 'writeTex',
    size: [sw, sh],
    format: 'rgba32float',
    usage: USAGE_STANDARD,
  });

  const dataTexA = device.createTexture({
    label: 'dataTexA',
    size: [sw, sh],
    format: 'rgba32float',
    usage: USAGE_STANDARD,
  });

  const dataTexB = device.createTexture({
    label: 'dataTexB',
    size: [sw, sh],
    format: 'rgba32float',
    usage: USAGE_STANDARD,
  });

  const dataTexC = device.createTexture({
    label: 'dataTexC',
    size: [sw, sh],
    format: 'rgba32float',
    usage: USAGE_STANDARD,
  });

  const historyTex = device.createTexture({
    label: 'historyTex',
    size: { width: sw, height: sh, depthOrArrayLayers: HISTORY_DEPTH },
    format: 'rgba32float',
    usage:
      GPUTextureUsage.TEXTURE_BINDING |
      GPUTextureUsage.STORAGE_BINDING |
      GPUTextureUsage.COPY_DST |
      GPUTextureUsage.COPY_SRC,
  });

  const depthRead = device.createTexture({
    label: 'depthRead',
    size: [fullW, fullH],
    format: 'r32float',
    usage: USAGE_SOURCE,
  });

  const depthWrite = device.createTexture({
    label: 'depthWrite',
    size: [sw, sh],
    format: 'r32float',
    usage: USAGE_STANDARD,
  });

  const emptyTex = device.createTexture({
    label: 'emptyTex',
    size: [1, 1],
    format: 'r32float',
    usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
  });

  device.queue.writeTexture(
    { texture: emptyTex },
    new Float32Array([0]),
    { bytesPerRow: 4 },
    [1, 1],
  );

  return {
    sourceTex,
    readTex,
    writeTex,
    dataTexA,
    dataTexB,
    dataTexC,
    historyTex,
    depthRead,
    depthWrite,
    emptyTex,
  };
}

export function createSamplers(device: GPUDevice): WebGPUSamplerSet {
  const filterSampler = device.createSampler({
    label: 'filterSampler',
    magFilter: 'linear',
    minFilter: 'linear',
    mipmapFilter: 'linear',
    addressModeU: 'repeat',
    addressModeV: 'repeat',
  });
  const nearestSampler = device.createSampler({
    label: 'nearestSampler',
    magFilter: 'nearest',
    minFilter: 'nearest',
    addressModeU: 'clamp-to-edge',
    addressModeV: 'clamp-to-edge',
  });
  const compSampler = device.createSampler({
    label: 'compSampler',
    compare: 'less',
  });
  return { filterSampler, nearestSampler, compSampler };
}

export function createBuffers(device: GPUDevice): WebGPUBufferSet {
  const uniformBuf = device.createBuffer({
    label: 'uniformBuf',
    size: UNIFORM_FLOATS * 4,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });
  const extraBuf = device.createBuffer({
    label: 'extraBuf',
    size: EXTRA_FLOATS * 4,
    usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
  });
  const plasmaBuf = device.createBuffer({
    label: 'plasmaBuf',
    size: Math.max(PLASMA_BYTES, 16),
    usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
  });
  return { uniformBuf, extraBuf, plasmaBuf };
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
  return device.createBindGroup({
    label: 'computeBG',
    layout,
    entries: [
      { binding: 0, resource: samplers.filterSampler },
      { binding: 1, resource: textures.readTex.createView() },
      { binding: 2, resource: textures.writeTex.createView() },
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

export function createBlitPipeline(
  device: GPUDevice,
  canvasFormat: GPUTextureFormat,
  blitReadTex: GPUTexture,
  scaledW: number,
  scaledH: number,
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

export function createTimestampQueries(device: GPUDevice): WebGPUTimestampQueries {
  const supportsTimestampQuery = device.features.has('timestamp-query');
  let querySet: GPUQuerySet | null = null;
  let queryBuffer: GPUBuffer | null = null;

  if (supportsTimestampQuery) {
    try {
      querySet = device.createQuerySet({
        type: 'timestamp',
        count: 8,
      });
      queryBuffer = device.createBuffer({
        size: 8 * 8,
        usage: GPUBufferUsage.QUERY_RESOLVE | GPUBufferUsage.COPY_SRC,
      });
      console.log('[WebGPU] Timestamp queries enabled for GPU profiling');
    } catch (e) {
      console.warn('[WebGPU] Timestamp query creation failed:', e);
      return { supportsTimestampQuery: false, querySet: null, queryBuffer: null };
    }
  }

  return { supportsTimestampQuery, querySet, queryBuffer };
}
