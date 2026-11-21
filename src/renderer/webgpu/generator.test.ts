/**
 * The generative-source stage (generator.ts): it runs ahead of the slot chain, leaves its picture
 * in readTex, keeps its own feedback textures, and never takes an effect slot.
 */

import { createFakeGpu, summarizeOps } from '../testing/fakeGpu';
import { createFakeFrameState } from '../testing/fakeFrameState';
import { WebGPUFrameRenderer } from './frame';
import { GeneratorStage } from './generator';

const GEN = 'gen-test';
const GEN_FEEDBACK = 'gen-feedback';

type FakeState = ReturnType<typeof createFakeFrameState>;

function build(options: {
  generator?: string | null;
  input?: 'generative' | 'image';
  slots?: Array<{ id: string }>;
  pipelines?: string[];
} = {}) {
  const fake = createFakeGpu();
  const state = createFakeFrameState(fake, {
    pipelines: options.pipelines ?? [GEN, GEN_FEEDBACK, 'liquid', 'fb'],
    usage: {
      [GEN_FEEDBACK]: { writesDataA: true, writesDataB: true, readsDataC: true },
      fb: { writesDataA: true, writesDataB: true, readsDataC: true },
    },
  });
  const generator = new GeneratorStage();
  generator.setShader(options.generator === undefined ? GEN : options.generator);
  (state as FakeState & { generator: GeneratorStage }).generator = generator;
  (state as { inputSource: string }).inputSource = options.input ?? 'generative';
  state.setSlots(options.slots ?? []);
  return { fake, state, generator, renderer: new WebGPUFrameRenderer() };
}

const IN = 'copy:sourceTex>readTex';
const W2R = 'copy:writeTex>readTex';
const PRESENT = 'render:?>canvas';
const P = 'bufcopy:slotParamsBuf>uniformBuf';
const GP = 'bufcopy:generatorParamsBuf>uniformBuf';

