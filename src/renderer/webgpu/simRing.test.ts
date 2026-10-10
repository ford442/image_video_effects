/**
 * Opt-in @group(1) sim ring (src/contracts/bind_group1.json).
 *
 * - Non-group-1 shaders still compile against the single-layout pipeline.
 * - Group-1 shaders get [group0, group1] and are refused when the contract or
 *   device limits are not met.
 * - The OOM ladder (65536 → 32768 → 16384 → 4096) persists px_simring_oom_cap.
 * - GraphRunner dispatches simState workgroups and encodes the
 *   simState → simIndex buffer barrier.
 */

import * as fs from 'fs';
import * as path from 'path';
import bindGroup1Contract from '../../contracts/bind_group1.json';
import webgpuLimitsContract from '../../contracts/webgpu_limits.json';
import { GraphRunner, GraphRunnerContext, GraphSimRingBindings } from '../GraphRunner';
import {
  expandGraph,
  graphUsesSimRing,
  MultipassGraphDef,
  validateGraph,
} from '../multipassGraph';
import { GRAPH_REGISTRY, resolveSimRingRequest } from '../multipassRegistry';
import { validateBindGroup } from '../bindGroupValidator';
import { expandShaderSource } from '../../test-utils/shaderSource';
import { WebGPUPipelineModule } from './pipeline';
import {
  allocateSimRing,
  checkSimRingLimits,
  declaresBindGroup1,
  nextSimRingRung,
  readSimRingOomCap,
  SIM_RING_OOM_CAP_KEY,
  SIM_RING_OOM_LADDER,
  SimRing,
  simRingRungsForRequest,
  validateGroup1Declarations,
} from './simRing';

const g = globalThis as Record<string, unknown>;
if (!g.GPUShaderStage) g.GPUShaderStage = { COMPUTE: 4 };
if (!g.GPUBufferUsage) {
  g.GPUBufferUsage = { UNIFORM: 64, COPY_DST: 8, COPY_SRC: 4, STORAGE: 128 };
}

function at<T>(a: readonly T[], i: number): T {
  const v = a[i];
  if (v === undefined) throw new Error(`missing index ${i}`);
  return v;
}

const SHADERS = path.join(__dirname, '../../../public/shaders');
const readShader = (name: string) => fs.readFileSync(path.join(SHADERS, name), 'utf8');

