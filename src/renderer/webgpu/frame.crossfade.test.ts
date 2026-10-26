/**
 * Cue crossfade inside the frame loop (#1314 WP-3 contract): a cue adds one capture pass at
 * the top of the encoder and swaps the present's pipeline, still in one command buffer and
 * one submit per frame. Steady frames — with or without param moves — are untouched.
 */

import { createFakeGpu, summarizeOps } from '../testing/fakeGpu';
import { createFakeFrameState } from '../testing/fakeFrameState';
import { WebGPUFrameRenderer } from './frame';

const IN = 'copy:sourceTex>readTex';
const P = 'bufcopy:slotParamsBuf>uniformBuf';
const PRESENT = 'render:?>canvas';
const CAPTURE = 'render:crossfadeCapture>crossfadeHold';

function build() {
  const fake = createFakeGpu();
  const state = createFakeFrameState(fake, { pipelines: ['a', 'b'] });
  state.setSlots([{ id: 'a' }]);
  return { fake, state, renderer: new WebGPUFrameRenderer() };
}

let now = 5000;
beforeEach(() => {
  now = 5000;
  vi.spyOn(performance, 'now').mockImplementation(() => now);
});
afterEach(() => vi.restoreAllMocks());

describe('cue crossfade in the frame loop', () => {
  it('a cue before the first present cuts: nothing to dissolve from', () => {
    const { fake, state, renderer } = build();
    expect(renderer.startCrossfade(state, 2000)).toBe(false);
    renderer.renderFrame(state);
    expect(summarizeOps(fake.ops)).toEqual([IN, P, 'compute:chained-a', PRESENT]);
    expect(fake.counters.createRenderPipeline).toBe(0);
  });

  it('puts the capture first, mixes in the present, and still submits once', () => {
    const { fake, state, renderer } = build();
    renderer.renderFrame(state); // the picture on screen
    fake.reset();

    expect(renderer.startCrossfade(state, 2000)).toBe(true);
    renderer.renderFrame(state);

    expect(summarizeOps(fake.ops)).toEqual([CAPTURE, IN, P, 'compute:chained-a', PRESENT]);
    expect(fake.counters.submits).toBe(1);
    expect(fake.counters.commandBuffers).toBe(1);
    const present = fake.ops.slice(fake.ops.findIndex((o) => o.op === 'beginRenderPass' && o.label === undefined));
    expect(present.filter((o) => o.op === 'setPipeline')).toEqual([
      { op: 'setPipeline', label: 'crossfade-mix-standard-bgra8unorm' },
    ]);
    expect(present.filter((o) => o.op === 'setBindGroup')).toEqual([
      { op: 'setBindGroup', index: 0, label: 'blitBG' },
      { op: 'setBindGroup', index: 1, label: 'crossfadeHoldBG' },
    ]);
  });

  it('keeps the orientation choice: the mix follows selectPresentPipeline, the hold the last present', () => {
    const { fake, state, renderer } = build();
    renderer.renderFrame(state);
    fake.reset();
    renderer.startCrossfade(state, 2000);
    (state as { inputSource: string }).inputSource = 'generative'; // the cue also switches the source
    renderer.renderFrame(state);

    const labels = fake.ops.flatMap((o) => (o.op === 'setPipeline' && o.label?.startsWith('crossfade') ? [o.label] : []));
    expect(labels).toEqual([
      'crossfade-blit-standard-rgba8unorm', // what was on screen
      'crossfade-mix-y-up-bgra8unorm', // what is rendered now
    ]);
  });

  it('ramps over the cue duration and then presents as before', () => {
    const { fake, state, renderer } = build();
    renderer.renderFrame(state);
    renderer.startCrossfade(state, 2000);
    renderer.renderFrame(state);
    now += 1000;
    renderer.renderFrame(state);
    fake.reset();

    now += 1001; // past the end of the ramp
    renderer.renderFrame(state);
    expect(summarizeOps(fake.ops)).toEqual([IN, P, 'compute:chained-a', PRESENT]);
    expect(fake.ops.filter((o) => o.op === 'setPipeline').slice(-1)).toEqual([
      { op: 'setPipeline', label: 'blitPipeline' },
    ]);
    expect(fake.ops.filter((o) => o.op === 'setBindGroup' && o.index === 1)).toEqual([]);
  });

  it('param-only frames never copy, allocate or bind a hold', () => {
    const { fake, state, renderer } = build();
    renderer.renderFrame(state);
    fake.reset();
    for (let i = 0; i < 5; i++) {
      state.slots[0]!.params = [i / 10, 0.5, 0.5, 0.5];
      renderer.renderFrame(state);
    }
    expect(fake.counters.createRenderPipeline).toBe(0);
    expect(fake.counters.submits).toBe(5);
    expect(fake.ops.filter((o) => o.op === 'setBindGroup' && o.index === 1)).toEqual([]);
    expect(summarizeOps(fake.ops).filter((s) => s.includes('crossfade'))).toEqual([]);
  });

  it('a shader change under no cue is a plain cut: no hold exists to mix', () => {
    const { fake, state, renderer } = build();
    renderer.renderFrame(state);
    fake.reset();
    state.setSlots([{ id: 'b' }]);
    renderer.renderFrame(state);
    expect(summarizeOps(fake.ops)).toEqual([IN, P, 'compute:chained-b', PRESENT]);
  });

  it('releasing the hold on teardown drops a running fade', () => {
    const { fake, state, renderer } = build();
    renderer.renderFrame(state);
    renderer.startCrossfade(state, 2000);
    renderer.renderFrame(state);
    renderer.releasePresentHold();
    expect(renderer.startCrossfade(state, 2000)).toBe(false); // nothing presented since the release
    fake.reset();
    renderer.renderFrame(state);
    expect(summarizeOps(fake.ops)).toEqual([IN, P, 'compute:chained-a', PRESENT]);
  });
});
