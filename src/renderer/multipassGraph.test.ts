import { validateGraph, createRippleTankGraph, resolveGraphForShader } from '../renderer/multipassGraph';

describe('multipassGraph', () => {
  it('validates ripple-tank demo graph', () => {
    const graph = createRippleTankGraph();
    expect(validateGraph(graph)).toEqual([]);
    expect(graph.nodes).toHaveLength(3);
  });

  it('reports missing shaderId on pass nodes', () => {
    const errors = validateGraph({
      id: 'bad',
      nodes: [{ type: 'pass', id: 'x', shaderId: '', readTexture: 'dataC', writeTexture: 'dataA' }],
    });
    expect(errors.length).toBeGreaterThan(0);
  });

  it('resolves graph for quantum-foam multipass starter', () => {
    const graph = resolveGraphForShader('quantum-foam-pass1');
    expect(graph?.id).toBe('quantum-foam-graph');
    expect(resolveGraphForShader('quantum-foam-pass2')).toBeNull();
  });
});
