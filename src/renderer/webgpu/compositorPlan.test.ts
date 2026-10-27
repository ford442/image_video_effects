import { defaultSlotLayer, type SlotLayer } from '../layerState';
import { compileFramePlan, resetFramePlanWarnings, type FramePlanContext } from './framePlan';
import type { CompositeOp } from './compositorPlan';
import type { FrameSlotDispatchPlan, SlotDispatchPlan } from './slotDispatch';

const pipeline = (id: string) => ({ label: `pipeline:${id}` } as unknown as GPUComputePipeline);

const ctx: FramePlanContext = {
  getPipeline: (id) => pipeline(id),
  getWorkgroupSize: () => ({ x: 16, y: 16 }),
  usesSimRing: () => false,
  simRing: null,
  maxPassesPerFrame: 16,
  framePassBudget: Number.POSITIVE_INFINITY,
  warn: () => {},
};

function slot(index: number, id: string, mode: 'chained' | 'parallel', layer?: Partial<SlotLayer>): SlotDispatchPlan {
  return {
    slot: {
      shaderId: id,
      enabled: true,
      mode,
      params: [0.5, 0.5, 0.5, 0.5],
      ...(layer ? { layer: { ...defaultSlotLayer(), ...layer } } : {}),
    },
    slotIndex: index,
    program: { kind: 'chain', shaderIds: [id] },
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

/** One token per op, readable in failures. */
function opTokens(slots: SlotDispatchPlan[]): string[] {
  return compileFramePlan(plan(slots), ctx).ops.flatMap((op) => {
    switch (op.kind) {
      case 'compute': return [`compute:${op.entry}`];
      case 'copy': return [`copy:${op.from}>${op.to}`];
      case 'captureLayer': return [`capture:${op.slotIndex}@${op.stackLayer}`];
      case 'composite': return [`composite:${op.group}:${op.layers.map((l) => `${l.slotIndex}${l.output[0]}`).join(',')}`];
      default: return [];
    }
  });
}

function composites(slots: SlotDispatchPlan[]): CompositeOp[] {
  return compileFramePlan(plan(slots), ctx).ops.filter((op): op is CompositeOp => op.kind === 'composite');
}

beforeEach(() => resetFramePlanWarnings());

describe('compositor frame plan', () => {
  it('compiles replace-only stacks exactly as before (no captures, no composite)', () => {
    const slots = [slot(0, 'a', 'parallel'), slot(1, 'b', 'parallel'), slot(2, 'c', 'chained')];
    expect(opTokens(slots)).toEqual([
      'compute:a', 'compute:b', 'copy:writeTex>readTex', 'compute:c', 'copy:writeTex>readTex',
    ]);
    expect(compileFramePlan(plan(slots), ctx).stackLayers).toBe(0);
  });

  it('composites a parallel group in one op after capturing every member', () => {
    const slots = [
      slot(0, 'a', 'parallel'),
      slot(1, 'b', 'parallel', { output: 'blend', blend: 'screen', opacity: 0.5 }),
    ];
    expect(opTokens(slots)).toEqual([
      'compute:a', 'capture:0@0',
      'compute:b', 'capture:1@1',
      'composite:parallel:0r,1b',
      'copy:writeTex>readTex',
    ]);
    const [op] = composites(slots);
    expect(op!.layers[1]).toMatchObject({ blend: 'screen', blendIndex: 2, opacity: 0.5, stackLayer: 1, mask: null });
    expect(compileFramePlan(plan(slots), ctx).stackLayers).toBe(2);
  });

  it('composites a chained slot over its own input (wet/dry)', () => {
    const slots = [slot(0, 'a', 'chained'), slot(1, 'b', 'chained', { output: 'blend', blend: 'normal', opacity: 0.25 })];
    expect(opTokens(slots)).toEqual([
      'compute:a', 'copy:writeTex>readTex',
      'compute:b', 'capture:1@0', 'composite:chained:1b', 'copy:writeTex>readTex',
    ]);
  });

  it('keeps the single-chained output in writeTex when it composites', () => {
    const fp = compileFramePlan(plan([slot(0, 'a', 'chained', { output: 'blend', blend: 'add' })]), ctx);
    expect(fp.output).toBe('writeTex');
    expect(fp.ops.at(-1)).toMatchObject({ kind: 'composite', group: 'chained' });
  });

  it('captures a replace slot only because another layer masks with it', () => {
    const slots = [
      slot(0, 'matte', 'chained'),
      slot(1, 'fx', 'chained', { output: 'blend', blend: 'normal', mask: { source: 'slot', slot: 0 } }),
    ];
    expect(opTokens(slots)).toEqual([
      'compute:matte', 'capture:0@0', 'copy:writeTex>readTex',
      'compute:fx', 'capture:1@1', 'composite:chained:1b', 'copy:writeTex>readTex',
    ]);
    const [op] = composites(slots);
    expect(op!.layers[0]!.mask).toEqual({ source: 'slot', srcStackLayer: 0, srcIsMatte: false, invert: false, feather: 0 });
  });

  it('reads a matte slot by luma and leaves it out of the colour result', () => {
    const slots = [
      slot(0, 'pattern', 'parallel', { output: 'mask' }),
      slot(1, 'fx', 'parallel', { output: 'blend', blend: 'add', mask: { source: 'slot', slot: 0, invert: true, feather: 0.5 } }),
    ];
    const [op] = composites(slots);
    expect(op!.layers.map((l) => l.output)).toEqual(['mask', 'blend']);
    expect(op!.layers[1]!.mask).toEqual({ source: 'slot', srcStackLayer: 0, srcIsMatte: true, invert: true, feather: 0.5 });
  });

  it('resolves a parallel member masking with a later member of the same group', () => {
    const slots = [
      slot(0, 'fx', 'parallel', { output: 'blend', blend: 'normal', mask: { source: 'slot', slot: 1 } }),
      slot(1, 'matte', 'parallel', { output: 'mask' }),
    ];
    const [op] = composites(slots);
    expect(op!.unresolvedMasks).toEqual([]);
    expect(op!.layers[0]!.mask).toMatchObject({ srcStackLayer: 1, srcIsMatte: true });
  });

  it('reports a chained mask on a slot that renders later as unresolved', () => {
    const slots = [
      slot(0, 'fx', 'chained', { output: 'blend', blend: 'normal', opacity: 0.5, mask: { source: 'slot', slot: 1 } }),
      slot(1, 'later', 'chained'),
    ];
    const [op] = composites(slots);
    expect(op!.unresolvedMasks).toEqual([0]);
    expect(op!.layers[0]!.mask).toBeNull();
  });

  it('resolves luma / depth masks against the layer itself', () => {
    const [op] = composites([
      slot(0, 'a', 'parallel', { output: 'blend', blend: 'multiply', mask: { source: 'depth', invert: true } }),
      slot(1, 'b', 'parallel', { output: 'blend', blend: 'luma-key', mask: { source: 'luma' } }),
    ]);
    expect(op!.layers[0]!.mask).toMatchObject({ source: 'depth', srcStackLayer: 0, invert: true });
    expect(op!.layers[1]!).toMatchObject({ key: 0.08, mask: { source: 'luma', srcStackLayer: 1 } });
  });
});