describe('generator stage', () => {
  it('with no effect slots the generator alone fills the frame', () => {
    const { fake, state, renderer } = build();
    renderer.renderFrame(state);
    expect(summarizeOps(fake.ops)).toEqual([IN, GP, `compute:generator:${GEN}`, GP, W2R, PRESENT]);
    expect(fake.counters.submits).toBe(1);
  });

  it('runs ahead of the slot chain, so slot 0 reads the generator picture', () => {
    const { fake, state, renderer } = build({ slots: [{ id: 'liquid' }] });
    renderer.renderFrame(state);
    expect(summarizeOps(fake.ops)).toEqual([
      IN, GP, `compute:generator:${GEN}`, GP, W2R, P, 'compute:chained-liquid', PRESENT,
    ]);
  });

  it('feeds every effect slot: four slots all run after the generator, in order', () => {
    const { fake, state, renderer } = build({
      slots: [{ id: 'liquid' }, { id: 'fb' }, { id: 'liquid' }, { id: 'fb' }],
    });
    renderer.renderFrame(state);
    const ops = summarizeOps(fake.ops);
    const genAt = ops.indexOf(`compute:generator:${GEN}`);
    const slotAt = ops.findIndex((o) => o.startsWith('compute:chained-'));
    expect(genAt).toBeGreaterThan(-1);
    expect(genAt).toBeLessThan(slotAt);
    expect(ops.filter((o) => o.startsWith('compute:chained-'))).toHaveLength(4);
  });

  it('keeps its feedback on a private A/B/C triple, never the slots\' dataTex', () => {
    const { fake, state, renderer } = build({ generator: GEN_FEEDBACK });
    renderer.renderFrame(state);
    const ops = summarizeOps(fake.ops);
    // Feedback contract (B → C first, A → C last) on the generator's own textures.
    expect(ops).toEqual([
      IN, GP, `compute:generator:${GEN_FEEDBACK}`, GP, W2R,
      'copy:generatorDataB>generatorDataC',
      'copy:generatorDataA>generatorDataC',
      PRESENT,
    ]);
    expect(ops.some((o) => /dataTex[ABC]/.test(o))).toBe(false);
  });

  it('a feedback slot after the generator keeps using the shared dataTex only', () => {
    const { fake, state, renderer } = build({ generator: GEN_FEEDBACK, slots: [{ id: 'fb' }] });
    renderer.renderFrame(state);
    const ops = summarizeOps(fake.ops);
    expect(ops).toContain('copy:generatorDataA>generatorDataC');
    expect(ops).toContain('copy:dataTexA>dataTexC');
    // Each triple is copied from exactly one side: no cross-over.
    expect(ops).not.toContain('copy:generatorDataA>dataTexC');
    expect(ops).not.toContain('copy:dataTexA>generatorDataC');
  });

  it('is off outside Generative input mode', () => {
    const { fake, state, renderer } = build({ input: 'image', slots: [{ id: 'liquid' }] });
    renderer.renderFrame(state);
    expect(summarizeOps(fake.ops)).toEqual([IN, P, 'compute:chained-liquid', PRESENT]);
  });

  it('is off with no shader set', () => {
    const { fake, state, renderer } = build({ generator: null });
    renderer.renderFrame(state);
    expect(summarizeOps(fake.ops)).toEqual([IN, PRESENT]);
  });

  it('waits quietly until the shader compiles', () => {
    const { fake, state, generator, renderer } = build({ pipelines: ['liquid'], slots: [{ id: 'liquid' }] });
    renderer.renderFrame(state);
    expect(summarizeOps(fake.ops)).toEqual([IN, P, 'compute:chained-liquid', PRESENT]);
    expect(generator.getStatus()).toMatchObject({ shaderId: GEN, ran: false, skipped: 'compiling' });
  });

  it('refuses a sim-ring shader (it needs the group-1 ring) and says so', () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const { fake, state, generator, renderer } = build();
    (state as { usesSimRing: (id: string) => boolean }).usesSimRing = () => true;
    renderer.renderFrame(state);
    renderer.renderFrame(state);
    expect(summarizeOps(fake.ops)).not.toContain(`compute:generator:${GEN}`);
    expect(generator.getStatus().skipped).toBe('sim-ring');
    expect(warn).toHaveBeenCalledTimes(1); // once per shader, not per frame
    warn.mockRestore();
  });

  it('builds its bind group once and reuses it frame to frame', () => {
    const { fake, state, renderer } = build({ slots: [{ id: 'liquid' }] });
    renderer.renderFrame(state);
    fake.reset();
    renderer.renderFrame(state);
    renderer.renderFrame(state);
    expect(fake.bindGroupLabels).toEqual([]);
  });

  it('switching shaders starts the new generator from clean feedback', () => {
    const { fake, state, generator, renderer } = build({ generator: GEN_FEEDBACK });
    const created: string[] = [];
    const device = fake.device as unknown as { createTexture: (d: { label?: string }) => unknown };
    const original = device.createTexture.bind(device);
    device.createTexture = (d) => {
      created.push(d.label ?? '?');
      return original(d);
    };
    renderer.renderFrame(state);
    expect(created).toEqual(['generatorDataA', 'generatorDataB', 'generatorDataC']);
    renderer.renderFrame(state);
    expect(created).toHaveLength(3); // steady state allocates nothing
    generator.setShader(GEN);
    renderer.renderFrame(state);
    expect(created).toHaveLength(6); // a different generator never inherits the last one's A/B/C
  });

  it('rebuilds its state on a new working size and its bind group on new shared textures', () => {
    const { fake, state, renderer } = build({ generator: GEN_FEEDBACK });
    const created: string[] = [];
    const device = fake.device as unknown as { createTexture: (d: { label?: string }) => unknown };
    const original = device.createTexture.bind(device);
    device.createTexture = (d) => {
      created.push(d.label ?? '?');
      return original(d);
    };
    renderer.renderFrame(state);
    Object.assign(state, { scaledW: 32, scaledH: 32 });
    renderer.renderFrame(state);
    expect(created).toHaveLength(6);
    // New shared textures (recreateScaleTextures) rebuild the bind group, not the state.
    fake.reset();
    Object.assign(state, { readTex: fake.texture('readTex2', 32, 32) });
    renderer.renderFrame(state);
    expect(fake.bindGroupLabels.filter((l) => l === 'computeBG-graph')).toHaveLength(1);
  });

  it('keeps the generator sliders and clamps junk', () => {
    const g = new GeneratorStage();
    g.setParams(0.1, 0.2, Number.NaN, 0.4);
    expect(g.getParams()).toEqual([0.1, 0.2, 0.5, 0.4]);
  });
});
