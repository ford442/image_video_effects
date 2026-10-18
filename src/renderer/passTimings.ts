/**
 * passTimings.ts
 *
 * Per-pass GPU timing record shared by the TS profiler (webgpu/WebGPUTiming.ts),
 * diagnostics, the flame strip, adaptive performance and the WASM mirror
 * (#1314 WP-4 / WP-5). One entry per graph node / slot step / fixed pass.
 */

export type PassKind = 'compute' | 'present' | 'video' | 'input' | 'chores' | 'resample';

export interface PassTiming {
  /** Stable across frames: `${slot}:${nodeId ?? entry}` for compute, the label otherwise. */
  key: string;
  label: string;
  kind: PassKind;
  slot?: number;
  /** The slot's shader (graph root for graph nodes). */
  shaderId?: string;
  /** Pipeline actually dispatched (chain step or graph entry). */
  entry?: string;
  nodeId?: string;
  /** Resolution scale the pass ran at (1 = full working size). */
  scale: number;
  /** Smoothed GPU milliseconds per frame, summed over the node's iterations. */
  gpuMs: number;
  /** Dispatches folded into this entry last frame (graph `repeat`). */
  iterations: number;
}

/** Sum of compute-pass GPU time (excludes present / input / video / chores). */
export function computeGpuMs(passes: readonly PassTiming[]): number {
  return passes.reduce((sum, p) => sum + (p.kind === 'compute' ? p.gpuMs : 0), 0);
}

/** The compute pass with the largest share of GPU time, if any. */
export function heaviestComputePass(passes: readonly PassTiming[]): PassTiming | null {
  let best: PassTiming | null = null;
  for (const p of passes) {
    if (p.kind === 'compute' && (!best || p.gpuMs > best.gpuMs)) best = p;
  }
  return best;
}
