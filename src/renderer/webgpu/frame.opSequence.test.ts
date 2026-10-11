/**
 * Frame encoding contract (#1314 WP-3): one encoder, one submit per frame, no
 * per-frame bind-group churn, and the slot / feedback / history order that
 * docs/BINDING_CONTRACT.md freezes. The golden op lists are the "pixel parity"
 * proxy for later frame-plan refactors: change them only on purpose.
 */

import { GpuChoresHost } from '../../gpuChores';
import { createFakeGpu, FakeGpu, summarizeOps } from '../testing/fakeGpu';
import { createFakeFrameState } from '../testing/fakeFrameState';
import { instrumentDevice } from './deviceCounters';
import { createTimestampQueries, profilePass, QUERY_COUNT } from './WebGPUTiming';
import { WebGPUFrameRenderer } from './frame';
import {
  createMediaInputState,
  encodeVideoFrame,
  WebGPUMediaInputContext,
} from './WebGPUMediaInput';

const GRAPH = 'anisotropic-kuwahara';
const GRAPH_ENTRIES = [
  'anisotropic-kuwahara-tensor',
  'anisotropic-kuwahara-filter',
  'anisotropic-kuwahara-render',
];

type FakeState = ReturnType<typeof createFakeFrameState>;
type Setup = (s: FakeState, fake: FakeGpu) => void;

function build(setup: Setup) {
  const fake = createFakeGpu();
  const state = createFakeFrameState(fake, {
    pipelines: ['a', 'b', 'c', 'd', 'e', 'f', 'hist', 'fb', GRAPH, ...GRAPH_ENTRIES],
    usage: {
      hist: { usesHistory: true },
      fb: { writesDataA: true, writesDataB: true, readsDataC: true },
    },
  });
  setup(state, fake);
  return { fake, state, renderer: new WebGPUFrameRenderer() };
}

function attachVideo(state: FakeState, fake: FakeGpu): void {
  const video = {
    label: 'video',
    paused: false,
    readyState: 4,
    videoWidth: 64,
    videoHeight: 64,
    error: null,
  } as unknown as HTMLVideoElement;
  const media = createMediaInputState();
  media.video = video;
  const ctx: WebGPUMediaInputContext = {
    device: fake.device,
    sourceTex: state.sourceTex,
    readTex: state.readTex,
    canvasW: state.canvasW,
    canvasH: state.canvasH,
    colorFormat: 'rgba32float',
    filterSampler: { label: 'filterSampler' } as unknown as GPUSampler,
    supportsExternalTexture: true,
    videoCopyPipeline: { label: 'videoCopyPipeline' } as unknown as GPURenderPipeline,
    videoCopyBindGroupLayout: { label: 'videoCopyBGL' } as unknown as GPUBindGroupLayout,
  };
  (state as { video: HTMLVideoElement | null }).video = video;
  // Same wiring as WebGPURenderer.encodeVideoFrame (lazy per-pass stamp).
  (state as { encodeVideoFrame: (e: GPUCommandEncoder) => boolean }).encodeVideoFrame =
    (encoder) => encodeVideoFrame(ctx, media, encoder, () =>
      profilePass(state.timestampRuntime, { kind: 'video', label: 'videoCopyPass' }));
}

const SIX = ['a', 'b', 'c', 'd', 'e', 'f'];

const CASES: Record<string, Setup> = {
  zeroSlots: () => {},
  oneSlot: (s) => s.setSlots([{ id: 'a' }]),
  sixChained: (s) => s.setSlots(SIX.map((id) => ({ id }))),
  sixParallel: (s) => s.setSlots(SIX.map((id) => ({ id, mode: 'parallel' as const }))),
  mixed: (s) => s.setSlots([{ id: 'a', mode: 'parallel' }, { id: 'fb' }, { id: 'b', mode: 'parallel' }, { id: 'c' }]),
  graph: (s) => s.setSlots([{ id: GRAPH }]),
  history: (s) => s.setSlots([{ id: 'hist' }]),
  feedback: (s) => s.setSlots([{ id: 'fb' }, { id: 'a' }]),
  video: (s, fake) => {
    s.setSlots([{ id: 'a' }]);
    attachVideo(s, fake);
  },
  videoZeroSlots: (s, fake) => attachVideo(s, fake),
  // Working size capped below the canvas at scale 1 (non-discrete adapters).
  cappedWorkingSize: (s) => {
    s.setSlots([{ id: 'a' }]);
    Object.assign(s, { canvasW: 128, canvasH: 128 });
  },
};

