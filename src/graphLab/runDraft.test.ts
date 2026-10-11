import { createWaveTankGraph, MultipassGraphDef } from '../renderer/multipassGraph';
import { GRAPH_REGISTRY } from '../renderer/multipassRegistry';
import type { PassTiming } from '../renderer/passTimings';
import type { RendererManager } from '../renderer/RendererManager';
import { clearRuntimeGraphs, getRuntimeGraph, GRAPH_LAB_RUNTIME_ID, setRuntimeGraph } from '../renderer/runtimeGraphs';
import { draftFromRegistryGraph, GraphDraft, newDraft, addNode } from './graphDraft';
import { readLive, runDraft, stopDraft } from './runDraft';

function fakeManager(overrides: Partial<Record<string, unknown>> = {}) {
  const cached = new Set<string>();
  const calls: string[] = [];
  const m = {
    getSlotState: jest.fn(() => ({ shaderId: 'plasma', enabled: true, mode: 'chained' })),
    setRuntimeGraph: jest.fn((id: string, graph: MultipassGraphDef | null) => {
      calls.push(`graph:${id}:${graph ? 'set' : 'clear'}`);
      setRuntimeGraph(id, graph);
      return true;
    }),
    isShaderCached: jest.fn((id: string) => cached.has(id)),
    loadShader: jest.fn(async (id: string, url: string) => {
      calls.push(`load:${id}:${url}`);
      cached.add(id);
      return true;
    }),
    setSlotShader: jest.fn((slot: number, id: string) => {
      calls.push(`slot:${slot}:${id}`);
    }),
    getDiagnostics: jest.fn(() => ({ webgpu: { graph: null } })),
    getPassTimings: jest.fn((): PassTiming[] => []),
    ...overrides,
  };
  return { manager: m as unknown as RendererManager, m, calls, cached };
}

const waveTank = (): GraphDraft => draftFromRegistryGraph('wave-tank', createWaveTankGraph());

afterEach(() => clearRuntimeGraphs());

describe('runDraft', () => {
  it('registers a fresh graph, compiles the root then each entry, and binds the slot', async () => {
    const { manager, calls } = fakeManager();
    const draft = waveTank();
    const res = await runDraft(manager, 1, draft);
    expect(res).toEqual({
      ok: true, slot: 1, entries: ['wave-step', 'wave-inject', 'wave-render'], previousShaderId: 'plasma',
    });
    expect(calls).toEqual([
      'graph:graphlab-draft:set',
      'load:graphlab-draft:shaders/wave-step.wgsl',
      'load:wave-step:shaders/wave-step.wgsl',
      'load:wave-inject:shaders/wave-inject.wgsl',
      'load:wave-render:shaders/wave-render.wgsl',
      'slot:1:graphlab-draft',
    ]);
    const registered = getRuntimeGraph(GRAPH_LAB_RUNTIME_ID);
    expect(registered).toEqual(draft.graph);
    expect(registered).not.toBe(draft.graph);
  });

  it('only loads what is not compiled yet when re-run after an edit', async () => {
    const { manager, calls } = fakeManager();
    const first = waveTank();
    await runDraft(manager, 0, first);
    calls.length = 0;
    const edited = addNode(first, 'extra-pass');
    await runDraft(manager, 0, edited, { previousShaderId: 'plasma' });
    expect(calls).toEqual(['graph:graphlab-draft:set', 'load:extra-pass:shaders/extra-pass.wgsl', 'slot:0:graphlab-draft']);
  });

  it('refuses an empty, invalid or sim-ring draft without touching the renderer', async () => {
    const { manager, calls } = fakeManager();
    const empty = await runDraft(manager, 0, newDraft());
    expect(empty).toMatchObject({ ok: false, reason: 'empty' });

    const bad = { ...waveTank(), graph: { maxPassesPerFrame: 2, nodes: createWaveTankGraph().nodes } };
    const invalid = await runDraft(manager, 0, bad);
    expect(invalid).toMatchObject({ ok: false, reason: 'invalid', message: 'graph exceeds maxPassesPerFrame: 5 > 2' });

    const dlaGraph = GRAPH_REGISTRY['dla-crystals'];
    if (!dlaGraph) throw new Error('missing dla-crystals graph');
    const dla = await runDraft(manager, 0, draftFromRegistryGraph('dla-crystals', dlaGraph));
    expect(dla).toMatchObject({ ok: false, reason: 'sim-ring' });

    expect(calls).toEqual([]);
  });

  it('reports a backend that cannot run graphs', async () => {
    const { manager, calls } = fakeManager({ setRuntimeGraph: jest.fn(() => false) });
    expect(await runDraft(manager, 0, waveTank())).toMatchObject({ ok: false, reason: 'backend' });
    expect(calls).toEqual([]);
  });

  it('stops before binding the slot when an entry fails to compile', async () => {
    const { manager, calls } = fakeManager({
      loadShader: jest.fn(async (id: string) => id !== 'wave-inject'),
    });
    const res = await runDraft(manager, 0, waveTank());
    expect(res).toMatchObject({ ok: false, reason: 'load-failed', message: 'Could not compile "wave-inject".' });
    expect(calls.some((c) => c.startsWith('slot:'))).toBe(false);
  });

  it('applies the entry catalog check when one is given', async () => {
    const { manager } = fakeManager();
    const res = await runDraft(manager, 0, waveTank(), { knownEntries: new Set(['wave-step']) });
    expect(res).toMatchObject({ ok: false, reason: 'invalid' });
  });
});

