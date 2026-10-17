/**
 * One bounded LRU for every cached compute pipeline (#1449 2c): user-selected
 * and warm-up pipelines alike, keyed by a source hash, never evicting a
 * pipeline that a slot is bound to.
 */

import { PIPELINE_CACHE_LIMIT, PipelineLru } from './pipelineCache';
import { WebGPUPipelineModule } from './pipeline';
import { ShaderWarmupQueue } from './shaderWarmup';
import { pipelineCacheKey } from '../wgslFormatRewrite';
import { fnv1a32, hashWgslSource } from '../wgslHash';
import { WebGPURenderer } from '../WebGPURenderer';
import { DEFAULT_CONFIG } from '../Renderer';

const g = globalThis as Record<string, unknown>;
if (!g.GPUShaderStage) g.GPUShaderStage = { COMPUTE: 4 };

const HEADER = /* wgsl */ `
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};
`;

const shaderSource = (n: number) => `${HEADER}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  textureStore(writeTexture, gid.xy, vec4<f32>(${n}.0));
}
`;

function makeDevice() {
  const device = {
    limits: { maxStorageBuffersPerShaderStage: 8, maxUniformBuffersPerShaderStage: 12, maxBindGroups: 4 },
    createBindGroupLayout: jest.fn(() => ({})),
    createPipelineLayout: jest.fn(() => ({})),
    createShaderModule: jest.fn(() => ({})),
    createComputePipeline: jest.fn(() => ({})),
    pushErrorScope: jest.fn(),
    popErrorScope: jest.fn(async () => null),
  };
  return device as unknown as GPUDevice;
}

beforeEach(() => {
  jest.spyOn(console, 'warn').mockImplementation(() => undefined);
  jest.spyOn(console, 'log').mockImplementation(() => undefined);
});
afterEach(() => jest.restoreAllMocks());

describe('PipelineLru', () => {
  it('evicts oldest first and skips protected ids', () => {
    const lru = new PipelineLru();
    ['a', 'b', 'c', 'd'].forEach((id) => lru.touch(id));
    lru.touch('a'); // a is now the most recent
    expect(lru.overflow(2, new Set(['b']))).toEqual(['c', 'd']);
    expect(lru.overflow(4, new Set())).toEqual([]);
  });

  it('may stay above the limit when everything left is protected', () => {
    const lru = new PipelineLru();
    ['a', 'b', 'c'].forEach((id) => lru.touch(id));
    expect(lru.overflow(1, new Set(['a', 'b', 'c']))).toEqual([]);
  });
});

describe('pipeline cache key', () => {
  it('is a short hash, not the WGSL source', () => {
    const big = shaderSource(1).repeat(50);
    const key = pipelineCacheKey(big, 'rgba32float');
    expect(key.length).toBeLessThan(48);
    expect(key).not.toContain('textureStore');
    expect(key).toBe(pipelineCacheKey(big, 'rgba32float'));
  });

  it('changes with the source and with the colour format', () => {
    expect(pipelineCacheKey(shaderSource(1), 'rgba32float')).not.toBe(pipelineCacheKey(shaderSource(2), 'rgba32float'));
    expect(pipelineCacheKey(shaderSource(1), 'rgba32float')).not.toBe(pipelineCacheKey(shaderSource(1), 'rgba16float'));
  });

  it('matches the FNV-1a 32-bit reference vectors', () => {
    expect(fnv1a32('')).toBe(0x811c9dc5);
    expect(fnv1a32('a')).toBe(0xe40c292c);
    expect(fnv1a32('foobar')).toBe(0xbf9cf968);
    expect(hashWgslSource('abc')).toHaveLength(16);
  });
});

