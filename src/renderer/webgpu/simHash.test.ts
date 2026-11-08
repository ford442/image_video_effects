/**
 * Optional spatial hash of the @group(1) sim ring (bind_group1.json `spatialHash`).
 *
 * - Shaders that declare binding 3 get a second, 4-binding layout; everything
 *   else keeps today's three bindings (DLA never allocates the hash).
 * - The planner inserts the head reset + scatter pass once, before the first
 *   reader, as a counted pass; it never inserts it for a graph that does not
 *   read simHash.
 * - The hash is part of each OOM-ladder rung, so a step-down rebuilds it smaller.
 */

import bindGroup1Contract from '../../contracts/bind_group1.json';
import { expandShaderSource, readExpandedShader } from '../../test-utils/shaderSource';
import { GRAPH_REGISTRY, resolveSimHashRequest, resolveSimRingRequest } from '../multipassRegistry';
import {
  capGraphDispatches,
  countGraphPasses,
  diagnoseGraph,
  expandGraph,
  graphUsesSimHash,
  graphUsesSimRing,
  MultipassGraphDef,
  SIM_HASH_BUILD_ENTRY,
  validateGraph,
} from '../multipassGraph';
import type { GraphSimRingBindings } from '../GraphRunner';
import { createFakeGpu, summarizeOps } from '../testing/fakeGpu';
import {
  compileFramePlan,
  ComputeOp,
  executeFramePlan,
  FramePlanContext,
  resetFramePlanWarnings,
} from './framePlan';
import { WebGPUPipelineModule } from './pipeline';
import {
  SIM_HASH_BINDING,
  SIM_HASH_CELL_COUNT,
  SIM_HASH_EMPTY,
  SIM_HASH_GRID,
  SIM_HASH_HEAD_BYTES,
  SIM_HASH_NEXT_OFFSET,
  simHashBufferBytes,
  simHashBuildWgsl,
} from './simHash';
import {
  checkSimRingLimits,
  declaresSimHash,
  SimRing,
  validateGroup1Declarations,
} from './simRing';
import { armSimRingFor } from './simRingArm';
import type { FrameSlotDispatchPlan, SlotDispatchPlan } from './slotDispatch';
import { validateBindGroup } from '../bindGroupValidator';

const g = globalThis as Record<string, unknown>;
if (!g.GPUShaderStage) g.GPUShaderStage = { COMPUTE: 4 };
if (!g.GPUBufferUsage) {
  g.GPUBufferUsage = { UNIFORM: 64, COPY_DST: 8, COPY_SRC: 4, STORAGE: 128 };
}

const BASE_LIMITS = {
  maxStorageBuffersPerShaderStage: 8,
  maxUniformBuffersPerShaderStage: 12,
  maxBindGroups: 4,
};

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

const HASH_WGSL = `${GROUP0}
struct SimParams { stateCount: u32, indexCount: u32, frame: u32, truncated: u32, };
@group(1) @binding(0) var<storage, read_write> simState: array<vec4<f32>>;
@group(1) @binding(1) var<storage, read> simIndex: array<u32>;
@group(1) @binding(2) var<uniform> simParams: SimParams;
@group(1) @binding(3) var<storage, read_write> simHash: array<atomic<u32>>;
@compute @workgroup_size(64, 1, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let head = atomicLoad(&simHash[gid.x % 16384u]);
  simState[gid.x] = vec4<f32>(f32(head));
}
`;

const RING_WGSL = HASH_WGSL.replace(/^@group\(1\) @binding\(3\).*\n/m, '');

