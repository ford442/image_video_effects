import { describe, expect, it } from 'vitest';
import {
  applyCurve,
  createSourceEvaluator,
  ModClock,
  ModInputs,
  ModRouter,
  ModSource,
  ModulationRuntime,
  modulate,
  ResolvedRoute,
  routeErrors,
  SEQUENCER_STEPS,
} from './index';

class FakeClock implements ModClock {
  constructor(public t = 0, public tempo = 120) {}
  now() { return this.t; }
  bpm() { return this.tempo; }
}

const quiet: ModInputs = { bass: 0, mid: 0, high: 0, external: {} };

const route = (source: ModSource, over: Partial<ResolvedRoute> = {}): ResolvedRoute => ({
  id: 'r', source, target: { slot: 0, param: 'p1' }, depth: 1, offset: 0, curve: 'linear', min: 0, max: 1, ...over,
});

const ALL_SOURCES: ModSource[] = [
  { kind: 'lfo', shape: 'sine', unit: 'hz', rate: 0.7 },
  { kind: 'lfo', shape: 'tri', unit: 'beats', rate: 2, phase: 0.25 },
  { kind: 'lfo', shape: 'saw', unit: 'hz', rate: 3 },
  { kind: 'lfo', shape: 'square', unit: 'beats', rate: 1 },
  { kind: 'lfo', shape: 'sh', unit: 'hz', rate: 4, seed: 7 },
  { kind: 'adsr', attack: 0.05, decay: 0.1, sustain: 0.6, release: 0.3, gate: { from: 'beat', every: 1, length: 0.5 } },
  { kind: 'adsr', attack: 0.01, decay: 0.2, sustain: 0.2, release: 0.2, gate: { from: 'onset' } },
  { kind: 'audio', band: 'bass' },
  { kind: 'audio', band: 'onset' },
  { kind: 'sequencer', steps: Array.from({ length: SEQUENCER_STEPS }, (_, i) => i / 15), stepBeats: 0.25 },
  { kind: 'random', seed: 42, rate: 10, step: 0.1 },
  { kind: 'external', key: 'midi-cc:1' },
];

function run(seedOffset: number, frames: number[]): number[] {
  const router = new ModRouter();
  router.setRoutes(ALL_SOURCES.map((s, i) => route(s, { id: `r${i}`, target: { slot: i, param: 'p1' } })));
  const clock = new FakeClock(0, 128 + seedOffset);
  const out: number[] = [];
  frames.forEach((t, f) => {
    clock.t = t;
    router.step(clock, { bass: (f % 7) / 7, mid: 0.3, high: 0.1, external: { 'midi-cc:1': (f % 3) / 3 } });
    for (let s = 0; s < ALL_SOURCES.length; s++) out.push(router.overlay(s, [0, 0, 0, 0, 1])!.values[0]!);
  });
  return out;
}

describe('modulation bus determinism', () => {
  const frames = Array.from({ length: 600 }, (_, i) => i / 60);

  it('same clock + same seed gives bit-identical output', () => {
    const a = run(0, frames);
    const b = run(0, frames);
    expect(a.length).toBe(600 * ALL_SOURCES.length);
    expect(Object.is(a.length, b.length)).toBe(true);
    for (let i = 0; i < a.length; i++) expect(Object.is(a[i], b[i])).toBe(true);
    expect(new Float64Array(a).buffer).toEqual(new Float64Array(b).buffer);
  });

  it('a different tempo changes tempo-synced output', () => {
    expect(run(0, frames)).not.toEqual(run(10, frames));
  });

  it('random walk and S&H depend on time only, not on the frame rate', () => {
    for (const src of [ALL_SOURCES[4]!, ALL_SOURCES[10]!]) {
      const fast = createSourceEvaluator(src);
      const slow = createSourceEvaluator(src);
      const clock = new FakeClock();
      let fastAt3 = 0;
      for (let i = 0; i <= 360; i++) { clock.t = i / 120; fastAt3 = fast.sample(clock, quiet); }
      clock.t = 1; slow.sample(clock, quiet);
      clock.t = 3;
      expect(Object.is(slow.sample(clock, quiet), fastAt3)).toBe(true);
    }
  });

  it('a different seed gives a different walk', () => {
    const clock = new FakeClock(5);
    const a = createSourceEvaluator({ kind: 'random', seed: 1, rate: 10, step: 0.2 }).sample(clock, quiet);
    const b = createSourceEvaluator({ kind: 'random', seed: 2, rate: 10, step: 0.2 }).sample(clock, quiet);
    expect(a).not.toBe(b);
  });
});

