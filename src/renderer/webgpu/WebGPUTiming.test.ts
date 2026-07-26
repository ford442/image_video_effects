/**
 * WebGPUTiming.test.ts — GPU timestamp helpers + honesty gate + readback fallback.
 */

import {
  TimestampPhaseTracker,
  buildGPUTimings,
  timestampDeltaMs,
  stampsIndicateRealGpuTimings,
  decodeGpuTimings,
  pickComputeTimestampWrites,
  pickPresentTimestampWrites,
  encodeResolveAndCopy,
  scheduleTimestampReadback,
  createTimestampQueries,
  createDisabledTimestampQueries,
  destroyTimestampQueries,
  kTsFrameStart,
  kTsComputeEnd,
  kTsParallelStart,
  kTsParallelEnd,
  kTsChainedStart,
  kTsChainedEnd,
  kTsPresentStart,
  kTsPresentEnd,
  TS_QUERY_COUNT,
  STAGING_RING_DEPTH,
  WebGPUTimestampQueries,
} from './WebGPUTiming';

const BU = {
  MAP_READ: 0x0001,
  COPY_DST: 0x0008,
  COPY_SRC: 0x0004,
  QUERY_RESOLVE: 0x0200,
} as const;

beforeAll(() => {
  (global as unknown as { GPUBufferUsage: typeof BU }).GPUBufferUsage = BU;
  (global as unknown as { GPUMapMode: { READ: number } }).GPUMapMode = { READ: 0x0001 };
});

function makeStamps(partial: Partial<Record<number, bigint>>): BigUint64Array {
  const stamps = new BigUint64Array(TS_QUERY_COUNT);
  for (const [idx, val] of Object.entries(partial)) {
    stamps[Number(idx)] = val as bigint;
  }
  return stamps;
}

describe('timestampDeltaMs', () => {
  it('returns 0 when end <= start or period is 0', () => {
    expect(timestampDeltaMs(10n, 10n, 1)).toBe(0);
    expect(timestampDeltaMs(10n, 5n, 1)).toBe(0);
    expect(timestampDeltaMs(0n, 1000n, 0)).toBe(0);
  });

  it('converts tick deltas to ms via period', () => {
    // 1_000_000 ticks * 1 ns = 1 ms
    expect(timestampDeltaMs(0n, 1_000_000n, 1)).toBe(1);
  });
});

describe('honesty gate — buildGPUTimings', () => {
  const base = { parallelTime: 1, chainedTime: 2, totalTime: 3 };

  it('reports wall-clock when feature present but hasRealGpuTimings=false', () => {
    const t = buildGPUTimings(base, true, false);
    expect(t.available).toBe(false);
    expect(t.timingSource).toBe('wall-clock');
    expect(t.totalTime).toBe(3);
  });

  it('reports gpu-timestamp only when feature + hasRealGpuTimings', () => {
    const t = buildGPUTimings(base, true, true);
    expect(t.available).toBe(true);
    expect(t.timingSource).toBe('gpu-timestamp');
  });

  it('defaults hasRealGpuTimings to false', () => {
    const t = buildGPUTimings(base, true);
    expect(t.available).toBe(false);
    expect(t.timingSource).toBe('wall-clock');
  });
});

describe('stamp validation + decode', () => {
  it('stampsIndicateRealGpuTimings requires monotonic frame span', () => {
    expect(stampsIndicateRealGpuTimings(makeStamps({}))).toBe(false);
    expect(
      stampsIndicateRealGpuTimings(
        makeStamps({ [kTsFrameStart]: 100n, [kTsPresentEnd]: 200n }),
      ),
    ).toBe(true);
    expect(
      stampsIndicateRealGpuTimings(
        makeStamps({ [kTsFrameStart]: 100n, [kTsComputeEnd]: 150n }),
      ),
    ).toBe(true);
  });

  it('decodeGpuTimings fills parallel/chained/total from indices', () => {
    const stamps = makeStamps({
      [kTsFrameStart]: 1000n,
      [kTsParallelStart]: 1000n,
      [kTsParallelEnd]: 2000n,
      [kTsChainedStart]: 2000n,
      [kTsChainedEnd]: 3000n,
      [kTsComputeEnd]: 3000n,
      [kTsPresentStart]: 3000n,
      [kTsPresentEnd]: 4000n,
    });
    const decoded = decodeGpuTimings(stamps, 1, { hadParallel: true, hadChained: true });
    expect(decoded.valid).toBe(true);
    expect(decoded.timings.parallelTime).toBeCloseTo(0.001);
    expect(decoded.timings.chainedTime).toBeCloseTo(0.001);
    expect(decoded.timings.totalTime).toBeCloseTo(0.003);
  });
});