function makeDevice(opts: { limits?: Partial<typeof BASE_LIMITS>; oomAtBytes?: number } = {}) {
  let scopeOom = false;
  const layouts: Array<{ label?: string; entries: GPUBindGroupLayoutEntry[] }> = [];
  const pipelineLayouts: GPUBindGroupLayout[][] = [];
  const created: Array<{ size: number; label?: string; destroyed: boolean }> = [];
  const bindGroups: Array<{ label?: string; entries: GPUBindGroupEntry[] }> = [];
  const writes: Array<{ label?: string; size: number }> = [];
  const device = {
    limits: { ...BASE_LIMITS, ...opts.limits },
    createBindGroupLayout: vi.fn((d: GPUBindGroupLayoutDescriptor) => {
      layouts.push({ label: d.label, entries: Array.from(d.entries) });
      return { label: d.label };
    }),
    createPipelineLayout: vi.fn((d: GPUPipelineLayoutDescriptor) => {
      const groups = Array.from(d.bindGroupLayouts) as GPUBindGroupLayout[];
      pipelineLayouts.push(groups);
      return { label: d.label, groups };
    }),
    createShaderModule: vi.fn(() => ({})),
    createComputePipeline: vi.fn((d: GPUComputePipelineDescriptor) => ({ layout: d.layout, label: d.label })),
    createBindGroup: vi.fn((d: GPUBindGroupDescriptor) => {
      bindGroups.push({ label: d.label, entries: Array.from(d.entries) });
      return { label: d.label };
    }),
    createBuffer: vi.fn((d: GPUBufferDescriptor) => {
      if (opts.oomAtBytes !== undefined && d.size >= opts.oomAtBytes) scopeOom = true;
      const rec = { size: d.size, label: d.label, destroyed: false };
      created.push(rec);
      return { size: d.size, label: d.label, destroy: () => { rec.destroyed = true; } };
    }),
    pushErrorScope: vi.fn(() => { scopeOom = false; }),
    popErrorScope: vi.fn(async () => {
      const err = scopeOom ? ({ name: 'GPUOutOfMemoryError', message: 'out of memory' } as GPUError) : null;
      scopeOom = false;
      return err;
    }),
    queue: {
      writeBuffer: vi.fn((b: GPUBuffer, _o: number, data: ArrayBufferView) => {
        writes.push({ label: (b as { label?: string }).label, size: data.byteLength });
      }),
    },
  };
  return { device: device as unknown as GPUDevice, raw: device, layouts, pipelineLayouts, created, bindGroups, writes };
}

beforeEach(() => {
  sessionStorage.clear();
  resetFramePlanWarnings();
  vi.spyOn(console, 'warn').mockImplementation(() => {});
  vi.spyOn(console, 'log').mockImplementation(() => {});
});

afterEach(() => {
  vi.restoreAllMocks();
});

const registered = (id: string): MultipassGraphDef => {
  const graph = GRAPH_REGISTRY[id];
  if (!graph) throw new Error(`${id} missing from GRAPH_REGISTRY`);
  return graph;
};

describe('spatialHash contract', () => {
  it('is a 128×128 grid, heads then one link per agent, and costs one more storage buffer', () => {
    const c = bindGroup1Contract;
    expect(c.version).toBe(2);
    expect(SIM_HASH_GRID).toBe(128);
    expect(SIM_HASH_CELL_COUNT).toBe(128 * 128);
    expect(SIM_HASH_NEXT_OFFSET).toBe(SIM_HASH_CELL_COUNT);
    expect(SIM_HASH_EMPTY).toBe(0xffffffff);
    expect(SIM_HASH_BINDING).toBe(3);
    expect(simHashBufferBytes(65536)).toBe((16384 + 65536) * 4);
    // simParams is untouched: grid width is a contract constant, not a uniform field.
    expect(c.bindings[2]!.sizeBytes).toBe(16);
    expect(c.bindings[2]!.fields).toEqual(['stateCount', 'indexCount', 'frame', 'truncated']);
    expect(c.bindings).toHaveLength(3);
    expect(c.spatialHash.group1RequiredLimits.maxStorageBuffersPerShaderStage).toBe(
      c.group1RequiredLimits.maxStorageBuffersPerShaderStage + 1,
    );
    expect(c.spatialHash.group1RequiredLimits.maxStorageBuffersPerShaderStage).toBeLessThanOrEqual(
      c.webgpuBaseLimits.maxStorageBuffersPerShaderStage,
    );
    expect(c.wasm.policy).toBe('refuse');
  });

  it('checks the hash limits against the device, not requiredLimits', () => {
    expect(checkSimRingLimits(BASE_LIMITS, true).ok).toBe(true);
    const four = { ...BASE_LIMITS, maxStorageBuffersPerShaderStage: 4 };
    expect(checkSimRingLimits(four).ok).toBe(true);
    const low = checkSimRingLimits(four, true);
    expect(low.ok).toBe(false);
    expect(low.failures.join()).toMatch(/maxStorageBuffersPerShaderStage: need >= 5/);
  });

  it('validates binding 3 and ignores it in comments', () => {
    expect(declaresSimHash(HASH_WGSL)).toBe(true);
    expect(declaresSimHash(RING_WGSL)).toBe(false);
    expect(declaresSimHash(`${RING_WGSL}\n// @group(1) @binding(3) var<storage, read_write> simHash: array<atomic<u32>>;`)).toBe(false);
    expect(validateGroup1Declarations(HASH_WGSL)).toEqual([]);
    const wrong = HASH_WGSL.replace('array<atomic<u32>>', 'array<u32>');
    expect(validateGroup1Declarations(wrong).join()).toMatch(/binding\(3\) must be `var<storage, read_write> simHash: array<atomic<u32>>`/);
    expect(validateGroup1Declarations(`${HASH_WGSL}\n@group(1) @binding(4) var<storage, read> x: array<u32>;`).join())
      .toMatch(/outside the sim-ring contract \(0–3\)/);
  });

  it('scatter shader hashes only agents inside the domain and links them through atomicExchange', () => {
    const wgsl = simHashBuildWgsl();
    expect(wgsl).toContain('atomicExchange(&simHash[');
    expect(wgsl).toContain(`const HASH_GRID: u32 = ${SIM_HASH_GRID}u;`);
    expect(wgsl).toContain(`const HASH_NEXT: u32 = ${SIM_HASH_NEXT_OFFSET}u;`);
    expect(wgsl).toMatch(/!\(p\.x >= 0\.0 && p\.y >= 0\.0 && p\.x < hp\.res\.x && p\.y < hp\.res\.y\)/);
  });
});

