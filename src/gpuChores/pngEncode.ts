/** Linear float RGBA → PNG data URL payload (no `data:image/png;base64,` prefix). */
export function rgbaFloatsToPngBase64(
  rgba: ArrayLike<number>,
  width: number,
  height: number,
): string | null {
  if (typeof document === 'undefined' || width <= 0 || height <= 0) return null;
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext('2d');
  if (!ctx) return null;
  const pixels = new Uint8ClampedArray(width * height * 4);
  for (let i = 0; i < width * height; i++) {
    const o = i * 4;
    pixels[o] = gammaEncode(rgba[o] ?? 0);
    pixels[o + 1] = gammaEncode(rgba[o + 1] ?? 0);
    pixels[o + 2] = gammaEncode(rgba[o + 2] ?? 0);
    const a = rgba[o + 3] ?? 1;
    pixels[o + 3] = Math.min(Math.max(a, 0), 1) * 255;
  }
  ctx.putImageData(new ImageData(pixels, width, height), 0, 0);
  return canvas.toDataURL('image/png').replace(/^data:image\/png;base64,/, '');
}

export function gammaEncode(linear: number): number {
  const t = Math.min(Math.max(linear, 0), 1);
  return Math.pow(t, 1 / 2.2) * 255;
}