const P = 'bufcopy:slotParamsBuf>uniformBuf';
const IN = 'copy:sourceTex>readTex';
const W2R = 'copy:writeTex>readTex';
const PRESENT = 'render:?>canvas';

const GOLDEN: Record<string, string[]> = {
  // Zero slots still refresh readTex from the source (was skipped before #1314,
  // which left video stale when every slot was off).
  zeroSlots: [IN, PRESENT],
  oneSlot: [IN, P, 'compute:chained-a', PRESENT],
  sixChained: [
    IN,
    ...SIX.flatMap((id) => [P, `compute:chained-${id}`, W2R]),
    PRESENT,
  ],
  sixParallel: [IN, ...SIX.flatMap((id) => [P, `compute:parallel-${id}`]), W2R, PRESENT],
  mixed: [
    IN,
    P, 'compute:parallel-a',
    P, 'compute:parallel-b',
    W2R,
    P, 'compute:chained-fb',
    W2R,
    // Feedback contract: B → C first, A → C last (A wins).
    'copy:dataTexB>dataTexC',
    'copy:dataTexA>dataTexC',
    P, 'compute:chained-c',
    W2R,
    PRESENT,
  ],
  graph: [
    IN,
    P,
    'compute:graph-tensor-0-anisotropic-kuwahara-tensor',
    'copy:dataTexA>dataTexC',
    'compute:graph-filter-0-anisotropic-kuwahara-filter',
    'copy:dataTexA>dataTexC',
    'compute:graph-render-0-anisotropic-kuwahara-render',
    'copy:dataTexA>dataTexC',
    PRESENT,
  ],
  history: [IN, P, 'compute:chained-hist', 'copy:writeTex>historyTex', PRESENT],
  feedback: [
    IN,
    P, 'compute:chained-fb',
    W2R,
    'copy:dataTexB>dataTexC',
    'copy:dataTexA>dataTexC',
    P, 'compute:chained-a',
    W2R,
    PRESENT,
  ],
  // Video ingest rides the frame encoder ahead of the input copy.
  video: ['render:videoCopyPass>sourceTex', IN, P, 'compute:chained-a', PRESENT],
  videoZeroSlots: ['render:videoCopyPass>sourceTex', IN, PRESENT],
  // A 128² → 64² copy would overrun readTex and invalidate the frame: resample.
  cappedWorkingSize: ['render:scalePass>readTex', P, 'compute:chained-a', PRESENT],
};

function caseOf(name: string): Setup {
  const setup = CASES[name];
  if (setup === undefined) throw new Error(`missing case ${name}`);
  return setup;
}