describe('stopDraft', () => {
  const showing = (shaderId: string | null) => ({ getSlotState: jest.fn(() => ({ shaderId, enabled: true, mode: 'chained' })) });

  it('restores the previous shader and drops the runtime graph', () => {
    const { manager, calls } = fakeManager(showing(GRAPH_LAB_RUNTIME_ID));
    stopDraft(manager, 2, 'plasma');
    expect(calls).toEqual(['slot:2:plasma', 'graph:graphlab-draft:clear']);
    stopDraft(manager, 2, null);
    expect(calls.slice(-2)[0]).toBe('slot:2:');
  });

  it('leaves the slot alone when the user picked another shader meanwhile', () => {
    const { manager, calls } = fakeManager(showing('kaleidoscope'));
    stopDraft(manager, 0, 'plasma');
    expect(calls).toEqual(['graph:graphlab-draft:clear']);
  });
});

describe('readLive', () => {
  const timing = (shaderId: string, nodeId: string): PassTiming => ({
    key: `0:${nodeId}`, label: nodeId, kind: 'compute', slot: 0, shaderId, nodeId, scale: 1, gpuMs: 0.5, iterations: 1,
  });

  it('returns the planner report and timings only for the running draft', () => {
    const report = { shaderId: GRAPH_LAB_RUNTIME_ID, requested: 5, executed: 4, truncated: 1, cap: 4, errors: [] };
    const { manager } = fakeManager({
      getDiagnostics: jest.fn(() => ({ webgpu: { graph: report } })),
      getPassTimings: jest.fn(() => [timing(GRAPH_LAB_RUNTIME_ID, 'step'), timing('other', 'x'), { ...timing(GRAPH_LAB_RUNTIME_ID, 'p'), kind: 'present' as const }]),
    });
    const live = readLive(manager);
    expect(live.report).toBe(report);
    expect(live.passTimings.map((t) => t.nodeId)).toEqual(['step']);
  });

  it('ignores another shader’s graph report', () => {
    const { manager } = fakeManager({
      getDiagnostics: jest.fn(() => ({ webgpu: { graph: { shaderId: 'ripple-tank', requested: 7, executed: 7, truncated: 0, cap: 8, errors: [] } } })),
    });
    expect(readLive(manager).report).toBeNull();
  });
});
