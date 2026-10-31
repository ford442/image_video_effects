/**
 * types.ts — parameter modulation bus (#1513 Part A). Pure data, no DOM.
 *
 * A Route connects one source (LFO, envelope, audio band, sequencer, random walk or an
 * external controller) to one slot param. See docs/MODULATION.md.
 */

/** Time source for the bus. #1401's RenderClock is meant to implement this. */
export interface ModClock {
  /** Seconds since the clock started (monotonic while playing). */
  now(): number;
  /** Tempo for beat-synced sources. */
  bpm(): number;
}

export const MOD_TARGET_PARAMS = ['p1', 'p2', 'p3', 'p4', 'opacity'] as const;
export type ModTargetParam = (typeof MOD_TARGET_PARAMS)[number];

export const MOD_CURVES = ['linear', 'exp', 'smooth'] as const;
export type ModCurve = (typeof MOD_CURVES)[number];

export const LFO_SHAPES = ['sine', 'tri', 'saw', 'square', 'sh'] as const;
export type LfoShape = (typeof LFO_SHAPES)[number];

export const AUDIO_BANDS = ['bass', 'mid', 'high', 'onset'] as const;
export type AudioBand = (typeof AUDIO_BANDS)[number];

/** What opens an ADSR's gate. */
export type GateSpec =
  | { from: 'onset' }
  | { from: 'external'; key: string }
  /** Opens for `length` beats every `every` beats. */
  | { from: 'beat'; every: number; length: number };

/** Every source outputs a value in [0, 1]. */
export type ModSource =
  | {
      kind: 'lfo';
      shape: LfoShape;
      /** `hz`: cycles per second. `beats`: the period in beats (tempo-synced). */
      unit: 'hz' | 'beats';
      rate: number;
      /** Phase offset in cycles, [0, 1). */
      phase?: number;
      /** Seed for the S&H shape. */
      seed?: number;
    }
  | { kind: 'adsr'; attack: number; decay: number; sustain: number; release: number; gate: GateSpec }
  | { kind: 'audio'; band: AudioBand }
  /** 16 steps; each lasts `stepBeats` beats (0.25 = sixteenth notes). */
  | { kind: 'sequencer'; steps: number[]; stepBeats: number }
  /** Seeded random walk: `rate` steps per second, each moving at most `step`. */
  | { kind: 'random'; seed: number; rate: number; step: number }
  /** A MIDI CC / OSC / key value from controlBindings, keyed `${source}:${id}`. */
  | { kind: 'external'; key: string };

export type ModSourceKind = ModSource['kind'];

export interface ModTarget {
  slot: number;
  param: ModTargetParam;
}

/** Persisted route (project files store these). */
export interface Route {
  id: string;
  source: ModSource;
  target: ModTarget;
  depth: number;
  offset: number;
  curve: ModCurve;
}

/** A route with its target's range resolved from the shader definition (what the renderer gets). */
export interface ResolvedRoute extends Route {
  min: number;
  max: number;
}

/** Per-frame inputs that are not time. */
export interface ModInputs {
  bass: number;
  mid: number;
  high: number;
  /** Latest external controller values (0..1) by key. */
  external: ReadonlyMap<string, number> | Record<string, number>;
}

export const SEQUENCER_STEPS = 16;
