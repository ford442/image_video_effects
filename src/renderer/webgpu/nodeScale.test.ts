import { createWaveTankGraph, MultipassGraphDef, validateGraph } from '../multipassGraph';
import { createFakeGpu, FakeGpu, summarizeOps } from '../testing/fakeGpu';
import { compileFramePlan, executeFramePlan, FramePlanContext, resetFramePlanWarnings } from './framePlan';
import {
  ISLAND_SCRATCH_BUDGET_BYTES,
  NodeScaleIslands,
  scaledIslandSize,
  snapNodeScale,
} from './nodeScale';
import type { FrameSlotDispatchPlan } from './slotDispatch';
import type { WebGPUTextureSet } from './resources';

const graphWithScalableStep = (): MultipassGraphDef => ({
  maxPassesPerFrame: 8,
  nodes: [
    { id: 'field', entry: 'field', reads: ['read'], writes: ['dataA'], scalable: true, minScale: 0.5 },
    { id: 'render', entry: 'render', reads: ['dataC'], writes: ['color'] },
  ],
});

function plan(graph: MultipassGraphDef): FrameSlotDispatchPlan {
  const slot = { slot: { shaderId: 'g', enabled: true, mode: 'chained' as const, params: [0.5, 0.5, 0.5, 0.5] }, slotIndex: 0, program: { kind: 'graph' as const, graph }, writesDataA: true, writesDataB: false };
  return { enabledCount: 1, parallel: [], chained: [slot], anyReadsDataC: false, anyUsesHistory: false, anyUsesSimRing: false };
}

function ctx(scales: Record<string, number> = {}): FramePlanContext {
  return {
    getPipeline: (id) => ({ label: `pipeline:${id}` } as unknown as GPUComputePipeline),
    getWorkgroupSize: () => ({ x: 16, y: 16 }),
    usesSimRing: () => false,
    simRing: null,
    maxPassesPerFrame: 16,
    framePassBudget: Number.POSITIVE_INFINITY,
    nodeScale: (slot, nodeId) => scales[`${slot}:${nodeId}`] ?? 1,
    warn: () => {},
  };
}

function textureSet(fake: FakeGpu, size = 256): WebGPUTextureSet {
  const t = (label: string) => fake.texture(label, size, size);
  return {
    sourceTex: t('sourceTex'), readTex: t('readTex'), writeTex: t('writeTex'),
    dataTexA: t('dataTexA'), dataTexB: t('dataTexB'), dataTexC: t('dataTexC'),
    historyTex: t('historyTex'), historyLayers: 4,
    depthRead: t('depthRead'), depthWrite: t('depthWrite'), emptyTex: t('emptyTex'),
  };
}

function islandsOn(fake: FakeGpu, size = 256): NodeScaleIslands {
  const islands = new NodeScaleIslands();
  islands.attach({
    device: fake.device,
    colorFormat: 'rgba16float',
    bindGroupLayout: { label: 'computeBGL' } as unknown as GPUBindGroupLayout,
    textures: textureSet(fake, size),
    buffers: {
      uniformBuf: fake.buffer('uniformBuf', 848),
      extraBuf: fake.buffer('extraBuf'),
      plasmaBuf: fake.buffer('plasmaBuf'),
    },
    samplers: {} as never,
    scaledW: size,
    scaledH: size,
  });
  return islands;
}

beforeEach(() => resetFramePlanWarnings());

describe('node scale helpers', () => {
  it('snaps to 0.25 steps between the node floor and 1', () => {
    expect(snapNodeScale(0.6)).toBe(0.5);
    expect(snapNodeScale(0.1)).toBe(0.25);
    expect(snapNodeScale(0.3, 0.5)).toBe(0.5);
    expect(snapNodeScale(2)).toBe(1);
    expect(snapNodeScale(Number.NaN)).toBe(1);
  });

  it('rounds scaled sizes up to whole workgroups', () => {
    expect(scaledIslandSize(1024, 1024, 0.5)).toEqual([512, 512]);
    expect(scaledIslandSize(1000, 600, 0.25)).toEqual([256, 160]);
    expect(scaledIslandSize(20, 20, 0.25)).toEqual([16, 16]);
  });

  it('validates the opt-in fields', () => {
    const bad: MultipassGraphDef = {
      maxPassesPerFrame: 4,
      nodes: [{ id: 'n', entry: 'n', reads: [], writes: ['color'], scalable: true, minScale: 0.3 }],
    };
    expect(validateGraph(bad).join()).toContain('minScale');
    expect(validateGraph(graphWithScalableStep())).toEqual([]);
  });
});

