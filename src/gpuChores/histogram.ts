import { lumaBt709, lumaToBin } from './bt709';
import { HISTOGRAM_BINS, LumaHistogram } from './types';

/** 256-bin BT.709 luma histogram over packed RGBA (4 floats per pixel, 0–1). */
export function lumaHistogramBt709(
  rgba: ArrayLike<number>,
  width: number,
  height: number,
): LumaHistogram {
  const bins = new Uint32Array(HISTOGRAM_BINS);
  const pixelCount = Math.max(0, width * height);
  const limit = Math.min(pixelCount, Math.floor(rgba.length / 4));
  for (let i = 0; i < limit; i++) {
    const o = i * 4;
    const y = lumaBt709(rgba[o], rgba[o + 1], rgba[o + 2]);
    bins[lumaToBin(y)] += 1;
  }
  return { bins, pixelCount: limit };
}
