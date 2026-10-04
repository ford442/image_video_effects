/**
 * Render-error classification for captured frames. Same thresholds as
 * scripts/lib/thumbnailHarness.mjs (isBlackFrame / isMagentaFrame) so the
 * in-app batch and the Playwright CLI agree on what counts as broken.
 */

export interface FrameStats {
  width: number;
  height: number;
  meanLuminance: number;
  activePixelRatio: number;
  magentaPixelRatio: number;
}

export type FrameErrorReason = 'black_frame' | 'magenta_frame' | 'error_frame';

export function analyzeImageData(data: Uint8ClampedArray, width: number, height: number): FrameStats {
  let lumSum = 0;
  let active = 0;
  let magenta = 0;
  const pixels = Math.max(1, width * height);
  for (let i = 0; i < data.length; i += 4) {
    const r = data[i] / 255;
    const g = data[i + 1] / 255;
    const b = data[i + 2] / 255;
    const lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    lumSum += lum;
    if (lum > 0.05) active++;
    if (r > 0.8 && g < 0.2 && b > 0.8) magenta++;
  }
  return {
    width,
    height,
    meanLuminance: lumSum / pixels,
    activePixelRatio: active / pixels,
    magentaPixelRatio: magenta / pixels,
  };
}

export function classifyFrame(stats: FrameStats): FrameErrorReason | null {
  const black = stats.activePixelRatio < 0.02 || stats.meanLuminance < 0.01;
  const magenta = stats.magentaPixelRatio >= 0.75;
  if (black && magenta) return 'error_frame';
  if (black) return 'black_frame';
  if (magenta) return 'magenta_frame';
  return null;
}

export function formatFrameStats(stats: FrameStats): string {
  return (
    `meanLuminance=${stats.meanLuminance.toFixed(4)} ` +
    `activePixelRatio=${stats.activePixelRatio.toFixed(4)} ` +
    `magentaPixelRatio=${stats.magentaPixelRatio.toFixed(4)}`
  );
}

/** Decodes a base64 PNG and measures it. */
export async function statsFromPngBase64(pngB64: string): Promise<FrameStats> {
  const bytes = Uint8Array.from(atob(pngB64), c => c.charCodeAt(0));
  const bitmap = await createImageBitmap(new Blob([bytes], { type: 'image/png' }));
  const canvas = document.createElement('canvas');
  canvas.width = bitmap.width;
  canvas.height = bitmap.height;
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('2D canvas unavailable for frame analysis');
  ctx.drawImage(bitmap, 0, 0);
  bitmap.close();
  const { data } = ctx.getImageData(0, 0, canvas.width, canvas.height);
  return analyzeImageData(data, canvas.width, canvas.height);
}
