import { lumaBt709 } from './bt709';
import type { LumaHistogram, ReduceF32 } from './types';

/** Min / max / mean luma over packed RGBA (4 floats per pixel, 0–1). */
export function reduceF32Luma(
  rgba: ArrayLike<number>,
  width: number,
  height: number,
): ReduceF32 {
  const pixelCount = Math.max(0, width * height);
  const limit = Math.min(pixelCount, Math.floor(rgba.length / 4));
  if (limit === 0) {
    return { min: 0, max: 0, mean: 0 };
  }
  let min = Number.POSITIVE_INFINITY;
  let max = Number.NEGATIVE_INFINITY;
  let sum = 0;
  for (let i = 0; i < limit; i++) {
    const o = i * 4;
    const y = lumaBt709(rgba[o], rgba[o + 1], rgba[o + 2]);
    if (y < min) min = y;
    if (y > max) max = y;
    sum += y;
  }
  return { min, max, mean: sum / limit };
}

/** Approximate reduce from a 256-bin luma histogram (GPU readback path). */
export function reduceF32FromHistogram(hist: LumaHistogram): ReduceF32 {
  const { bins, pixelCount } = hist;
  if (pixelCount <= 0) {
    return { min: 0, max: 0, mean: 0 };
  }
  let minBin = -1;
  let maxBin = 0;
  let weighted = 0;
  for (let i = 0; i < bins.length; i++) {
    const c = bins[i];
    if (c === 0) continue;
    if (minBin < 0) minBin = i;
    maxBin = i;
    weighted += c * ((i + 0.5) / 256);
  }
  if (minBin < 0) {
    return { min: 0, max: 0, mean: 0 };
  }
  return {
    min: minBin / 255,
    max: maxBin / 255,
    mean: weighted / pixelCount,
  };
}
