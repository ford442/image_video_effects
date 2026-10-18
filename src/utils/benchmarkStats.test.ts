import { computeBenchmarkStats, countReadbacks } from './benchmarkStats';

describe('computeBenchmarkStats', () => {
  it('gives exact nearest-rank percentiles', () => {
    expect(computeBenchmarkStats([100, 10, 20, 12, 15])).toEqual({
      n: 5,
      p50: 15,
      p95: 100,
      max: 100,
      mean: 31.4,
    });
  });

  it('separates p95 from max once there are enough samples', () => {
    const values = Array.from({ length: 100 }, (_, i) => i + 1);
    const stats = computeBenchmarkStats(values);
    expect(stats.p50).toBe(50);
    expect(stats.p95).toBe(95);
    expect(stats.max).toBe(100);
  });

  it('returns zeros, not NaN, for no samples', () => {
    expect(computeBenchmarkStats([])).toEqual({ n: 0, p50: 0, p95: 0, max: 0, mean: 0 });
    expect(computeBenchmarkStats([NaN, Infinity])).toEqual({ n: 0, p50: 0, p95: 0, max: 0, mean: 0 });
  });

  it('keeps p50 ≤ p95 ≤ max on random inputs', () => {
    for (let trial = 0; trial < 200; trial++) {
      const n = 1 + Math.floor(Math.random() * 120);
      const values = Array.from({ length: n }, () => Math.random() * 50);
      const s = computeBenchmarkStats(values);
      expect(s.n).toBe(n);
      expect(s.p50).toBeLessThanOrEqual(s.p95);
      expect(s.p95).toBeLessThanOrEqual(s.max);
      expect(s.max).toBe(Math.max(...values));
    }
  });

  it('does not mutate its input', () => {
    const values = [3, 1, 2];
    computeBenchmarkStats(values);
    expect(values).toEqual([3, 1, 2]);
  });
});

describe('countReadbacks', () => {
  it('counts value changes and skips zeros', () => {
    expect(countReadbacks([])).toBe(0);
    expect(countReadbacks([0, 0, 1.2, 1.2, 1.2, 1.4, 1.4, 1.2])).toBe(3);
  });
});
