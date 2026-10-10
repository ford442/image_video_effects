import { createWaveTankGraph, cappedDispatches, MultipassGraphDef } from '../renderer/multipassGraph';
import { GRAPH_REGISTRY } from '../renderer/multipassRegistry';
import { analyzeGraph } from './graphAnalysis';

const waveTank = createWaveTankGraph();

function capOf(graph: MultipassGraphDef, id: string) {
  const cap = analyzeGraph(graph).caps.find((c) => c.id === id);
  if (!cap) throw new Error(`no cap preview for ${id}`);
  return cap;
}

describe('analyzeGraph', () => {
  it('reports the reference graph as valid with its cost', () => {
    const a = analyzeGraph(waveTank);
    expect(a).toMatchObject({ valid: true, requested: 5, ceiling: 8, usesSimRing: false });
    expect(a.errors).toEqual([]);
    expect(a.nodes.map((n) => [n.nodeId, n.passes])).toEqual([['step', 3], ['inject', 1], ['render', 1]]);
    expect(a.nodes.reduce((s, n) => s + n.share, 0)).toBeCloseTo(1);
  });

  describe('dependencies', () => {
    const rows = analyzeGraph(waveTank).rows;

    it('lists every expanded dispatch in order', () => {
      expect(rows.map((r) => `${r.nodeId}:${r.iteration}`)).toEqual([
        'step:0', 'step:1', 'step:2', 'inject:0', 'render:0',
      ]);
    });

    it('traces each read to its producer', () => {
      expect(rows[0].reads).toEqual([{ role: 'dataC', from: 'previous frame' }]);
      // Later iterations sample dataC, which a barrier refreshed from the previous iteration's dataA.
      expect(rows[2].reads[0]).toEqual({ role: 'dataC', from: 'dataA → dataC (step#2)' });
      expect(rows[3].reads).toEqual([{ role: 'dataA', from: 'step#3' }]);
      expect(rows[4].reads).toEqual([{ role: 'dataB', from: 'inject' }]);
    });

    it('shows the copy barriers the planner will insert', () => {
      expect(rows[0].barriers).toEqual([]);
      expect(rows[1].barriers).toEqual(['dataA → dataC']);
      expect(rows[3].barriers).toEqual(['dataA → dataC']);
      const a = analyzeGraph(waveTank);
      expect(a.barrierCount).toBe(rows.reduce((s, r) => s + r.barriers.length, 0));
      expect(a.nodes.find((n) => n.nodeId === 'step')?.barriers).toBe(2);
    });

    it('names the source image and says so when nothing produces a role', () => {
      const a = analyzeGraph({
        maxPassesPerFrame: 4,
        nodes: [{ id: 'a', entry: 'x', reads: ['read', 'dataB'], writes: ['color'] }],
      });
      expect(a.rows[0].reads).toEqual([
        { role: 'read', from: 'source image' },
        { role: 'dataB', from: 'nothing produces it' },
      ]);
      expect(a.valid).toBe(false);
    });
  });

  describe('quality caps', () => {
    it('previews every policy and matches the planner exactly', () => {
      const a = analyzeGraph(waveTank);
      expect(a.caps.map((c) => c.id)).toEqual(['battery', 'balanced', 'ultra', 'auto-low', 'auto-mobile', 'auto-desktop']);
      for (const cap of a.caps) {
        const planned = cappedDispatches(waveTank, cap.policyCap);
        expect(cap.executed).toBe(planned.length);
        expect(cap.truncated).toBe(5 - planned.length);
        expect(cap.dispatches).toHaveLength(planned.length);
      }
    });

    it('shows truncation under a tight cap and what survives', () => {
      const battery = capOf(waveTank, 'battery');
      expect(battery).toMatchObject({ policyCap: 4, effectiveCap: 4, executed: 4, truncated: 1, keepsColorWriter: true });
      expect(battery.dispatches).toEqual(['step#1', 'step#2', 'inject', 'render']);
      const balanced = capOf(waveTank, 'balanced');
      expect(balanced).toMatchObject({ executed: 5, truncated: 0, frameBudget: 16 });
    });

    it('applies the graph ceiling when it is lower than the policy cap', () => {
      const graph: MultipassGraphDef = {
        maxPassesPerFrame: 3,
        nodes: [
          { id: 'a', entry: 'x', reads: ['dataC'], writes: ['dataA'], repeat: 2 },
          { id: 'render', entry: 'y', reads: ['dataA'], writes: ['color'] },
        ],
      };
      const ultra = capOf(graph, 'ultra');
      expect(ultra).toMatchObject({ policyCap: 16, effectiveCap: 3, executed: 3, truncated: 0 });
    });

    it('keeps the display pass when a long iterative node is cut', () => {
      const graph: MultipassGraphDef = {
        maxPassesPerFrame: 16,
        nodes: [
          { id: 'jacobi', entry: 'x', reads: ['dataC'], writes: ['dataA'], repeat: 12 },
          { id: 'render', entry: 'y', reads: ['dataC'], writes: ['color', 'dataA'] },
        ],
      };
      const battery = capOf(graph, 'battery');
      expect(battery.executed).toBe(4);
      expect(battery.keepsColorWriter).toBe(true);
      expect(battery.dispatches[battery.dispatches.length - 1]).toBe('render');
    });

    it('reports keepsColorWriter as null when there is nothing to keep', () => {
      const a = analyzeGraph({ maxPassesPerFrame: 8, nodes: [{ id: 'a', entry: 'x', reads: ['dataC'], writes: ['dataA'] }] });
      expect(a.valid).toBe(true);
      expect(a.warnings.map((w) => w.code)).toContain('no-color-writer');
      expect(a.caps.every((c) => c.keepsColorWriter === null)).toBe(true);
    });

    it('previews nothing for a graph the planner would refuse', () => {
      const a = analyzeGraph({
        maxPassesPerFrame: 2,
        nodes: [
          { id: 'a', entry: 'x', reads: ['dataC'], writes: ['dataA'], repeat: 3 },
          { id: 'render', entry: 'y', reads: ['dataA'], writes: ['color'] },
        ],
      });
      expect(a.valid).toBe(false);
      expect(a.errors[0].code).toBe('pass-budget');
      expect(a.caps).toEqual([]);
    });
  });

  describe('robustness', () => {
    it('survives an imported graph with an absurd repeat', () => {
      const a = analyzeGraph({
        maxPassesPerFrame: 8,
        nodes: [{ id: 'a', entry: 'x', reads: ['dataC'], writes: ['color'], repeat: 1e9 }],
      });
      expect(a.errors.map((e) => e.code)).toContain('repeat-range');
      expect(a.requested).toBe(64);
      expect(a.rows).toHaveLength(64);
    });

    it('handles an empty graph', () => {
      const a = analyzeGraph({ maxPassesPerFrame: 8, nodes: [] });
      expect(a.valid).toBe(false);
      expect(a.rows).toEqual([]);
      expect(a.requested).toBe(0);
    });

    it('does not mutate its input', () => {
      const graph = createWaveTankGraph();
      const before = JSON.stringify(graph);
      analyzeGraph(graph);
      expect(JSON.stringify(graph)).toBe(before);
    });
  });

  it('feeds the entry catalog into missing-entry diagnostics', () => {
    const a = analyzeGraph(waveTank, { knownEntries: new Set(['wave-step', 'wave-render']) });
    expect(a.errors.map((e) => [e.code, e.nodeId])).toEqual([['missing-entry', 'inject']]);
  });

  it('flags sim-ring graphs', () => {
    expect(analyzeGraph(GRAPH_REGISTRY['dla-crystals']).usesSimRing).toBe(true);
  });

  it('analyses every registry graph as valid with a full preview', () => {
    for (const [id, graph] of Object.entries(GRAPH_REGISTRY)) {
      const a = analyzeGraph(graph);
      expect({ id, valid: a.valid, previews: a.caps.length }).toEqual({ id, valid: true, previews: 6 });
    }
  });
});
