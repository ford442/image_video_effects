import {
  createWaveTankGraph,
  diagnoseGraph,
  GraphDiagnostic,
  GraphDiagnosticCode,
  GraphNodeDef,
  MultipassGraphDef,
  validateGraph,
} from './multipassGraph';
import { GRAPH_REGISTRY } from './multipassRegistry';

const graphOf = (nodes: GraphNodeDef[], maxPassesPerFrame = 16): MultipassGraphDef => ({ maxPassesPerFrame, nodes });

const codes = (diags: GraphDiagnostic[], severity?: 'error' | 'warning'): GraphDiagnosticCode[] =>
  diags.filter((d) => !severity || d.severity === severity).map((d) => d.code);

const first = (diags: GraphDiagnostic[], code: GraphDiagnosticCode): GraphDiagnostic => {
  const hit = diags.find((d) => d.code === code);
  if (!hit) throw new Error(`no ${code} diagnostic in ${JSON.stringify(codes(diags))}`);
  return hit;
};

describe('diagnoseGraph', () => {
  it('is empty for the reference graph and every registry graph', () => {
    expect(diagnoseGraph(createWaveTankGraph())).toEqual([]);
    for (const [id, graph] of Object.entries(GRAPH_REGISTRY)) {
      expect({ id, diagnostics: diagnoseGraph(graph) }).toEqual({ id, diagnostics: [] });
    }
  });

  it('keeps validateGraph strings identical to the error diagnostics (registry + broken graphs)', () => {
    const broken: MultipassGraphDef[] = [
      graphOf([], 0),
      graphOf([{ id: 'a', entry: '', reads: ['dataC', 'bogus' as never], writes: ['simIndex'], repeat: 100 }], 1),
      graphOf([{ id: 'a', entry: 'x', reads: ['dataA'], writes: ['dataA'] }]),
      graphOf([{ id: 'a', entry: 'x', reads: [], writes: [], dispatch: 'weird' as never, minScale: 0.1 }]),
    ];
    for (const graph of [...Object.values(GRAPH_REGISTRY), ...broken]) {
      const errors = diagnoseGraph(graph, { knownEntries: new Set(['wave-step']) })
        .filter((d) => d.severity === 'error')
        .map((d) => d.message);
      expect(validateGraph(graph, { knownEntries: new Set(['wave-step']) })).toEqual(errors);
    }
  });

  it('reports an absurd repeat instead of simulating it (imported JSON must not freeze the tab)', () => {
    const graph = graphOf([{ id: 'a', entry: 'x', reads: ['dataC'], writes: ['color'], repeat: 1e9 }], 8);
    const started = Date.now();
    const d = diagnoseGraph(graph);
    expect(Date.now() - started).toBeLessThan(1000);
    expect(codes(d, 'error')).toEqual(expect.arrayContaining(['repeat-range', 'pass-budget']));
    expect(validateGraph(graph)).toEqual(d.filter((x) => x.severity === 'error').map((x) => x.message));
  });

  it('never lets a warning change validateGraph', () => {
    const graph = graphOf([{ id: 'a', entry: 'x', reads: ['dataC'], writes: ['dataA'], repeat: 1.5 }]);
    expect(codes(diagnoseGraph(graph), 'warning')).toContain('non-integer-repeat');
    expect(validateGraph(graph)).toEqual([]);
  });

  describe('error codes', () => {
    const run = (nodes: GraphNodeDef[], max = 16, known?: Set<string>) =>
      diagnoseGraph(graphOf(nodes, max), known ? { knownEntries: known } : undefined);
    const ok: GraphNodeDef = { id: 'a', entry: 'x', reads: ['dataC'], writes: ['color'] };

    it('max-passes / empty-graph', () => {
      expect(codes(run([ok], 0), 'error')).toContain('max-passes');
      expect(codes(run([]), 'error')).toEqual(['empty-graph']);
    });

    it('pass-budget carries the same text the runtime logs', () => {
      const d = run([{ ...ok, repeat: 5 }], 4);
      expect(first(d, 'pass-budget').message).toBe('graph exceeds maxPassesPerFrame: 5 > 4');
    });

    it('missing-entry for an empty entry and for an unknown entry', () => {
      expect(first(run([{ ...ok, entry: '' }]), 'missing-entry')).toMatchObject({ nodeId: 'a', severity: 'error' });
      const unknown = run([{ ...ok, entry: 'nope' }], 16, new Set(['x']));
      expect(first(unknown, 'missing-entry').message).toBe('node a: unknown entry "nope"');
      expect(codes(run([ok], 16, new Set(['x'])), 'error')).toEqual([]);
    });

    it('node-id, repeat-range, invalid-role, sim-index-write, invalid-dispatch, no-io, min-scale, scalable-sim', () => {
      const d = run([
        { ...ok, id: '' },
        { ...ok, id: 'r', repeat: 65 },
        { ...ok, id: 'role', reads: ['bogus' as never] },
        { ...ok, id: 'simw', writes: ['simIndex'] },
        { ...ok, id: 'disp', dispatch: 'weird' as never },
        { id: 'io', entry: 'x', reads: [], writes: [] },
        { ...ok, id: 'min', minScale: 0.1 },
        { ...ok, id: 'scal', dispatch: 'simState', scalable: true },
      ], 200);
      const errs = codes(d, 'error');
      for (const code of [
        'node-id', 'repeat-range', 'invalid-role', 'sim-index-write', 'invalid-dispatch', 'no-io', 'min-scale',
        'scalable-sim',
      ] as GraphDiagnosticCode[]) {
        expect(errs).toContain(code);
      }
    });
  });

  describe('dependency vs cycle', () => {
    it('dependency: nothing produces the role before the reader', () => {
      const d = diagnoseGraph(graphOf([
        { id: 'a', entry: 'x', reads: ['dataB'], writes: ['dataA'] },
        { id: 'b', entry: 'y', reads: ['dataA'], writes: ['color'] },
      ]));
      expect(first(d, 'dependency')).toMatchObject({
        nodeId: 'a', iteration: 0, role: 'dataB', severity: 'error',
        message: 'node a iter 0: reads "dataB" before any producer in this frame',
      });
      expect(codes(d)).not.toContain('cycle');
    });

    it('cycle: a node that waits on its own output', () => {
      const d = diagnoseGraph(graphOf([{ id: 'a', entry: 'x', reads: ['dataA'], writes: ['dataA', 'color'] }]));
      expect(first(d, 'cycle')).toMatchObject({ nodeId: 'a', role: 'dataA' });
    });

    it('cycle: two nodes that wait on each other', () => {
      const d = diagnoseGraph(graphOf([
        { id: 'a', entry: 'x', reads: ['dataB'], writes: ['dataA'] },
        { id: 'b', entry: 'y', reads: ['dataA'], writes: ['dataB', 'color'] },
      ]));
      expect(first(d, 'cycle')).toMatchObject({ nodeId: 'a', role: 'dataB' });
    });

    it('a seeded dataC read is not a dependency error (previous-frame feedback)', () => {
      const d = diagnoseGraph(graphOf([
        { id: 'a', entry: 'x', reads: ['dataC'], writes: ['dataA'] },
        { id: 'b', entry: 'y', reads: ['dataC'], writes: ['color', 'dataA'] },
      ]));
      expect(codes(d, 'error')).toEqual([]);
    });
  });

  describe('authoring warnings', () => {
    const warnings = (nodes: GraphNodeDef[], max = 16) => codes(diagnoseGraph(graphOf(nodes, max)), 'warning');

    it('no-color-writer', () => {
      expect(warnings([{ id: 'a', entry: 'x', reads: ['dataC'], writes: ['dataA'] }])).toContain('no-color-writer');
    });

    it('duplicate-node-id is reported once per id', () => {
      const d = diagnoseGraph(graphOf([
        { id: 'a', entry: 'x', reads: ['dataC'], writes: ['dataA'] },
        { id: 'a', entry: 'y', reads: ['dataA'], writes: ['dataB'] },
        { id: 'a', entry: 'z', reads: ['dataB'], writes: ['color'] },
      ]));
      expect(d.filter((x) => x.code === 'duplicate-node-id')).toHaveLength(1);
    });

    it('non-integer-repeat, ineffective-role, unbounded-max-passes', () => {
      expect(warnings([{ id: 'a', entry: 'x', reads: ['dataC'], writes: ['color'], repeat: 2.5 }])).toContain(
        'non-integer-repeat',
      );
      const w = warnings([{ id: 'a', entry: 'x', reads: ['color'], writes: ['read', 'dataC', 'color'] }]);
      expect(w.filter((c) => c === 'ineffective-role')).toHaveLength(3);
      expect(warnings([{ id: 'a', entry: 'x', reads: ['dataC'], writes: ['color'] }], 1000)).toContain(
        'unbounded-max-passes',
      );
    });

    it('reading the source image via "read" is a valid declaration, not a warning', () => {
      expect(warnings([{ id: 'a', entry: 'x', reads: ['read'], writes: ['color'] }])).toEqual([]);
    });
  });
});
