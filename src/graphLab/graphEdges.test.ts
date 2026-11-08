import { createWaveTankGraph, MultipassGraphDef } from '../renderer/multipassGraph';
import { graphEdges, OUTPUT_NODE, SOURCE_NODE } from './graphEdges';

const brief = (g: MultipassGraphDef) =>
  graphEdges(g).map((e) => `${e.from}>${e.to}:${e.role}${e.feedback ? '~' : ''}${e.via ? `(${e.via})` : ''}`);

describe('graphEdges', () => {
  it('connects source, a step chain through the dataA → dataC handoff, and the display', () => {
    const g: MultipassGraphDef = {
      maxPassesPerFrame: 8,
      nodes: [
        { id: 'step', entry: 's', reads: ['read', 'dataC'], writes: ['dataA'] },
        { id: 'render', entry: 'r', reads: ['dataC'], writes: ['color'] },
      ],
    };
    expect(brief(g)).toEqual([
      `${SOURCE_NODE}>0:read`,
      '0>0:dataC~(dataA → dataC)',
      '0>1:dataC(dataA → dataC)',
      `1>${OUTPUT_NODE}:color`,
    ]);
  });

  it('marks reads that only the previous frame satisfies as feedback', () => {
    const g: MultipassGraphDef = {
      maxPassesPerFrame: 8,
      nodes: [
        { id: 'a', entry: 'a', reads: ['dataB'], writes: ['color'] },
        { id: 'b', entry: 'b', reads: [], writes: ['dataB'] },
      ],
    };
    expect(brief(g)).toContain('1>0:dataB~');
  });

  it('routes simIndex reads through the simState snapshot', () => {
    const g: MultipassGraphDef = {
      maxPassesPerFrame: 8,
      nodes: [
        { id: 'walk', entry: 'w', reads: ['simState'], writes: ['simState'], dispatch: 'simState' },
        { id: 'draw', entry: 'd', reads: ['simIndex'], writes: ['color'] },
      ],
    };
    expect(brief(g)).toContain('0>1:simIndex(simState → simIndex)');
  });

  it('routes simHash reads through the simState writer (the planner builds the hash from it)', () => {
    const g: MultipassGraphDef = {
      maxPassesPerFrame: 8,
      nodes: [
        { id: 'march', entry: 'm', reads: [], writes: ['simState'], dispatch: 'simState' },
        { id: 'splat', entry: 's', reads: ['simHash', 'simIndex'], writes: ['color'] },
      ],
    };
    expect(brief(g)).toEqual(
      expect.arrayContaining(['0>1:simHash(simState → simHash)', '0>1:simIndex(simState → simIndex)']),
    );
  });

  it('derives edges for the shipped wave-tank graph without throwing', () => {
    const edges = graphEdges(createWaveTankGraph());
    expect(edges.some((e) => e.to === OUTPUT_NODE)).toBe(true);
    expect(new Set(edges.map((e) => e.id)).size).toBe(edges.length);
  });
});
