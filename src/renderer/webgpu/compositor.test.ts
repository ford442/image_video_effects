import { createFakeGpu, summarizeOps } from '../testing/fakeGpu';
import { DEFAULT_SLOT_OUTPUT, type SlotOutput } from '../slotOutput';
import { compileFramePlan, executeFramePlan, resetFramePlanWarnings, type FramePlanContext } from './framePlan';
import type { FrameSlotDispatchPlan, SlotDispatchPlan } from './slotDispatch';
import {
  COMPOSITE_PARAMS_BYTES,
  KEY_SOFTNESS,
  SlotCompositor,
  featherRadiusPx,
  packCompositeParams,
  packMaskParams,
  planCompositeGroup,
} from './compositor';
import { blendChannel, compositePixel, type Rgba } from './compositeReference';

const blend = (patch: Partial<SlotOutput>): SlotOutput => ({ ...DEFAULT_SLOT_OUTPUT, mode: 'blend', ...patch });

beforeEach(() => resetFramePlanWarnings());

describe('planCompositeGroup', () => {
  it('is null when every output replaces (last one wins, unchanged)', () => {
    expect(planCompositeGroup([{ slotIndex: 0 }, { slotIndex: 1, output: { ...DEFAULT_SLOT_OUTPUT } }])).toBeNull();
  });

  it('gives each slot a layer in slot order and resolves slot masks to layers', () => {
    const plan = planCompositeGroup([
      { slotIndex: 1, output: { ...DEFAULT_SLOT_OUTPUT, mode: 'mask' } },
      { slotIndex: 3, output: blend({ blend: 'screen', opacity: 0.5, mask: 'slot1', feather: 0.25 }) },
      { slotIndex: 4, output: blend({ mask: 'slot2' }) },
    ])!;
    expect(plan.layerCount).toBe(3);
    expect(plan.layers.map((l) => [l.slotIndex, l.kind, l.layer])).toEqual([[1, 'mask', 0], [3, 'blend', 1], [4, 'blend', 2]]);
    // A mask-mode source is a luma matte; feather is carried through.
    expect(plan.layers[1]!.mask).toEqual({ source: 'slot', sourceLayer: 0, matte: 'luma', invert: false, feather: 0.25 });
    // slot2 is not in this group: drawn unmasked, with a warning.
    expect(plan.layers[2]!.mask).toBeNull();
    expect(plan.warnings).toHaveLength(1);
  });

  it('uses a blend source slot as an alpha matte and luma / depth as own-layer masks', () => {
    const plan = planCompositeGroup([
      { slotIndex: 0, output: blend({ mask: 'luma', maskInvert: true }) },
      { slotIndex: 1, output: blend({ mask: 'slot0' }) },
      { slotIndex: 2, output: blend({ mask: 'depth' }) },
    ])!;
    expect(plan.layers[0]!.mask).toMatchObject({ source: 'luma', sourceLayer: 0, invert: true });
    expect(plan.layers[1]!.mask).toMatchObject({ source: 'slot', sourceLayer: 0, matte: 'alpha' });
    expect(plan.layers[2]!.mask).toMatchObject({ source: 'depth', sourceLayer: 2 });
  });
});

describe('uniform packing', () => {
  it('lays out CompositeParams as composite.wgsl reads it', () => {
    const plan = planCompositeGroup([
      { slotIndex: 0 },
      { slotIndex: 2, output: blend({ blend: 'screen', opacity: 0.5, mask: 'depth' }) },
    ])!;
    const buf = packCompositeParams(plan);
    expect(buf.byteLength).toBe(COMPOSITE_PARAMS_BYTES);
    const u32 = new Uint32Array(buf);
    const f32 = new Float32Array(buf);
    expect(u32[0]).toBe(2);
    expect([u32[4], u32[5], u32[6], u32[7]]).toEqual([0, 0, 0, 0xffffffff]); // replace, normal, layer 0, no mask
    expect([u32[12], u32[13], u32[14], u32[15]]).toEqual([1, 2, 1, 1]); // blend, screen, layer 1, mask 1
    expect(f32[16]).toBeCloseTo(0.5);
    expect(f32[18]).toBeCloseTo(KEY_SOFTNESS);
    expect(Array.from(packMaskParams({ source: 'slot', sourceLayer: 3, matte: 'luma', invert: true, feather: 0 })))
      .toEqual([3, 3, 1, 1]);
    expect(featherRadiusPx(0.5)).toBe(16);
  });
});

