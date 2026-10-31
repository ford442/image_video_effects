/**
 * sources.ts — modulation source evaluators (#1513). Every output is in [0, 1].
 *
 * Determinism: an evaluator's output depends only on the sequence of (clock, inputs) it
 * was sampled with and its seed. Time-based sources (LFO, sequencer, random walk) are
 * functions of clock time alone, independent of how often they are sampled.
 */

import type { GateSpec, ModClock, ModInputs, ModSource } from './types';
import { SEQUENCER_STEPS } from './types';

const TAU = Math.PI * 2;

/** 32-bit integer hash → [0, 1). Bit-identical across engines (Math.imul only). */
export function hash01(seed: number, n: number): number {
  let h = (Math.imul(seed | 0, 0x9e3779b1) ^ Math.imul(n | 0, 0x85ebca6b)) >>> 0;
  h = Math.imul(h ^ (h >>> 16), 0x7feb352d) >>> 0;
  h = Math.imul(h ^ (h >>> 15), 0x846ca68b) >>> 0;
  h = (h ^ (h >>> 16)) >>> 0;
  return h / 4294967296;
}

const clamp01 = (x: number) => (x < 0 ? 0 : x > 1 ? 1 : Number.isFinite(x) ? x : 0);

export function beatsAt(clock: ModClock): number {
  const bpm = clock.bpm();
  return (clock.now() * (Number.isFinite(bpm) && bpm > 0 ? bpm : 120)) / 60;
}

function external(inputs: ModInputs, key: string): number {
  const ext = inputs.external;
  const v = ext instanceof Map ? ext.get(key) : (ext as Record<string, number>)[key];
  return clamp01(v ?? 0);
}

export interface SourceEvaluator {
  sample(clock: ModClock, inputs: ModInputs): number;
}

export function lfoValue(shape: ModSource & { kind: 'lfo' }, cycles: number): number {
  const c = cycles + (shape.phase ?? 0);
  const f = c - Math.floor(c);
  switch (shape.shape) {
    case 'sine': return 0.5 - 0.5 * Math.cos(TAU * f);
    case 'tri': return f < 0.5 ? f * 2 : 2 - f * 2;
    case 'saw': return f;
    case 'square': return f < 0.5 ? 1 : 0;
    case 'sh': return hash01(shape.seed ?? 0, Math.floor(c));
  }
}

function lfoCycles(src: ModSource & { kind: 'lfo' }, clock: ModClock): number {
  if (src.unit === 'beats') return src.rate > 0 ? beatsAt(clock) / src.rate : 0;
  return clock.now() * src.rate;
}

export function sequencerValue(src: ModSource & { kind: 'sequencer' }, beats: number): number {
  const stepBeats = src.stepBeats > 0 ? src.stepBeats : 0.25;
  const n = Math.floor(beats / stepBeats);
  const i = ((n % SEQUENCER_STEPS) + SEQUENCER_STEPS) % SEQUENCER_STEPS;
  return clamp01(src.steps[i] ?? 0);
}

/** Random walk: tick-indexed, so its value at time t does not depend on the frame rate. */
class RandomWalk implements SourceEvaluator {
  private tick = 0;
  private value = 0.5;
  constructor(private readonly src: ModSource & { kind: 'random' }) {}
  sample(clock: ModClock): number {
    const rate = this.src.rate > 0 ? this.src.rate : 1;
    const target = Math.max(0, Math.floor(clock.now() * rate));
    if (target < this.tick) {
      this.tick = 0;
      this.value = 0.5;
    }
    // Long jumps are bounded: beyond 1e5 ticks we restart from the target tick.
    if (target - this.tick > 100_000) {
      this.tick = target;
      this.value = hash01(this.src.seed, target);
    }
    const step = Math.max(0, this.src.step);
    while (this.tick < target) {
      this.tick++;
      this.value = clamp01(this.value + (hash01(this.src.seed, this.tick) * 2 - 1) * step);
    }
    return this.value;
  }
}

