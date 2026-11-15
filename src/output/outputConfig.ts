/**
 * outputConfig.ts — what one stage output does with the program picture.
 *
 * Plain data: it crosses the render-worker boundary (structured clone), is saved
 * as a named calibration, and is packed into the output stage's uniform here so
 * the WGSL layout lives next to its one writer.
 */

import { cornerPinInverse, IDENTITY_MAT3, IDENTITY_QUAD, isConvexQuad, type Mat3, type Quad, type Vec2 } from './homography';

/** Patterns the output stage draws itself (in program space, so they warp with the pin). */
export const TEST_PATTERNS = ['none', 'grid', 'crosshatch', 'bars', 'white'] as const;
export type TestPattern = (typeof TEST_PATTERNS)[number];

export interface OutputColour {
  /** Linear gain applied before the sRGB encode (1 = unchanged). */
  gain: number;
  /** Extra display gamma after the encode (1 = unchanged, >1 darkens mids). */
  gamma: number;
  /** Black-level lift, 0..0.5 (projector black floor matching). */
  blackLevel: number;
}

export interface OutputConfig {
  /** Where the program's corners land on this output, in output UV (Y-down, 0..1). */
  corners: Quad;
  testPattern: TestPattern;
  /** Draw the quad's edge (calibration aid). */
  outline: boolean;
  colour: OutputColour;
}

export const DEFAULT_OUTPUT_COLOUR: OutputColour = { gain: 1, gamma: 1, blackLevel: 0 };

export function defaultOutputConfig(): OutputConfig {
  return {
    corners: IDENTITY_QUAD.map((c) => [c[0], c[1]] as Vec2) as unknown as Quad,
    testPattern: 'none',
    outline: false,
    colour: { ...DEFAULT_OUTPUT_COLOUR },
  };
}

/** Corners may sit off-screen (a surface larger than the output), but not absurdly. */
export const CORNER_MIN = -2;
export const CORNER_MAX = 3;

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
const finite = (v: unknown, fallback: number): number =>
  typeof v === 'number' && Number.isFinite(v) ? v : fallback;
const isObj = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);

function sanitizeCorners(raw: unknown): Quad {
  const fallback = IDENTITY_QUAD;
  if (!Array.isArray(raw) || raw.length !== 4) return defaultOutputConfig().corners;
  const out = fallback.map((def, i) => {
    const c: unknown = raw[i];
    if (!Array.isArray(c) || c.length !== 2) return [def[0], def[1]] as Vec2;
    return [
      clamp(finite(c[0], def[0]), CORNER_MIN, CORNER_MAX),
      clamp(finite(c[1], def[1]), CORNER_MIN, CORNER_MAX),
    ] as Vec2;
  }) as unknown as Quad;
  return out;
}

/** Accept anything (a stored calibration, a message) and return a usable config. */
export function sanitizeOutputConfig(raw: unknown): OutputConfig {
  const def = defaultOutputConfig();
  if (!isObj(raw)) return def;
  const colour = isObj(raw.colour) ? raw.colour : {};
  const pattern = raw.testPattern;
  return {
    corners: sanitizeCorners(raw.corners),
    testPattern: (TEST_PATTERNS as readonly unknown[]).includes(pattern) ? (pattern as TestPattern) : 'none',
    outline: raw.outline === true,
    colour: {
      gain: clamp(finite(colour.gain, 1), 0, 4),
      gamma: clamp(finite(colour.gamma, 1), 0.2, 5),
      blackLevel: clamp(finite(colour.blackLevel, 0), 0, 0.5),
    },
  };
}

/** Move one corner by (dx, dy) in output UV, keeping it in range. */
export function nudgeCorner(config: OutputConfig, index: number, dx: number, dy: number): OutputConfig {
  const corners = config.corners.map((c, i) =>
    i === index
      ? ([clamp(c[0] + dx, CORNER_MIN, CORNER_MAX), clamp(c[1] + dy, CORNER_MIN, CORNER_MAX)] as Vec2)
      : c,
  ) as unknown as Quad;
  return { ...config, corners };
}

/** Put one corner at an absolute output-UV position. */
export function setCorner(config: OutputConfig, index: number, x: number, y: number): OutputConfig {
  const c = config.corners[index];
  if (!c) return config;
  return nudgeCorner(config, index, x - c[0], y - c[1]);
}

// ── Uniform packing ─────────────────────────────────────────────────────────
//
// public/shaders/_output/corner_pin.wgsl `OutputParams` (5 × vec4<f32> = 80 bytes):
//   [0..2]  rows of the inverse corner pin (output UV → program UV), .w unused
//   [3]     gain, gamma, blackLevel, flipY (1 = generative / Y-up program)
//   [4]     pattern id, outline (0/1), output width px, output height px

export const OUTPUT_UNIFORM_FLOATS = 20;
export const OUTPUT_UNIFORM_BYTES = OUTPUT_UNIFORM_FLOATS * 4;

export const TEST_PATTERN_IDS: Record<TestPattern, number> = {
  none: 0,
  grid: 1,
  crosshatch: 2,
  bars: 3,
  white: 4,
};

export interface PackOptions {
  /** The program texture is Y-up (generative input): the present flips it. */
  generative: boolean;
  width: number;
  height: number;
}

/**
 * The inverse corner pin, or identity when the quad cannot be inverted. A
 * non-convex quad is still drawn (the operator may be mid-drag) — only a
 * singular one falls back.
 */
export function outputInverse(config: OutputConfig): { matrix: Mat3; valid: boolean; convex: boolean } {
  const inv = cornerPinInverse(config.corners);
  return { matrix: inv ?? IDENTITY_MAT3, valid: inv !== null, convex: isConvexQuad(config.corners) };
}

export function packOutputUniform(
  config: OutputConfig,
  opts: PackOptions,
  out: Float32Array<ArrayBuffer> = new Float32Array(OUTPUT_UNIFORM_FLOATS),
): Float32Array<ArrayBuffer> {
  const { matrix: m } = outputInverse(config);
  out.set([m[0], m[1], m[2], 0, m[3], m[4], m[5], 0, m[6], m[7], m[8], 0], 0);
  out.set([config.colour.gain, config.colour.gamma, config.colour.blackLevel, opts.generative ? 1 : 0], 12);
  out.set([TEST_PATTERN_IDS[config.testPattern], config.outline ? 1 : 0, opts.width, opts.height], 16);
  return out;
}
