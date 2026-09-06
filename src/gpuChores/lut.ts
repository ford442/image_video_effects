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

/**
 * Unpack rgba8unorm classifyTex (R = band 0..7) into one byte per pixel.
 * `bytesPerRow` must match the GPU copy (256-byte aligned).
 */
export function unpackClassifyRgba8(
  packed: Uint8Array,
  width: number,
  height: number,
  bytesPerRow: number,
): Uint8Array {
  const out = new Uint8Array(Math.max(0, width * height));
  const rowStride = Math.max(bytesPerRow, width * 4);
  for (let y = 0; y < height; y++) {
    const row = y * rowStride;
    for (let x = 0; x < width; x++) {
      out[y * width + x] = packed[row + x * 4] ?? 0;
    }
  }
  return out;
}

/** Distinct hues for Dev Tools false-color (band 0..7). */
export const CLASSIFY_FALSE_COLOR: ReadonlyArray<[number, number, number]> = [
  [20, 24, 48],
  [48, 72, 160],
  [32, 140, 180],
  [40, 180, 96],
  [220, 196, 48],
  [232, 128, 36],
  [220, 56, 64],
  [200, 80, 200],
];

/** Band indices → RGBA8 false-color (4 bytes/pixel). */
export function classifyBandsToRgba(
  bands: ArrayLike<number>,
  width: number,
  height: number,
): Uint8ClampedArray {
  const n = Math.max(0, width * height);
  const out = new Uint8ClampedArray(n * 4);
  const palette = CLASSIFY_FALSE_COLOR;
  for (let i = 0; i < n; i++) {
    const band = Math.max(0, Math.min(palette.length - 1, bands[i] ?? 0));
    const rgb = palette[band];
    const o = i * 4;
    out[o] = rgb[0];
    out[o + 1] = rgb[1];
    out[o + 2] = rgb[2];
    out[o + 3] = 255;
  }
  return out;
}
