import {
  validateGraph,
  expandGraph,
  createWaveTankGraph,
  countGraphPasses,
} from '../renderer/multipassGraph';
import { resolveGraphForShader } from '../renderer/multipassRegistry';
import { analyzeGraphBindingUsage } from '../renderer/GraphRunner';

describe('multipassGraph', () => {
  it('validates wave-tank demo graph', () => {
    const graph = createWaveTankGraph();
    expect(validateGraph(graph)).toEqual([]);
    expect(graph.nodes).toHaveLength(3);
    expect(countGraphPasses(graph)).toBe(5);
  });

  it('reports invalid texture roles', () => {
    const errors = validateGraph({
      maxPassesPerFrame: 8,
      nodes: [{
        id: 'bad',
        entry: 'x',
        reads: ['dataC' as const, 'bogus' as never],
        writes: ['dataA'],
      }],
    });
    expect(errors.some((e) => e.includes('invalid read role'))).toBe(true);
  });

  it('reports pass cap exceeded', () => {
    const errors = validateGraph({
      maxPassesPerFrame: 2,
      nodes: [
        { id: 'a', entry: 'wave-step', reads: ['dataC'], writes: ['dataA'], repeat: 3 },
      ],
    });
    expect(errors.some((e) => e.includes('maxPassesPerFrame'))).toBe(true);
  });

  it('reports repeat out of bounds', () => {
    const errors = validateGraph({
      maxPassesPerFrame: 64,
      nodes: [{ id: 'a', entry: 'x', reads: ['dataC'], writes: ['dataA'], repeat: 100 }],
    });
    expect(errors.some((e) => e.includes('repeat'))).toBe(true);
  });

  it('expands repeat nodes and inserts copy barriers', () => {
    const expanded = expandGraph(createWaveTankGraph());
    expect(expanded).toHaveLength(5);
    expect(expanded[0].entry).toBe('wave-step');
    expect(expanded[1].copiesBefore.length).toBeGreaterThan(0);
    expect(expanded[1].copiesBefore[0].from).toBe('dataA');
  });

  it('resolves graph for wave-tank from registry', () => {
    const graph = resolveGraphForShader('wave-tank');
    expect(graph?.nodes).toHaveLength(3);
    expect(resolveGraphForShader('wave-equation')).toBeNull();
  });

  it('resolves quantum-foam graph from registry', () => {
    const graph = resolveGraphForShader('quantum-foam-pass1');
    expect(graph?.nodes).toHaveLength(3);
  });

  it('validates and expands ripple-tank Tier C graph from registry', () => {
    const graph = resolveGraphForShader('ripple-tank');
    expect(graph).not.toBeNull();
    expect(graph?.nodes).toHaveLength(4);
    expect(validateGraph(graph!)).toEqual([]);
    expect(countGraphPasses(graph!)).toBe(7);

    const expanded = expandGraph(graph!);
    expect(expanded).toHaveLength(7);
    expect(expanded[0].entry).toBe('ripple-tank-step');
    expect(expanded[4].entry).toBe('ripple-tank-inject');
    expect(expanded[5].entry).toBe('ripple-tank-pass2');
    expect(expanded[6].entry).toBe('ripple-tank-pass3');
    expect(expanded[1].copiesBefore[0]?.from).toBe('dataA');
    expect(expanded[4].copiesBefore[0]?.from).toBe('dataA');
    expect(expanded[5].copiesBefore[0]?.from).toBe('dataB');
  });

  it('analyzes ripple-tank graph binding usage', () => {
    const graph = resolveGraphForShader('ripple-tank');
    const usage = analyzeGraphBindingUsage(graph!);
    expect(usage.writesDataA).toBe(true);
    expect(usage.writesDataB).toBe(true);
    expect(usage.readsDataC).toBe(true);
  });

  it('validates fabric-of-reality and photonic-caustics-graph', () => {
    const fabric = resolveGraphForShader('fabric-of-reality');
    const photonic = resolveGraphForShader('photonic-caustics-graph');
    expect(validateGraph(fabric!)).toEqual([]);
    expect(validateGraph(photonic!)).toEqual([]);
    expect(countGraphPasses(fabric!)).toBe(7);
    expect(countGraphPasses(photonic!)).toBe(4);
  });

  it('prefers dataA→dataC copy after a sibling dataB write (fabric handoff)', () => {
    const fabric = resolveGraphForShader('fabric-of-reality');
    const expanded = expandGraph(fabric!);
    // Last dispatch is render; must sample positions from A, not tear mask from B
    const render = expanded[expanded.length - 1];
    expect(render.entry).toBe('fabric-render');
    expect(render.copiesBefore.some((c) => c.from === 'dataA')).toBe(true);
    expect(render.copiesBefore.some((c) => c.from === 'dataB')).toBe(false);
  });

  it('analyzes graph binding usage', () => {
    const usage = analyzeGraphBindingUsage(createWaveTankGraph());
    expect(usage.writesDataA).toBe(true);
    expect(usage.writesDataB).toBe(true);
    expect(usage.readsDataC).toBe(true);
  });
});
