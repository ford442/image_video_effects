import { createWaveTankGraph, MultipassGraphDef } from '../renderer/multipassGraph';
import { GRAPH_REGISTRY } from '../renderer/multipassRegistry';
import type { PassTiming } from '../renderer/passTimings';
import type { RendererManager } from '../renderer/RendererManager';
import { resolveSimRingRequest } from '../renderer/multipassRegistry';
import {
  clearRuntimeGraphs,
  getRuntimeGraph,
  GRAPH_LAB_RUNTIME_ID,
  RuntimeSimRingRequest,
  setRuntimeGraph,
} from '../renderer/runtimeGraphs';
import { draftFromRegistryGraph, GraphDraft, newDraft, addNode, setSimRing, toggleRole } from './graphDraft';
import { readLive, runDraft, stopDraft } from './runDraft';

function fakeManager(overrides: Partial<Record<string, unknown>> = {}) {
  const cached = new Set<string>();
  const calls: string[] = [];
  const m = {
    getSlotState: vi.fn(() => ({ shaderId: 'plasma', enabled: true, mode: 'chained' })),
    setRuntimeGraph: vi.fn((id: string, graph: MultipassGraphDef | null, simRing: RuntimeSimRingRequest | null = null) => {
      calls.push(`graph:${id}:${graph ? 'set' : 'clear'}${simRing ? `:ring=${simRing.stateCount}` : ''}`);
      setRuntimeGraph(id, graph, simRing);
      return true;
    }),
    isShaderCached: vi.fn((id: string) => cached.has(id)),
    loadShader: vi.fn(async (id: string, url: string) => {
      calls.push(`load:${id}:${url}`);
      cached.add(id);
      return true;
    }),
    setSlotShader: vi.fn((slot: number, id: string) => {
      calls.push(`slot:${slot}:${id}`);
    }),
    getDiagnostics: vi.fn(() => ({ webgpu: { graph: null } })),
    getPassTimings: vi.fn((): PassTiming[] => []),
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

  it('refuses an empty or invalid draft without touching the renderer', async () => {
    const { manager, calls } = fakeManager();
    const empty = await runDraft(manager, 0, newDraft());
    expect(empty).toMatchObject({ ok: false, reason: 'empty' });

    const bad = { ...waveTank(), graph: { maxPassesPerFrame: 2, nodes: createWaveTankGraph().nodes } };
    const invalid = await runDraft(manager, 0, bad);
    expect(invalid).toMatchObject({ ok: false, reason: 'invalid', message: 'graph exceeds maxPassesPerFrame: 5 > 2' });

    expect(calls).toEqual([]);
  });

  it('never loads a graph with an illegal read (a role used before it is produced)', async () => {
    const { manager, m, calls } = fakeManager();
    // step reads dataB, which only the later inject writes.
    const illegal = toggleRole(waveTank(), 0, 'reads', 'dataB');
    const res = await runDraft(manager, 0, illegal);
    expect(res).toMatchObject({ ok: false, reason: 'invalid' });
    expect(m.loadShader).not.toHaveBeenCalled();
    expect(m.setRuntimeGraph).not.toHaveBeenCalled();
    expect(calls).toEqual([]);
  });

  it('reports a backend that cannot run graphs', async () => {
    const { manager, calls } = fakeManager({ setRuntimeGraph: vi.fn(() => false) });
    expect(await runDraft(manager, 0, waveTank())).toMatchObject({ ok: false, reason: 'backend' });
    expect(calls).toEqual([]);
  });

  it('stops before binding the slot when an entry fails to compile', async () => {
    const { manager, calls } = fakeManager({
      loadShader: vi.fn(async (id: string) => id !== 'wave-inject'),
    });
    const res = await runDraft(manager, 0, waveTank());
    expect(res).toMatchObject({ ok: false, reason: 'load-failed', message: 'Could not compile "wave-inject".' });
    expect(calls.some((c) => c.startsWith('slot:'))).toBe(false);
  });

  describe('sim-ring drafts', () => {
    const dla = (stateCount?: number): GraphDraft => {
      const graph = GRAPH_REGISTRY['dla-crystals'];
      if (!graph) throw new Error('missing dla-crystals graph');
      return setSimRing(draftFromRegistryGraph('dla-crystals', graph), true, stateCount);
    };

    it('run, sending the ring request with the graph so group-1 entries size the ring from it', async () => {
      const { manager, calls } = fakeManager();
      const res = await runDraft(manager, 0, dla(16384));
      expect(res).toMatchObject({ ok: true, entries: ['dla-walkers', 'dla-render'] });
      expect(calls[0]).toBe('graph:graphlab-draft:set:ring=16384');
      // What WebGPURenderer.loadShader hands SimRing.ensure for the root and each entry.
      expect(resolveSimRingRequest(GRAPH_LAB_RUNTIME_ID)).toBe(16384);
      expect(resolveSimRingRequest('dla-walkers')).toBe(16384);
      stopDraft(manager, 0, 'plasma');
      // Dropped with the draft: the shipped definition's request is back.
      expect(resolveSimRingRequest('dla-walkers')).toBe(65536);
    });

    it('recompile every entry when asked to re-arm (Run, size change), not on plain edits', async () => {
      const { manager, calls } = fakeManager();
      await runDraft(manager, 0, dla(), { rearmSimRing: true });
      calls.length = 0;
      await runDraft(manager, 0, dla(4096), { rearmSimRing: true });
      expect(calls).toEqual([
        'graph:graphlab-draft:set:ring=4096',
        'load:graphlab-draft:shaders/dla-walkers.wgsl',
        'load:dla-walkers:shaders/dla-walkers.wgsl',
        'load:dla-render:shaders/dla-render.wgsl',
        'slot:0:graphlab-draft',
      ]);
      calls.length = 0;
      await runDraft(manager, 0, dla(4096));
      expect(calls).toEqual(['graph:graphlab-draft:set:ring=4096', 'slot:0:graphlab-draft']);
    });

    it('send no ring request for a plain draft, and never recompile it to re-arm', async () => {
      const { manager, calls } = fakeManager();
      await runDraft(manager, 0, waveTank(), { rearmSimRing: true });
      calls.length = 0;
      await runDraft(manager, 0, waveTank(), { rearmSimRing: true });
      expect(calls).toEqual(['graph:graphlab-draft:set', 'slot:0:graphlab-draft']);
    });
  });

  it('applies the entry catalog check when one is given', async () => {
    const { manager } = fakeManager();
    const res = await runDraft(manager, 0, waveTank(), { knownEntries: new Set(['wave-step']) });
    expect(res).toMatchObject({ ok: false, reason: 'invalid' });
  });
});

describe('stopDraft', () => {
  const showing = (shaderId: string | null) => ({ getSlotState: vi.fn(() => ({ shaderId, enabled: true, mode: 'chained' })) });

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
      getDiagnostics: vi.fn(() => ({ webgpu: { graph: report } })),
      getPassTimings: vi.fn(() => [timing(GRAPH_LAB_RUNTIME_ID, 'step'), timing('other', 'x'), { ...timing(GRAPH_LAB_RUNTIME_ID, 'p'), kind: 'present' as const }]),
    });
    const live = readLive(manager);
    expect(live.report).toBe(report);
    expect(live.passTimings.map((t) => t.nodeId)).toEqual(['step']);
  });

  it('ignores another shader’s graph report', () => {
    const { manager } = fakeManager({
      getDiagnostics: vi.fn(() => ({ webgpu: { graph: { shaderId: 'ripple-tank', requested: 7, executed: 7, truncated: 0, cap: 8, errors: [] } } })),
    });
    expect(readLive(manager).report).toBeNull();
  });
});
