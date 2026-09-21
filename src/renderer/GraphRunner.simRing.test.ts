import { GraphRunner, GraphRunnerContext } from './GraphRunner';
import {
  MultipassGraphDef,
  expandGraph,
  trailingBufferCopies,
  validateGraph,
} from './multipassGraph';
import { resolveGraphForShader } from './multipassRegistry';
import type { SimRingBindings } from './webgpu/simRing';

type Op =
  | { kind: 'texCopy' }
  | { kind: 'bufCopy'; src: string; dst: string; bytes: number }
  | { kind: 'pass'; label: string; groups: number[]; dispatch: [number, number, number] };

function mockEncoder(ops: Op[]): GPUCommandEncoder {
  return {
    copyTextureToTexture: () => { ops.push({ kind: 'texCopy' }); },
    copyBufferToBuffer: (
      src: { label: string }, _so: number, dst: { label: string }, _do: number, bytes: number,
    ) => {
      ops.push({ kind: 'bufCopy', src: src.label, dst: dst.label, bytes });
    },
    beginComputePass: ({ label }: { label: string }) => {
      const groups: number[] = [];
      const op: Op = { kind: 'pass', label, groups, dispatch: [0, 0, 0] };
      return {
        setPipeline: () => {},
        setBindGroup: (i: number) => { groups.push(i); },
        dispatchWorkgroups: (x: number, y: number, z: number) => {
          (op as Extract<Op, { kind: 'pass' }>).dispatch = [x, y, z];
        },
        end: () => { ops.push(op); },
      };
    },
  } as unknown as GPUCommandEncoder;
}

function mockRing(stateCount = 4096): SimRingBindings {
  return {
    bindGroup: { label: 'simRingBG' } as unknown as GPUBindGroup,
    stateBuf: { label: 'simState', size: stateCount * 16 } as unknown as GPUBuffer,
    indexBuf: { label: 'simIndex', size: stateCount * 16 } as unknown as GPUBuffer,
    stateCount,
    indexCount: stateCount * 4,
    copyBytes: stateCount * 16,
    truncated: stateCount < 65536,
  };
}

function ctx(overrides: Partial<GraphRunnerContext> = {}): GraphRunnerContext {
  return {
    device: {} as GPUDevice,
    pipelineLayout: {} as GPUPipelineLayout,
    getPipeline: () => ({} as GPUComputePipeline),
    getWorkgroupSize: (id) => (id.includes('walk') || id === 'jacobi-relax'
      ? { x: 64, y: 1 }
      : { x: 16, y: 16 }),
    createBindGroupForRoles: () => ({} as GPUBindGroup),
    textures: {
      read: {} as GPUTexture,
      color: {} as GPUTexture,
      dataA: {} as GPUTexture,
      dataB: {} as GPUTexture,
      dataC: {} as GPUTexture,
    },
    scaledW: 512,
    scaledH: 256,
    maxPassesPerFrame: 16,
    simRing: mockRing(),
    usesSimRing: (id) => id !== 'plain-render',
    ...overrides,
  };
}

/** Jacobi-style: each repeat reads the previous iteration's published snapshot. */
const JACOBI: MultipassGraphDef = {
  maxPassesPerFrame: 8,
  nodes: [
    {
      id: 'relax',
      entry: 'jacobi-relax',
      reads: [],
      writes: [],
      bufferReads: ['simIndex'],
      bufferWrites: ['simState'],
      dispatch: 'simState',
      repeat: 3,
    },
    { id: 'render', entry: 'jacobi-render', reads: ['read'], writes: ['color'], bufferReads: ['simIndex'] },
  ],
};

describe('multipassGraph sim-ring buffer barriers', () => {
  it('publishes simState → simIndex between repeats and before the next reader', () => {
    const expanded = expandGraph(JACOBI);
    expect(expanded.map((d) => d.bufferCopiesBefore.length)).toEqual([0, 1, 1, 1]);
    expect(expanded[1].bufferCopiesBefore[0].reason).toMatch(/between repeats of relax/);
    expect(expanded[3].bufferCopiesBefore[0].reason).toMatch(/before render/);
    expect(expanded.map((d) => d.dispatch)).toEqual(['simState', 'simState', 'simState', 'pixels']);
    // The render reader already consumed the last write, so nothing is left to publish.
    expect(trailingBufferCopies(expanded)).toEqual([]);
  });

  it('adds a trailing publish when the last simState write has no reader this frame', () => {
    const graph: MultipassGraphDef = {
      maxPassesPerFrame: 4,
      nodes: [
        { id: 'read', entry: 'walk-read', reads: [], writes: [], bufferReads: ['simIndex'] },
        { id: 'write', entry: 'walk-write', reads: [], writes: ['color'], bufferWrites: ['simState'] },
      ],
    };
    const expanded = expandGraph(graph);
    expect(expanded.every((d) => d.bufferCopiesBefore.length === 0)).toBe(true);
    expect(trailingBufferCopies(expanded)).toHaveLength(1);
  });

  it('never adds barriers for graphs that only touch simState', () => {
    const graph: MultipassGraphDef = {
      maxPassesPerFrame: 4,
      nodes: [
        { id: 'walk', entry: 'walk', reads: ['dataC'], writes: ['dataA'], bufferWrites: ['simState'], dispatch: 'simState', repeat: 2 },
      ],
    };
    const expanded = expandGraph(graph);
    expect(expanded.flatMap((d) => d.bufferCopiesBefore)).toEqual([]);
    expect(trailingBufferCopies(expanded)).toEqual([]);
  });

  it('rejects writes to simIndex, unknown roles, and particle dispatch without simState', () => {
    const errors = validateGraph({
      maxPassesPerFrame: 4,
      nodes: [
        { id: 'a', entry: 'a', reads: [], writes: [], bufferWrites: ['simIndex'] },
        { id: 'b', entry: 'b', reads: [], writes: [], bufferReads: ['photons' as never] },
        { id: 'c', entry: 'c', reads: ['read'], writes: ['color'], dispatch: 'simState' },
      ],
    });
    expect(errors.join('\n')).toMatch(/"simIndex" is read-only/);
    expect(errors.join('\n')).toMatch(/invalid buffer read role "photons"/);
    expect(errors.join('\n')).toMatch(/dispatch "simState" requires simState/);
  });

  it('accepts a node that only declares buffer roles', () => {
    expect(validateGraph(JACOBI)).toEqual([]);
  });
});

