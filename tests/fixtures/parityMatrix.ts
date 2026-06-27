/**
 * Core shader cases for WASM vs TS parity and benchmark suites.
 */
export type ParityCategory =
  | 'fluid'
  | 'reaction-diffusion'
  | 'audio-reactive'
  | 'generative'
  | 'interactive';

export interface ParityShaderCase {
  id: string;
  url: string;
  category: ParityCategory;
  slot?: number;
  /** Fixed render state for more stable comparisons. */
  testState?: {
    time: number;
    mouseX: number;
    mouseY: number;
    bass?: number;
    mid?: number;
    treble?: number;
  };
  /** Max mean-luminance delta allowed between WASM and WebGPU (0–1). */
  maxLuminanceDelta?: number;
  /** Minimum non-black pixel ratio both backends must exceed. */
  minActivePixelRatio?: number;
}

/** Representative effects across categories — extend as coverage grows. */
export const PARITY_MATRIX: ParityShaderCase[] = [
  {
    id: 'sim-fluid-feedback-coupled',
    url: './shaders/sim-fluid-feedback-coupled.wgsl',
    category: 'fluid',
    testState: { time: 2.5, mouseX: 0.55, mouseY: 0.45 },
    maxLuminanceDelta: 0.35,
  },
  {
    id: 'gen-lichen-reaction-diffusion',
    url: './shaders/gen-lichen-reaction-diffusion.wgsl',
    category: 'reaction-diffusion',
    testState: { time: 3.0, mouseX: 0.5, mouseY: 0.5, bass: 0.4, mid: 0.3, treble: 0.2 },
    maxLuminanceDelta: 0.4,
  },
  {
    id: 'cyber-ripples',
    url: './shaders/cyber-ripples.wgsl',
    category: 'audio-reactive',
    testState: { time: 1.8, mouseX: 0.6, mouseY: 0.4, bass: 0.7, mid: 0.5, treble: 0.3 },
    maxLuminanceDelta: 0.35,
  },
  {
    id: 'plasma',
    url: './shaders/plasma.wgsl',
    category: 'generative',
    testState: { time: 4.0, mouseX: 0.5, mouseY: 0.5 },
    maxLuminanceDelta: 0.3,
  },
  {
    id: 'liquid',
    url: './shaders/liquid.wgsl',
    category: 'interactive',
    testState: { time: 2.0, mouseX: 0.65, mouseY: 0.35 },
    maxLuminanceDelta: 0.35,
  },
];

/** Subset used for CI benchmark job (keeps runtime bounded). */
export const BENCHMARK_MATRIX: ParityShaderCase[] = PARITY_MATRIX.slice(0, 3);

export const PARITY_THRESHOLDS = {
  defaultMaxLuminanceDelta: 0.35,
  defaultMinActivePixelRatio: 0.02,
  warmupMs: 2500,
  settleMs: 500,
};
