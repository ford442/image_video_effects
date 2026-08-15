import type { AutoExposure, LumaHistogram } from './types';
import { reduceF32FromHistogram } from './reduce';

/** Rec.709 / photography middle grey. */
export const MIDDLE_GREY = 0.18;
const MIN_LUMA = 1e-4;
const MAX_GAIN = 16;
const MIN_GAIN = 1 / 16;

/** Auto-exposure from a BT.709 luma histogram. */
export function autoExposureFromHistogram(hist: LumaHistogram): AutoExposure {
  const { mean } = reduceF32FromHistogram(hist);
  return autoExposureFromMean(mean);
}

export function autoExposureFromMean(lumaMean: number): AutoExposure {
  const mean = Number.isFinite(lumaMean) ? lumaMean : 0;
  const denom = mean > MIN_LUMA ? mean : MIN_LUMA;
  let gain = MIDDLE_GREY / denom;
  if (gain > MAX_GAIN) gain = MAX_GAIN;
  if (gain < MIN_GAIN) gain = MIN_GAIN;
  return {
    lumaMean: mean,
    gain,
    ev: Math.log2(gain),
  };
}
