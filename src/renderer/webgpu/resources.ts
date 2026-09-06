/**
 * resources.ts
 *
 * GPU texture, buffer, and sampler lifecycle for the TypeScript WebGPU renderer.
 * Mirrors wasm_renderer/resources.cpp.
 */

import { UNIFORM_FLOATS } from '../UniformBuffer';
import type { InternalColorFormat } from '../../config/formatPolicy';
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
  /** Actual history ring layers (≤ HISTORY_DEPTH). */
  historyLayers: number;
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

export function createTextures(
  device: GPUDevice,
  canvasW: number,
  canvasH: number,
  scaledW: number,
  scaledH: number,
  colorFormat: InternalColorFormat = 'rgba32float',
  historyLayers: number = HISTORY_DEPTH,
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

  // scalePass renders into readTex when resolutionScale < 1, so RENDER_ATTACHMENT
  // is required in addition to the usual storage/copy usages.
  const USAGE_READ =
    USAGE_STANDARD | GPUTextureUsage.RENDER_ATTACHMENT;

  const rgbaFormat = colorFormat;

  const sourceTex = device.createTexture({
    label: 'sourceTex',
    size: [fullW, fullH],
    format: rgbaFormat,
    usage: USAGE_SOURCE,
  });

  const readTex = device.createTexture({
    label: 'readTex',
    size: [sw, sh],
    format: rgbaFormat,
    usage: USAGE_READ,
  });

  const writeTex = device.createTexture({
    label: 'writeTex',
    size: [sw, sh],
    format: rgbaFormat,
    usage: USAGE_STANDARD,
  });

  const dataTexA = device.createTexture({
    label: 'dataTexA',
    size: [sw, sh],
    format: rgbaFormat,
    usage: USAGE_STANDARD,
  });

  const dataTexB = device.createTexture({
    label: 'dataTexB',
    size: [sw, sh],
    format: rgbaFormat,
    usage: USAGE_STANDARD,
  });

  const dataTexC = device.createTexture({
    label: 'dataTexC',
    size: [sw, sh],
    format: rgbaFormat,
    usage: USAGE_STANDARD,
  });

  const layers = Math.max(1, Math.min(HISTORY_DEPTH, historyLayers | 0));
  const historyTex = device.createTexture({
    label: 'historyTex',
    size: { width: sw, height: sh, depthOrArrayLayers: layers },
    format: rgbaFormat,
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
    historyLayers: layers,
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

/** Manages GPU textures, buffers, samplers, and the default compute bind group. */
export class WebGPUResourcePool {
  colorFormat: InternalColorFormat = 'rgba32float';

  sourceTex!: GPUTexture;
  readTex!: GPUTexture;
  writeTex!: GPUTexture;
  dataTexA!: GPUTexture;
  dataTexB!: GPUTexture;
  dataTexC!: GPUTexture;
  historyTex!: GPUTexture;
  historyLayers = HISTORY_DEPTH;
  depthRead!: GPUTexture;
  depthWrite!: GPUTexture;
  emptyTex!: GPUTexture;

  filterSampler!: GPUSampler;
  nearestSampler!: GPUSampler;
  compSampler!: GPUSampler;

  uniformBuf!: GPUBuffer;
  extraBuf!: GPUBuffer;
  plasmaBuf!: GPUBuffer;

  blitReadTex!: GPUTexture;

  setup(
    device: GPUDevice,
    canvasW: number,
    canvasH: number,
    scaledW: number,
    scaledH: number,
    colorFormat: InternalColorFormat = 'rgba32float',
    historyLayers: number = HISTORY_DEPTH,
  ): void {
    this.colorFormat = colorFormat;
    const textures = createTextures(
      device, canvasW, canvasH, scaledW, scaledH, colorFormat, historyLayers,
    );
    this.applyTextureSet(textures);

    const samplers = createSamplers(device);
    this.filterSampler = samplers.filterSampler;
    this.nearestSampler = samplers.nearestSampler;
    this.compSampler = samplers.compSampler;

    const buffers = createBuffers(device);
    this.uniformBuf = buffers.uniformBuf;
    this.extraBuf = buffers.extraBuf;
    this.plasmaBuf = buffers.plasmaBuf;
  }

  applyTextureSet(tex: WebGPUTextureSet): void {
    this.sourceTex = tex.sourceTex;
    this.readTex = tex.readTex;
    this.writeTex = tex.writeTex;
    this.dataTexA = tex.dataTexA;
    this.dataTexB = tex.dataTexB;
    this.dataTexC = tex.dataTexC;
    this.historyTex = tex.historyTex;
    this.historyLayers = tex.historyLayers;
    this.depthRead = tex.depthRead;
    this.depthWrite = tex.depthWrite;
    this.emptyTex = tex.emptyTex;
    this.blitReadTex = this.readTex;
  }

  getTextureSet(): WebGPUTextureSet {
    return {
      sourceTex: this.sourceTex,
      readTex: this.readTex,
      writeTex: this.writeTex,
      dataTexA: this.dataTexA,
      dataTexB: this.dataTexB,
      dataTexC: this.dataTexC,
      historyTex: this.historyTex,
      historyLayers: this.historyLayers,
      depthRead: this.depthRead,
      depthWrite: this.depthWrite,
      emptyTex: this.emptyTex,
    };
  }

  getBufferSet(): WebGPUBufferSet {
    return {
      uniformBuf: this.uniformBuf,
      extraBuf: this.extraBuf,
      plasmaBuf: this.plasmaBuf,
    };
  }

  getSamplerSet(): WebGPUSamplerSet {
    return {
      filterSampler: this.filterSampler,
      nearestSampler: this.nearestSampler,
      compSampler: this.compSampler,
    };
  }

  destroyWorkingTextures(): void {
    for (const t of [
      this.sourceTex, this.readTex, this.writeTex, this.dataTexA, this.dataTexB,
      this.dataTexC, this.historyTex, this.depthRead, this.depthWrite, this.emptyTex,
    ]) {
      t?.destroy();
    }
  }

  recreateScaleTextures(
    device: GPUDevice,
    canvasW: number,
    canvasH: number,
    scaledW: number,
    scaledH: number,
    colorFormat: InternalColorFormat = this.colorFormat,
    historyLayers: number = this.historyLayers,
  ): WebGPUTextureSet {
    this.colorFormat = colorFormat;
    this.destroyWorkingTextures();
    const textures = createTextures(
      device, canvasW, canvasH, scaledW, scaledH, colorFormat, historyLayers,
    );
    this.applyTextureSet(textures);
    return textures;
  }

  destroyBuffers(): void {
    for (const b of [this.uniformBuf, this.extraBuf, this.plasmaBuf]) {
      b?.destroy();
    }
  }
}