describe('flagship shaders', () => {
  it.each(['murmuration-flock', 'murmuration-render', 'photon-bins-march', 'photon-bins-splat', 'photon-bins-present'])(
    '%s compiles against the catalog bind-group contract with no pasted header',
    async (id) => {
      const raw = (await import('fs')).readFileSync(`public/shaders/${id}.wgsl`, 'utf8');
      expect(raw).toMatch(/#include "_prelude\.wgsl"/);
      expect(raw).not.toMatch(/@group\(0\) @binding\(0\)/);
      const wgsl = await expandShaderSource(raw, `${id}.wgsl`);
      expect(validateGroup1Declarations(wgsl)).toEqual([]);
      expect(validateBindGroup(id, wgsl).valid).toBe(true);
    },
  );

  it('only the shaders that read the hash declare binding 3', async () => {
    const declares = async (id: string) => declaresSimHash((await readExpandedShader(id))!);
    expect(await declares('murmuration-flock')).toBe(true);
    expect(await declares('photon-bins-splat')).toBe(true);
    expect(await declares('photon-bins-march')).toBe(false);
    expect(await declares('murmuration-render')).toBe(false);
    expect(await declares('dla-walkers')).toBe(false);
    expect(await declares('dla-render')).toBe(false);
  });

  it('asks for the hash in the definition and nowhere else', () => {
    expect(resolveSimHashRequest('murmuration')).toBe(true);
    expect(resolveSimHashRequest('murmuration-flock')).toBe(true);
    expect(resolveSimHashRequest('photon-bins')).toBe(true);
    expect(resolveSimHashRequest('photon-bins-splat')).toBe(true);
    expect(resolveSimHashRequest('dla-crystals')).toBe(false);
    expect(resolveSimHashRequest('dla-walkers')).toBe(false);
    expect(resolveSimRingRequest('murmuration')).toBe(65536);
    expect(resolveSimRingRequest('photon-bins-present')).toBe(65536);
  });
});

describe('multipass graph: simHash role', () => {
  it('validates the flagships and counts the scatter pass in their budget', () => {
    for (const id of ['murmuration', 'photon-bins']) {
      expect(validateGraph(registered(id))).toEqual([]);
      expect(graphUsesSimRing(registered(id))).toBe(true);
      expect(graphUsesSimHash(registered(id))).toBe(true);
    }
    expect(countGraphPasses(registered('murmuration'))).toBe(3);
    expect(countGraphPasses(registered('photon-bins'))).toBe(4);
    expect(graphUsesSimHash(registered('dla-crystals'))).toBe(false);
    expect(countGraphPasses(registered('dla-crystals'))).toBe(2);
  });

  it('inserts one scatter immediately before the first reader, and none for DLA', () => {
    expect(expandGraph(registered('murmuration')).map((d) => d.entry)).toEqual([
      SIM_HASH_BUILD_ENTRY, 'murmuration-flock', 'murmuration-render',
    ]);
    expect(expandGraph(registered('photon-bins')).map((d) => d.entry)).toEqual([
      'photon-bins-march', SIM_HASH_BUILD_ENTRY, 'photon-bins-splat', 'photon-bins-present',
    ]);
    expect(expandGraph(registered('dla-crystals')).map((d) => d.entry)).toEqual(['dla-walkers', 'dla-render']);
    expect(expandGraph(registered('dla-crystals')).every((d) => d.dispatch !== 'simHashBuild')).toBe(true);
  });

  it('rebuilds only after a simState write makes the chain stale', () => {
    const graph: MultipassGraphDef = {
      maxPassesPerFrame: 16,
      nodes: [
        { id: 'a', entry: 'a', dispatch: 'simState', reads: ['simHash'], writes: ['simState'] },
        { id: 'b', entry: 'b', reads: ['simHash'], writes: ['dataA'] },
        { id: 'c', entry: 'c', reads: ['simHash', 'dataC'], writes: ['color'] },
      ],
    };
    // a reads a stale chain (build), writes simState → b needs a fresh one (build); c shares b's.
    expect(expandGraph(graph).map((d) => d.entry)).toEqual([
      SIM_HASH_BUILD_ENTRY, 'a', SIM_HASH_BUILD_ENTRY, 'b', 'c',
    ]);
    expect(countGraphPasses(graph)).toBe(5);
  });

  it('makes simHash read-only for nodes', () => {
    const bad: MultipassGraphDef = {
      maxPassesPerFrame: 4,
      nodes: [{ id: 'x', entry: 'x', reads: ['simState'], writes: ['simHash', 'color'] }],
    };
    expect(validateGraph(bad).join()).toMatch(/simHash is read-only/);
    expect(diagnoseGraph(bad).map((d) => d.code)).toContain('sim-hash-write');
  });

  it('truncation drops the author force before the final colour write', () => {
    const murmuration = registered('murmuration');
    // 3 dispatches fit; at 2 the flock (and the scatter that only it needed) goes.
    expect(capGraphDispatches(murmuration, 3).map((d) => d.entry)).toEqual([
      SIM_HASH_BUILD_ENTRY, 'murmuration-flock', 'murmuration-render',
    ]);
    expect(capGraphDispatches(murmuration, 2).map((d) => d.entry)).toEqual(['murmuration-render']);
    expect(capGraphDispatches(murmuration, 1).map((d) => d.entry)).toEqual(['murmuration-render']);
    const photon = registered('photon-bins');
    expect(capGraphDispatches(photon, 4)).toHaveLength(4);
    expect(capGraphDispatches(photon, 3).map((d) => d.entry)).toEqual(['photon-bins-march', 'photon-bins-present']);
    expect(capGraphDispatches(photon, 1).map((d) => d.entry)).toEqual(['photon-bins-present']);
  });
});

// ── Frame planner ───────────────────────────────────────────────────────────

const pipeline = (id: string) => ({ label: `pipeline:${id}` } as unknown as GPUComputePipeline);
const HASH_ENTRIES = new Set(['murmuration-flock', 'photon-bins-splat']);
const RING_ENTRIES = new Set([
  'murmuration-flock', 'photon-bins-march', 'photon-bins-splat', 'dla-walkers', 'dla-render',
]);
const SIM_ENTRIES = new Set(['murmuration-flock', 'photon-bins-march', 'dla-walkers']);

function ringBindings(fake: ReturnType<typeof createFakeGpu>, withHash: boolean): GraphSimRingBindings {
  return {
    bindGroup: { label: 'simRingBG' } as unknown as GPUBindGroup,
    stateBuffer: fake.buffer('simState'),
    indexBuffer: fake.buffer('simIndex'),
    stateCount: 4096,
    byteSize: 4096 * 16,
    hash: withHash
      ? {
          bindGroup: { label: 'simRingHashBG' } as unknown as GPUBindGroup,
          buildBindGroup: { label: 'simHashBuildBG' } as unknown as GPUBindGroup,
          buffer: fake.buffer('simHash'),
          emptyBuffer: fake.buffer('simHashEmpty'),
          headBytes: SIM_HASH_HEAD_BYTES,
        }
      : null,
  };
}

function ctx(simRing: GraphSimRingBindings | null, over: Partial<FramePlanContext> = {}): FramePlanContext {
  return {
    getPipeline: (id) => pipeline(id),
    getWorkgroupSize: (id) => (SIM_ENTRIES.has(id) ? { x: 64, y: 1 } : { x: 16, y: 16 }),
    usesSimRing: (id) => RING_ENTRIES.has(id),
    usesSimHash: (id) => HASH_ENTRIES.has(id),
    getSimHashBuildPipeline: () => pipeline('simHashBuild'),
    simRing,
    maxPassesPerFrame: 16,
    framePassBudget: Number.POSITIVE_INFINITY,
    warn: () => {},
    ...over,
  };
}

function graphPlan(id: string): FrameSlotDispatchPlan {
  const slot: SlotDispatchPlan = {
    slot: { shaderId: id, enabled: true, mode: 'chained', params: [0.5, 0.5, 0.5, 0.5] },
    slotIndex: 0,
    program: { kind: 'graph', graph: registered(id) },
    writesDataA: true,
    writesDataB: false,
  };
  return {
    enabledCount: 1,
    parallel: [],
    chained: [slot],
    anyReadsDataC: true,
    anyUsesHistory: false,
    anyUsesSimRing: true,
  };
}

const computes = (ops: ReturnType<typeof compileFramePlan>['ops']): ComputeOp[] =>
  ops.filter((op): op is ComputeOp => op.kind === 'compute');

describe('frame planner: scatter pass', () => {
  it.each([
    ['murmuration', ['murmuration-flock', 'murmuration-render']],
    ['photon-bins', ['photon-bins-march', 'photon-bins-splat', 'photon-bins-present']],
  ])('%s: one scatter, before every reader, and counted as a compute pass', (id, entries) => {
    const fake = createFakeGpu();
    const fp = compileFramePlan(graphPlan(id), ctx(ringBindings(fake, true)));
    const cs = computes(fp.ops);
    const builds = cs.filter((c) => c.dispatch === 'simHashBuild');
    expect(builds).toHaveLength(1);
    expect(cs.filter((c) => c.dispatch !== 'simHashBuild').map((c) => c.entry)).toEqual(entries);
    // The scatter precedes every node that reads the hash.
    const buildAt = cs.indexOf(builds[0]!);
    for (const reader of cs.filter((c) => HASH_ENTRIES.has(c.entry))) {
      expect(cs.indexOf(reader)).toBeGreaterThan(buildAt);
    }
    expect(fp.computeCount).toBe(entries.length + 1);
    expect(fp.graphReports[0]).toMatchObject({ requested: entries.length + 1, executed: entries.length + 1, truncated: 0 });
    expect(builds[0]).toMatchObject({ entry: SIM_HASH_BUILD_ENTRY, bindSimRing: false, bindSimHash: false });
  });

  it('binds the 4-binding group-1 layout only to entries that declare simHash', () => {
    const fake = createFakeGpu();
    const fp = compileFramePlan(graphPlan('photon-bins'), ctx(ringBindings(fake, true)));
    const by = Object.fromEntries(computes(fp.ops).map((c) => [c.entry, [c.bindSimRing, c.bindSimHash]]));
    expect(by['photon-bins-march']).toEqual([true, false]);
    expect(by['photon-bins-splat']).toEqual([true, true]);
    expect(by['photon-bins-present']).toEqual([false, false]);
  });

  it('does not insert the scatter for dla-crystals', () => {
    const fake = createFakeGpu();
    const fp = compileFramePlan(graphPlan('dla-crystals'), ctx(ringBindings(fake, false)));
    const cs = computes(fp.ops);
    expect(cs.map((c) => c.entry)).toEqual(['dla-walkers', 'dla-render']);
    expect(cs.some((c) => c.dispatch === 'simHashBuild' || c.bindSimHash)).toBe(false);
    expect(fp.computeCount).toBe(2);
  });

  it('shares the frame pass budget: truncation drops the force node and its scatter, keeps the colour write', () => {
    const fake = createFakeGpu();
    const base = ringBindings(fake, true);
    const entriesAt = (cap: number) =>
      computes(compileFramePlan(graphPlan('murmuration'), ctx(base, { framePassBudget: cap })).ops).map((c) => c.entry);
    expect(entriesAt(3)).toEqual([SIM_HASH_BUILD_ENTRY, 'murmuration-flock', 'murmuration-render']);
    expect(entriesAt(2)).toEqual(['murmuration-render']);
    // The per-graph quality cap (battery 4) still fits photon-bins in full.
    const photon = computes(compileFramePlan(graphPlan('photon-bins'), ctx(base, { maxPassesPerFrame: 4 })).ops);
    expect(photon).toHaveLength(4);
    const truncated = compileFramePlan(graphPlan('photon-bins'), ctx(base, { maxPassesPerFrame: 3 }));
    expect(computes(truncated.ops).map((c) => c.entry)).toEqual(['photon-bins-march', 'photon-bins-present']);
    expect(truncated.graphReports[0]).toMatchObject({ requested: 4, executed: 2, truncated: 2 });
  });

  it('skips (and warns once) when the hash is not armed', () => {
    const fake = createFakeGpu();
    const warn = vi.fn();
    const noHash = ringBindings(fake, false);
    const fp = compileFramePlan(graphPlan('murmuration'), ctx(noHash, { warn }));
    expect(computes(fp.ops).map((c) => c.entry)).toEqual(['murmuration-render']);
    expect(warn).toHaveBeenCalledWith(expect.stringMatching(/sim hash but none is armed/));
    const noPipeline = compileFramePlan(
      graphPlan('murmuration'),
      ctx(ringBindings(fake, true), { getSimHashBuildPipeline: () => null, warn }),
    );
    // Readers still run (a stale-but-valid chain is safe: every walk is visit-capped).
    expect(computes(noPipeline.ops).map((c) => c.entry)).toEqual(['murmuration-flock', 'murmuration-render']);
  });
});

describe('frame executor: scatter pass', () => {
  function run(id: string, withHash = true) {
    const fake = createFakeGpu();
    const ring = ringBindings(fake, withHash);
    const fp = compileFramePlan(graphPlan(id), ctx(ring));
    const encoder = fake.device.createCommandEncoder({ label: 'frame' });
    executeFramePlan(encoder, fp, {
      textures: {
        readTex: fake.texture('readTex'),
        writeTex: fake.texture('writeTex'),
        dataTexA: fake.texture('dataTexA'),
        dataTexB: fake.texture('dataTexB'),
        dataTexC: fake.texture('dataTexC'),
      },
      computeBindGroup: { label: 'computeBG' } as unknown as GPUBindGroup,
      simRing: ring,
      scaledW: 64,
      scaledH: 64,
    });
    return fake;
  }

  it('resets the heads from the empty buffer, then scatters, before the snapshot and the force pass', () => {
    const fake = run('murmuration');
    expect(summarizeOps(fake.ops)).toEqual([
      'bufcopy:simHashEmpty>simHash',
      `compute:graph-${SIM_HASH_BUILD_ENTRY}-0`,
      'bufcopy:simState>simIndex',
      'compute:graph-flock-0-murmuration-flock',
      'copy:dataTexA>dataTexC',
      'compute:graph-render-0-murmuration-render',
      // End-of-frame feedback (dataA → dataC) is the slot's, as for any graph.
      'copy:dataTexA>dataTexC',
    ]);
    const head = fake.ops.find((o) => o.op === 'copyBufferToBuffer');
    expect(head).toMatchObject({ size: SIM_HASH_HEAD_BYTES });
    // Scatter binds only its own group 0; the force pass binds the hash layout at group 1.
    const sets = fake.ops.filter((o) => o.op === 'setBindGroup');
    expect(sets.map((o) => (o as { index: number; label?: string }).label)).toEqual([
      'simHashBuildBG', 'computeBG', 'simRingHashBG', 'computeBG',
    ]);
    const dispatch = fake.ops.filter((o) => o.op === 'dispatch');
    expect(dispatch[0]).toMatchObject({ x: 4096 / 64, y: 1, z: 1 });
  });

  it('leaves dla-crystals on the three-binding group', () => {
    const fake = run('dla-crystals', false);
    expect(summarizeOps(fake.ops)).toEqual([
      'compute:graph-walkers-0-dla-walkers',
      'copy:dataTexA>dataTexC',
      'compute:graph-render-0-dla-render',
      'copy:dataTexA>dataTexC',
    ]);
    expect(fake.ops.filter((o) => o.op === 'setBindGroup').map((o) => (o as { label?: string }).label)).toEqual([
      'computeBG', 'simRingBG', 'computeBG', 'simRingBG',
    ]);
  });
});

// ── Allocation, layouts, ladder ─────────────────────────────────────────────

describe('SimRing: spatial hash allocation', () => {
  const layouts = { layout: { label: 'hashBGL' } as GPUBindGroupLayout, buildLayout: { label: 'buildBGL' } as GPUBindGroupLayout };
  const base = { label: 'baseBGL' } as GPUBindGroupLayout;

  it('does not allocate the hash (or its bind groups) for a ring nobody asked a hash of', async () => {
    const { device, created, bindGroups } = makeDevice();
    const ring = new SimRing();
    expect(await ring.ensure(device, base)).toBe(true);
    expect(ring.hashAllocated).toBe(false);
    expect(ring.getHashBindGroup()).toBeNull();
    expect(created.map((b) => b.label).sort()).toEqual(['simIndex', 'simParams', 'simState']);
    expect(bindGroups.map((b) => b.label)).toEqual(['simRingBG']);
    expect(bindGroups[0]!.entries.map((e) => e.binding)).toEqual([0, 1, 2]);
  });

  it('allocates heads + links, an empty-heads source and the scatter params with the hash', async () => {
    const { device, created, bindGroups, writes } = makeDevice();
    const ring = new SimRing();
    expect(await ring.ensure(device, base, 65536, layouts)).toBe(true);
    expect(ring.hashAllocated).toBe(true);
    expect(ring.hashByteSize).toBe(simHashBufferBytes(65536));
    const bySize = Object.fromEntries(created.map((b) => [b.label, b.size]));
    expect(bySize.simHash).toBe((16384 + 65536) * 4);
    expect(bySize.simHashEmpty).toBe(SIM_HASH_HEAD_BYTES);
    expect(bySize.simHashParams).toBe(16);
    expect(bySize.simParams).toBe(16);
    // The author bind group is the base ring plus binding 3; the scatter group is its own.
    expect(bindGroups.map((b) => b.label)).toEqual(['simRingBG', 'simRingHashBG', 'simHashBuildBG']);
    expect(bindGroups[1]!.entries.map((e) => e.binding)).toEqual([0, 1, 2, SIM_HASH_BINDING]);
    // Heads start empty in both the live hash and the reset source.
    expect(writes.filter((w) => w.size === SIM_HASH_HEAD_BYTES).map((w) => w.label).sort()).toEqual(['simHash', 'simHashEmpty']);
  });

  it('writes the working size to the scatter pass without touching simParams', async () => {
    const { device, raw } = makeDevice();
    const ring = new SimRing();
    await ring.ensure(device, base, 4096, layouts);
    raw.queue.writeBuffer.mockClear();
    ring.writeParams(device.queue, 1920, 1080);
    const labels = raw.queue.writeBuffer.mock.calls.map((c) => [(c[0] as { label?: string }).label, (c[2] as ArrayBufferView).byteLength]);
    expect(labels).toEqual([['simParams', 16], ['simHashParams', 16]]);
    const hashData = raw.queue.writeBuffer.mock.calls[1]![2] as Uint32Array;
    expect(new Float32Array(hashData.buffer, 0, 2)).toEqual(new Float32Array([1920, 1080]));
    expect(hashData[2]).toBe(4096);
    // No hash → only simParams, with or without a size.
    const plain = makeDevice();
    const ring2 = new SimRing();
    await ring2.ensure(plain.device, base, 4096);
    plain.raw.queue.writeBuffer.mockClear();
    ring2.writeParams(plain.device.queue, 1920, 1080);
    expect(plain.raw.queue.writeBuffer).toHaveBeenCalledTimes(1);
  });

  it('upgrades a hash-less ring in place when a hash shader arms, and keeps the hash for later plain entries', async () => {
    const { device, created } = makeDevice();
    const ring = new SimRing();
    await ring.ensure(device, base);
    expect(ring.hashAllocated).toBe(false);
    const plainState = ring.stateBuffer;
    await ring.ensure(device, base, 65536, layouts);
    expect(ring.hashAllocated).toBe(true);
    expect(ring.stateBuffer).not.toBe(plainState);
    expect(created.filter((b) => b.label === 'simState').map((b) => b.destroyed)).toEqual([true, false]);
    // A later entry that does not ask for the hash must not drop it.
    const hashBuffer = ring.getHashBuffers()!.hashBuffer;
    await ring.ensure(device, base, 65536);
    expect(ring.getHashBuffers()!.hashBuffer).toBe(hashBuffer);
    expect(ring.hashAllocated).toBe(true);
  });

  it('rebuilds the hash at the smaller count when the OOM ladder steps down (no separate ladder)', async () => {
    // simState at 32768 is 512 KiB: it OOMs; 16384 (256 KiB) fits.
    const { device, created } = makeDevice({ oomAtBytes: 32768 * 16 });
    const ring = new SimRing();
    await ring.ensure(device, base, 65536, layouts);
    expect(ring.stateCount).toBe(16384);
    expect(ring.truncated).toBe(true);
    expect(ring.hashByteSize).toBe(simHashBufferBytes(16384));
    expect(sessionStorage.getItem('px_simring_oom_cap')).toBe('16384');
    // Every failed rung freed its hash along with its ring.
    const failedHash = created.filter((b) => b.label === 'simHash' && b.size === simHashBufferBytes(65536));
    expect(failedHash.every((b) => b.destroyed)).toBe(true);
  });

  it('frees the hash with the ring', async () => {
    const { device, created } = makeDevice();
    const ring = new SimRing();
    await ring.ensure(device, base, 4096, layouts);
    ring.destroy();
    expect(created.every((b) => b.destroyed)).toBe(true);
    expect(ring.hashAllocated).toBe(false);
  });
});

describe('pipeline layouts', () => {
  it('compiles a hash shader against the 4-binding group-1 layout and a ring shader against the base one', async () => {
    const { device, raw, pipelineLayouts, layouts } = makeDevice();
    const mod = new WebGPUPipelineModule();
    mod.setupComputeLayout(device, true);

    expect(await mod.shaderManager.compile(device, mod.pipelineLayout, 'ring', RING_WGSL)).toBe(true);
    expect(mod.simRingHashBindGroupLayout).toBeNull();
    expect(await mod.shaderManager.compile(device, mod.pipelineLayout, 'hash', HASH_WGSL)).toBe(true);

    expect(mod.shaderManager.usesSimRing('hash')).toBe(true);
    expect(mod.shaderManager.usesSimHash('hash')).toBe(true);
    expect(mod.shaderManager.usesSimRing('ring')).toBe(true);
    expect(mod.shaderManager.usesSimHash('ring')).toBe(false);

    const descs = raw.createComputePipeline.mock.calls.map((c) => c[0] as GPUComputePipelineDescriptor);
    expect(descs[0]!.layout).not.toBe(descs[1]!.layout);
    expect(pipelineLayouts.at(-1)).toEqual([mod.bindGroupLayout, mod.simRingHashBindGroupLayout]);

    const hashBgl = layouts.find((l) => l.label === 'simRingHashBGL')!;
    expect(hashBgl.entries.map((e) => [e.binding, e.buffer?.type])).toEqual([
      [0, 'storage'], [1, 'read-only-storage'], [2, 'uniform'], [3, 'storage'],
    ]);
    const baseBgl = layouts.find((l) => l.label === 'simRingBGL')!;
    expect(baseBgl.entries).toHaveLength(3);
    // The base layout is created once and shared by the hash ring's non-hash entries.
    expect(layouts.filter((l) => l.label === 'simRingBGL')).toHaveLength(1);
  });

  it('refuses a hash shader on a device with only the base ring storage buffers', async () => {
    const { device } = makeDevice({ limits: { maxStorageBuffersPerShaderStage: 4 } });
    const mod = new WebGPUPipelineModule();
    mod.setupComputeLayout(device, true);
    expect(await mod.shaderManager.compile(device, mod.pipelineLayout, 'hash', HASH_WGSL)).toBe(false);
    expect(mod.shaderManager.hasPipeline('hash')).toBe(false);
    // The three-binding ring is unaffected (DLA still loads).
    expect(await mod.shaderManager.compile(device, mod.pipelineLayout, 'ring', RING_WGSL)).toBe(true);
  });

  it('builds the scatter pipeline lazily, on its own layout', () => {
    const { device, raw, layouts } = makeDevice();
    const mod = new WebGPUPipelineModule();
    mod.setupComputeLayout(device, true);
    expect(raw.createComputePipeline).not.toHaveBeenCalled();
    const build = mod.getSimHashBuildResources()!;
    expect(build.pipeline).toBeDefined();
    expect(mod.getSimHashBuildResources()).toBe(build);
    expect(layouts.find((l) => l.label === 'simHashBuildBGL')!.entries.map((e) => [e.binding, e.buffer?.type])).toEqual([
      [0, 'read-only-storage'], [1, 'storage'], [2, 'uniform'],
    ]);
  });
});

describe('arming', () => {
  async function armed(wgsl: string, askedForHash: boolean) {
    const { device } = makeDevice();
    const mod = new WebGPUPipelineModule();
    mod.setupComputeLayout(device, true);
    expect(await mod.shaderManager.compile(device, mod.pipelineLayout, 'x', wgsl)).toBe(true);
    const ring = new SimRing();
    const ok = await armSimRingFor(device, mod, ring, 'x', 4096, askedForHash);
    return { ok, ring };
  }

  it('arms a hash shader only when its definition asked for the hash', async () => {
    const refused = await armed(HASH_WGSL, false);
    expect(refused.ok).toBe(false);
    expect(refused.ring.allocated).toBe(false);
    expect(console.warn).toHaveBeenCalledWith(expect.stringMatching(/does not set simRing\.spatialHash/));
    const ok = await armed(HASH_WGSL, true);
    expect(ok.ok).toBe(true);
    expect(ok.ring.hashAllocated).toBe(true);
  });

  it('arms a plain ring shader without a hash even when the flag is set elsewhere in the graph', async () => {
    const { ok, ring } = await armed(RING_WGSL, true);
    expect(ok).toBe(true);
    expect(ring.allocated).toBe(true);
    expect(ring.hashAllocated).toBe(false);
  });
});