describe('pickComputeTimestampWrites / pickPresentTimestampWrites', () => {
  const querySet = { __brand: 'GPUQuerySet' } as unknown as GPUQuerySet;

  it('first parallel pass claims frame start + parallel end', () => {
    const tracker = new TimestampPhaseTracker();
    const writes = pickComputeTimestampWrites(tracker, querySet, 'parallel', false);
    expect(writes.beginningOfPassWriteIndex).toBe(kTsFrameStart);
    expect(writes.endOfPassWriteIndex).toBe(kTsParallelEnd);
    expect(tracker.tsFrameStartWritten).toBe(true);
    expect(tracker.tsParallelStartWritten).toBe(true);
  });

  it('first chained after parallel claims chained start', () => {
    const tracker = new TimestampPhaseTracker();
    pickComputeTimestampWrites(tracker, querySet, 'parallel', false);
    const writes = pickComputeTimestampWrites(tracker, querySet, 'chained', true);
    expect(writes.beginningOfPassWriteIndex).toBe(kTsChainedStart);
    expect(writes.endOfPassWriteIndex).toBe(kTsComputeEnd);
  });

  it('present writes require frame start', () => {
    const tracker = new TimestampPhaseTracker();
    expect(pickPresentTimestampWrites(tracker, querySet)).toBeUndefined();
    tracker.tsFrameStartWritten = true;
    const writes = pickPresentTimestampWrites(tracker, querySet)!;
    expect(writes.beginningOfPassWriteIndex).toBe(kTsPresentStart);
    expect(writes.endOfPassWriteIndex).toBe(kTsPresentEnd);
  });
});

describe('createTimestampQueries', () => {
  it('returns disabled state when feature absent', () => {
    const device = {
      features: { has: () => false },
      queue: { timestampPeriod: 1 },
      createQuerySet: jest.fn(),
      createBuffer: jest.fn(),
    } as unknown as GPUDevice;
    const t = createTimestampQueries(device);
    expect(t.supportsTimestampQuery).toBe(false);
    expect(device.createQuerySet).not.toHaveBeenCalled();
  });

  it('returns disabled when timestamp period is 0', () => {
    const device = {
      features: { has: (f: string) => f === 'timestamp-query' },
      queue: { timestampPeriod: 0 },
      createQuerySet: jest.fn(),
      createBuffer: jest.fn(),
    } as unknown as GPUDevice;
    const t = createTimestampQueries(device);
    expect(t.supportsTimestampQuery).toBe(false);
  });

  it('allocates query set + resolve + staging ring when feature present', () => {
    const device = {
      features: { has: (f: string) => f === 'timestamp-query' },
      queue: { timestampPeriod: 10 },
      createQuerySet: jest.fn(() => ({ destroy: jest.fn() })),
      createBuffer: jest.fn(() => ({ destroy: jest.fn(), mapAsync: jest.fn() })),
    } as unknown as GPUDevice;
    const t = createTimestampQueries(device);
    expect(t.supportsTimestampQuery).toBe(true);
    expect(t.timestampPeriodNs).toBe(10);
    expect(t.stagingRing).toHaveLength(STAGING_RING_DEPTH);
    expect(device.createQuerySet).toHaveBeenCalledWith({ type: 'timestamp', count: 8 });
    destroyTimestampQueries(t);
  });
});

