/**
 * nodeScale.ts
 *
 * Per-node resolution scale for opt-in graph nodes (#1314 WP-3). A scaled
 * node runs inside an "island":
 *
 *   enter: resample readTex and dataTexC (the only readable roles, bindings
 *          1 and 9) into scratch textures at the scaled size, and patch
 *          uniforms config.zw (bytes 8-15) to that size
 *   node:  dispatch over the scaled size with a bind group over the scratch set
 *   exit:  resample each *declared* write (color / dataA / dataB) back to full
 *          size and restore config.zw
 *
 * The shader sees a consistent smaller world and needs no changes. Depth and
 * history stay full size, which is why nodes must opt in (`scalable`).
 * Present, history and every other pass are untouched.
 */

import type { InternalColorFormat } from '../../config/formatPolicy';
import { NODE_SCALE_LEVELS } from '../multipassGraph';
import { rewriteWgslStorageFormats } from '../wgslFormatRewrite';
import { createComputeBindGroupForRoles } from './pipeline';
import type { WebGPUBufferSet, WebGPUSamplerSet, WebGPUTextureSet } from './resources';
import { WG_SIZE_X, WG_SIZE_Y } from './webgpuConstants';

export type IslandRole = 'color' | 'dataA' | 'dataB';

type ScratchRole = 'read' | 'color' | 'dataA' | 'dataB' | 'dataC';
const SCRATCH_ROLES: readonly ScratchRole[] = ['read', 'color', 'dataA', 'dataB', 'dataC'];

/** All scratch levels together may not exceed this (else the node runs unscaled). */
export const ISLAND_SCRATCH_BUDGET_BYTES = 128 * 1024 * 1024;

/** Byte offset of config.zw (resolution) in the 848-byte uniform block. */
const CONFIG_ZW_OFFSET = 8;

export function nodeScaleKey(slot: number, nodeId: string): string {
  return `${slot}:${nodeId}`;
}

/** Snap a requested scale to 0.25 steps within [max(0.25, minScale), 1]. */
export function snapNodeScale(scale: number, minScale = 0.25): number {
  const floor = Math.max(0.25, Math.min(1, minScale));
  const clamped = Math.max(floor, Math.min(1, Number.isFinite(scale) ? scale : 1));
  return Math.max(floor, Math.round(clamped * 4) / 4);
}

/** Scaled dispatch size, rounded up to whole workgroups and never above full size. */
export function scaledIslandSize(fullW: number, fullH: number, scale: number): [number, number] {
  const w = Math.min(fullW, Math.max(WG_SIZE_X, Math.ceil((fullW * scale) / WG_SIZE_X) * WG_SIZE_X));
  const h = Math.min(fullH, Math.max(WG_SIZE_Y, Math.ceil((fullH * scale) / WG_SIZE_Y) * WG_SIZE_Y));
  return [w, h];
}

function bytesPerTexel(format: InternalColorFormat): number {
  return format === 'rgba32float' ? 16 : 8;
}

/**
 * Bilinear resample src → dst at dst's size using textureLoad (no filterable-
 * float requirement, so it works for rgba32float). Identity when sizes match.
 */
export const RESAMPLE_WGSL = /* wgsl */ `
@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var dst: texture_storage_2d<rgba32float, write>;

fn tap(p: vec2i, maxP: vec2i) -> vec4f {
  return textureLoad(src, clamp(p, vec2i(0), maxP), 0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3u) {
  let dstSize = textureDimensions(dst);
  if (id.x >= dstSize.x || id.y >= dstSize.y) { return; }
  let srcSize = vec2f(textureDimensions(src));
  let p = (vec2f(id.xy) + 0.5) / vec2f(dstSize) * srcSize - 0.5;
  let base = floor(p);
  let f = p - base;
  let p0 = vec2i(base);
  let maxP = vec2i(srcSize) - vec2i(1);
  let top = mix(tap(p0, maxP), tap(p0 + vec2i(1, 0), maxP), f.x);
  let bottom = mix(tap(p0 + vec2i(0, 1), maxP), tap(p0 + vec2i(1, 1), maxP), f.x);
  textureStore(dst, id.xy, mix(top, bottom, f.y));
}
`;

export interface IslandEnvironment {
  device: GPUDevice;
  colorFormat: InternalColorFormat;
  /** The compute bind-group layout (bindings 0–13). */
  bindGroupLayout: GPUBindGroupLayout;
  textures: WebGPUTextureSet;
  buffers: WebGPUBufferSet;
  samplers: WebGPUSamplerSet;
  scaledW: number;
  scaledH: number;
}

