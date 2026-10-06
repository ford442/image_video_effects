/**
 * Speedup metric for the #1080 WASM promotion gate.
 *
 * FPS is capped at the display rate when both backends finish inside the frame
 * budget, so on a T4 it read 60 vs 60. The ratio now comes from the most
 * direct measurement both legs have:
 *   1. 'gpu-ms'      — median GPU timestamp span (both legs 'gpu-timestamp').
 *   2. 'uncapped-ms' — ms/frame of N frames submitted without rAF, timed to GPU idle.
 *   3. 'fps'         — the old metric, kept as a fallback ('frame-ms' when FPS is missing).
 * Ratios are WASM-over-TS speed: > 1 means WASM is faster.
 */

export type SpeedupMetric = 'gpu-ms' | 'uncapped-ms' | 'fps' | 'frame-ms' | 'none';

export interface SpeedupLeg {
  avgFps: number;
  avgTotalMs: number;
  timingSource?: string;
  totalMsStats?: { p50: number };
  uncappedMsPerFrame?: number;
}

export interface Speedup {
  ratio: number;
  metric: SpeedupMetric;
  /** Both legs measured the same quantity; the gate needs it. */
  likeForLike: boolean;
  meetsGate: boolean;
  gateReason?: string;
}

export const VSYNC_FPS = 60;
/** Both legs at ≥ 99% of the display rate: the FPS ratio says nothing. */
const VSYNC_CAPPED_FRACTION = 0.99;

function isVsyncCapped(wasm: SpeedupLeg, webgpu: SpeedupLeg, refreshHz: number): boolean {
  const floor = refreshHz * VSYNC_CAPPED_FRACTION;
  return wasm.avgFps >= floor && webgpu.avgFps >= floor;
}

export function computeSpeedup(
  wasm: SpeedupLeg,
  webgpu: SpeedupLeg,
  minRatio: number,
  refreshHz = VSYNC_FPS,
): Speedup {
  const gpuMs = (leg: SpeedupLeg) =>
    leg.timingSource === 'gpu-timestamp' ? leg.totalMsStats?.p50 ?? 0 : 0;
  const finish = (ratio: number, metric: SpeedupMetric, likeForLike: boolean, reason?: string): Speedup => {
    const ratioMet = ratio >= minRatio;
    const gateReason = ratioMet && !likeForLike ? 'mixed timing sources' : reason;
    return {
      ratio,
      metric,
      likeForLike,
      meetsGate: ratioMet && likeForLike,
      ...(gateReason ? { gateReason } : {}),
    };
  };

  if (gpuMs(wasm) > 0 && gpuMs(webgpu) > 0) {
    return finish(gpuMs(webgpu) / gpuMs(wasm), 'gpu-ms', true);
  }
  const wasmUncapped = wasm.uncappedMsPerFrame ?? 0;
  const webgpuUncapped = webgpu.uncappedMsPerFrame ?? 0;
  if (wasmUncapped > 0 && webgpuUncapped > 0) {
    return finish(webgpuUncapped / wasmUncapped, 'uncapped-ms', true);
  }

  // FPS fallback: the pre-#1080 rule (timing sources must match) still applies.
  const likeForLike = (wasm.timingSource ?? 'unavailable') === (webgpu.timingSource ?? 'unavailable');
  const capped = isVsyncCapped(wasm, webgpu, refreshHz) ? 'fps (vsync-capped)' : undefined;
  if (wasm.avgFps > 0 && webgpu.avgFps > 0) {
    return finish(wasm.avgFps / webgpu.avgFps, 'fps', likeForLike, capped);
  }
  if (wasm.avgTotalMs > 0 && webgpu.avgTotalMs > 0) {
    return finish(webgpu.avgTotalMs / wasm.avgTotalMs, 'frame-ms', likeForLike);
  }
  return finish(0, 'none', false);
}
