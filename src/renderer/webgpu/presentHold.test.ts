/**
 * Cue crossfade hold (presentHold.ts): one copy per cue, one linear mix in the present
 * pass, a cut — never a thrown frame — when the hold cannot exist. Driven over the fake
 * device; the real shader math runs on SwiftShader in tests/ (no GPU needed here).
 */

import { createFakeGpu, FakeGpu, summarizeOps } from '../testing/fakeGpu';
import { createFakeFrameState } from '../testing/fakeFrameState';
import type { WebGPUFrameState } from './frameState';
import { crossfadeMix } from '../../utils/transitionMath';
import { HOLD_FORMAT, PresentHold } from './presentHold';

interface Harness {
  fake: FakeGpu;
  state: WebGPUFrameState;
  hold: PresentHold;
  canvas: GPUTexture;
  textures: Array<{ desc: GPUTextureDescriptor; destroy: ReturnType<typeof vi.fn> }>;
  clock: { now: number };
  /** Encode one frame the way the presenter does: optional capture first, then the present's binding. */
  frame(opts?: { capture?: boolean; generative?: boolean }): ReturnType<PresentHold['presentBinding']>;
}

function harness(): Harness {
  const fake = createFakeGpu();
  const state = createFakeFrameState(fake, { size: 64 });
  const textures: Harness['textures'] = [];
  const createTexture = fake.device.createTexture.bind(fake.device);
  fake.device.createTexture = ((desc: GPUTextureDescriptor) => {
    const texture = createTexture(desc) as GPUTexture & { destroy: ReturnType<typeof vi.fn> };
    texture.destroy = vi.fn();
    textures.push({ desc, destroy: texture.destroy });
    return texture;
  }) as GPUDevice['createTexture'];
  const clock = { now: 1000 };
  const hold = new PresentHold(() => clock.now);
  const self: Harness = {
    fake,
    state,
    hold,
    canvas: fake.texture('canvas', 64, 64),
    textures,
    clock,
    frame({ capture = true, generative = false } = {}) {
      const encoder = fake.device.createCommandEncoder({ label: 'frame' });
      if (capture) hold.encodeCapture(state, encoder, generative);
      const binding = hold.presentBinding(state, self.canvas);
      fake.device.queue.submit([encoder.finish()]);
      hold.afterSubmit();
      return binding;
    },
  };
  return self;
}

const flushVerdict = () => new Promise<void>((resolve) => setTimeout(resolve, 0));