describe('sources', () => {
  it('LFO shapes stay in [0, 1] and hit their landmarks', () => {
    const clock = new FakeClock();
    const sine = createSourceEvaluator({ kind: 'lfo', shape: 'sine', unit: 'hz', rate: 1 });
    const saw = createSourceEvaluator({ kind: 'lfo', shape: 'saw', unit: 'hz', rate: 1 });
    const sq = createSourceEvaluator({ kind: 'lfo', shape: 'square', unit: 'hz', rate: 1 });
    clock.t = 0; expect(sine.sample(clock, quiet)).toBeCloseTo(0);
    clock.t = 0.5; expect(sine.sample(clock, quiet)).toBeCloseTo(1);
    clock.t = 0.25; expect(saw.sample(clock, quiet)).toBeCloseTo(0.25);
    expect(sq.sample(clock, quiet)).toBe(1);
    clock.t = 0.75; expect(sq.sample(clock, quiet)).toBe(0);
  });

  it('tempo-synced LFO: a 1-beat period at 120 BPM is 0.5 s', () => {
    const clock = new FakeClock(0.25, 120);
    const saw = createSourceEvaluator({ kind: 'lfo', shape: 'saw', unit: 'beats', rate: 1 });
    expect(saw.sample(clock, quiet)).toBeCloseTo(0.5);
  });

  it('sequencer walks 16 steps on the beat grid and wraps', () => {
    const steps = Array.from({ length: 16 }, (_, i) => i / 16);
    const seq = createSourceEvaluator({ kind: 'sequencer', steps, stepBeats: 0.25 });
    const clock = new FakeClock(0, 60); // 1 beat per second → a step every 0.25 s
    clock.t = 0.26; expect(seq.sample(clock, quiet)).toBeCloseTo(1 / 16);
    clock.t = 4.0; expect(seq.sample(clock, quiet)).toBe(0);
  });

  it('ADSR rises on the gate, sustains, and releases', () => {
    const env = createSourceEvaluator({ kind: 'adsr', attack: 0.1, decay: 0.1, sustain: 0.5, release: 0.2, gate: { from: 'external', key: 'k' } });
    const clock = new FakeClock();
    const on: ModInputs = { ...quiet, external: { k: 1 } };
    env.sample(clock, on);
    clock.t = 0.05; expect(env.sample(clock, on)).toBeCloseTo(0.5);
    clock.t = 0.5; expect(env.sample(clock, on)).toBeCloseTo(0.5);
    clock.t = 0.6; expect(env.sample(clock, quiet)).toBeCloseTo(0);
    clock.t = 0.65; expect(env.sample(clock, quiet)).toBeCloseTo(0);
  });

  it('onset fires on a bass jump and decays', () => {
    const onset = createSourceEvaluator({ kind: 'audio', band: 'onset' });
    const clock = new FakeClock();
    for (let i = 0; i < 30; i++) { clock.t = i / 60; onset.sample(clock, { ...quiet, bass: 0.1 }); }
    clock.t = 0.5; expect(onset.sample(clock, { ...quiet, bass: 0.9 })).toBe(1);
    clock.t = 1.0; expect(onset.sample(clock, { ...quiet, bass: 0.1 })).toBeLessThan(0.05);
  });
});

