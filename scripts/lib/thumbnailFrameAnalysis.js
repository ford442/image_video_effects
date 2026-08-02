/**
 * Canvas frame analysis for thumbnail capture — black / magenta error detection.
 */

function isBlackFrame(stats, { minActive = 0.02, minLuminance = 0.01 } = {}) {
  return stats.activePixelRatio < minActive || stats.meanLuminance < minLuminance;
}

function isMagentaFrame(stats, { minMagentaRatio = 0.75 } = {}) {
  if (stats.magentaPixelRatio != null) {
    return stats.magentaPixelRatio >= minMagentaRatio;
  }
  const r = stats.meanR ?? 0;
  const g = stats.meanG ?? 0;
  const b = stats.meanB ?? 0;
  return r > 0.75 && g < 0.25 && b > 0.75;
}

function isErrorFrame(stats, opts = {}) {
  return isBlackFrame(stats, opts) || isMagentaFrame(stats, opts);
}

function classifyErrorFrame(stats) {
  const black = isBlackFrame(stats);
  const magenta = isMagentaFrame(stats);
  if (black && magenta) return 'error_frame';
  if (black) return 'black_frame';
  if (magenta) return 'magenta_frame';
  return null;
}

function formatFrameStats(stats) {
  const parts = [
    `meanLuminance=${(stats.meanLuminance ?? 0).toFixed(4)}`,
    `activePixelRatio=${(stats.activePixelRatio ?? 0).toFixed(4)}`,
  ];
  if (stats.magentaPixelRatio != null) {
    parts.push(`magentaPixelRatio=${stats.magentaPixelRatio.toFixed(4)}`);
  }
  if (stats.meanR != null) {
    parts.push(`meanRGB=(${(stats.meanR).toFixed(3)},${(stats.meanG).toFixed(3)},${(stats.meanB).toFixed(3)})`);
  }
  return parts.join(' ');
}

/** Analyze raw RGBA byte buffer (0–255 per channel). */
function analyzeRgbaBuffer(data, width, height) {
  let lumSum = 0;
  let active = 0;
  let magenta = 0;
  let rSum = 0;
  let gSum = 0;
  let bSum = 0;
  const pixels = width * height;
  for (let i = 0; i < data.length; i += 4) {
    const r = data[i] / 255;
    const g = data[i + 1] / 255;
    const b = data[i + 2] / 255;
    rSum += r;
    gSum += g;
    bSum += b;
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
    meanR: rSum / pixels,
    meanG: gSum / pixels,
    meanB: bSum / pixels,
  };
}

module.exports = {
  isBlackFrame,
  isMagentaFrame,
  isErrorFrame,
  classifyErrorFrame,
  formatFrameStats,
  analyzeRgbaBuffer,
};
