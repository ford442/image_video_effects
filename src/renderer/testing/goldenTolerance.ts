/**
 * goldenTolerance.ts
 *
 * Tolerances for golden-frame tests that read pixels back through
 * `__pixelocity__.captureThumbnailPng` (#1512 Part C). The readback averages
 * the presented working texture down, gamma-encodes it (pngEncode.ts,
 * γ 2.2, clamped) and writes 8-bit PNG, so an expected linear value maps to
 * one byte per channel, and rgba16float storage, the downsample and the
 * rounding each move it by a little.
 *
 * Two measures:
 *   - channel delta (bytes): golden pixels against compositorReference.ts
 *   - CIE76 ΔE on 8-bit sRGB: two renders of the same shader (f16 vs f32)
 */

import { gammaEncode } from '../../gpuChores/pngEncode';

/** Max per-channel byte delta a golden pixel may show (FP16 storage + rounding). */
export const GOLDEN_CHANNEL_TOLERANCE = 3;

/** ΔE below which two renders count as the same colour (just-noticeable difference). */
export const EQUIVALENT_DELTA_E = 1;

/** The 8-bit value the thumbnail readback produces for a linear channel value. */
export function captureByte(linear: number): number {
  return Math.round(gammaEncode(linear));
}

/** Expected RGB bytes of a linear RGB(A) colour after readback. */
export function captureRgb(linear: readonly number[]): [number, number, number] {
  return [captureByte(linear[0] ?? 0), captureByte(linear[1] ?? 0), captureByte(linear[2] ?? 0)];
}

/** Largest absolute RGB byte difference between two pixels. */
export function maxChannelDelta(a: readonly number[], b: readonly number[]): number {
  let max = 0;
  for (let c = 0; c < 3; c++) max = Math.max(max, Math.abs((a[c] ?? 0) - (b[c] ?? 0)));
  return max;
}

function srgbToLinear(byte: number): number {
  const c = byte / 255;
  return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
}

/** CIE L*a*b* (D65) of an 8-bit sRGB pixel. */
export function srgb8ToLab(rgb: readonly number[]): [number, number, number] {
  const r = srgbToLinear(rgb[0] ?? 0);
  const g = srgbToLinear(rgb[1] ?? 0);
  const b = srgbToLinear(rgb[2] ?? 0);
  const x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047;
  const y = 0.2126729 * r + 0.7151522 * g + 0.072175 * b;
  const z = (0.0193339 * r + 0.119192 * g + 0.9503041 * b) / 1.08883;
  const f = (t: number) => (t > 216 / 24389 ? Math.cbrt(t) : (24389 / 27 * t + 16) / 116);
  const fx = f(x);
  const fy = f(y);
  const fz = f(z);
  return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
}

/** CIE76 colour difference between two 8-bit sRGB pixels. */
export function deltaE76(a: readonly number[], b: readonly number[]): number {
  const la = srgb8ToLab(a);
  const lb = srgb8ToLab(b);
  return Math.hypot(la[0] - lb[0], la[1] - lb[1], la[2] - lb[2]);
}

export interface DeltaEStats {
  mean: number;
  p95: number;
  max: number;
}

/** ΔE statistics over two same-sized RGBA (or RGB, `channels` = 3) byte images. */
export function imageDeltaE(a: ArrayLike<number>, b: ArrayLike<number>, channels = 4): DeltaEStats {
  const n = Math.min(a.length, b.length);
  const values: number[] = [];
  for (let i = 0; i + 2 < n; i += channels) {
    values.push(deltaE76([a[i] ?? 0, a[i + 1] ?? 0, a[i + 2] ?? 0], [b[i] ?? 0, b[i + 1] ?? 0, b[i + 2] ?? 0]));
  }
  if (values.length === 0) return { mean: 0, p95: 0, max: 0 };
  const sorted = [...values].sort((x, y) => x - y);
  const mean = values.reduce((s, v) => s + v, 0) / values.length;
  return {
    mean,
    p95: sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * 0.95))] ?? 0,
    max: sorted[sorted.length - 1] ?? 0,
  };
}
