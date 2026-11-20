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

/** Default DSSIM a golden frame may drift by (tests/golden-frames.swiftshader.spec.ts, #1401). */
export const GOLDEN_FRAME_DSSIM = 0.004;

/**
 * Structural dissimilarity of two same-sized RGBA (or RGB) byte images: (1 − mean SSIM) / 2
 * over non-overlapping `window`² luma blocks (BT.709 weights, the usual C1 / C2). 0 is
 * identical; dssim-style thresholds of a few 1e-3 accept rasteriser / driver noise and
 * reject a changed shader. Blocks also catch local changes a whole-image mean would hide:
 * the result is the mean, `worst` the most changed block.
 */
export function imageDssim(
  a: ArrayLike<number>,
  b: ArrayLike<number>,
  width: number,
  height: number,
  channels = 4,
  window = 8,
): { dssim: number; worst: number } {
  const C1 = (0.01 * 255) ** 2;
  const C2 = (0.03 * 255) ** 2;
  const luma = (img: ArrayLike<number>, i: number) =>
    0.2126 * (img[i] ?? 0) + 0.7152 * (img[i + 1] ?? 0) + 0.0722 * (img[i + 2] ?? 0);
  let sum = 0;
  let blocks = 0;
  let worst = 0;
  for (let by = 0; by + window <= height; by += window) {
    for (let bx = 0; bx + window <= width; bx += window) {
      let ma = 0, mb = 0, va = 0, vb = 0, cov = 0;
      const n = window * window;
      for (let y = by; y < by + window; y++) {
        for (let x = bx; x < bx + window; x++) {
          const i = (y * width + x) * channels;
          ma += luma(a, i);
          mb += luma(b, i);
        }
      }
      ma /= n;
      mb /= n;
      for (let y = by; y < by + window; y++) {
        for (let x = bx; x < bx + window; x++) {
          const i = (y * width + x) * channels;
          const da = luma(a, i) - ma;
          const db = luma(b, i) - mb;
          va += da * da;
          vb += db * db;
          cov += da * db;
        }
      }
      va /= n - 1;
      vb /= n - 1;
      cov /= n - 1;
      const ssim = ((2 * ma * mb + C1) * (2 * cov + C2)) / ((ma * ma + mb * mb + C1) * (va + vb + C2));
      sum += ssim;
      blocks++;
      worst = Math.max(worst, (1 - ssim) / 2);
    }
  }
  if (blocks === 0) return { dssim: 0, worst: 0 };
  return { dssim: (1 - sum / blocks) / 2, worst };
}