describe('routes', () => {
  it('curves map [0,1] onto [0,1]', () => {
    for (const c of ['linear', 'exp', 'smooth'] as const) {
      expect(applyCurve(c, 0)).toBeCloseTo(0);
      expect(applyCurve(c, 1)).toBeCloseTo(1);
    }
    expect(applyCurve('exp', 0.5)).toBeLessThan(0.5);
  });

  it('clamps base + depth*curve(src) + offset to the param range', () => {
    expect(modulate(0.5, 1, 1, 0, 0, 1)).toBe(1);
    expect(modulate(2, 3, 0.5, -1, 0, 10)).toBe(2.5);
    expect(modulate(0.1, -1, 1, 0, 0, 1)).toBe(0);
  });

  it('sums several routes on one target and leaves other params at base', () => {
    const router = new ModRouter();
    const ext = { kind: 'external', key: 'a' } as const;
    router.setRoutes([
      route(ext, { id: 'a', depth: 0.2 }),
      route(ext, { id: 'b', depth: 0.1, offset: 0.05 }),
      route(ext, { id: 'c', target: { slot: 0, param: 'opacity' }, depth: -0.5 }),
    ]);
    router.step(new FakeClock(), { ...quiet, external: { a: 1 } });
    const o = router.overlay(0, [0.4, 0.3, 0.2, 0.1, 1])!;
    expect(o.values[0]).toBeCloseTo(0.75);
    expect(o.values[1]).toBe(0.3);
    expect(o.values[4]).toBeCloseTo(0.5);
    expect(o.mask).toBe(0b10001);
    expect(router.overlay(1, [0, 0, 0, 0, 1])).toBeNull();
  });

  it('validates route shape', () => {
    expect(routeErrors(route(ALL_SOURCES[0]!))).toEqual([]);
    expect(routeErrors({ ...route(ALL_SOURCES[0]!), curve: 'cubic' })).toHaveLength(1);
    expect(routeErrors({ ...route(ALL_SOURCES[0]!), target: { slot: 0, param: 'p9' } })).toHaveLength(1);
    expect(routeErrors({ ...route({ kind: 'nope' } as unknown as ModSource) })).toHaveLength(1);
  });
});

describe('ModulationRuntime overlay', () => {
  it('overlays params and opacity for one frame and restores the base values', () => {
    const rt = new ModulationRuntime();
    rt.setExternal({ x: 1 });
    rt.setRoutes([
      route({ kind: 'external', key: 'x' }, { id: 'p', target: { slot: 1, param: 'p2' }, depth: 0.25 }),
      route({ kind: 'external', key: 'x' }, { id: 'o', target: { slot: 1, param: 'opacity' }, depth: -0.5 }),
    ]);
    const params = [0.5, 0.5, 0.5, 0.5];
    const layer = { opacity: 1, blend: 'screen' };
    const slots = [{ params: [0, 0, 0, 0] }, { params, layer }];
    const undo = rt.applyOverlay(slots, 0, { bass: 0, mid: 0, treble: 0 });
    expect(slots[1]!.params).toEqual([0.5, 0.75, 0.5, 0.5]);
    expect(slots[1]!.layer).toEqual({ opacity: 0.5, blend: 'screen' });
    expect(params).toEqual([0.5, 0.5, 0.5, 0.5]);
    undo();
    expect(slots[1]!.params).toBe(params);
    expect(slots[1]!.layer).toBe(layer);
    expect(layer.opacity).toBe(1);
  });

  it('uses an injected clock (the #1401 RenderClock seam)', () => {
    const rt = new ModulationRuntime();
    rt.setRoutes([route({ kind: 'lfo', shape: 'saw', unit: 'hz', rate: 1 }, { depth: 1 })]);
    rt.setClock(new FakeClock(0.25));
    const slots = [{ params: [0, 0, 0, 0] }];
    rt.applyOverlay(slots, 99, { bass: 0, mid: 0, treble: 0 });
    expect(slots[0]!.params[0]).toBeCloseTo(0.25);
  });

  it('is a no-op without routes and drops malformed ones', () => {
    const rt = new ModulationRuntime();
    rt.setRoutes([{ id: 'bad' } as unknown as ResolvedRoute]);
    expect(rt.routeCount).toBe(0);
    const slots = [{ params: [0.1, 0.2, 0.3, 0.4] }];
    const p = slots[0]!.params;
    rt.applyOverlay(slots, 1, { bass: 1, mid: 1, treble: 1 })();
    expect(slots[0]!.params).toBe(p);
  });
});