describe('frame encoding contract', () => {
  it.each(Object.keys(CASES))('%s: encodes the golden op order into one command buffer', (name) => {
    const { fake, state, renderer } = build(caseOf(name));
    renderer.renderFrame(state);
    expect(fake.counters.submits).toBe(1);
    expect(fake.counters.commandBuffers).toBe(1);
    expect(fake.submitted[0]!.label).toBe('frame');
    expect(summarizeOps(fake.ops)).toEqual(GOLDEN[name]);
  });

  it.each(Object.keys(CASES))('%s: steady state creates no bind groups except the video external group', (name) => {
    const { fake, state, renderer } = build(caseOf(name));
    renderer.renderFrame(state);
    fake.reset();
    renderer.renderFrame(state);
    renderer.renderFrame(state);
    const expected = name.startsWith('video') ? ['videoCopyBG', 'videoCopyBG'] : [];
    expect(fake.bindGroupLabels).toEqual(expected);
    expect(fake.counters.submits).toBe(2);
  });

  it('reports one submit per frame through the instrumented device counters', () => {
    const { fake, state, renderer } = build((s, f) => {
      s.setSlots(SIX.map((id) => ({ id })));
      attachVideo(s, f);
    });
    instrumentDevice(fake.device);
    for (let i = 0; i < 4; i++) renderer.renderFrame(state);
    const stats = renderer.getFrameStats();
    expect(stats.submitsLastFrame).toBe(1);
    expect(stats.bindGroupsLastFrame).toBe(1); // the per-frame video external group
    expect(stats.framesRendered).toBe(3);
  });

  it('keeps chores (pre-FX passes + periodic readback) inside the frame submit', async () => {
    window.webgpuProbe = {
      ok: true,
      finishedAt: new Date().toISOString(),
      userAgent: 'test',
      userAgentBrands: [],
      attempts: [],
    };
    const { fake, state, renderer } = build((s) => s.setSlots([{ id: 'a' }]));
    const chores = new GpuChoresHost();
    chores.attach(fake.device);
    expect(chores.getBreadcrumbs().gpuComputeAvailable).toBe(true);
    const s = state as {
      encodePreFxChores?: (e: GPUCommandEncoder) => void;
      encodePostFxChores?: (e: GPUCommandEncoder) => void;
      afterFrameSubmitChores?: () => void;
    };
    s.encodePreFxChores = (e) => chores.encodePreFx(e, state.readTex, 64, 64, state.writeTex);
    s.encodePostFxChores = (e) => chores.encodeReadback(e);
    s.afterFrameSubmitChores = () => chores.afterSubmit();

    const readbackFrames: number[] = [];
    let firstReadbackOps: string[] = [];
    for (let frame = 1; frame <= 9; frame++) {
      fake.reset();
      renderer.renderFrame(state);
      expect(fake.counters.submits).toBe(1);
      const ops = summarizeOps(fake.ops);
      if (ops.some((op) => op.startsWith('readback:'))) {
        readbackFrames.push(frame);
        if (firstReadbackOps.length === 0) firstReadbackOps = ops;
      }
      // Let the fake mapAsync settle so the next readback slot is free.
      await Promise.resolve();
      await Promise.resolve();
    }
    expect(readbackFrames).toEqual([1, 9]);
    // Readback copies trail present inside the same command buffer.
    const present = firstReadbackOps.indexOf(PRESENT);
    const readback = firstReadbackOps.findIndex((op) => op.startsWith('readback:'));
    expect(present).toBeGreaterThan(-1);
    expect(readback).toBeGreaterThan(present);
    chores.destroy();
  });

  it('profiles every pass once: video, input, slots, graph nodes and present, then resolves', () => {
    const { fake, state, renderer } = build((st, f) => {
      st.setSlots([{ id: 'a', mode: 'parallel' }, { id: GRAPH }]);
      attachVideo(st, f);
    });
    (state as { timestampRuntime: unknown }).timestampRuntime = createTimestampQueries(fake.device);
    renderer.renderFrame(state);

    const passes = fake.ops.filter((op) => op.op === 'beginComputePass' || op.op === 'beginRenderPass');
    const stamped = passes.filter((op) => 'timestampWrites' in op && op.timestampWrites);
    expect(stamped).toHaveLength(passes.length);
    const indices = stamped.flatMap((op) => {
      const tw = (op as { timestampWrites: { begin?: number; end?: number } }).timestampWrites;
      return [tw.begin, tw.end];
    });
    expect(new Set(indices).size).toBe(indices.length);
    expect(Math.max(...(indices as number[]))).toBeLessThan(QUERY_COUNT);

    const ops = summarizeOps(fake.ops);
    expect(ops[ops.length - 2]).toBe(`resolve:0+${passes.length * 2}`);
    expect(state.timestampRuntime.frame.passes.map((p) => p.kind)).toEqual([
      'video', 'compute', 'compute', 'compute', 'compute', 'present',
    ]);
    expect(state.timestampRuntime.frame.passes[2]).toMatchObject({ slot: 1, nodeId: 'tensor', shaderId: GRAPH });
  });
});
