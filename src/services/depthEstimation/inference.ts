/**
 * Run depth inference and produce normalized map for updateDepthMap.
 * Errors are returned, never thrown — depth must never brick the renderer.
 */

import type { DepthEstimatorPipeline, NormalizedDepthMap } from './types';
import { classifyDepthLoadError, normalizeDepthMap } from './types';

export interface DepthInferenceResult {
  ok: true;
  map: NormalizedDepthMap;
}

export interface DepthInferenceFailure {
  ok: false;
  message: string;
  phase: 'error' | 'offline' | 'cancelled';
}

export type DepthInferenceOutcome = DepthInferenceResult | DepthInferenceFailure;

export async function runDepthInference(
  pipeline: DepthEstimatorPipeline,
  imageUrl: string
): Promise<DepthInferenceOutcome> {
  try {
    const output = await pipeline(imageUrl);
    const map = normalizeDepthMap(output.predicted_depth);
    return { ok: true, map };
  } catch (error) {
    const classified = classifyDepthLoadError(error);
    console.error('[depth] inference failed:', error);
    return {
      ok: false,
      message: classified.message,
      phase: classified.phase === 'cancelled' ? 'cancelled' : classified.phase,
    };
  }
}
