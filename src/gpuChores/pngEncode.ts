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
  ctx.putImageData(new ImageData(toPixels(rgba, width, height), width, height), 0, 0);
  return canvas.toDataURL('image/png').replace(/^data:image\/png;base64,/, '');
}

function toPixels(rgba: ArrayLike<number>, width: number, height: number): Uint8ClampedArray {
  const pixels = new Uint8ClampedArray(width * height * 4);
  for (let i = 0; i < width * height; i++) {
    const o = i * 4;
    pixels[o] = gammaEncode(rgba[o] ?? 0);
    pixels[o + 1] = gammaEncode(rgba[o + 1] ?? 0);
    pixels[o + 2] = gammaEncode(rgba[o + 2] ?? 0);
    const a = rgba[o + 3] ?? 1;
    pixels[o + 3] = Math.min(Math.max(a, 0), 1) * 255;
  }
  return pixels;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

/**
 * Same as rgbaFloatsToPngBase64, but also works without a DOM (the render
 * worker, #1314) by encoding through OffscreenCanvas.convertToBlob.
 */
export async function rgbaFloatsToPngBase64Async(
  rgba: ArrayLike<number>,
  width: number,
  height: number,
): Promise<string | null> {
  if (typeof document !== 'undefined') return rgbaFloatsToPngBase64(rgba, width, height);
  if (typeof OffscreenCanvas === 'undefined' || width <= 0 || height <= 0) return null;
  const canvas = new OffscreenCanvas(width, height);
  const ctx = canvas.getContext('2d');
  if (!ctx) return null;
  ctx.putImageData(new ImageData(toPixels(rgba, width, height), width, height), 0, 0);
  const blob = await canvas.convertToBlob({ type: 'image/png' });
  return bytesToBase64(new Uint8Array(await blob.arrayBuffer()));
}

export function gammaEncode(linear: number): number {
  const t = Math.min(Math.max(linear, 0), 1);
  return Math.pow(t, 1 / 2.2) * 255;
}