/** Onset follower: a jump in bass above its running average, decaying over ~0.12 s. */
export class OnsetDetector {
  private avg = 0;
  private env = 0;
  private last: number | null = null;
  /** True on the sample an onset fired. */
  fired = false;
  sample(t: number, bass: number): number {
    const dt = this.last === null ? 0 : Math.max(0, t - this.last);
    if (this.last !== null && t === this.last) return this.env;
    this.last = t;
    this.env *= Math.exp(-dt / 0.12);
    this.fired = bass > this.avg * 1.4 + 0.05 && this.env < 0.5;
    if (this.fired) this.env = 1;
    this.avg += (bass - this.avg) * Math.min(1, dt * 4);
    return this.env;
  }
}

class Adsr implements SourceEvaluator {
  private level = 0;
  private stage: 'idle' | 'attack' | 'decay' | 'sustain' | 'release' = 'idle';
  private last: number | null = null;
  private readonly onset = new OnsetDetector();
  constructor(private readonly src: ModSource & { kind: 'adsr' }) {}

  private gate(gate: GateSpec, clock: ModClock, inputs: ModInputs): boolean {
    switch (gate.from) {
      case 'onset':
        this.onset.sample(clock.now(), inputs.bass);
        return this.onset.fired;
      case 'external':
        return external(inputs, gate.key) > 0.5;
      case 'beat': {
        const every = gate.every > 0 ? gate.every : 1;
        const b = beatsAt(clock);
        return b - Math.floor(b / every) * every < Math.max(0, gate.length);
      }
    }
  }

  sample(clock: ModClock, inputs: ModInputs): number {
    const t = clock.now();
    const dt = this.last === null ? 0 : Math.max(0, t - this.last);
    this.last = t;
    const { attack, decay, sustain, release } = this.src;
    const s = clamp01(sustain);
    const open = this.gate(this.src.gate, clock, inputs);
    // Onset gates are triggers (one sample long): they retrigger and hold through A+D.
    const trigger = this.src.gate.from === 'onset';
    if (open && (trigger || this.stage === 'idle' || this.stage === 'release')) this.stage = 'attack';
    else if (!open && !trigger && this.stage !== 'idle') this.stage = 'release';

    let remaining = dt;
    // Advance through stage boundaries within one frame.
    for (let guard = 0; guard < 4 && remaining >= 0; guard++) {
      if (this.stage === 'attack') {
        const rate = attack > 0 ? 1 / attack : Infinity;
        const need = (1 - this.level) / rate;
        if (need > remaining) { this.level += remaining * rate; break; }
        remaining -= need; this.level = 1; this.stage = 'decay';
      } else if (this.stage === 'decay') {
        const rate = decay > 0 ? (1 - s) / decay : Infinity;
        const need = rate === Infinity ? 0 : (this.level - s) / rate;
        if (need > remaining) { this.level -= remaining * rate; break; }
        remaining -= need; this.level = s;
        this.stage = trigger ? 'release' : 'sustain';
      } else if (this.stage === 'release') {
        const rate = release > 0 ? 1 / release : Infinity;
        this.level = Math.max(0, this.level - remaining * rate);
        if (this.level <= 0) this.stage = 'idle';
        break;
      } else break;
    }
    return clamp01(this.level);
  }
}

export function createSourceEvaluator(src: ModSource): SourceEvaluator {
  switch (src.kind) {
    case 'lfo': return { sample: (clock) => lfoValue(src, lfoCycles(src, clock)) };
    case 'sequencer': return { sample: (clock) => sequencerValue(src, beatsAt(clock)) };
    case 'random': return new RandomWalk(src);
    case 'adsr': return new Adsr(src);
    case 'external': return { sample: (_c, inputs) => external(inputs, src.key) };
    case 'audio': {
      if (src.band === 'onset') {
        const onset = new OnsetDetector();
        return { sample: (clock, inputs) => onset.sample(clock.now(), inputs.bass) };
      }
      const band = src.band;
      return { sample: (_c, inputs) => clamp01(inputs[band]) };
    }
  }
}
