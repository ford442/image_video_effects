import { draftFromRegistryGraph, setNodeDispatch, setRepeat, setSimRing, simRingRequest } from '../graphLab/graphDraft';
import { createWaveTankGraph, MultipassGraphDef } from './multipassGraph';
import {
  getGraphEntryIds,
  GRAPH_REGISTRY,
  hasGraph,
  resolveGraphForShader,
  resolveSimRingRequest,
} from './multipassRegistry';
import {
  clearRuntimeGraphs,
  getRuntimeGraph,
  getRuntimeSimRingRequest,
  GRAPH_LAB_RUNTIME_ID,
  listRuntimeGraphIds,
  setRuntimeGraph,
} from './runtimeGraphs';
import { compileFramePlan, FramePlanContext, resetFramePlanWarnings } from './webgpu/framePlan';
import type { GraphSimRingBindings } from './GraphRunner';
import type { FrameSlotDispatchPlan } from './webgpu/slotDispatch';
import { resolveSlotDispatchProgram } from './webgpu/slotDispatch';

const draft = (): MultipassGraphDef => ({
  maxPassesPerFrame: 8,
  nodes: [
    { id: 'seed', entry: 'draft-seed', reads: ['dataC'], writes: ['dataA'], repeat: 3 },
    { id: 'show', entry: 'draft-show', reads: ['dataA'], writes: ['color', 'dataA'] },
  ],
});

beforeEach(() => {
  clearRuntimeGraphs();
  resetFramePlanWarnings();
});
afterAll(() => clearRuntimeGraphs());

describe('runtime graph overlay', () => {
  it('is empty by default and lists what was registered', () => {
    expect(getRuntimeGraph(GRAPH_LAB_RUNTIME_ID)).toBeNull();
    expect(hasGraph(GRAPH_LAB_RUNTIME_ID)).toBe(false);
    setRuntimeGraph(GRAPH_LAB_RUNTIME_ID, draft());
    expect(listRuntimeGraphIds()).toEqual([GRAPH_LAB_RUNTIME_ID]);
  });

  it('makes an unregistered id resolve as a graph with its entries', () => {
    const graph = draft();
    setRuntimeGraph(GRAPH_LAB_RUNTIME_ID, graph);
    expect(hasGraph(GRAPH_LAB_RUNTIME_ID)).toBe(true);
    expect(resolveGraphForShader(GRAPH_LAB_RUNTIME_ID)).toBe(graph);
    expect(getGraphEntryIds(GRAPH_LAB_RUNTIME_ID)).toEqual(['draft-seed', 'draft-show']);
  });

  it('takes precedence over a static registry graph and restores it on removal', () => {
    const staticGraph = GRAPH_REGISTRY['wave-tank'];
    expect(staticGraph).toBeDefined();
    const override = draft();
    setRuntimeGraph('wave-tank', override);
    expect(resolveGraphForShader('wave-tank')).toBe(override);
    expect(getGraphEntryIds('wave-tank')).toEqual(['draft-seed', 'draft-show']);
    setRuntimeGraph('wave-tank', null);
    expect(resolveGraphForShader('wave-tank')).toBe(staticGraph);
    expect(getGraphEntryIds('wave-tank')).toEqual(['wave-step', 'wave-inject', 'wave-render']);
  });

  it('carries a sim-ring request for the graph and its entries, dropped with the graph', () => {
    setRuntimeGraph(GRAPH_LAB_RUNTIME_ID, draft(), { stateCount: 16384 });
    expect(getRuntimeSimRingRequest(GRAPH_LAB_RUNTIME_ID)).toBe(16384);
    expect(getRuntimeSimRingRequest('draft-seed')).toBe(16384);
    expect(getRuntimeSimRingRequest('plasma')).toBeUndefined();
    // Overrides a shipped definition's request for a shared entry.
    expect(resolveSimRingRequest('dla-walkers')).toBe(65536);
    setRuntimeGraph(GRAPH_LAB_RUNTIME_ID, { maxPassesPerFrame: 4, nodes: [{ id: 'w', entry: 'dla-walkers', reads: ['simState'], writes: ['simState', 'color'] }] }, { stateCount: 4096 });
    expect(resolveSimRingRequest('dla-walkers')).toBe(4096);
    setRuntimeGraph(GRAPH_LAB_RUNTIME_ID, null, { stateCount: 4096 });
    expect(getRuntimeSimRingRequest(GRAPH_LAB_RUNTIME_ID)).toBeUndefined();
    expect(resolveSimRingRequest('dla-walkers')).toBe(65536);
    // Re-registering without a request clears the old one.
    setRuntimeGraph(GRAPH_LAB_RUNTIME_ID, draft(), { stateCount: 4096 });
    setRuntimeGraph(GRAPH_LAB_RUNTIME_ID, draft());
    expect(getRuntimeSimRingRequest('draft-seed')).toBeUndefined();
  });

  it('leaves ordinary shaders alone', () => {
    setRuntimeGraph(GRAPH_LAB_RUNTIME_ID, draft());
    expect(hasGraph('plasma')).toBe(false);
    expect(resolveSlotDispatchProgram('plasma')).toEqual({ kind: 'chain', shaderIds: ['plasma'] });
  });
});

