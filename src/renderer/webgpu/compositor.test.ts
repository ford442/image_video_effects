import { createFakeGpu, summarizeOps } from '../testing/fakeGpu';
import { referenceComposite } from '../testing/compositorReference';
import { defaultSlotLayer, type SlotLayer } from '../layerState';
import {
  COMPOSITE_PARAMS_BYTES,
  COMPOSITE_WGSL,
  COMPOSITOR_STACK_BUDGET_BYTES,
  FEATHER_WGSL,
  LayerCompositor,
  MASK_WGSL,
  featherRadiusPx,
  packCompositeParams,
  packMaskParams,
  stackBytes,
} from './compositor';
import { LayerStackBuilder, type CompositeLayer } from './compositorPlan';
import { executeFramePlan, type FramePlan } from './framePlan';
import { rewriteWgslStorageFormats } from '../wgslFormatRewrite';
import { loadRealNaga } from '../../test-utils/nagaWasmNode';
import type { ShaderSlot } from './webgpuConstants';

function layer(overrides: Partial<CompositeLayer> = {}): CompositeLayer {
  return {
    slotIndex: 0,
    stackLayer: 0,
    output: 'blend',
    blend: 'screen',
    blendIndex: 2,
    opacity: 0.5,
    key: 0.5,
    mask: null,
    ...overrides,
  };
}

function shaderSlot(id: string, layerState?: Partial<SlotLayer>): ShaderSlot {
  return {
    shaderId: id,
    enabled: true,
    mode: 'parallel',
    ...(layerState ? { layer: { ...defaultSlotLayer(), ...layerState } } : {}),
  };
}

function setup(size = 64) {
  const fake = createFakeGpu();
  const textures = {
    readTex: fake.texture('readTex', size, size),
    writeTex: fake.texture('writeTex', size, size),
    dataTexA: fake.texture('dataTexA', size, size),
    dataTexB: fake.texture('dataTexB', size, size),
    dataTexC: fake.texture('dataTexC', size, size),
  };
  const compositor = new LayerCompositor();
  compositor.attach({
    device: fake.device,
    colorFormat: 'rgba16float',
    readTex: textures.readTex,
    writeTex: textures.writeTex,
    depthTex: fake.texture('depthRead', size, size),
    scaledW: size,
    scaledH: size,
  });
  return { fake, textures, compositor };
}

/** A two-slot parallel plan: slot 0 replace, slot 1 `blendLayer`. */
function parallelPlan(blendLayer: Partial<SlotLayer>): FramePlan {
  const stack = new LayerStackBuilder();
  const plans = [
    { slotIndex: 0, slot: shaderSlot('a') },
    { slotIndex: 1, slot: shaderSlot('b', { output: 'blend', ...blendLayer }) },
  ];
  const ops: FramePlan['ops'] = [];
  for (const p of plans) ops.push(stack.capture(p.slotIndex, p.slot)!);
  ops.push(stack.composite('parallel', plans));
  return { ops, computeCount: 0, output: 'readTex', graphReports: [], stackLayers: stack.size };
}

describe('packCompositeParams', () => {
  it('matches composite.wgsl Params (info + Layer{mode u32×4, amount f32×4})', () => {
    const buf = packCompositeParams([
      layer({ output: 'replace', blendIndex: 0, stackLayer: 0, opacity: 1 }),
      layer({ stackLayer: 1, mask: { source: 'luma', srcStackLayer: 1, srcIsMatte: false, invert: false, feather: 0 } }),
    ]);
    expect(buf.byteLength).toBe(COMPOSITE_PARAMS_BYTES);
    const u32 = new Uint32Array(buf);
    const f32 = new Float32Array(buf);
    expect(u32[0]).toBe(2);
    expect([...u32.slice(4, 8)]).toEqual([0, 0, 0, 0]);
    expect([...u32.slice(12, 16)]).toEqual([1, 2, 1, 1]);
    expect(f32[16]).toBeCloseTo(0.5);
    expect(f32[18]).toBeCloseTo(0.04);
  });

  it('packs mask draws (source, source layer, invert, matte, own layer)', () => {
    const u32 = new Uint32Array(packMaskParams(layer({
      stackLayer: 3,
      mask: { source: 'slot', srcStackLayer: 1, srcIsMatte: true, invert: true, feather: 0 },
    })));
    expect([...u32]).toEqual([3, 1, 1, 1, 3, 0, 0, 0]);
  });
});