describe('GraphRunner sim ring', () => {
  it('encodes buffer copies in order, binds group 1, and sizes particle dispatches', () => {
    const ops: Op[] = [];
    const report = new GraphRunner().runGraph(mockEncoder(ops), JACOBI, ctx());

    const summary = ops.map((op) => (op.kind === 'pass' ? `pass:${op.label.split('-')[1]}` : op.kind));
    expect(summary).toEqual([
      'pass:relax', 'bufCopy', 'pass:relax', 'bufCopy', 'pass:relax', 'bufCopy', 'pass:render',
    ]);
    const copies = ops.filter((op): op is Extract<Op, { kind: 'bufCopy' }> => op.kind === 'bufCopy');
    expect(copies.every((c) => c.src === 'simState' && c.dst === 'simIndex' && c.bytes === 4096 * 16))
      .toBe(true);

    const passes = ops.filter((op): op is Extract<Op, { kind: 'pass' }> => op.kind === 'pass');
    expect(passes[0].groups).toEqual([0, 1]);
    expect(passes[0].dispatch).toEqual([64, 1, 1]); // 4096 particles / 64
    expect(passes[3].dispatch).toEqual([32, 16, 1]); // 512×256 pixels / 16×16

    expect(report.executed).toBe(4);
    expect(report.errors).toEqual([]);
    expect(report.simRing).toEqual({ particles: 4096, truncated: true, bufferCopies: 3 });
  });

  it('binds group 1 only for pipelines built on the two-group layout', () => {
    const ops: Op[] = [];
    const graph: MultipassGraphDef = {
      maxPassesPerFrame: 4,
      nodes: [
        { id: 'walk', entry: 'walk', reads: [], writes: ['dataA'], bufferWrites: ['simState'], dispatch: 'simState' },
        { id: 'render', entry: 'plain-render', reads: ['dataA'], writes: ['color'] },
      ],
    };
    new GraphRunner().runGraph(mockEncoder(ops), graph, ctx());
    const passes = ops.filter((op): op is Extract<Op, { kind: 'pass' }> => op.kind === 'pass');
    expect(passes.map((p) => p.groups)).toEqual([[0, 1], [0]]);
  });

  it('skips ring nodes (and reports it) when the ring is not allocated', () => {
    const ops: Op[] = [];
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    const report = new GraphRunner().runGraph(mockEncoder(ops), JACOBI, ctx({ simRing: null }));
    warn.mockRestore();

    expect(ops.some((op) => op.kind === 'bufCopy')).toBe(false);
    expect(report.executed).toBe(0);
    expect(report.errors[0]).toMatch(/sim ring not allocated/);
    expect(report.simRing).toEqual({ particles: 0, truncated: false, bufferCopies: 0 });
  });

  it('reports simRing: null and never touches buffers for texture-only graphs', () => {
    const ops: Op[] = [];
    const graph: MultipassGraphDef = {
      maxPassesPerFrame: 4,
      nodes: [
        { id: 'step', entry: 'plain-step', reads: ['dataC'], writes: ['dataA'] },
        { id: 'render', entry: 'plain-render', reads: ['dataA'], writes: ['color'] },
      ],
    };
    const report = new GraphRunner().runGraph(
      mockEncoder(ops),
      graph,
      ctx({ simRing: null, usesSimRing: () => false }),
    );
    expect(report.simRing).toBeNull();
    expect(report.executed).toBe(2);
    expect(ops.some((op) => op.kind === 'bufCopy')).toBe(false);
    const passes = ops.filter((op): op is Extract<Op, { kind: 'pass' }> => op.kind === 'pass');
    expect(passes.every((p) => p.groups.length === 1)).toBe(true);
  });
});

describe('dla-crystals flagship graph', () => {
  it('is valid and dispatches walkers once per particle between two A → C handoffs', () => {
    const graph = resolveGraphForShader('dla-crystals')!;
    expect(validateGraph(graph)).toEqual([]);

    const ringEntries = new Set(['dla-walkers']);
    const ops: Op[] = [];
    const report = new GraphRunner().runGraph(mockEncoder(ops), graph, ctx({
      simRing: mockRing(65536),
      usesSimRing: (id) => ringEntries.has(id),
      getWorkgroupSize: (id) => (id === 'dla-walkers' ? { x: 64, y: 1 } : { x: 16, y: 16 }),
    }));

    const summary = ops.map((op) => (op.kind === 'pass' ? op.label.split('-')[1] : op.kind));
    expect(summary).toEqual(['freeze', 'texCopy', 'walkers', 'texCopy', 'render']);
    const passes = ops.filter((op): op is Extract<Op, { kind: 'pass' }> => op.kind === 'pass');
    expect(passes.map((p) => p.groups)).toEqual([[0], [0, 1], [0]]);
    expect(passes[1].dispatch).toEqual([1024, 1, 1]); // 65536 walkers / 64
    expect(report.simRing).toEqual({ particles: 65536, truncated: false, bufferCopies: 0 });
  });
});