interface IslandLevel {
  scale: number;
  w: number;
  h: number;
  textures: Record<ScratchRole, GPUTexture>;
  bindGroup: GPUBindGroup;
  /** Byte offset of this level's [w, h] in the params buffer. */
  paramsOffset: number;
  bytes: number;
}

export type PassProfiler = (label: string) => GPUComputePassTimestampWrites | undefined;

export class NodeScaleIslands {
  private env: IslandEnvironment | null = null;
  private levels = new Map<number, IslandLevel>();
  private refused = new Set<number>();
  private pipeline: GPUComputePipeline | null = null;
  private resampleLayout: GPUBindGroupLayout | null = null;
  private pipelineKey = '';
  private params: GPUBuffer | null = null;
  private resampleGroups = new WeakMap<GPUTexture, WeakMap<GPUTexture, GPUBindGroup>>();

  /** Bind to the renderer's current resources; drops scratch when anything changed. */
  attach(env: IslandEnvironment): void {
    const prev = this.env;
    if (
      prev &&
      prev.device === env.device &&
      prev.colorFormat === env.colorFormat &&
      prev.bindGroupLayout === env.bindGroupLayout &&
      prev.textures.readTex === env.textures.readTex &&
      prev.scaledW === env.scaledW &&
      prev.scaledH === env.scaledH
    ) {
      this.env = env;
      return;
    }
    this.releaseLevels();
    this.env = env;
  }

  /** Free every scratch level (e.g. when no node is demoted any more). */
  releaseLevels(): void {
    for (const level of this.levels.values()) {
      for (const tex of Object.values(level.textures)) tex.destroy();
    }
    this.levels.clear();
    this.refused.clear();
    this.params?.destroy();
    this.params = null;
    this.resampleGroups = new WeakMap();
  }

  destroy(): void {
    this.releaseLevels();
    this.pipeline = null;
    this.resampleLayout = null;
    this.pipelineKey = '';
    this.env = null;
  }

  /** Scales that currently hold scratch textures. */
  allocatedScales(): number[] {
    return Array.from(this.levels.keys()).sort();
  }

  scratchBytes(): number {
    let total = 0;
    for (const level of this.levels.values()) total += level.bytes;
    return total;
  }

  size(scale: number): [number, number] | null {
    const level = this.levels.get(scale);
    return level ? [level.w, level.h] : null;
  }

  bindGroup(scale: number): GPUBindGroup | null {
    return this.levels.get(scale)?.bindGroup ?? null;
  }

  /**
   * Resample inputs into the scale level and patch config.zw. Returns false
   * (nothing encoded) when the level cannot be prepared; the caller then runs
   * the node at full size.
   */
  encodeEnter(encoder: GPUCommandEncoder, scale: number, profile?: PassProfiler): boolean {
    const env = this.env;
    const level = env ? this.prepare(scale) : null;
    if (!env || !level || !this.params) return false;
    this.resample(encoder, env.textures.readTex, level.textures.read, level.w, level.h, 'island-down-read', profile);
    this.resample(encoder, env.textures.dataTexC, level.textures.dataC, level.w, level.h, 'island-down-dataC', profile);
    encoder.copyBufferToBuffer(this.params, level.paramsOffset, env.buffers.uniformBuf, CONFIG_ZW_OFFSET, 8);
    return true;
  }

  /** Resample the node's declared writes back to full size and restore config.zw. */
  encodeExit(encoder: GPUCommandEncoder, scale: number, writes: readonly IslandRole[], profile?: PassProfiler): void {
    const env = this.env;
    const level = this.levels.get(scale);
    if (!env || !level || !this.params) return;
    const full: Record<IslandRole, GPUTexture> = {
      color: env.textures.writeTex,
      dataA: env.textures.dataTexA,
      dataB: env.textures.dataTexB,
    };
    for (const role of writes) {
      this.resample(encoder, level.textures[role], full[role], env.scaledW, env.scaledH, `island-up-${role}`, profile);
    }
    encoder.copyBufferToBuffer(this.params, 0, env.buffers.uniformBuf, CONFIG_ZW_OFFSET, 8);
  }