describe('LayerCompositor encoding', () => {
  it('captures, masks, feathers and composites in order, with no bind-group churn after the first frame', () => {
    const { fake, textures, compositor } = setup();
    const plan = parallelPlan({ blend: 'screen', opacity: 0.5, mask: { source: 'luma', feather: 0.5 } });
    const run = () => {
      const encoder = fake.device.createCommandEncoder({ label: 'frame' });
      executeFramePlan(encoder, plan, {
        textures,
        computeBindGroup: { label: 'computeBG' } as unknown as GPUBindGroup,
        simRing: null,
        scaledW: 64,
        scaledH: 64,
        compositor,
      });
    };
    run();
    expect(summarizeOps(fake.ops)).toEqual([
      'copy:writeTex>compositorLayers',
      'copy:writeTex>compositorLayers',
      'render:composite-mask-1>compositorMasks',
      'render:composite-mask-1-feather-x>compositorFeatherScratch',
      'render:composite-mask-1-feather-y>compositorMasks',
      'compute:composite-parallel-0+1',
    ]);
    expect(compositor.allocatedLayers()).toBe(2);
    expect(compositor.lastFrameComposites).toBe(1);

    fake.reset();
    run();
    expect(fake.counters.createBindGroup).toBe(0);
    expect(summarizeOps(fake.ops)).toHaveLength(6);
  });

  it('skips compositor ops (replace semantics) when the stack is over budget', () => {
    const size = 5000;
    expect(stackBytes(2, size, size, 'rgba16float')).toBeGreaterThan(COMPOSITOR_STACK_BUDGET_BYTES);
    const { fake, textures, compositor } = setup(size);
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const encoder = fake.device.createCommandEncoder({ label: 'frame' });
    executeFramePlan(encoder, parallelPlan({ blend: 'add' }), {
      textures,
      computeBindGroup: { label: 'computeBG' } as unknown as GPUBindGroup,
      simRing: null,
      scaledW: size,
      scaledH: size,
      compositor,
    });
    expect(summarizeOps(fake.ops)).toEqual([]);
    expect(warn).toHaveBeenCalledTimes(1);
    warn.mockRestore();
  });

  it('frees the stack when the working size changes', () => {
    const { fake, textures, compositor } = setup();
    expect(compositor.prepare(3)).toBe(true);
    expect(compositor.allocatedLayers()).toBe(3);
    compositor.attach({
      device: fake.device,
      colorFormat: 'rgba16float',
      readTex: textures.readTex,
      writeTex: textures.writeTex,
      depthTex: fake.texture('depthRead'),
      scaledW: 32,
      scaledH: 32,
    });
    expect(compositor.allocatedLayers()).toBe(0);
  });

  it('scales the feather radius with the working height', () => {
    expect(featherRadiusPx(1, 1024)).toBe(24);
    expect(featherRadiusPx(0.5, 2048)).toBe(24);
    expect(featherRadiusPx(0, 1024)).toBe(0);
  });
});

describe('compositor reference math', () => {
  it('screen at 50% over a replace base', () => {
    const out = referenceComposite([0, 0, 0, 1], [
      { output: 'replace', blend: 'normal', opacity: 1, color: [0.5, 0.2, 0, 1] },
      { output: 'blend', blend: 'screen', opacity: 0.5, color: [0.5, 0.5, 1, 1] },
    ]);
    // screen(0.5, 0.5) = 0.75 → mix(0.5, 0.75, 0.5) = 0.625
    expect(out[0]).toBeCloseTo(0.625);
    expect(out[1]).toBeCloseTo(0.2 + (0.6 - 0.2) * 0.5);
    expect(out[2]).toBeCloseTo(0.5);
  });

  it('keeps HDR highlights through add and screen', () => {
    expect(referenceComposite([2, 0, 0, 1], [{ output: 'blend', blend: 'screen', opacity: 1, color: [0.5, 0, 0, 1] }])[0])
      .toBeCloseTo(2);
    expect(referenceComposite([1.5, 0, 0, 1], [{ output: 'blend', blend: 'add', opacity: 1, color: [1, 0, 0, 1] }])[0])
      .toBeCloseTo(2.5);
  });

  it('ignores matte layers and applies masks multiplicatively', () => {
    const base: [number, number, number, number] = [0.2, 0.2, 0.2, 1];
    expect(referenceComposite(base, [{ output: 'mask', blend: 'normal', opacity: 1, color: [1, 1, 1, 1] }])).toEqual(base);
    const masked = referenceComposite(base, [{ output: 'blend', blend: 'normal', opacity: 1, mask: 0.25, color: [1, 1, 1, 1] }]);
    expect(masked[0]).toBeCloseTo(0.4);
  });
});

describe('compositor WGSL', () => {
  it('validates under naga in both colour tiers', async () => {
    const naga = await loadRealNaga();
    for (const format of ['rgba16float', 'rgba32float'] as const) {
      const result = naga.validate(rewriteWgslStorageFormats(COMPOSITE_WGSL, format));
      expect(result.message ?? '').toBe('');
      expect(result.ok).toBe(true);
    }
    expect(naga.validate(MASK_WGSL).ok).toBe(true);
    expect(naga.validate(FEATHER_WGSL).ok).toBe(true);
  });
});
