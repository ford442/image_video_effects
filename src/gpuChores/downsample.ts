/** Box-filter downsample of packed RGBA (4 floats/pixel) to destW×destH. */
export function downsample2d(
  rgba: ArrayLike<number>,
  srcW: number,
  srcH: number,
  destW: number,
  destH: number,
  exposureGain = 1,
): Float32Array {
  const out = new Float32Array(Math.max(0, destW * destH * 4));
  if (srcW <= 0 || srcH <= 0 || destW <= 0 || destH <= 0) return out;
  const gain = exposureGain;

  for (let dy = 0; dy < destH; dy++) {
    const y0 = Math.floor((dy * srcH) / destH);
    const y1 = Math.max(y0 + 1, Math.floor(((dy + 1) * srcH) / destH));
    for (let dx = 0; dx < destW; dx++) {
      const x0 = Math.floor((dx * srcW) / destW);
      const x1 = Math.max(x0 + 1, Math.floor(((dx + 1) * srcW) / destW));
      let r = 0;
      let g = 0;
      let b = 0;
      let a = 0;
      let n = 0;
      for (let y = y0; y < y1 && y < srcH; y++) {
        for (let x = x0; x < x1 && x < srcW; x++) {
          const si = (y * srcW + x) * 4;
          r += rgba[si];
          g += rgba[si + 1];
          b += rgba[si + 2];
          a += rgba[si + 3];
          n += 1;
        }
      }
      const di = (dy * destW + dx) * 4;
      const inv = n > 0 ? 1 / n : 0;
      out[di] = r * inv * gain;
      out[di + 1] = g * inv * gain;
      out[di + 2] = b * inv * gain;
      out[di + 3] = a * inv;
    }
  }
  return out;
}
