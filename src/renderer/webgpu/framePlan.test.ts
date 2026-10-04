import { createWaveTankGraph, MultipassGraphDef } from '../multipassGraph';
import { QUALITY_PRESETS } from '../../config/performancePolicy';
import { framePassBudgetFor } from '../performanceStatus';
import { createFakeGpu, summarizeOps } from '../testing/fakeGpu';
import {
  allocateGraphCaps,
  compileFramePlan,
  executeFramePlan,
  FramePlanContext,
  resetFramePlanWarnings,
} from './framePlan';
import type { FrameSlotDispatchPlan, SlotDispatchPlan } from './slotDispatch';

const pipeline = (id: string) => ({ label: `pipeline:${id}` } as unknown as GPUComputePipeline);

function ctx(overrides: Partial<FramePlanContext> = {}): FramePlanContext {
  return {
    getPipeline: (id) => pipeline(id),
    getWorkgroupSize: () => ({ x: 16, y: 16 }),
    usesSimRing: () => false,
    simRing: null,
    maxPassesPerFrame: 16,
    framePassBudget: Number.POSITIVE_INFINITY,
    warn: () => {},
    ...overrides,
  };
}

function slot(index: number, program: SlotDispatchPlan['program'], mode: 'chained' | 'parallel' = 'chained'): SlotDispatchPlan {
  const shaderId = program.kind === 'chain' ? program.shaderIds[0] : `graph-${index}`;
  return {
    slot: { shaderId, enabled: true, mode, params: [0.5, 0.5, 0.5, 0.5] },
    slotIndex: index,
    program,
    writesDataA: false,
    writesDataB: false,
  };
}

function plan(slots: SlotDispatchPlan[]): FrameSlotDispatchPlan {
  return {
    enabledCount: slots.length,
    parallel: slots.filter((s) => s.slot.mode === 'parallel'),
    chained: slots.filter((s) => s.slot.mode === 'chained'),
    anyReadsDataC: false,
    anyUsesHistory: false,
    anyUsesSimRing: false,
  };
}

const chain = (...ids: string[]) => ({ kind: 'chain' as const, shaderIds: ids });
const graph = (g: MultipassGraphDef = createWaveTankGraph()) => ({ kind: 'graph' as const, graph: g });

beforeEach(() => resetFramePlanWarnings());

describe('frame pass budget', () => {
  it('derives battery / balanced / ultra budgets from passes × slots', () => {
    expect(framePassBudgetFor(QUALITY_PRESETS.battery)).toBe(4);
    expect(framePassBudgetFor(QUALITY_PRESETS.balanced)).toBe(16);
    expect(framePassBudgetFor(QUALITY_PRESETS.ultra)).toBe(48);
    expect(framePassBudgetFor(QUALITY_PRESETS.battery, 6)).toBe(24);
  });

  it('charges linear chains first and shares the rest between graphs, never below 1', () => {
    // wave-tank graph wants 5 passes (step ×3, inject, render).
    expect(allocateGraphCaps([chain('a', 'b'), graph(), graph()], 8, 100)).toEqual([0, 8, 8]);
    expect(allocateGraphCaps([chain('a', 'b'), graph(), graph()], 8, 9)).toEqual([0, 7, 2]);
    expect(allocateGraphCaps([chain('a', 'b', 'c', 'd'), graph()], 8, 4)).toEqual([0, 1]);
  });

  it('truncates a graph to the frame budget while keeping its color writer', () => {
    const fp = compileFramePlan(plan([slot(0, chain('a', 'b', 'c')), slot(1, graph())]), ctx({ framePassBudget: 5 }));
    const computes = fp.ops.filter((op) => op.kind === 'compute').map((op) => op.kind === 'compute' && op.entry);
    expect(computes).toEqual(['a', 'b', 'c', 'wave-step', 'wave-render']);
    expect(fp.graphReports[0]).toMatchObject({ requested: 5, executed: 2, truncated: 3 });
  });

  it('leaves per-graph caps alone when the frame budget is unbounded', () => {
    const fp = compileFramePlan(plan([slot(0, chain('a', 'b', 'c')), slot(1, graph())]), ctx());
    expect(fp.computeCount).toBe(8);
    expect(fp.graphReports[0]).toMatchObject({ executed: 5, truncated: 0 });
  });
});

describe('compileFramePlan', () => {
  it('records slot index, entry and output texture', () => {
    const single = compileFramePlan(plan([slot(2, chain('a'))]), ctx());
    expect(single.output).toBe('writeTex');
    const compute = single.ops.find((op) => op.kind === 'compute');
    expect(compute).toMatchObject({ slotIndex: 2, entry: 'a', shaderId: 'a', mode: 'chained' });

    const two = compileFramePlan(plan([slot(0, chain('a')), slot(1, chain('b'))]), ctx());
    expect(two.output).toBe('readTex');
  });

  it('skips missing pipelines and unarmed sim-ring passes, warning once', () => {
    const warn = jest.fn();
    const c = ctx({
      getPipeline: (id) => (id === 'missing' ? undefined : pipeline(id)),
      usesSimRing: (id) => id === 'ringy',
      warn,
    });
    const p = plan([slot(0, chain('missing', 'ringy', 'ok'))]);
    const fp = compileFramePlan(p, c);
    compileFramePlan(p, c);
    expect(fp.computeCount).toBe(1);
    expect(warn).toHaveBeenCalledTimes(2);
  });

  it('reports invalid graphs without encoding them', () => {
    const warn = jest.fn();
    const bad: MultipassGraphDef = { maxPassesPerFrame: 0, nodes: [] };
    const fp = compileFramePlan(plan([slot(0, graph(bad))]), ctx({ warn }));
    expect(fp.computeCount).toBe(0);
    expect(fp.graphReports[0].errors.length).toBeGreaterThan(0);
    expect(warn).toHaveBeenCalledTimes(1);
  });
});

describe('executeFramePlan', () => {
  it('asks for timestamp writes with the pass index and the compiled pass count', () => {
    const fake = createFakeGpu();
    const fp = compileFramePlan(plan([slot(0, chain('a', 'b')), slot(1, chain('c'))]), ctx());
    const seen: Array<[string, number, number]> = [];
    const encoder = fake.device.createCommandEncoder({ label: 'frame' });
    executeFramePlan(encoder, fp, {
      textures: {
        readTex: fake.texture('readTex'),
        writeTex: fake.texture('writeTex'),
        dataTexA: fake.texture('dataTexA'),
        dataTexB: fake.texture('dataTexB'),
        dataTexC: fake.texture('dataTexC'),
      },
      computeBindGroup: { label: 'computeBG' } as unknown as GPUBindGroup,
      simRing: null,
      scaledW: 64,
      scaledH: 64,
    }, {
      timestampWrites: (op, index, count) => {
        seen.push([op.entry, index, count]);
        return index === count - 1
          ? { querySet: {} as GPUQuerySet, endOfPassWriteIndex: 1 }
          : undefined;
      },
    });
    expect(seen).toEqual([['a', 0, 3], ['b', 1, 3], ['c', 2, 3]]);
    expect(summarizeOps(fake.ops)).toEqual([
      'compute:chained-a',
      'compute:chained-b',
      'copy:writeTex>readTex',
      'compute:chained-c ts(-,1)',
      'copy:writeTex>readTex',
    ]);
  });
});