describe('PresentHold', () => {
  it('has nothing to dissolve from before the first present, and a duration of 0 is a cut', () => {
    const h = harness();
    expect(h.hold.start(h.state, 2000, false)).toBe(false);
    expect(h.hold.start(h.state, 0, true)).toBe(false);
    expect(h.hold.start(h.state, Number.NaN, true)).toBe(false);
    expect(h.textures).toHaveLength(0);
    expect(h.hold.active).toBe(false);
    expect(h.frame()).toBeNull();
  });

  it('builds no pipeline and no texture until a cue starts', () => {
    const h = harness();
    h.frame({ capture: false });
    expect(h.fake.counters.createRenderPipeline).toBe(0);
    expect(h.textures).toHaveLength(0);
  });

  it('copies the last presented picture once, into one canvas-sized rgba8unorm texture', () => {
    const h = harness();
    expect(h.hold.start(h.state, 2000, true)).toBe(true);
    expect(h.hold.hasPending).toBe(true);

    h.frame();
    expect(h.textures).toHaveLength(1);
    expect(h.textures[0]!.desc).toMatchObject({ size: [64, 64, 1], format: HOLD_FORMAT });
    expect(summarizeOps(h.fake.ops)).toEqual(['render:crossfadeCapture>crossfadeHold']);
    const capture = h.fake.ops.filter((o) => o.op === 'setPipeline' || o.op === 'setBindGroup');
    expect(capture).toEqual([
      { op: 'setPipeline', label: 'crossfade-blit-standard-rgba8unorm' },
      { op: 'setBindGroup', index: 0, label: 'blitBG' },
    ]);
    expect(h.hold.hasPending).toBe(false);

    // Later frames of the same cue copy nothing and allocate nothing.
    h.fake.ops.length = 0;
    h.clock.now += 100;
    h.frame();
    h.clock.now += 100;
    h.frame();
    expect(h.fake.ops).toEqual([]);
    expect(h.textures).toHaveLength(1);
  });

  it('captures the orientation the last present used', () => {
    const h = harness();
    h.hold.start(h.state, 2000, true);
    h.frame({ generative: true });
    expect(h.fake.ops.find((o) => o.op === 'setPipeline')).toEqual({
      op: 'setPipeline',
      label: 'crossfade-blit-y-up-rgba8unorm',
    });
  });

  it('ramps the mix from the hold to the live frame with the orchestrator curve, then lets go', () => {
    const h = harness();
    h.hold.start(h.state, 2000, true);

    const mixes: number[] = [];
    for (let elapsed = 0; elapsed < 2000; elapsed += 250) {
      h.clock.now = 1000 + elapsed;
      const binding = h.frame();
      expect(binding).not.toBeNull();
      mixes.push(binding!.mix);
      expect(binding!.bindGroup).toMatchObject({ label: 'crossfadeHoldBG' });
    }
    expect(mixes[0]).toBe(1);
    mixes.forEach((mix, i) => expect(mix).toBeCloseTo(crossfadeMix((i * 250) / 2000), 12));
    expect([...mixes].sort((a, b) => b - a)).toEqual(mixes);

    h.clock.now = 1000 + 2000;
    expect(h.frame()).toBeNull();
    expect(h.hold.active).toBe(false);
    // The texture is released with the frame after the ramp, not kept around.
    expect(h.textures[0]!.destroy).toHaveBeenCalledTimes(1);
    expect(h.frame()).toBeNull();
  });

  it('writes the mix to the present-only uniform, once per presented frame', () => {
    const h = harness();
    h.hold.start(h.state, 1000, true);
    h.frame();
    const afterCapture = h.fake.counters.writeBuffer;
    h.clock.now += 250;
    h.frame();
    h.clock.now += 250;
    h.frame();
    expect(h.fake.counters.writeBuffer - afterCapture).toBe(2);
  });

  it('offers a Y-up and a standard mix pipeline over the target format', () => {
    const h = harness();
    h.hold.start(h.state, 1000, true);
    const binding = h.frame()!;
    expect(binding.standard).toMatchObject({ label: 'crossfade-mix-standard-bgra8unorm' });
    expect(binding.generative).toMatchObject({ label: 'crossfade-mix-y-up-bgra8unorm' });
    expect(binding.standard).not.toBe(binding.generative);

    // Pipelines are cached per (kind, orientation, format): no rebuild on later frames.
    const built = h.fake.counters.createRenderPipeline;
    h.clock.now += 100;
    h.frame();
    expect(h.fake.counters.createRenderPipeline).toBe(built);
  });

  it('a cue during a cue replaces the hold with the current present and restarts the ramp', () => {
    const h = harness();
    h.hold.start(h.state, 1000, true);
    h.frame();
    h.clock.now += 500;
    expect(h.frame()!.mix).toBeCloseTo(0.5, 12);

    h.fake.ops.length = 0;
    h.hold.start(h.state, 1000, true);
    h.hold.start(h.state, 3000, true); // two cues before a frame: only the last survives
    const restarted = h.frame()!;

    // The old hold is re-copied under the live frame at the weight it was last presented.
    expect(summarizeOps(h.fake.ops)).toEqual(['render:crossfadeCapture>crossfadeHold']);
    expect(h.fake.ops.filter((o) => o.op === 'setPipeline')).toEqual([
      { op: 'setPipeline', label: 'crossfade-mix-standard-rgba8unorm' },
    ]);
    expect(h.fake.ops.filter((o) => o.op === 'setBindGroup')).toEqual([
      { op: 'setBindGroup', index: 0, label: 'blitBG' },
      { op: 'setBindGroup', index: 1, label: 'crossfadeHoldBG' },
    ]);
    expect(restarted.mix).toBe(1);

    // Three textures in all (first cue, discarded second cue, last cue); only one stays alive.
    expect(h.textures).toHaveLength(3);
    expect(h.textures.map((t) => t.destroy.mock.calls.length)).toEqual([1, 1, 0]);

    // The restarted ramp runs the new duration from now.
    h.clock.now += 1500;
    expect(h.frame()!.mix).toBeCloseTo(crossfadeMix(0.5), 12);
  });

  it('a duration of 0 during a fade ends it at once', () => {
    const h = harness();
    h.hold.start(h.state, 2000, true);
    h.frame();
    h.clock.now += 100;
    expect(h.frame()).not.toBeNull();

    expect(h.hold.start(h.state, 0, true)).toBe(false);
    expect(h.hold.active).toBe(false);
    h.clock.now += 100;
    expect(h.frame()).toBeNull();
    expect(h.textures[0]!.destroy).toHaveBeenCalledTimes(1);
  });

  it('cuts when the canvas no longer matches the hold', () => {
    const h = harness();
    h.hold.start(h.state, 2000, true);
    h.frame();
    Object.assign(h.state, { canvasW: 128, canvasH: 128 });
    h.canvas = h.fake.texture('canvas', 128, 128);
    h.clock.now += 100;
    expect(h.frame()).toBeNull();
    expect(h.hold.active).toBe(false);
  });

  it('drops a pending cue whose canvas changed before its capture', () => {
    const h = harness();
    h.hold.start(h.state, 2000, true);
    Object.assign(h.state, { canvasW: 32, canvasH: 32 });
    expect(h.frame()).toBeNull();
    expect(h.fake.ops).toEqual([]);
    expect(h.textures[0]!.destroy).toHaveBeenCalledTimes(1);
  });

  it('release frees a running fade and starts clean on the next cue', () => {
    const h = harness();
    h.hold.start(h.state, 2000, true);
    h.frame();
    h.hold.release();
    expect(h.textures[0]!.destroy).toHaveBeenCalledTimes(1);
    expect(h.hold.active).toBe(false);
    expect(h.hold.start(h.state, 2000, true)).toBe(true);
  });

  it('forgets everything when the renderer moves to a new device', () => {
    const h = harness();
    h.hold.start(h.state, 2000, true);
    h.frame();
    const next = createFakeGpu();
    const nextState = createFakeFrameState(next, { size: 64 });
    expect(h.hold.start(nextState, 1000, true)).toBe(true);
    expect(h.textures[0]!.destroy).toHaveBeenCalledTimes(1);
    expect(h.hold.hasPending).toBe(true);
  });

  describe('when the hold cannot be allocated', () => {
    it('takes the allocation inside its own out-of-memory and validation scopes', () => {
      const h = harness();
      const push = vi.spyOn(h.fake.device, 'pushErrorScope');
      const pop = vi.spyOn(h.fake.device, 'popErrorScope');
      h.hold.start(h.state, 2000, true);
      // Balanced and sync: the renderer's own OOM handler (working-size cap) never sees this error.
      expect(push.mock.calls.map((c) => c[0])).toEqual(['out-of-memory', 'validation']);
      expect(pop).toHaveBeenCalledTimes(2);
    });

    it('cuts once on an out-of-memory verdict and keeps rendering', async () => {
      const h = harness();
      const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
      let pops = 0;
      // Inner (validation) pops first, then the outer out-of-memory scope.
      h.fake.device.popErrorScope = (() =>
        Promise.resolve(++pops === 2 ? ({ message: 'out of memory' } as GPUError) : null)) as GPUDevice['popErrorScope'];

      expect(h.hold.start(h.state, 2000, true)).toBe(true); // the verdict is asynchronous
      await flushVerdict();

      expect(h.hold.active).toBe(false);
      expect(warn).toHaveBeenCalledWith(expect.stringContaining('allocation failed'));
      expect(() => h.frame()).not.toThrow();
      expect(h.frame()).toBeNull();
      expect(h.fake.ops).toEqual([]); // no capture was encoded for the dead cue
      expect(h.textures[0]!.destroy).toHaveBeenCalledTimes(1);

      // No retry on its own, and the next cue gets a fresh try.
      expect(h.textures).toHaveLength(1);
      h.fake.device.popErrorScope = (() => Promise.resolve(null)) as GPUDevice['popErrorScope'];
      expect(h.hold.start(h.state, 2000, true)).toBe(true);
      await flushVerdict();
      expect(h.hold.active).toBe(true);
      warn.mockRestore();
    });

    it('stops a running ramp when the verdict arrives late', async () => {
      const h = harness();
      const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
      let release!: (error: GPUError | null) => void;
      let pops = 0;
      h.fake.device.popErrorScope = (() =>
        ++pops === 2 ? new Promise<GPUError | null>((r) => { release = r; }) : Promise.resolve(null)) as GPUDevice['popErrorScope'];

      h.hold.start(h.state, 2000, true);
      expect(h.frame()).not.toBeNull(); // optimistic first frame
      release({ message: 'out of memory' } as GPUError);
      await flushVerdict();

      h.clock.now += 100;
      expect(h.frame()).toBeNull();
      expect(h.hold.active).toBe(false);
      warn.mockRestore();
    });

    it('cuts when creating the texture throws', () => {
      const h = harness();
      const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
      h.fake.device.createTexture = (() => {
        throw new Error('device lost');
      }) as GPUDevice['createTexture'];
      expect(() => h.hold.start(h.state, 2000, true)).not.toThrow();
      expect(h.hold.start(h.state, 2000, true)).toBe(false);
      expect(h.hold.active).toBe(false);
      expect(h.frame()).toBeNull();
      warn.mockRestore();
    });

    it('cuts when the capture pass cannot be encoded', () => {
      const h = harness();
      const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
      h.hold.start(h.state, 2000, true);
      h.fake.device.createRenderPipeline = (() => {
        throw new Error('no pipeline');
      }) as GPUDevice['createRenderPipeline'];
      expect(() => h.frame()).not.toThrow();
      expect(h.hold.active).toBe(false);
      expect(h.textures[0]!.destroy).toHaveBeenCalledTimes(1);
      warn.mockRestore();
    });
  });
});