describe('composite reference math (linear light)', () => {
  const base: Rgba = [0.2, 0.4, 0.6, 1];
  const layer: Rgba = [0.8, 0.5, 0.1, 1];

  it('screen at 50% opacity', () => {
    const plan = planCompositeGroup([{ slotIndex: 1, output: blend({ blend: 'screen', opacity: 0.5 }) }])!;
    const out = compositePixel(plan, base, [layer]);
    const expected = [0, 1, 2].map((c) => {
      const s = base[c]! + layer[c]! - base[c]! * layer[c]!;
      return base[c]! + (s - base[c]!) * 0.5;
    });
    out.slice(0, 3).forEach((v, c) => expect(v).toBeCloseTo(expected[c]!, 6));
  });

  it('keeps every mode exact on [0,1] and HDR-safe above it', () => {
    expect(blendChannel('add', 0.25, 0.5)).toBeCloseTo(0.75);
    expect(blendChannel('multiply', 0.5, 0.5)).toBeCloseTo(0.25);
    expect(blendChannel('difference', 0.25, 0.75)).toBeCloseTo(0.5);
    expect(blendChannel('overlay', 0.25, 0.5)).toBeCloseTo(0.25);
    expect(blendChannel('overlay', 0.75, 0.5)).toBeCloseTo(0.75);
    expect(blendChannel('soft-light', 0.5, 0.5)).toBeCloseTo(0.5);
    // Screen never folds an HDR base back below itself.
    expect(blendChannel('screen', 2, 0.5)).toBeCloseTo(2);
    expect(blendChannel('soft-light', 1.5, 0.5)).toBeCloseTo(1.5);
  });

  it('keys on luma and depth with a soft ramp', () => {
    const lumaKey = planCompositeGroup([{ slotIndex: 0, output: blend({ blend: 'luma-key', keyThreshold: 0.5 }) }])!;
    expect(compositePixel(lumaKey, base, [[0.05, 0.05, 0.05, 1]])).toEqual(base);
    expect(compositePixel(lumaKey, base, [[0.9, 0.9, 0.9, 1]])[0]).toBeCloseTo(0.9);
    const depthKey = planCompositeGroup([{ slotIndex: 0, output: blend({ blend: 'depth-key', keyThreshold: 0.5 }) }])!;
    expect(compositePixel(depthKey, base, [layer], 0.1)).toEqual(base);
    expect(compositePixel(depthKey, base, [layer], 0.9)[0]).toBeCloseTo(layer[0]);
  });

  it('masks by another slot and ignores mask-mode layers when drawing', () => {
    const plan = planCompositeGroup([
      { slotIndex: 0, output: { ...DEFAULT_SLOT_OUTPUT, mode: 'mask' } },
      { slotIndex: 1, output: blend({ mask: 'slot0' }) },
    ])!;
    const matte: Rgba = [0.5, 0.5, 0.5, 1]; // luma 0.5
    const out = compositePixel(plan, base, [matte, layer]);
    out.slice(0, 3).forEach((v, c) => expect(v).toBeCloseTo(base[c]! + (layer[c]! - base[c]!) * 0.5, 6));
  });
});

// ── Frame plan + executor ────────────────────────────────────────────────────

const pipeline = (id: string) => ({ label: `pipeline:${id}` } as unknown as GPUComputePipeline);

function ctx(overrides: Partial<FramePlanContext> = {}): FramePlanContext {
  return {
    getPipeline: (id) => (id === 'missing' ? undefined : pipeline(id)),
    getWorkgroupSize: () => ({ x: 16, y: 16 }),
    usesSimRing: () => false,
    simRing: null,
    maxPassesPerFrame: 16,
    framePassBudget: Number.POSITIVE_INFINITY,
    compositing: true,
    warn: () => {},
    ...overrides,
  };
}