describe('WebGPUShaderManager pipeline cache', () => {
  it('holds at most the limit after compiling 50 distinct shaders', async () => {
    const device = makeDevice();
    const mod = new WebGPUPipelineModule();
    mod.setupComputeLayout(device, true);
    const manager = mod.shaderManager;

    for (let i = 0; i < 50; i++) {
      expect(await manager.compile(device, mod.pipelineLayout, `shader-${i}`, shaderSource(i))).toBe(true);
    }

    const stats = manager.getCacheStats();
    expect(PIPELINE_CACHE_LIMIT).toBe(32);
    expect(stats.cachedCount).toBeLessThanOrEqual(PIPELINE_CACHE_LIMIT);
    // The most recent ones survive, the oldest are gone.
    expect(manager.hasPipeline('shader-49')).toBe(true);
    expect(manager.hasPipeline('shader-0')).toBe(false);
  });

  it('never evicts slot-bound pipelines, however old', async () => {
    const device = makeDevice();
    const mod = new WebGPUPipelineModule();
    mod.setupComputeLayout(device, true);
    const manager = mod.shaderManager;
    const bound = new Set(['shader-0', 'shader-1', 'shader-2']);
    manager.setBoundIdsProvider(() => bound);

    for (let i = 0; i < 50; i++) {
      await manager.compile(device, mod.pipelineLayout, `shader-${i}`, shaderSource(i));
    }

    expect(manager.getCacheStats().cachedCount).toBeLessThanOrEqual(PIPELINE_CACHE_LIMIT);
    bound.forEach((id) => expect(manager.hasPipeline(id)).toBe(true));
    expect(manager.hasPipeline('shader-3')).toBe(false);
  });

  it('treats a pipeline used by the frame loop as recently used', async () => {
    const device = makeDevice();
    const mod = new WebGPUPipelineModule();
    mod.setupComputeLayout(device, true);
    const manager = mod.shaderManager;
    manager.setCacheLimit(3);

    for (let i = 0; i < 3; i++) {
      await manager.compile(device, mod.pipelineLayout, `shader-${i}`, shaderSource(i));
    }
    manager.getPipeline('shader-0'); // rendered until just now
    await manager.compile(device, mod.pipelineLayout, 'shader-3', shaderSource(3));

    expect(manager.hasPipeline('shader-0')).toBe(true);
    expect(manager.hasPipeline('shader-1')).toBe(false);
  });

  it('recompiles an evicted shader and skips an unchanged cached one', async () => {
    const device = makeDevice();
    const mod = new WebGPUPipelineModule();
    mod.setupComputeLayout(device, true);
    const manager = mod.shaderManager;
    manager.setCacheLimit(1);
    const create = device.createComputePipeline as jest.Mock;

    await manager.compile(device, mod.pipelineLayout, 'a', shaderSource(1));
    await manager.compile(device, mod.pipelineLayout, 'a', shaderSource(1));
    expect(create).toHaveBeenCalledTimes(1);

    await manager.compile(device, mod.pipelineLayout, 'b', shaderSource(2));
    expect(manager.hasPipeline('a')).toBe(false);
    await manager.compile(device, mod.pipelineLayout, 'a', shaderSource(1));
    expect(create).toHaveBeenCalledTimes(3);

    // Changed source under the same id recompiles even while cached.
    await manager.compile(device, mod.pipelineLayout, 'a', shaderSource(9));
    expect(create).toHaveBeenCalledTimes(4);
  });

  it('keeps warm-up working: warmed pipelines are bounded by the same LRU', async () => {
    const device = makeDevice();
    const mod = new WebGPUPipelineModule();
    mod.setupComputeLayout(device, true);
    const manager = mod.shaderManager;
    manager.setCacheLimit(4);
    const queue = new ShaderWarmupQueue(
      {
        load: (e) => manager.compile(device, mod.pipelineLayout, e.id, shaderSource(Number(e.id.slice(1)))),
        isCached: (id) => manager.hasPipeline(id),
        boundIds: () => new Set(),
        evict: (id) => manager.evict(id),
      },
      { concurrency: 1, schedule: (job) => job() },
    );

    const ids = Array.from({ length: 10 }, (_, i) => `w${i}`);
    queue.request(ids.map((id) => ({ id, url: `shaders/${id}.wgsl` })));
    for (let i = 0; i < 40 && queue.pending > 0; i++) await new Promise((r) => setTimeout(r, 0));

    expect(manager.getCacheStats().cachedCount).toBeLessThanOrEqual(4);
    expect(manager.hasPipeline('w9')).toBe(true);
    expect(queue.warmedIds().every((id) => manager.hasPipeline(id))).toBe(true);
  });
});

describe('WebGPURenderer wiring', () => {
  it('protects the shaders bound to its slots', async () => {
    const wgpu = new WebGPURenderer(DEFAULT_CONFIG);
    const manager = wgpu.pipeline.shaderManager;
    const [slot] = (wgpu as unknown as { slots: Array<{ shaderId: string | null }> }).slots;
    if (slot) slot.shaderId = 'shader-0';
    const device = makeDevice();
    wgpu.pipeline.setupComputeLayout(device, true);
    manager.setCacheLimit(2);

    for (let i = 0; i < 5; i++) {
      await manager.compile(device, wgpu.pipeline.pipelineLayout, `shader-${i}`, shaderSource(i));
    }

    expect(manager.hasPipeline('shader-0')).toBe(true);
    expect(manager.getCacheStats().cachedCount).toBeLessThanOrEqual(2);
  });
});
