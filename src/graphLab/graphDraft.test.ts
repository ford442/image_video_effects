import { createWaveTankGraph, validateGraph } from '../renderer/multipassGraph';
import { GRAPH_REGISTRY } from '../renderer/multipassRegistry';
import {
  addNode,
  draftFromDefinition,
  draftFromRegistryGraph,
  duplicateNodeAt,
  forkDraft,
  GraphDraft,
  isSimRingDraft,
  moveNode,
  newDraft,
  removeNodeAt,
  setMaxPasses,
  setNodeEntry,
  setRepeat,
  setScalable,
  toggleRole,
  uniqueNodeId,
} from './graphDraft';

const waveTank = (): GraphDraft => draftFromRegistryGraph('wave-tank', createWaveTankGraph());
const ids = (d: GraphDraft) => d.graph.nodes.map((n) => n.id);

describe('graphDraft edits', () => {
  it('start from an empty graph and add nodes with usable defaults', () => {
    let d = newDraft();
    expect(d.graph.nodes).toEqual([]);
    d = addNode(d, 'wave-step');
    d = addNode(d, 'wave-render');
    expect(d.graph.nodes[0]).toMatchObject({ id: 'step', entry: 'wave-step', reads: ['dataC'], writes: ['color', 'dataA'] });
    // Only the first node claims the display target.
    expect(d.graph.nodes[1]).toMatchObject({ id: 'render', writes: ['dataA'] });
    expect(validateGraph(d.graph)).toEqual([]);
  });

  it('never mutates: every edit returns a new draft with a new graph object', () => {
    const before = waveTank();
    const snapshot = JSON.stringify(before);
    const edits: GraphDraft[] = [
      addNode(before, 'x-pass'),
      removeNodeAt(before, 0),
      duplicateNodeAt(before, 0),
      moveNode(before, 0, 2),
      setNodeEntry(before, 0, 'other'),
      toggleRole(before, 0, 'reads', 'dataA'),
      setRepeat(before, 0, 5),
      setScalable(before, 0, true, 0.5),
      setMaxPasses(before, 12),
    ];
    for (const next of edits) {
      expect(next).not.toBe(before);
      expect(next.graph).not.toBe(before.graph);
    }
    expect(JSON.stringify(before)).toBe(snapshot);
  });

  it('generates unique node ids', () => {
    expect(uniqueNodeId([], 'wave-step')).toBe('step');
    let d = newDraft();
    d = addNode(d, 'a-blur');
    d = addNode(d, 'b-blur');
    d = duplicateNodeAt(d, 0);
    expect(ids(d)).toEqual(['blur', 'blur-3', 'blur-2']);
    expect(new Set(ids(d)).size).toBe(3);
  });

  it('moves, removes and duplicates by position', () => {
    const d = waveTank();
    expect(ids(moveNode(d, 2, 0))).toEqual(['render', 'step', 'inject']);
    expect(ids(removeNodeAt(d, 1))).toEqual(['step', 'render']);
    expect(ids(duplicateNodeAt(d, 0))).toEqual(['step', 'step-2', 'inject', 'render']);
    expect(moveNode(d, 0, 0)).toBe(d);
    expect(removeNodeAt(d, 9)).toBe(d);
  });

  it('toggles only the editable roles and keeps a canonical order', () => {
    let d = waveTank();
    d = toggleRole(d, 0, 'reads', 'read');
    expect(d.graph.nodes[0]?.reads).toEqual(['read', 'dataC']);
    d = toggleRole(d, 0, 'reads', 'dataC');
    expect(d.graph.nodes[0]?.reads).toEqual(['read']);
    // `color` is a display target, not a readable role; simState is view-only.
    expect(toggleRole(d, 0, 'reads', 'color')).toBe(d);
    expect(toggleRole(d, 0, 'reads', 'simState')).toBe(d);
    expect(toggleRole(d, 0, 'writes', 'dataC')).toBe(d);
    d = toggleRole(d, 0, 'writes', 'color');
    expect(d.graph.nodes[0]?.writes).toEqual(['color', 'dataA']);
  });

  it('preserves roles it does not expose when toggling others', () => {
    const d = draftFromDefinition({
      multipass: { graph: { maxPassesPerFrame: 8, nodes: [{ id: 'a', entry: 'x', reads: ['dataC', 'simState'], writes: ['simState', 'dataA'] }] } },
    });
    if (!d.ok) throw new Error(d.error);
    const next = toggleRole(d.draft, 0, 'reads', 'dataA');
    expect(next.graph.nodes[0]?.reads).toEqual(['dataA', 'dataC', 'simState']);
    expect(next.graph.nodes[0]?.writes).toEqual(['simState', 'dataA']);
  });

  it('clamps repeat to a whole number in 1–64 and omits the default', () => {
    let d = waveTank();
    expect(setRepeat(d, 0, 0).graph.nodes[0]?.repeat).toBeUndefined();
    expect(setRepeat(d, 0, 2.6).graph.nodes[0]?.repeat).toBe(3);
    expect(setRepeat(d, 0, 1000).graph.nodes[0]?.repeat).toBe(64);
    expect(setRepeat(d, 0, NaN).graph.nodes[0]?.repeat).toBeUndefined();
    d = setRepeat(d, 0, 1);
    const cleared = d.graph.nodes[0];
    expect(cleared !== undefined && !('repeat' in cleared)).toBe(true);
  });

  it('sets scalable with a valid minScale and removes both keys when switched off', () => {
    let d = setScalable(waveTank(), 0, true, 0.25);
    expect(d.graph.nodes[0]).toMatchObject({ scalable: true, minScale: 0.25 });
    expect(setScalable(d, 0, true, 0.3).graph.nodes[0]?.minScale).toBe(0.25);
    d = setScalable(d, 0, false);
    const off = d.graph.nodes[0];
    expect(off !== undefined && !('scalable' in off)).toBe(true);
    expect(off !== undefined && !('minScale' in off)).toBe(true);
    expect(validateGraph(setScalable(waveTank(), 0, true).graph)).toEqual([]);
  });

  it('clamps the graph ceiling to at least 1', () => {
    expect(setMaxPasses(waveTank(), 0).graph.maxPassesPerFrame).toBe(1);
    expect(setMaxPasses(waveTank(), 10.4).graph.maxPassesPerFrame).toBe(10);
  });
});

