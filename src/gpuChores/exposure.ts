import type { AutoExposure, LumaHistogram } from './types';
import { reduceF32FromHistogram } from './reduce';

/** Rec.709 / photography middle grey. */
export const MIDDLE_GREY = 0.18;
const MIN_LUMA = 1e-4;
export const MAX_GAIN = 16;
export const MIN_GAIN = 1 / 16;

/** Clamp auto-exposure gain; non-finite values become 1. */
export function clampExposureGain(gain: number): number {
  if (!Number.isFinite(gain)) return 1;
  if (gain > MAX_GAIN) return MAX_GAIN;
  if (gain < MIN_GAIN) return MIN_GAIN;
  return gain;
}

/** RGB *= gain, alpha unchanged. Packed RGBA (4 floats/pixel). */
export function applyGain2d(
  rgba: ArrayLike<number>,
  width: number,
  height: number,
  gain: number,
): Float32Array {
  const g = clampExposureGain(gain);
  const n = Math.max(0, width * height);
  const out = new Float32Array(n * 4);
  for (let i = 0; i < n; i++) {
    const o = i * 4;
    out[o] = (rgba[o] ?? 0) * g;
    out[o + 1] = (rgba[o + 1] ?? 0) * g;
    out[o + 2] = (rgba[o + 2] ?? 0) * g;
    out[o + 3] = rgba[o + 3] ?? 0;
  }
  return out;
}

/** Auto-exposure from a BT.709 luma histogram. */
export function autoExposureFromHistogram(hist: LumaHistogram): AutoExposure {
  const { mean } = reduceF32FromHistogram(hist);
  return autoExposureFromMean(mean);
}

export function autoExposureFromMean(lumaMean: number): AutoExposure {
  const mean = Number.isFinite(lumaMean) ? lumaMean : 0;
  const denom = mean > MIN_LUMA ? mean : MIN_LUMA;
  let gain = MIDDLE_GREY / denom;
  if (gain > MAX_GAIN) gain = MAX_GAIN;
  if (gain < MIN_GAIN) gain = MIN_GAIN;
  return {
    lumaMean: mean,
    gain,
    ev: Math.log2(gain),
  };
}
