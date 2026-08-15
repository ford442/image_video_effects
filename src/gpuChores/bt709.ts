import { BT709_LUMA } from './types';

/** BT.709 luma for a linear-ish RGB triple in [0, 1]. */
export function lumaBt709(r: number, g: number, b: number): number {
  return BT709_LUMA.r * r + BT709_LUMA.g * g + BT709_LUMA.b * b;
}

/** Map luma in [0, 1] to a 256-bin index (Chromashift-style). */
export function lumaToBin(y: number): number {
  const t = y < 0 ? 0 : y > 1 ? 1 : y;
  const bin = Math.floor(t * 256);
  return bin > 255 ? 255 : bin;
}