  private ensurePipeline(env: IslandEnvironment): boolean {
    const key = env.colorFormat;
    if (this.pipeline && this.pipelineKey === key) return true;
    try {
      const layout = env.device.createBindGroupLayout({
        label: 'islandResampleBGL',
        entries: [
          { binding: 0, visibility: GPUShaderStage.COMPUTE, texture: { sampleType: 'unfilterable-float' } },
          {
            binding: 1,
            visibility: GPUShaderStage.COMPUTE,
            storageTexture: { access: 'write-only', format: env.colorFormat },
          },
        ],
      });
      const module = env.device.createShaderModule({
        label: 'islandResample',
        code: rewriteWgslStorageFormats(RESAMPLE_WGSL, env.colorFormat),
      });
      this.pipeline = env.device.createComputePipeline({
        label: 'islandResample',
        layout: env.device.createPipelineLayout({ bindGroupLayouts: [layout] }),
        compute: { module, entryPoint: 'main' },
      });
      this.resampleLayout = layout;
      this.pipelineKey = key;
      this.resampleGroups = new WeakMap();
      return true;
    } catch (e) {
      console.warn('[WebGPU] island resample pipeline failed:', e);
      this.pipeline = null;
      return false;
    }
  }

  private ensureParams(env: IslandEnvironment): GPUBuffer {
    if (!this.params) {
      this.params = env.device.createBuffer({
        label: 'islandParams',
        size: 8 * (NODE_SCALE_LEVELS.length + 1),
        usage: GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST,
      });
      env.device.queue.writeBuffer(this.params, 0, new Float32Array([env.scaledW, env.scaledH]));
    }
    return this.params;
  }

  private prepare(scale: number): IslandLevel | null {
    const env = this.env;
    if (!env || scale >= 1 || this.refused.has(scale)) return null;
    const existing = this.levels.get(scale);
    if (existing) return existing;
    if (!this.ensurePipeline(env)) return null;

    const [w, h] = scaledIslandSize(env.scaledW, env.scaledH, scale);
    const bytes = SCRATCH_ROLES.length * w * h * bytesPerTexel(env.colorFormat);
    if (this.scratchBytes() + bytes > ISLAND_SCRATCH_BUDGET_BYTES) {
      console.warn(`[WebGPU] node scale ${scale}: scratch ${(bytes / 2 ** 20).toFixed(0)} MiB over budget — running full size`);
      this.refused.add(scale);
      return null;
    }

    const usage =
      GPUTextureUsage.TEXTURE_BINDING |
      GPUTextureUsage.STORAGE_BINDING |
      GPUTextureUsage.COPY_SRC |
      GPUTextureUsage.COPY_DST;
    const textures = {} as Record<ScratchRole, GPUTexture>;
    for (const role of SCRATCH_ROLES) {
      textures[role] = env.device.createTexture({
        label: `island-${scale}-${role}`,
        size: [w, h],
        format: env.colorFormat,
        usage,
      });
    }
    const bindGroup = createComputeBindGroupForRoles(
      env.device,
      env.bindGroupLayout,
      { read: textures.read, color: textures.color, dataA: textures.dataA, dataB: textures.dataB, dataC: textures.dataC },
      env.textures,
      env.buffers,
      env.samplers,
    );
    const levelIndex = (NODE_SCALE_LEVELS as readonly number[]).indexOf(scale);
    const paramsOffset = 8 * (levelIndex + 1);
    env.device.queue.writeBuffer(this.ensureParams(env), paramsOffset, new Float32Array([w, h]));
    const level: IslandLevel = { scale, w, h, textures, bindGroup, paramsOffset, bytes };
    this.levels.set(scale, level);
    return level;
  }

  private resample(
    encoder: GPUCommandEncoder,
    src: GPUTexture,
    dst: GPUTexture,
    w: number,
    h: number,
    label: string,
    profile?: PassProfiler,
  ): void {
    const env = this.env;
    if (!env || !this.pipeline || !this.resampleLayout) return;
    let byDst = this.resampleGroups.get(src);
    if (!byDst) {
      byDst = new WeakMap();
      this.resampleGroups.set(src, byDst);
    }
    let group = byDst.get(dst);
    if (!group) {
      group = env.device.createBindGroup({
        label: `${label}-bg`,
        layout: this.resampleLayout,
        entries: [
          { binding: 0, resource: src.createView() },
          { binding: 1, resource: dst.createView() },
        ],
      });
      byDst.set(dst, group);
    }
    const timestampWrites = profile?.(label);
    const pass = encoder.beginComputePass(timestampWrites ? { label, timestampWrites } : { label });
    pass.setPipeline(this.pipeline);
    pass.setBindGroup(0, group);
    pass.dispatchWorkgroups(Math.ceil(w / 8), Math.ceil(h / 8), 1);
    pass.end();
  }
}
