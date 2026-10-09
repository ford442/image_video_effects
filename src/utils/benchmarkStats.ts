/**
 * Summary statistics for benchmark samples (#1357 T4).
 *
 * Pure so it can run in-page (useTestHarness.runBenchmark) and under Jest.
 * Percentiles are nearest-rank on a sorted copy; an empty input gives zeros.
 */
export interface BenchmarkStats {
  n: number;
  p50: number;
  p95: number;
  max: number;
  mean: number;
}

function nearestRank(sorted: number[], p: number): number {
  const rank = Math.ceil((p / 100) * sorted.length);
  return sorted[Math.min(sorted.length, Math.max(1, rank)) - 1];
}

export function computeBenchmarkStats(values: number[]): BenchmarkStats {
  const sorted = values.filter((v) => Number.isFinite(v)).sort((a, b) => a - b);
  const n = sorted.length;
  if (n === 0) return { n: 0, p50: 0, p95: 0, max: 0, mean: 0 };
  return {
    n,
    p50: nearestRank(sorted, 50),
    p95: nearestRank(sorted, 95),
    max: sorted[n - 1],
    mean: sorted.reduce((a, b) => a + b, 0) / n,
  };
}

/** Value changes in a per-frame series: one per timestamp readback (zeros skipped, #1080). */
export function countReadbacks(values: number[]): number {
  let count = 0;
  let prev: number | undefined;
  for (const v of values) {
    if (v > 0 && v !== prev) count += 1;
    prev = v;
  }
  return count;
}