describe('graphDraft import', () => {
  it('imports a shader definition and keeps its fields for round-trip', () => {
    const res = draftFromDefinition({
      id: 'wave-tank',
      name: 'Wave Tank',
      url: 'shaders/wave-step.wgsl',
      description: 'd',
      requiresRgba32Float: true,
      multipass: { pass: 1, graph: GRAPH_REGISTRY['wave-tank'] },
    });
    if (!res.ok) throw new Error(res.error);
    expect(res.draft).toMatchObject({ id: 'wave-tank', name: 'Wave Tank', sourceId: 'wave-tank' });
    expect(res.draft.envelope).toMatchObject({ url: 'shaders/wave-step.wgsl', description: 'd', requiresRgba32Float: true });
    expect(res.draft.multipassExtra).toEqual({ pass: 1 });
    expect(res.draft.graph).toEqual(GRAPH_REGISTRY['wave-tank']);
    expect(res.draft.graph).not.toBe(GRAPH_REGISTRY['wave-tank']);
  });

  it('accepts the array-wrapped form and a bare graph', () => {
    const wrapped = draftFromDefinition([{ id: 'a', multipass: { graph: createWaveTankGraph() } }]);
    expect(wrapped.ok && wrapped.draft.id).toBe('a');
    const bare = draftFromDefinition(createWaveTankGraph());
    expect(bare.ok && bare.draft.graph.nodes).toHaveLength(3);
  });

  it('rejects things that are not graphs', () => {
    for (const bad of [null, 'x', 4, {}, { multipass: {} }, { multipass: { graph: { nodes: 'no' } } }, { nodes: [1] }]) {
      expect(draftFromDefinition(bad).ok).toBe(false);
    }
  });

  it('flags sim-ring drafts as view-only', () => {
    expect(isSimRingDraft(waveTank())).toBe(false);
    const dlaGraph = GRAPH_REGISTRY['dla-crystals'];
    if (!dlaGraph) throw new Error('missing dla-crystals graph');
    const dla = draftFromRegistryGraph('dla-crystals', dlaGraph);
    expect(isSimRingDraft(dla)).toBe(true);
    const withField = draftFromDefinition({ id: 'x', simRing: { stateCount: 4 }, multipass: { graph: createWaveTankGraph() } });
    expect(withField.ok && isSimRingDraft(withField.draft)).toBe(true);
  });

  it('forks a template under a new id without keeping its source link', () => {
    const fork = forkDraft(waveTank(), 'wave-lab', 'Wave Lab');
    expect(fork).toMatchObject({ id: 'wave-lab', name: 'Wave Lab', sourceId: undefined });
    expect(fork.graph).toEqual(createWaveTankGraph());
  });
});
