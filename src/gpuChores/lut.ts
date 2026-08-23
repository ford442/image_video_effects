import { lumaBt709, lumaToBin } from './bt709';
import { CLASSIFY_BANDS, LUT_SIZE } from './types';

/**
 * 8-band luma classification LUT (Chromashift-shaped mask).
 * Output byte is the band index 0..7.
 */
export function buildLumaClassifyLut(bands: number = CLASSIFY_BANDS): Uint8Array {
  const n = bands < 1 ? 1 : bands;
  const lut = new Uint8Array(LUT_SIZE);
  for (let i = 0; i < LUT_SIZE; i++) {
    lut[i] = Math.min(n - 1, Math.floor((i / LUT_SIZE) * n));
  }
  return lut;
}

/** Apply a 256-entry u8 LUT to packed RGBA luma; returns one byte per pixel. */
export function lutU8Map(
  rgba: ArrayLike<number>,
  width: number,
  height: number,
  lut: Uint8Array,
): Uint8Array {
  const pixelCount = Math.max(0, width * height);
  const limit = Math.min(pixelCount, Math.floor(rgba.length / 4));
  const out = new Uint8Array(limit);
  const lutLen = lut.length;
  for (let i = 0; i < limit; i++) {
    const o = i * 4;
    const bin = lumaToBin(lumaBt709(rgba[o], rgba[o + 1], rgba[o + 2]));
    out[i] = lut[bin < lutLen ? bin : lutLen - 1] ?? 0;
  }
  return out;
}
