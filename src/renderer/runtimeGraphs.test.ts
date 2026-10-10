import { createWaveTankGraph, MultipassGraphDef } from './multipassGraph';
import {
  getGraphEntryIds,
  GRAPH_REGISTRY,
  hasGraph,
  resolveGraphForShader,
} from './multipassRegistry';
import {
  clearRuntimeGraphs,
  getRuntimeGraph,
  GRAPH_LAB_RUNTIME_ID,
  listRuntimeGraphIds,
  setRuntimeGraph,
} from './runtimeGraphs';
import { compileFramePlan, FramePlanContext, resetFramePlanWarnings } from './webgpu/framePlan';
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
    expect(fp.graphReports[0].executed).toBe(0);
    expect(fp.graphReports[0].errors.join(' ')).toContain('reads "dataB" before any producer');
  });

  it('plans a fresh graph object per edit (plans are memoised per object)', () => {
    const first = createWaveTankGraph();
    setRuntimeGraph(GRAPH_LAB_RUNTIME_ID, first);
    expect(compileFramePlan(planFor(GRAPH_LAB_RUNTIME_ID), ctx()).graphReports[0].requested).toBe(5);
    const edited: MultipassGraphDef = {
      ...first,
      nodes: first.nodes.map((n) => (n.id === 'step' ? { ...n, repeat: 1 } : n)),
    };
    setRuntimeGraph(GRAPH_LAB_RUNTIME_ID, edited);
    expect(compileFramePlan(planFor(GRAPH_LAB_RUNTIME_ID), ctx()).graphReports[0].requested).toBe(3);
  });
});