const GROUP0 = /* wgsl */ `
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

const PLAIN_WGSL = `${GROUP0}
// @group(1) mentioned in a comment only — must not opt in.
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  textureStore(writeTexture, gid.xy, vec4<f32>(0.0));
}
`;

const SIM_WGSL = `${GROUP0}
struct SimParams { stateCount: u32, indexCount: u32, frame: u32, truncated: u32, };
@group(1) @binding(0) var<storage, read_write> simState: array<vec4<f32>>;
@group(1) @binding(1) var<storage, read> simIndex: array<u32>;
@group(1) @binding(2) var<uniform> simParams: SimParams;
@compute @workgroup_size(64, 1, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  if (gid.x >= simParams.stateCount) { return; }
  simState[gid.x] = simState[gid.x] + vec4<f32>(f32(simIndex[gid.x * 4u]));
}
`;

const BASE_LIMITS = {
  maxStorageBuffersPerShaderStage: 8,
  maxUniformBuffersPerShaderStage: 12,
  maxBindGroups: 4,
};

function makeDevice(opts: {
  limits?: Partial<typeof BASE_LIMITS>;
  /** Buffers at or above this byte size report OOM through the error scope. */
  oomAtBytes?: number;
} = {}) {
  let scopeOom = false;
  const pipelineLayouts: GPUBindGroupLayout[][] = [];
  const created: { size: number; label?: string; destroyed: boolean }[] = [];
  const params: number[][] = [];
  const device = {
    limits: { ...BASE_LIMITS, ...opts.limits },
    createBindGroupLayout: jest.fn((d: GPUBindGroupLayoutDescriptor) => ({ label: d.label })),
    createPipelineLayout: jest.fn((d: GPUPipelineLayoutDescriptor) => {
      const groups = Array.from(d.bindGroupLayouts) as GPUBindGroupLayout[];
      pipelineLayouts.push(groups);
      return { label: d.label, groups: groups.length };
    }),
    createShaderModule: jest.fn(() => ({})),
    createComputePipeline: jest.fn((d: GPUComputePipelineDescriptor) => ({ layout: d.layout })),
    createBindGroup: jest.fn((d: GPUBindGroupDescriptor) => ({ label: d.label })),
    createBuffer: jest.fn((d: GPUBufferDescriptor) => {
      if (opts.oomAtBytes !== undefined && d.size >= opts.oomAtBytes) scopeOom = true;
      const rec = { size: d.size, label: d.label, destroyed: false };
      created.push(rec);
      return { size: d.size, label: d.label, destroy: () => { rec.destroyed = true; } };
    }),
    pushErrorScope: jest.fn(() => { scopeOom = false; }),
    popErrorScope: jest.fn(async () => {
      const err = scopeOom ? ({ name: 'GPUOutOfMemoryError', message: 'out of memory' } as GPUError) : null;
      scopeOom = false;
      return err;
    }),
    // Real writeBuffer copies synchronously; snapshot so reuse of the params array is visible.
    queue: {
      writeBuffer: jest.fn((_b: GPUBuffer, _o: number, data: Uint32Array) => {
        params.push(Array.from(data));
      }),
    },
  };
  return { device: device as unknown as GPUDevice, raw: device, pipelineLayouts, created, params };
}

beforeEach(() => {
  sessionStorage.clear();
  jest.spyOn(console, 'warn').mockImplementation(() => {});
  jest.spyOn(console, 'log').mockImplementation(() => {});
});

afterEach(() => {
  jest.restoreAllMocks();
});

describe('bind_group1.json contract', () => {
  it('keeps group-1 limits within WebGPU base limits and out of the catalog-wide contract', () => {
    for (const [k, v] of Object.entries(bindGroup1Contract.group1RequiredLimits)) {
      expect(v).toBeLessThanOrEqual(
        bindGroup1Contract.webgpuBaseLimits[k as keyof typeof bindGroup1Contract.webgpuBaseLimits],
      );
    }
    expect(webgpuLimitsContract.minimumComputeLimits.maxStorageBuffersPerShaderStage).toBe(2);
    expect('maxBindGroups' in webgpuLimitsContract.minimumComputeLimits).toBe(false);
  });

  it('detects opt-in declarations and ignores comments', () => {
    expect(declaresBindGroup1(PLAIN_WGSL)).toBe(false);
    expect(declaresBindGroup1(SIM_WGSL)).toBe(true);
    expect(validateGroup1Declarations(SIM_WGSL)).toEqual([]);
  });

  it('rejects declarations that disagree with the contract', () => {
    const wrongType = SIM_WGSL.replace(
      'var<storage, read> simIndex: array<u32>',
      'var<storage, read_write> simIndex: array<u32>',
    );
    expect(validateGroup1Declarations(wrongType).join()).toMatch(/binding\(1\)/);
    const extra = `${SIM_WGSL}\n@group(1) @binding(3) var<storage, read> more: array<u32>;`;
    expect(validateGroup1Declarations(extra).join()).toMatch(/outside the sim-ring contract/);
    expect(validateBindGroup('bad', extra).valid).toBe(false);
  });

  it('accepts the DLA flagship shaders', async () => {
    for (const file of ['dla-walkers.wgsl', 'dla-render.wgsl']) {
      // Validate what the runtime compiles: the group-0 header may come from _prelude.wgsl.
      const wgsl = await expandShaderSource(readShader(file), file);
      expect(declaresBindGroup1(wgsl)).toBe(true);
      expect(validateGroup1Declarations(wgsl)).toEqual([]);
      expect(validateBindGroup(file, wgsl).valid).toBe(true);
    }
    expect(readShader('dla-walkers.wgsl')).toMatch(/@workgroup_size\(64, 1, 1\)/);
    expect(readShader('dla-walkers.wgsl')).not.toMatch(/extraBuffer\[/);
  });

  it('checks group-1 limits against the device, not requiredLimits', () => {
    expect(checkSimRingLimits(BASE_LIMITS).ok).toBe(true);
    const low = checkSimRingLimits({ ...BASE_LIMITS, maxBindGroups: 1 });
    expect(low.ok).toBe(false);
    expect(low.failures.join()).toMatch(/maxBindGroups/);
  });
});

describe('pipeline layout selection', () => {
  it('compiles a non-group-1 shader against the single-layout pipeline', async () => {
    const { device, raw, pipelineLayouts } = makeDevice();
    const mod = new WebGPUPipelineModule();
    mod.setupComputeLayout(device, true);

    expect(await mod.shaderManager.compile(device, mod.pipelineLayout, 'plain', PLAIN_WGSL)).toBe(true);

    const desc = at(raw.createComputePipeline.mock.calls, 0)[0] as GPUComputePipelineDescriptor;
    expect(desc.layout).toBe(mod.pipelineLayout);
    expect(pipelineLayouts).toHaveLength(1);
    expect(pipelineLayouts[0]).toHaveLength(1);
    expect(mod.shaderManager.usesSimRing('plain')).toBe(false);
    // The sim-ring layout is never built for sessions without group-1 shaders.
    expect(mod.simRingBindGroupLayout).toBeNull();
  });

  it('compiles a group-1 shader against [group0, group1]', async () => {
    const { device, raw, pipelineLayouts } = makeDevice();
    const mod = new WebGPUPipelineModule();
    mod.setupComputeLayout(device, true);

    expect(await mod.shaderManager.compile(device, mod.pipelineLayout, 'sim', SIM_WGSL)).toBe(true);
    expect(await mod.shaderManager.compile(device, mod.pipelineLayout, 'plain', PLAIN_WGSL)).toBe(true);

    const descs = raw.createComputePipeline.mock.calls.map(
      (c) => c[0] as GPUComputePipelineDescriptor,
    );
    const simDesc = at(descs, 0);
    const plainDesc = at(descs, 1);
    expect(simDesc.layout).not.toBe(mod.pipelineLayout);
    expect(pipelineLayouts[1]).toEqual([mod.bindGroupLayout, mod.simRingBindGroupLayout]);
    expect(plainDesc.layout).toBe(mod.pipelineLayout);
    expect(mod.shaderManager.usesSimRing('sim')).toBe(true);
    expect(mod.shaderManager.usesSimRing('plain')).toBe(false);

    const simBgl = raw.createBindGroupLayout.mock.calls
      .map((c) => c[0] as GPUBindGroupLayoutDescriptor)
      .find((d) => d.label === 'simRingBGL')!;
    expect(Array.from(simBgl.entries).map((e) => [e.binding, e.buffer?.type])).toEqual(
      bindGroup1Contract.bindings.map((b) => [b.binding, b.bufferType]),
    );
  });

  it('refuses a group-1 shader when the device lacks group-1 limits', async () => {
    const { device, raw } = makeDevice({ limits: { maxBindGroups: 1 } });
    const mod = new WebGPUPipelineModule();
    mod.setupComputeLayout(device, true);

    expect(await mod.shaderManager.compile(device, mod.pipelineLayout, 'sim', SIM_WGSL)).toBe(false);
    expect(mod.shaderManager.hasPipeline('sim')).toBe(false);
    expect(await mod.shaderManager.compile(device, mod.pipelineLayout, 'plain', PLAIN_WGSL)).toBe(true);
    expect(raw.createComputePipeline).toHaveBeenCalledTimes(1);
  });
});

describe('sim ring OOM ladder', () => {
  it('walks 65536 → 32768 → 16384 and persists the session cap', async () => {
    // 16384 × 16 B = 256 KiB fits; 32768 × 16 B = 512 KiB OOMs.
    const { device } = makeDevice({ oomAtBytes: 32768 * 16 });
    const alloc = await allocateSimRing(device, 65536);
    expect(alloc?.stateCount).toBe(16384);
    expect(alloc?.requested).toBe(65536);
    expect(sessionStorage.getItem(SIM_RING_OOM_CAP_KEY)).toBe('16384');
    expect(readSimRingOomCap()).toBe(16384);
    // A reload never retries a rung that already OOMed.
    expect(simRingRungsForRequest(65536)).toEqual([16384, 4096]);
  });

  it('returns null below the bottom rung and caps at 4096', async () => {
    const { device, created } = makeDevice({ oomAtBytes: 1 });
    expect(await allocateSimRing(device)).toBeNull();
    expect(sessionStorage.getItem(SIM_RING_OOM_CAP_KEY)).toBe('4096');
    expect(created.every((b) => b.destroyed)).toBe(true);
  });

  it('matches the contract ladder', () => {
    expect(SIM_RING_OOM_LADDER).toEqual([65536, 32768, 16384, 4096]);
    expect(nextSimRingRung(65536)).toBe(32768);
    expect(nextSimRingRung(4096)).toBeNull();
    expect(simRingRungsForRequest(100, null)).toEqual([4096]);
    expect(simRingRungsForRequest(20000, null)).toEqual([16384, 4096]);
  });

  it('defaults to ~2 MiB (state + snapshot) and writes simParams', async () => {
    const { device, created, params } = makeDevice();
    const ring = new SimRing();
    expect(await ring.ensure(device, {} as GPUBindGroupLayout)).toBe(true);
    expect(ring.stateCount).toBe(65536);
    const storageBytes = created
      .filter((b) => b.label === 'simState' || b.label === 'simIndex')
      .reduce((s, b) => s + b.size, 0);
    expect(storageBytes).toBe(2 * 1024 * 1024);

    ring.writeParams(device.queue);
    ring.writeParams(device.queue);
    expect(params[0]).toEqual([65536, 65536 * 4, 0, 0]);
    expect(at(params, 1)[2]).toBe(1);
    ring.resetFrame();
    ring.writeParams(device.queue);
    expect(at(params, 2)[2]).toBe(0);
  });

  it('reallocates on a new device instead of reusing lost-device buffers', async () => {
    const a = makeDevice();
    const b = makeDevice();
    const ring = new SimRing();
    await ring.ensure(a.device, {} as GPUBindGroupLayout);
    const first = ring.stateBuffer;
    await ring.ensure(a.device, {} as GPUBindGroupLayout);
    expect(ring.stateBuffer).toBe(first);
    await ring.ensure(b.device, {} as GPUBindGroupLayout);
    expect(ring.stateBuffer).not.toBe(first);
    expect(b.raw.createBuffer).toHaveBeenCalled();
  });

  it('flags truncation after an OOM step-down', async () => {
    const { device, params } = makeDevice({ oomAtBytes: 65536 * 16 });
    const ring = new SimRing();
    await ring.ensure(device, {} as GPUBindGroupLayout, 65536);
    expect(ring.stateCount).toBe(32768);
    expect(ring.truncated).toBe(true);
    ring.writeParams(device.queue);
    expect(at(params, 0)[3]).toBe(1);
  });
});

function makeEncoder() {
  const log: string[] = [];
  const dispatches: { label: string; xyz: number[]; groups: number[] }[] = [];
  const encoder = {
    copyTextureToTexture: () => log.push('copy:tex'),
    copyBufferToBuffer: (_s: GPUBuffer, _so: number, _d: GPUBuffer, _do: number, size: number) =>
      log.push(`copy:buf:${size}`),
    beginComputePass: (desc: GPUComputePassDescriptor) => {
      const rec = { label: desc.label ?? '', xyz: [] as number[], groups: [] as number[] };
      return {
        setPipeline: () => {},
        setBindGroup: (i: number) => rec.groups.push(i),
        dispatchWorkgroups: (x: number, y = 1, z = 1) => { rec.xyz = [x, y, z]; },
        end: () => { dispatches.push(rec); log.push(`pass:${rec.label}`); },
      };
    },
  } as unknown as GPUCommandEncoder;
  return { encoder, log, dispatches };
}

function ringBindings(stateCount: number): GraphSimRingBindings {
  return {
    bindGroup: { label: 'simRingBG' } as unknown as GPUBindGroup,
    stateBuffer: {} as GPUBuffer,
    indexBuffer: {} as GPUBuffer,
    stateCount,
    byteSize: stateCount * 16,
  };
}

function graphCtx(over: Partial<GraphRunnerContext>): GraphRunnerContext {
  return {
    device: {} as GPUDevice,
    pipelineLayout: {} as GPUPipelineLayout,
    getPipeline: () => ({} as GPUComputePipeline),
    getWorkgroupSize: (id) => (id === 'dla-walkers' ? { x: 64, y: 1 } : { x: 16, y: 16 }),
    createBindGroupForRoles: () => ({} as GPUBindGroup),
    textures: {
      read: {} as GPUTexture,
      color: {} as GPUTexture,
      dataA: {} as GPUTexture,
      dataB: {} as GPUTexture,
      dataC: {} as GPUTexture,
    },
    scaledW: 1024,
    scaledH: 1024,
    maxPassesPerFrame: 8,
    usesSimRing: (id) => id === 'dla-walkers' || id === 'dla-render',
    ...over,
  };
}

describe('dla-crystals flagship graph', () => {
  const registered = GRAPH_REGISTRY['dla-crystals'];
  if (!registered) throw new Error('dla-crystals missing from GRAPH_REGISTRY');
  const graph = registered;

  it('is a valid simState-dispatch graph with a sim-ring request', () => {
    expect(validateGraph(graph)).toEqual([]);
    expect(graphUsesSimRing(graph)).toBe(true);
    expect(expandGraph(graph).map((d) => [d.entry, d.dispatch])).toEqual([
      ['dla-walkers', 'simState'],
      ['dla-render', 'pixels'],
    ]);
    expect(resolveSimRingRequest('dla-crystals')).toBe(65536);
    expect(resolveSimRingRequest('dla-walkers')).toBe(65536);
  });

  it('dispatches simState workgroups and binds group 1', () => {
    const { encoder, log, dispatches } = makeEncoder();
    const report = new GraphRunner().runGraph(
      encoder,
      graph,
      graphCtx({ simRing: ringBindings(65536), shaderId: 'dla-crystals' }),
    );
    expect(report.executed).toBe(2);
    expect(at(dispatches, 0).xyz).toEqual([65536 / 64, 1, 1]);
    expect(at(dispatches, 0).groups).toEqual([0, 1]);
    expect(at(dispatches, 1).xyz).toEqual([1024 / 16, 1024 / 16, 1]);
    // dataA (walker freezes) → dataC before the render pass reads it.
    expect(log).toEqual(['pass:graph-walkers-0-dla-walkers', 'copy:tex', 'pass:graph-render-0-dla-render']);
  });

  it('survives the OOM ladder: dispatch shrinks with the allocated ring', async () => {
    const { device } = makeDevice({ oomAtBytes: 32768 * 16 });
    const ring = new SimRing();
    await ring.ensure(device, {} as GPUBindGroupLayout, resolveSimRingRequest('dla-crystals'));
    expect(ring.stateCount).toBe(16384);

    const { encoder, dispatches } = makeEncoder();
    new GraphRunner().runGraph(
      encoder,
      graph,
      graphCtx({
        simRing: {
          bindGroup: ring.getBindGroup()!,
          stateBuffer: ring.stateBuffer!,
          indexBuffer: ring.indexBuffer!,
          stateCount: ring.stateCount,
          byteSize: ring.byteSize,
        },
      }),
    );
    expect(at(dispatches, 0).xyz).toEqual([16384 / 64, 1, 1]);
  });

  it('skips sim passes (logged) when no ring is armed', () => {
    const { encoder, dispatches } = makeEncoder();
    const report = new GraphRunner().runGraph(encoder, graph, graphCtx({ simRing: null }));
    expect(report.executed).toBe(0);
    expect(dispatches).toHaveLength(0);
    expect(console.warn).toHaveBeenCalledWith(expect.stringMatching(/needs the sim ring/));
  });
});

describe('simState → simIndex barrier', () => {
  const graph: MultipassGraphDef = {
    maxPassesPerFrame: 8,
    nodes: [
      { id: 'move', entry: 'move', dispatch: 'simState', reads: ['simIndex'], writes: ['simState'], repeat: 2 },
      { id: 'splat', entry: 'splat', reads: ['simIndex'], writes: ['color'] },
    ],
  };

  it('snapshots before each reader that follows a simState write', () => {
    expect(validateGraph(graph)).toEqual([]);
    const { encoder, log } = makeEncoder();
    new GraphRunner().runGraph(
      encoder,
      graph,
      graphCtx({ simRing: ringBindings(4096), usesSimRing: () => true }),
    );
    expect(log).toEqual([
      'copy:buf:65536', 'pass:graph-move-0-move',
      'copy:buf:65536', 'pass:graph-move-1-move',
      'copy:buf:65536', 'pass:graph-splat-0-splat',
    ]);
  });

  it('rejects writes to simIndex and unknown dispatch domains', () => {
    const bad: MultipassGraphDef = {
      maxPassesPerFrame: 4,
      nodes: [
        { id: 'x', entry: 'x', reads: [], writes: ['simIndex'] },
        { id: 'y', entry: 'y', reads: ['dataC'], writes: ['color'], dispatch: 'voxels' as never },
      ],
    };
    const errors = validateGraph(bad).join('\n');
    expect(errors).toMatch(/simIndex is read-only/);
    expect(errors).toMatch(/invalid dispatch "voxels"/);
  });

  it('leaves texture-only graphs on the single-layout path', () => {
    const plain: MultipassGraphDef = {
      maxPassesPerFrame: 2,
      nodes: [{ id: 'r', entry: 'r', reads: ['dataC'], writes: ['color', 'dataA'] }],
    };
    expect(graphUsesSimRing(plain)).toBe(false);
    const { encoder, dispatches } = makeEncoder();
    new GraphRunner().runGraph(encoder, plain, graphCtx({ usesSimRing: () => false }));
    expect(at(dispatches, 0).groups).toEqual([0]);
  });
});