function slot(index: number, id: string, mode: 'chained' | 'parallel', output?: SlotOutput): SlotDispatchPlan {
  return {
    slot: { shaderId: id, enabled: true, mode, params: [0.5, 0.5, 0.5, 0.5], output },
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

const kinds = (fp: ReturnType<typeof compileFramePlan>) =>
  fp.ops.filter((op) => op.kind !== 'slotStart').map((op) => {
    if (op.kind === 'compute') return `compute:${op.entry}`;
    if (op.kind === 'copy') return `copy:${op.from}>${op.to}`;
    if (op.kind === 'layerCopy') return `layer:${op.layer}/${op.layerCount}`;
    return op.kind;
  });

describe('compileFramePlan with the compositor', () => {
  it('compiles a replace-only parallel group exactly as before (no copies, no pass)', () => {
    const fp = compileFramePlan(plan([slot(0, 'a', 'parallel'), slot(1, 'b', 'parallel')]), ctx());
    expect(kinds(fp)).toEqual(['compute:a', 'compute:b', 'copy:writeTex>readTex']);
    expect(fp.composites).toEqual([]);
  });

  it('copies each composited slot to a layer and composites once before the group copy', () => {
    const fp = compileFramePlan(plan([
      slot(0, 'base', 'chained'),
      slot(1, 'a', 'parallel'),
      slot(2, 'b', 'parallel', blend({ blend: 'screen', opacity: 0.5 })),
    ]), ctx());
    expect(kinds(fp)).toEqual([
      'compute:a', 'layer:0/2', 'compute:b', 'layer:1/2', 'composite', 'copy:writeTex>readTex',
      // Chained slots are unchanged.
      'compute:base', 'copy:writeTex>readTex',
    ]);
    expect(fp.composites).toHaveLength(1);
  });

  it('leaves a slot that encoded nothing out of the layers', () => {
    const fp = compileFramePlan(plan([
      slot(1, 'missing', 'parallel', blend({ blend: 'add' })),
      slot(2, 'b', 'parallel'),
    ]), ctx());
    // Only a replace slot encoded: back to today's ops, copies removed.
    expect(kinds(fp)).toEqual(['compute:b', 'copy:writeTex>readTex']);
  });

  it('stays last-one-wins while no compositor can run', () => {
    const fp = compileFramePlan(plan([
      slot(1, 'a', 'parallel'),
      slot(2, 'b', 'parallel', blend({ blend: 'screen' })),
    ]), ctx({ compositing: false }));
    expect(kinds(fp)).toEqual(['compute:a', 'compute:b', 'copy:writeTex>readTex']);
  });
});

describe('SlotCompositor on a fake device', () => {
  function run(slots: SlotDispatchPlan[]) {
    const fake = createFakeGpu();
    const compositor = new SlotCompositor();
    compositor.attach({
      device: fake.device, colorFormat: 'rgba16float', scaledW: 64, scaledH: 64, depthTex: fake.texture('depthRead'),
    });
    const fp = compileFramePlan(plan(slots), ctx());
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
      compositor,
    });
    return { fake, compositor };
  }

  it('encodes layer copies, masks with feather, then one composite pass', () => {
    const { fake, compositor } = run([
      slot(0, 'a', 'parallel'),
      slot(1, 'b', 'parallel', blend({ blend: 'screen', opacity: 0.5, mask: 'depth', feather: 0.5 })),
    ]);
    expect(summarizeOps(fake.ops)).toEqual([
      'compute:parallel-a',
      'copy:writeTex>compositor-layers×2',
      'compute:parallel-b',
      'copy:writeTex>compositor-layers×2',
      'render:mask-1>compositor-mask-1',
      'render:feather-h-1>compositor-mask-scratch',
      'render:feather-v-1>compositor-mask-1',
      'compute:composite',
      'copy:writeTex>readTex',
    ]);
    expect(compositor.stats()).toMatchObject({ layers: 2, masks: 1, composites: 1, error: null });
  });

  it('skips the composite (last one wins) without a compositor', () => {
    const fake = createFakeGpu();
    const fp = compileFramePlan(plan([slot(0, 'a', 'parallel', blend({}))]), ctx());
    executeFramePlan(fake.device.createCommandEncoder({ label: 'frame' }), fp, {
      textures: {
        readTex: fake.texture('readTex'), writeTex: fake.texture('writeTex'),
        dataTexA: fake.texture('dataTexA'), dataTexB: fake.texture('dataTexB'), dataTexC: fake.texture('dataTexC'),
      },
      computeBindGroup: { label: 'computeBG' } as unknown as GPUBindGroup,
      simRing: null, scaledW: 64, scaledH: 64,
    });
    expect(summarizeOps(fake.ops)).toEqual(['compute:parallel-a', 'copy:writeTex>readTex']);
  });

  it('frees layers and masks on release and rebuilds at a new size', () => {
    const { compositor, fake } = run([slot(0, 'a', 'parallel', blend({ mask: 'luma' }))]);
    compositor.releaseTextures();
    expect(compositor.stats()).toMatchObject({ layers: 0, masks: 0, textureMiB: 0 });
    compositor.attach({
      device: fake.device, colorFormat: 'rgba16float', scaledW: 128, scaledH: 128, depthTex: fake.texture('depthRead'),
    });
    expect(compositor.available).toBe(true);
  });
});