describe('encodeResolveAndCopy + scheduleTimestampReadback', () => {
  function makeTiming(overrides: Partial<WebGPUTimestampQueries> = {}): WebGPUTimestampQueries {
    const staging = {
      mapAsync: jest.fn(),
      getMappedRange: jest.fn(),
      unmap: jest.fn(),
      destroy: jest.fn(),
    };
    const timing = createDisabledTimestampQueries();
    timing.supportsTimestampQuery = true;
    timing.querySet = { destroy: jest.fn() } as unknown as GPUQuerySet;
    timing.queryBuffer = { destroy: jest.fn() } as unknown as GPUBuffer;
    timing.stagingRing = [staging as unknown as GPUBuffer, { ...staging } as unknown as GPUBuffer];
    timing.timestampPeriodNs = 1;
    timing.tracker.tsFrameStartWritten = true;
    timing.tracker.hadParallel = true;
    Object.assign(timing, overrides);
    return timing;
  }

  it('skips resolve when readback is pending', () => {
    const timing = makeTiming({ readbackPending: true });
    const encoder = {
      resolveQuerySet: jest.fn(),
      copyBufferToBuffer: jest.fn(),
    } as unknown as GPUCommandEncoder;
    expect(encodeResolveAndCopy(encoder, timing)).toBeNull();
    expect(encoder.resolveQuerySet).not.toHaveBeenCalled();
  });

  it('encodes resolve + copy and schedules readback success → hasRealGpuTimings', async () => {
    const stamps = makeStamps({
      [kTsFrameStart]: 100n,
      [kTsParallelStart]: 100n,
      [kTsParallelEnd]: 200n,
      [kTsComputeEnd]: 200n,
      [kTsPresentEnd]: 300n,
    });
    const staging = {
      mapAsync: jest.fn().mockResolvedValue(undefined),
      getMappedRange: jest.fn(() => {
        const buf = new ArrayBuffer(TS_QUERY_COUNT * 8);
        new BigUint64Array(buf).set(stamps);
        return buf;
      }),
      unmap: jest.fn(),
      destroy: jest.fn(),
    };
    const timing = makeTiming();
    timing.stagingRing = [staging as unknown as GPUBuffer, staging as unknown as GPUBuffer];

    const encoder = {
      resolveQuerySet: jest.fn(),
      copyBufferToBuffer: jest.fn(),
    } as unknown as GPUCommandEncoder;

    const slot = encodeResolveAndCopy(encoder, timing);
    expect(slot).toBe(0);
    expect(encoder.resolveQuerySet).toHaveBeenCalled();
    expect(encoder.copyBufferToBuffer).toHaveBeenCalled();

    scheduleTimestampReadback(timing, slot!);
    expect(timing.readbackPending).toBe(true);
    // Must not await in submit path — promise is fire-and-forget.
    expect(staging.mapAsync).toHaveBeenCalledWith(GPUMapMode.READ);

    await staging.mapAsync.mock.results[0].value;
    // allow microtask for .then
    await Promise.resolve();

    expect(timing.hasRealGpuTimings).toBe(true);
    expect(timing.readbackPending).toBe(false);
    expect(timing.gpuTimings.totalTime).toBeGreaterThan(0);
    expect(staging.unmap).toHaveBeenCalled();
  });

  it('mapAsync rejection clears pending and hasRealGpuTimings', async () => {
    const staging = {
      mapAsync: jest.fn().mockRejectedValue(new Error('device lost')),
      getMappedRange: jest.fn(),
      unmap: jest.fn(),
      destroy: jest.fn(),
    };
    const timing = makeTiming({ hasRealGpuTimings: true });
    timing.stagingRing = [staging as unknown as GPUBuffer];

    scheduleTimestampReadback(timing, 0);
    await Promise.resolve();
    await Promise.resolve();

    expect(timing.readbackPending).toBe(false);
    expect(timing.hasRealGpuTimings).toBe(false);
  });
});