describe('runtime graphs through the frame planner', () => {
  const pipeline = (id: string) => ({ label: `pipeline:${id}` } as unknown as GPUComputePipeline);
  const ctx = (overrides: Partial<FramePlanContext> = {}): FramePlanContext => ({
    getPipeline: (id) => pipeline(id),
    getWorkgroupSize: () => ({ x: 16, y: 16 }),
    usesSimRing: () => false,
    simRing: null,
    maxPassesPerFrame: 16,
    framePassBudget: Number.POSITIVE_INFINITY,
    warn: () => {},
    ...overrides,
  });
  const planFor = (shaderId: string): FrameSlotDispatchPlan => {
    const slot = {
      slot: { shaderId, enabled: true, mode: 'chained' as const, params: [0.5, 0.5, 0.5, 0.5] },
      slotIndex: 0,
      program: resolveSlotDispatchProgram(shaderId),
      writesDataA: true,
      writesDataB: false,
    };
    return { enabledCount: 1, parallel: [], chained: [slot], anyReadsDataC: true, anyUsesHistory: false, anyUsesSimRing: false };
  };

  it('resolves the draft as a graph slot and compiles every pass', () => {
    setRuntimeGraph(GRAPH_LAB_RUNTIME_ID, draft());
    expect(resolveSlotDispatchProgram(GRAPH_LAB_RUNTIME_ID).kind).toBe('graph');
    const fp = compileFramePlan(planFor(GRAPH_LAB_RUNTIME_ID), ctx());
    expect(fp.graphReports[0]).toMatchObject({
      shaderId: GRAPH_LAB_RUNTIME_ID, requested: 4, executed: 4, truncated: 0, errors: [],
    });
    expect(fp.ops.filter((op) => op.kind === 'compute').map((op) => op.kind === 'compute' && op.entry)).toEqual([
      'draft-seed', 'draft-seed', 'draft-seed', 'draft-show',
    ]);
  });

  it('keeps the color writer when the quality cap truncates the draft', () => {
    setRuntimeGraph(GRAPH_LAB_RUNTIME_ID, draft());
    const fp = compileFramePlan(planFor(GRAPH_LAB_RUNTIME_ID), ctx({ maxPassesPerFrame: 2 }));
    expect(fp.graphReports[0]).toMatchObject({ requested: 4, executed: 2, truncated: 2, cap: 2 });
    const entries = fp.ops.filter((op) => op.kind === 'compute').map((op) => op.kind === 'compute' && op.entry);
    expect(entries[entries.length - 1]).toBe('draft-show');
  });

  it('reports a broken draft without encoding it', () => {
    setRuntimeGraph(GRAPH_LAB_RUNTIME_ID, {
      maxPassesPerFrame: 8,
      nodes: [{ id: 'bad', entry: 'draft-bad', reads: ['dataB'], writes: ['color'] }],
    });
    const fp = compileFramePlan(planFor(GRAPH_LAB_RUNTIME_ID), ctx());
    expect(fp.computeCount).toBe(0);
    expect(fp.graphReports[0]?.executed).toBe(0);
    expect(fp.graphReports[0]?.errors.join(' ')).toContain('reads "dataB" before any producer');
  });

  it('plans a fresh graph object per edit (plans are memoised per object)', () => {
    const first = createWaveTankGraph();
    setRuntimeGraph(GRAPH_LAB_RUNTIME_ID, first);
    expect(compileFramePlan(planFor(GRAPH_LAB_RUNTIME_ID), ctx()).graphReports[0]?.requested).toBe(5);
    const edited: MultipassGraphDef = {
      ...first,
      nodes: first.nodes.map((n) => (n.id === 'step' ? { ...n, repeat: 1 } : n)),
    };
    setRuntimeGraph(GRAPH_LAB_RUNTIME_ID, edited);
    expect(compileFramePlan(planFor(GRAPH_LAB_RUNTIME_ID), ctx()).graphReports[0]?.requested).toBe(3);
  });

  const computeOps = (shaderId: string, overrides: Partial<FramePlanContext> = {}) =>
    compileFramePlan(planFor(shaderId), ctx(overrides)).ops.flatMap((op) =>
      op.kind === 'compute' ? [{ entry: op.entry, nodeId: op.nodeId, iteration: op.iteration, dispatch: op.dispatch, bindSimRing: op.bindSimRing }] : [],
    );

  it('expands a repeat edited in the Lab exactly like the same repeat written in JSON', () => {
    // 6 + inject + render = 8, the graph's own ceiling.
    const edited = setRepeat(draftFromRegistryGraph('wave-tank', createWaveTankGraph()), 0, 6).graph;
    setRuntimeGraph(GRAPH_LAB_RUNTIME_ID, edited);
    const fromLab = computeOps(GRAPH_LAB_RUNTIME_ID);

    const json = JSON.parse(JSON.stringify(createWaveTankGraph())) as MultipassGraphDef;
    const step = json.nodes.find((n) => n.id === 'step');
    if (!step) throw new Error('wave-tank has no step node');
    step.repeat = 6;
    setRuntimeGraph('wave-tank', json);
    const fromJson = computeOps('wave-tank');

    expect(fromLab).toEqual(fromJson);
    expect(fromLab.filter((op) => op.nodeId === 'step').map((op) => op.iteration)).toEqual([0, 1, 2, 3, 4, 5]);
    expect(fromLab).toHaveLength(8);
    setRuntimeGraph('wave-tank', null);
  });

  it('never attaches group 1 to an entry that does not declare it, even with the ring on and armed', () => {
    let d = setSimRing(draftFromRegistryGraph('wave-tank', createWaveTankGraph()), true, 4096);
    d = setNodeDispatch(d, 0, 'simState');
    const request = simRingRequest(d);
    expect(request).toEqual({ stateCount: 4096 });
    setRuntimeGraph(GRAPH_LAB_RUNTIME_ID, d.graph, request);
    const ring = { bindGroup: {}, stateBuffer: {}, indexBuffer: {}, stateCount: 4096, byteSize: 65536 } as unknown as GraphSimRingBindings;

    // wave-* are group-0 WGSL: ShaderManager compiled them with the group-0 layout (usesSimRing false).
    const armed = computeOps(GRAPH_LAB_RUNTIME_ID, { usesSimRing: () => false, simRing: ring });
    expect(armed.length).toBeGreaterThan(0);
    expect(armed.every((op) => op.bindSimRing === false)).toBe(true);
    expect(armed.filter((op) => op.dispatch === 'simState').map((op) => op.entry)).toEqual(['wave-step', 'wave-step', 'wave-step']);

    // No group-1 entry ever armed the ring: the simState dispatch is skipped, nothing binds group 1.
    const unarmed = computeOps(GRAPH_LAB_RUNTIME_ID, { usesSimRing: () => false, simRing: null });
    expect(unarmed.map((op) => op.entry)).toEqual(['wave-inject', 'wave-render']);
    expect(unarmed.every((op) => op.bindSimRing === false)).toBe(true);
  });
});