describe('frame plan islands', () => {
  it('wraps only the demoted opt-in node, carrying its declared writes', () => {
    const fp = compileFramePlan(plan(graphWithScalableStep()), ctx({ '0:field': 0.5 }));
    const kinds = fp.ops.map((op) => (op.kind === 'compute' ? `compute:${op.entry}@${op.scale}` : op.kind));
    expect(kinds).toEqual([
      'slotStart',
      'islandEnter',
      'compute:field@0.5',
      'islandExit',
      'copy',
      'compute:render@1',
    ]);
    expect(fp.ops[3]).toMatchObject({ kind: 'islandExit', scale: 0.5, writes: ['dataA'] });
  });

  it('respects minScale and never scales nodes that did not opt in', () => {
    const below = compileFramePlan(plan(graphWithScalableStep()), ctx({ '0:field': 0.25, '0:render': 0.25 }));
    const computes = below.ops.filter((op) => op.kind === 'compute').map((op) => op.kind === 'compute' && op.scale);
    expect(computes).toEqual([0.5, 1]);
    const plain = compileFramePlan(plan(createWaveTankGraph()), ctx({ '0:step': 0.5 }));
    expect(plain.ops.some((op) => op.kind === 'islandEnter')).toBe(false);
  });

  it('executes the island on its scaled bind group and size, or falls back to full size', () => {
    const fake = createFakeGpu();
    const fp = compileFramePlan(plan(graphWithScalableStep()), ctx({ '0:field': 0.5 }));
    const textures = {
      readTex: fake.texture('readTex', 256, 256),
      writeTex: fake.texture('writeTex', 256, 256),
      dataTexA: fake.texture('dataTexA', 256, 256),
      dataTexB: fake.texture('dataTexB', 256, 256),
      dataTexC: fake.texture('dataTexC', 256, 256),
    };
    const base = {
      textures,
      computeBindGroup: { label: 'computeBG' } as unknown as GPUBindGroup,
      simRing: null,
      scaledW: 256,
      scaledH: 256,
    };

    const islands = islandsOn(fake);
    const scales: number[] = [];
    executeFramePlan(fake.device.createCommandEncoder({ label: 'frame' }), fp, { ...base, islands }, {
      timestampWrites: (_op, _i, _n, effective) => {
        scales.push(effective);
        return undefined;
      },
    });
    const ops = summarizeOps(fake.ops);
    expect(ops).toEqual([
      'compute:island-down-read',
      'compute:island-down-dataC',
      'bufcopy:islandParams>uniformBuf',
      'compute:graph-field-0-field',
      'compute:island-up-dataA',
      'bufcopy:islandParams>uniformBuf',
      'copy:dataTexA>dataTexC',
      'compute:graph-render-0-render',
    ]);
    const fieldDispatch = fake.ops.filter((o) => o.op === 'dispatch')[2];
    expect(fieldDispatch).toMatchObject({ x: 8, y: 8 }); // 128² / 16
    expect(scales).toEqual([0.5, 1]);

    fake.reset();
    scales.length = 0;
    executeFramePlan(fake.device.createCommandEncoder({ label: 'frame' }), fp, base, {
      timestampWrites: (_op, _i, _n, effective) => {
        scales.push(effective);
        return undefined;
      },
    });
    expect(summarizeOps(fake.ops)).toEqual([
      'compute:graph-field-0-field',
      'copy:dataTexA>dataTexC',
      'compute:graph-render-0-render',
    ]);
    expect(scales).toEqual([1, 1]);
  });
});

describe('NodeScaleIslands', () => {
  it('allocates one scratch level per scale once and reuses its bind groups', () => {
    const fake = createFakeGpu();
    const islands = islandsOn(fake);
    const encoder = fake.device.createCommandEncoder();
    expect(islands.encodeEnter(encoder, 0.5)).toBe(true);
    islands.encodeExit(encoder, 0.5, ['color', 'dataA']);
    const groupsAfterFirst = fake.counters.createBindGroup;
    expect(islands.encodeEnter(encoder, 0.5)).toBe(true);
    islands.encodeExit(encoder, 0.5, ['color', 'dataA']);
    expect(fake.counters.createBindGroup).toBe(groupsAfterFirst);
    expect(islands.allocatedScales()).toEqual([0.5]);
    expect(islands.size(0.5)).toEqual([128, 128]);
    islands.releaseLevels();
    expect(islands.allocatedScales()).toEqual([]);
  });

  it('refuses a level that would exceed the scratch budget (node then runs full size)', () => {
    const fake = createFakeGpu();
    const big = Math.ceil(Math.sqrt(ISLAND_SCRATCH_BUDGET_BYTES / (5 * 8)) / 0.75) + 64;
    const islands = islandsOn(fake, big);
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    expect(islands.encodeEnter(fake.device.createCommandEncoder(), 0.75)).toBe(false);
    warn.mockRestore();
    expect(islands.allocatedScales()).toEqual([]);
  });
});
