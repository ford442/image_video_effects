import { computeSpeedup, type SpeedupLeg } from './benchmarkSpeedup';

const leg = (overrides: Partial<SpeedupLeg> = {}): SpeedupLeg => ({
  avgFps: 60,
  avgTotalMs: 1,
  timingSource: 'wall-clock',
  ...overrides,
});
const gpu = (p50: number, extra: Partial<SpeedupLeg> = {}) =>
  leg({ timingSource: 'gpu-timestamp', totalMsStats: { p50 }, ...extra });

describe('computeSpeedup', () => {
  it('prefers GPU ms when both legs have timestamps', () => {
    const s = computeSpeedup(gpu(2, { uncappedMsPerFrame: 5 }), gpu(3, { uncappedMsPerFrame: 5 }), 1.25);
    expect(s.metric).toBe('gpu-ms');
    expect(s.ratio).toBeCloseTo(1.5);
    expect(s.likeForLike).toBe(true);
    expect(s.meetsGate).toBe(true);
    expect(s.gateReason).toBeUndefined();
  });

  it('falls back to uncapped ms when only one leg has timestamps', () => {
    const s = computeSpeedup(
      leg({ uncappedMsPerFrame: 4 }),
      gpu(3, { uncappedMsPerFrame: 6 }),
      1.25,
    );
    expect(s.metric).toBe('uncapped-ms');
    expect(s.ratio).toBeCloseTo(1.5);
    expect(s.meetsGate).toBe(true);
  });

  it('ignores a zero GPU median', () => {
    const s = computeSpeedup(gpu(0, { uncappedMsPerFrame: 2 }), gpu(1, { uncappedMsPerFrame: 2 }), 1.25);
    expect(s.metric).toBe('uncapped-ms');
  });

  it('falls back to FPS and flags a vsync cap', () => {
    const s = computeSpeedup(leg({ avgFps: 60 }), leg({ avgFps: 59.9 }), 1.25);
    expect(s.metric).toBe('fps');
    expect(s.ratio).toBeCloseTo(60 / 59.9);
    expect(s.meetsGate).toBe(false);
    expect(s.gateReason).toBe('fps (vsync-capped)');
  });

  it('keeps the mixed-source rule on the FPS fallback', () => {
    const s = computeSpeedup(leg({ avgFps: 60 }), gpu(0, { avgFps: 40 }), 1.25);
    expect(s.metric).toBe('fps');
    expect(s.ratio).toBeCloseTo(1.5);
    expect(s.likeForLike).toBe(false);
    expect(s.meetsGate).toBe(false);
    expect(s.gateReason).toBe('mixed timing sources');
  });

  it('meets the gate on a like-for-like uncapped FPS win', () => {
    const s = computeSpeedup(leg({ avgFps: 50 }), leg({ avgFps: 30 }), 1.25);
    expect(s.meetsGate).toBe(true);
    expect(s.gateReason).toBeUndefined();
  });

  it('uses frame ms when FPS is missing, and none when nothing was measured', () => {
    expect(computeSpeedup(leg({ avgFps: 0, avgTotalMs: 2 }), leg({ avgFps: 0, avgTotalMs: 3 }), 1.25))
      .toMatchObject({ metric: 'frame-ms', ratio: 1.5 });
    expect(computeSpeedup(leg({ avgFps: 0, avgTotalMs: 0 }), leg({ avgFps: 0, avgTotalMs: 0 }), 1.25))
      .toMatchObject({ metric: 'none', ratio: 0, meetsGate: false });
  });
});
