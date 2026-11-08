/**
 * Physics Lab set 2 (#1619, the rest of #1513 Part C) on the sim ring.
 *
 * - physarum-agents: Jones physarum agents on the plain v1 ring (no hash). diffuse (pixels) →
 *   agents (simState) → render (pixels), 3 passes, so battery (cap 4) runs all of it.
 * - sph-fluid: WCSPH on the ring + spatial hash with stride-2 records. The density pass writes only the
 *   parked aux records, so it is `keepsHash` and the planner reuses its hash for the force pass:
 *   scatter → density → force → render, 4 passes (5 without the flag).
 * - Both numpy CPU specs (scripts/sim_models/) run here when numpy is importable; they validate the
 *   solver spec, not the WGSL (SwiftShader covers the WGSL: tests/physics-lab-set2.swiftshader.spec.ts).
 */

import { spawn, spawnSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import { FP32_REQUIRED_SHADER_IDS } from '../../config/formatPolicy';
import { expandShaderSource } from '../../test-utils/shaderSource';
import { validateBindGroup } from '../bindGroupValidator';
import type { GraphSimRingBindings } from '../GraphRunner';
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
import { GRAPH_REGISTRY, resolveSimHashRequest, resolveSimRingRequest } from '../multipassRegistry';
import { createFakeGpu, summarizeOps } from '../testing/fakeGpu';
import {
  compileFramePlan,
  ComputeOp,
  executeFramePlan,
  FramePlanContext,
  resetFramePlanWarnings,
} from './framePlan';
import { SIM_HASH_HEAD_BYTES } from './simHash';
import { declaresBindGroup1, declaresSimHash, validateGroup1Declarations } from './simRing';
import type { FrameSlotDispatchPlan } from './slotDispatch';

const ROOT = path.join(__dirname, '../../..');
const readShader = (id: string) => fs.readFileSync(path.join(ROOT, 'public/shaders', `${id}.wgsl`), 'utf8');
const readDefinition = (id: string) =>
  JSON.parse(fs.readFileSync(path.join(ROOT, 'shader_definitions/simulation', `${id}.json`), 'utf8'));

const registered = (id: string): MultipassGraphDef => {
  const graph = GRAPH_REGISTRY[id];
  if (!graph) throw new Error(`${id} missing from GRAPH_REGISTRY`);
  return graph;
};

const PHYSARUM = ['physarum-agents-diffuse', 'physarum-agents-step', 'physarum-agents-render'];
const SPH = ['sph-fluid-density', 'sph-fluid-force', 'sph-fluid-render'];
/** Entries that declare any @group(1) binding (the renders declare only simParams, or nothing). */
const RING_ENTRIES = new Set([
  'physarum-agents-diffuse', 'physarum-agents-step', 'sph-fluid-density', 'sph-fluid-force', 'sph-fluid-render',
]);
const HASH_ENTRIES = new Set(['sph-fluid-density', 'sph-fluid-force']);
const SIM_ENTRIES = new Set(['physarum-agents-step', 'sph-fluid-density', 'sph-fluid-force']);

beforeEach(() => {
  resetFramePlanWarnings();
  vi.spyOn(console, 'warn').mockImplementation(() => {});
});

afterEach(() => {
  vi.restoreAllMocks();
});

// ── Frame-plan harness (same shape as simHash.test.ts) ──────────────────────

function ringBindings(fake: ReturnType<typeof createFakeGpu>, stateCount: number, withHash: boolean): GraphSimRingBindings {
  return {
    bindGroup: { label: 'simRingBG' } as unknown as GPUBindGroup,
    stateBuffer: fake.buffer('simState'),
    indexBuffer: fake.buffer('simIndex'),
    stateCount,
    byteSize: stateCount * 16,
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
    getPipeline: (id) => ({ label: `pipeline:${id}` } as unknown as GPUComputePipeline),
    getWorkgroupSize: (id) => (SIM_ENTRIES.has(id) ? { x: 64, y: 1 } : { x: 16, y: 16 }),
    usesSimRing: (id) => RING_ENTRIES.has(id),
    usesSimHash: (id) => HASH_ENTRIES.has(id),
    getSimHashBuildPipeline: () => ({ label: 'pipeline:simHashBuild' } as unknown as GPUComputePipeline),
    simRing,
    maxPassesPerFrame: 16,
    framePassBudget: Number.POSITIVE_INFINITY,
    warn: () => {},
    ...over,
  };
}

function slotPlan(id: string): FrameSlotDispatchPlan {
  return {
    enabledCount: 1,
    parallel: [],
    chained: [{
      slot: { shaderId: id, enabled: true, mode: 'chained', params: [0.5, 0.5, 0.5, 0.5] },
      slotIndex: 0,
      program: { kind: 'graph', graph: registered(id) },
      writesDataA: true,
      writesDataB: false,
    }],
    anyReadsDataC: true,
    anyUsesHistory: false,
    anyUsesSimRing: true,
  };
}

const computes = (ops: ReturnType<typeof compileFramePlan>['ops']): ComputeOp[] =>
  ops.filter((op): op is ComputeOp => op.kind === 'compute');

function execute(id: string, stateCount: number, withHash: boolean, size = 1024) {
  const fake = createFakeGpu();
  const ring = ringBindings(fake, stateCount, withHash);
  const plan = compileFramePlan(slotPlan(id), ctx(ring));
  executeFramePlan(fake.device.createCommandEncoder({ label: 'frame' }), plan, {
    textures: {
      readTex: fake.texture('readTex'),
      writeTex: fake.texture('writeTex'),
      dataTexA: fake.texture('dataTexA'),
      dataTexB: fake.texture('dataTexB'),
      dataTexC: fake.texture('dataTexC'),
    },
    computeBindGroup: { label: 'computeBG' } as unknown as GPUBindGroup,
    simRing: ring,
    scaledW: size,
    scaledH: size,
  });
  const dispatches = fake.ops.filter((o) => o.op === 'dispatch') as Array<{ x: number; y: number; z: number }>;
  return { fake, plan, dispatches };
}

// ── physarum-agents ─────────────────────────────────────────────────────────

describe('physarum-agents (v1 ring, no hash)', () => {
  const graph = registered('physarum-agents');

  it('is a valid 3-pass graph: diffuse (pixels) → agents (simState) → render (pixels)', () => {
    expect(validateGraph(graph)).toEqual([]);
    expect(graphUsesSimRing(graph)).toBe(true);
    expect(graphUsesSimHash(graph)).toBe(false);
    expect(countGraphPasses(graph)).toBe(3);
    const expanded = expandGraph(graph);
    expect(expanded.map((d) => [d.entry, d.dispatch])).toEqual([
      ['physarum-agents-diffuse', 'pixels'],
      ['physarum-agents-step', 'simState'],
      ['physarum-agents-render', 'pixels'],
    ]);
    // The agents sense (and deposit on) the diffused field; the render sees the deposits.
    expect(expanded.map((d) => d.copiesBefore.map((c) => `${c.from}>${c.to}`))).toEqual([
      [], ['dataA>dataC'], ['dataA>dataC'],
    ]);
  });

  it('asks for the top ring rung and no hash, for the definition and each entry', () => {
    for (const id of ['physarum-agents', ...PHYSARUM]) {
      expect(resolveSimRingRequest(id)).toBe(65536);
      expect(resolveSimHashRequest(id)).toBe(false);
    }
    expect(graph.maxPassesPerFrame).toBe(4);
  });

  it('fits battery (cap 4) whole; a tighter frame budget drops the agents before the render', () => {
    expect(capGraphDispatches(graph, 4)).toHaveLength(3);
    expect(capGraphDispatches(graph, 2).map((d) => d.entry)).toEqual(['physarum-agents-diffuse', 'physarum-agents-render']);
    expect(capGraphDispatches(graph, 1).map((d) => d.entry)).toEqual(['physarum-agents-render']);
  });

  it('dispatches 65536 / 64 agent workgroups and 16 × 16 pixel tiles', () => {
    const { fake, plan, dispatches } = execute('physarum-agents', 65536, false);
    expect(plan.graphReports[0]).toMatchObject({ requested: 3, executed: 3, truncated: 0 });
    expect(dispatches).toEqual([
      { op: 'dispatch', x: 1024 / 16, y: 1024 / 16, z: 1 },
      { op: 'dispatch', x: 65536 / 64, y: 1, z: 1 },
      { op: 'dispatch', x: 1024 / 16, y: 1024 / 16, z: 1 },
    ]);
    expect(summarizeOps(fake.ops)).toEqual([
      'compute:graph-diffuse-0-physarum-agents-diffuse',
      'copy:dataTexA>dataTexC',
      'compute:graph-agents-0-physarum-agents-step',
      'copy:dataTexA>dataTexC',
      'compute:graph-render-0-physarum-agents-render',
      'copy:dataTexA>dataTexC',
    ]);
    // No scatter, no hash layout: the agents bind the 3-binding ring.
    expect(fake.ops.some((o) => o.op === 'copyBufferToBuffer')).toBe(false);
    expect(fake.ops.filter((o) => o.op === 'setBindGroup').map((o) => (o as { label?: string }).label)).toEqual([
      'computeBG', 'simRingBG', 'computeBG', 'simRingBG', 'computeBG',
    ]);
  });

  it('shrinks the agent dispatch with the OOM ladder', () => {
    const { dispatches } = execute('physarum-agents', 16384, false);
    expect(dispatches[1]).toMatchObject({ x: 16384 / 64, y: 1, z: 1 });
  });

  it.each(PHYSARUM)('%s compiles against the catalog contract with no pasted header', async (id) => {
    const raw = readShader(id);
    expect(raw).toMatch(/#include "_prelude\.wgsl"/);
    expect(raw).not.toMatch(/@group\(0\) @binding\(0\)/);
    const wgsl = await expandShaderSource(raw, `${id}.wgsl`);
    expect(validateGroup1Declarations(wgsl)).toEqual([]);
    expect(validateBindGroup(id, wgsl).valid).toBe(true);
    expect(declaresSimHash(wgsl)).toBe(false);
  });

  it('declares group 1 only where it is used, and steps agents at 64 × 1 × 1', () => {
    expect(declaresBindGroup1(readShader('physarum-agents-diffuse'))).toBe(true);   // simParams: clear on re-arm
    expect(declaresBindGroup1(readShader('physarum-agents-step'))).toBe(true);
    expect(declaresBindGroup1(readShader('physarum-agents-render'))).toBe(false);
    expect(readShader('physarum-agents-step')).toMatch(/@workgroup_size\(64, 1, 1\)/);
    expect(readShader('physarum-agents-diffuse')).toMatch(/@workgroup_size\(16, 16, 1\)/);
    expect(readShader('physarum-agents-step')).not.toMatch(/extraBuffer\[/);
  });

  it('deposits a value that depends only on the texel, so the last-writer race has one outcome', () => {
    const step = readShader('physarum-agents-step');
    const stores = step.match(/textureStore\(dataTextureA,[^;]*;/g) ?? [];
    expect(stores).toEqual([
      'textureStore(dataTextureA, t, vec4<f32>(min(c.r + dep, TRAIL_CAP), u.config.x, 0.0, 0.0));',
    ]);
    // c is the diffused field at that texel (dataC), dep is per frame: nothing per-agent in the value.
    expect(step).toMatch(/let c = textureLoad\(dataTextureC, t, 0\);/);
  });
});

// ── sph-fluid ───────────────────────────────────────────────────────────────

describe('sph-fluid (ring + hash, stride-2 records)', () => {
  const graph = registered('sph-fluid');

  it('is a valid 4-pass graph: one scatter feeds both readers because density keeps the hash', () => {
    expect(validateGraph(graph)).toEqual([]);
    expect(diagnoseGraph(graph).filter((d) => d.severity === 'warning')).toEqual([]);
    expect(graphUsesSimRing(graph)).toBe(true);
    expect(graphUsesSimHash(graph)).toBe(true);
    expect(graph.nodes.find((n) => n.id === 'density')?.keepsHash).toBe(true);
    expect(countGraphPasses(graph)).toBe(4);
    const expanded = expandGraph(graph);
    expect(expanded.map((d) => [d.entry, d.dispatch])).toEqual([
      [SIM_HASH_BUILD_ENTRY, 'simHashBuild'],
      ['sph-fluid-density', 'simState'],
      ['sph-fluid-force', 'simState'],
      ['sph-fluid-render', 'pixels'],
    ]);
    // simIndex is re-snapshotted after the density write (the force pass reads the aux records), the
    // hash is not rebuilt, and the render sees the force pass's stamps.
    expect(expanded.map((d) => d.copiesBefore.map((c) => `${c.from}>${c.to}`))).toEqual([
      [], ['simState>simIndex'], ['simState>simIndex'], ['dataA>dataC'],
    ]);
  });

  it('without keepsHash the planner rebuilds before each reader, and both scatters count', () => {
    const plain: MultipassGraphDef = {
      maxPassesPerFrame: 8,
      nodes: graph.nodes.map(({ keepsHash: _k, ...node }) => node),
    };
    expect(validateGraph(plain)).toEqual([]);
    expect(countGraphPasses(plain)).toBe(5);
    expect(expandGraph(plain).map((d) => d.entry)).toEqual([
      SIM_HASH_BUILD_ENTRY, 'sph-fluid-density', SIM_HASH_BUILD_ENTRY, 'sph-fluid-force', 'sph-fluid-render',
    ]);
    // A 5-pass fluid would not fit battery's 4; with keepsHash it does (next test).
    expect(capGraphDispatches(plain, 4).map((d) => d.entry)).not.toContain('sph-fluid-force');
  });

  it('fits battery (cap 4) whole; below that the force pass goes before the colour write', () => {
    expect(capGraphDispatches(graph, 4)).toHaveLength(4);
    expect(capGraphDispatches(graph, 3).map((d) => d.entry)).toEqual([
      SIM_HASH_BUILD_ENTRY, 'sph-fluid-density', 'sph-fluid-render',
    ]);
    expect(capGraphDispatches(graph, 1).map((d) => d.entry)).toEqual(['sph-fluid-render']);
    const truncated = compileFramePlan(slotPlan('sph-fluid'), ctx(ringBindings(createFakeGpu(), 65536, true), { maxPassesPerFrame: 3 }));
    expect(truncated.graphReports[0]).toMatchObject({ requested: 4, executed: 3, truncated: 1 });
  });

  it('asks for the hash and the top rung, for the definition and each entry', () => {
    for (const id of ['sph-fluid', ...SPH]) {
      expect(resolveSimRingRequest(id)).toBe(65536);
      expect(resolveSimHashRequest(id)).toBe(true);
    }
  });

  it('counts the scatter in the report and binds the hash layout only to the readers', () => {
    const plan = compileFramePlan(slotPlan('sph-fluid'), ctx(ringBindings(createFakeGpu(), 65536, true)));
    const cs = computes(plan.ops);
    expect(cs.map((c) => [c.entry, c.bindSimRing, c.bindSimHash])).toEqual([
      [SIM_HASH_BUILD_ENTRY, false, false],
      ['sph-fluid-density', true, true],
      ['sph-fluid-force', true, true],
      ['sph-fluid-render', true, false],
    ]);
    expect(plan.computeCount).toBe(4);
    expect(plan.graphReports[0]).toMatchObject({ requested: 4, executed: 4, truncated: 0 });
  });

  it('dispatches 65536 / 64 workgroups per simState pass and 16 × 16 render tiles', () => {
    const { fake, dispatches } = execute('sph-fluid', 65536, true);
    expect(summarizeOps(fake.ops)).toEqual([
      'bufcopy:simHashEmpty>simHash',
      `compute:graph-${SIM_HASH_BUILD_ENTRY}-0`,
      'bufcopy:simState>simIndex',
      'compute:graph-density-0-sph-fluid-density',
      'bufcopy:simState>simIndex',
      'compute:graph-force-0-sph-fluid-force',
      'copy:dataTexA>dataTexC',
      'compute:graph-render-0-sph-fluid-render',
      'copy:dataTexA>dataTexC',
    ]);
    expect(dispatches).toEqual([
      { op: 'dispatch', x: 65536 / 64, y: 1, z: 1 },
      { op: 'dispatch', x: 65536 / 64, y: 1, z: 1 },
      { op: 'dispatch', x: 65536 / 64, y: 1, z: 1 },
      { op: 'dispatch', x: 1024 / 16, y: 1024 / 16, z: 1 },
    ]);
  });

  it('is FP32-pinned', () => {
    expect(FP32_REQUIRED_SHADER_IDS.has('sph-fluid')).toBe(true);
    expect(readDefinition('sph-fluid').requiresRgba32Float).toBe(true);
    expect(readDefinition('sph-fluid').simRing).toMatchObject({ stateCount: 65536, spatialHash: true });
    expect(readDefinition('sph-fluid').simRing.packing).toMatch(/stride 2/);
  });

  it.each(SPH)('%s compiles against the catalog contract with no pasted header', async (id) => {
    const raw = readShader(id);
    expect(raw).toMatch(/#include "_prelude\.wgsl"/);
    expect(raw).not.toMatch(/@group\(0\) @binding\(0\)/);
    const wgsl = await expandShaderSource(raw, `${id}.wgsl`);
    expect(validateGroup1Declarations(wgsl)).toEqual([]);
    expect(validateBindGroup(id, wgsl).valid).toBe(true);
    expect(declaresSimHash(wgsl)).toBe(HASH_ENTRIES.has(id));
  });

  it('writes every aux record with the (-1, -1) sentinel, so the hash never sees one', () => {
    for (const id of ['sph-fluid-density', 'sph-fluid-force']) {
      const src = readShader(id);
      for (const write of src.match(/simState\[e \+ 1u\] = [^;]*;/g) ?? []) {
        expect(write).toMatch(/^simState\[e \+ 1u\] = vec4<f32>\(-1\.0, -1\.0, /);
      }
    }
    // The force pass never writes an aux record; the density pass writes positions only on frame 0
    // (the seed), which is why the force pass skips frame 0.
    expect(readShader('sph-fluid-force')).not.toMatch(/simState\[e \+ 1u\] =/);
    expect(readShader('sph-fluid-force')).toMatch(/if \(simParams\.frame == 0u\) \{ return; \}/);
  });
});

// ── keepsHash (planner) ─────────────────────────────────────────────────────

describe('keepsHash planner flag', () => {
  const graph = (keepsHash: boolean | undefined): MultipassGraphDef => ({
    maxPassesPerFrame: 16,
    nodes: [
      { id: 'a', entry: 'a', dispatch: 'simState', reads: ['simHash', 'simIndex'], writes: ['simState'], keepsHash },
      { id: 'b', entry: 'b', dispatch: 'simState', reads: ['simHash', 'simIndex'], writes: ['simState'] },
      { id: 'c', entry: 'c', reads: ['simHash'], writes: ['color'] },
    ],
  });

  it('keeps the hash fresh across a keepsHash write but still re-snapshots simIndex', () => {
    const kept = expandGraph(graph(true));
    expect(kept.map((d) => d.entry)).toEqual([SIM_HASH_BUILD_ENTRY, 'a', 'b', SIM_HASH_BUILD_ENTRY, 'c']);
    expect(kept.find((d) => d.entry === 'b')?.copiesBefore).toEqual([
      { from: 'simState', to: 'simIndex', reason: 'simState → simIndex snapshot' },
    ]);
    expect(countGraphPasses(graph(true))).toBe(5);
    expect(expandGraph(graph(false)).map((d) => d.entry)).toEqual([
      SIM_HASH_BUILD_ENTRY, 'a', SIM_HASH_BUILD_ENTRY, 'b', SIM_HASH_BUILD_ENTRY, 'c',
    ]);
    expect(countGraphPasses(graph(undefined))).toBe(6);
  });

  it('counts the same builds when shrinking to a cap', () => {
    expect(capGraphDispatches(graph(true), 5)).toHaveLength(5);
    // At 4 the node nearest the colour write (b) goes; with it, c reads a hash a never invalidated.
    expect(capGraphDispatches(graph(true), 4).map((d) => d.entry)).toEqual([SIM_HASH_BUILD_ENTRY, 'a', 'c']);
  });

  it('warns when the flag cannot matter (the node does not write simState)', () => {
    const g: MultipassGraphDef = {
      maxPassesPerFrame: 4,
      nodes: [
        { id: 'r', entry: 'r', dispatch: 'simState', reads: ['simHash'], writes: ['dataA'], keepsHash: true },
        { id: 'p', entry: 'p', reads: ['dataC'], writes: ['color'] },
      ],
    };
    expect(validateGraph(g)).toEqual([]);
    expect(diagnoseGraph(g).filter((d) => d.code === 'ineffective-keeps-hash')).toEqual([
      expect.objectContaining({ severity: 'warning', nodeId: 'r' }),
    ]);
  });

  it('still refuses graph JSON that writes simIndex or simHash', () => {
    const base = registered('sph-fluid');
    const writing = (role: 'simIndex' | 'simHash'): MultipassGraphDef => ({
      ...base,
      nodes: base.nodes.map((n) => (n.id === 'density' ? { ...n, writes: [...n.writes, role] } : n)),
    });
    expect(validateGraph(writing('simIndex')).join()).toMatch(/simIndex is read-only/);
    expect(diagnoseGraph(writing('simHash')).map((d) => d.code)).toContain('sim-hash-write');
  });
});

// ── numpy CPU specs ─────────────────────────────────────────────────────────

function pyConstants(file: string): Record<string, number> {
  const out: Record<string, number> = {};
  for (const m of fs.readFileSync(path.join(ROOT, file), 'utf8').matchAll(/^([A-Z][A-Z0-9_]*) = (-?[0-9.]+(?:e-?\d+)?)\b/gm)) {
    out[m[1]!] = Number(m[2]);
  }
  return out;
}

function wgslConstants(id: string): Record<string, number> {
  const out: Record<string, number> = {};
  for (const m of readShader(id).matchAll(/^const ([A-Z][A-Z0-9_]*): (?:f32|u32) = (-?[0-9.]+(?:e-?\d+)?)u?;/gm)) {
    out[m[1]!] = Number(m[2]);
  }
  return out;
}

describe('numpy CPU specs (scripts/sim_models)', () => {
  it('physarum-agents-step uses the model constants', () => {
    const py = pyConstants('scripts/sim_models/physarum_agents.py');
    const wg = wgslConstants('physarum-agents-step');
    for (const name of ['FOOD_W', 'WANDER', 'DEP0', 'TRAIL_CAP']) {
      expect(wg[name], name).toBe(py[name]);
    }
    expect(wgslConstants('physarum-agents-diffuse').TRAIL_CAP).toBe(py.TRAIL_CAP);
  });

  it('the sph-fluid passes use the model constants', () => {
    const py = pyConstants('scripts/sim_models/sph_fluid.py');
    const force = wgslConstants('sph-fluid-force');
    for (const name of ['VISIT_CAP', 'C_SOUND', 'VMAX', 'GAMMA', 'EPS_V', 'RHO_CLAMP', 'RHO_LO', 'RHO_HI', 'OCC_MAX',
      'WALL_K', 'WALL_R', 'WALL_BOUNCE', 'OBST_PUSH', 'OBST_DRAG', 'OBST_PROBE']) {
      expect(force[name], name).toBe(py[name]);
    }
    const density = wgslConstants('sph-fluid-density');
    for (const name of ['VISIT_CAP', 'RHO_LO', 'RHO_HI', 'OCC_MAX']) expect(density[name], name).toBe(py[name]);
    // ACTIVE_MAX = COVERAGE * OCC_SEED * 128 * 128 in the model.
    expect(density.ACTIVE_MAX).toBe(Math.trunc(py.COVERAGE! * py.OCC_SEED! * 128 * 128));
    expect(force.ACTIVE_MAX).toBe(density.ACTIVE_MAX);
    expect(force.POLY6).toBeCloseTo(4 / Math.PI, 9);
    expect(force.SPIKY).toBeCloseTo(-30 / Math.PI, 9);
    expect(force.VISC_LAP).toBeCloseTo(40 / Math.PI, 8);
    expect(force.COH).toBeCloseTo(32 / Math.PI, 8);
    // The visit cap is the hash contract's upper rung.
    expect(force.VISIT_CAP).toBe(16);
  });

  const hasNumpy = spawnSync('python3', ['-c', 'import numpy'], { stdio: 'ignore' }).status === 0;
  if (!hasNumpy) {
    // Visible in the run log; CI's Python job installs numpy and runs both models directly.
    console.info('[physicsLabSet2] numpy not importable: skipping the sim_models runs');
  }

  const runModel = (file: string) =>
    new Promise<{ status: number | null; out: string }>((resolve) => {
      const child = spawn('python3', [path.join(ROOT, file)], { cwd: ROOT });
      let out = '';
      child.stdout.on('data', (d) => { out += String(d); });
      child.stderr.on('data', (d) => { out += String(d); });
      child.on('close', (status) => resolve({ status, out }));
    });

  describe.skipIf(!hasNumpy)('model runs (exit non-zero outside tolerance)', () => {
    it.concurrent('physarum_agents.py: networks form, the random-walk control is rejected', async () => {
      const { status, out } = await runModel('scripts/sim_models/physarum_agents.py');
      expect(out).toMatch(/all cases inside tolerance/);
      expect(out).toMatch(/control: no steer.*rejected/);
      expect(status, out).toBe(0);
    }, 240_000);

    it.concurrent('sph_fluid.py: 100-step stats inside tolerance, the overfilled-hash control is rejected', async () => {
      const { status, out } = await runModel('scripts/sim_models/sph_fluid.py');
      expect(out).toMatch(/all cases inside tolerance/);
      expect(out).toMatch(/control occ ~18.*rejected:.*visit-cap truncation/);
      expect(out).toMatch(/neighbours \(count:particles\)/);
      expect(status, out).toBe(0);
    }, 240_000);
  });
});
