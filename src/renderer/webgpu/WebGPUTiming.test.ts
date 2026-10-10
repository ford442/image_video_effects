/**
 * WebGPUTiming.test.ts — per-pass timestamp profiler (#1314 WP-4): query
 * allocation, resolve/readback cadence, decode, smoothing and the honesty gate.
 */

import {
  buildGPUTimings,
  createDisabledTimestampQueries,
  createTimestampQueries,
  decodePassTimings,
  destroyTimestampQueries,
  encodeResolveAndCopy,
  MAX_PROFILED_PASSES,
  PassProfileMeta,
  profilePass,
  QUERY_COUNT,
  READBACK_INTERVAL_MS,
  scheduleTimestampReadback,
  smoothPassTimings,
  STAGING_RING_DEPTH,
  timestampDeltaMs,
  WebGPUTimestampQueries,
} from './WebGPUTiming';
import { computeGpuMs, heaviestComputePass } from '../passTimings';

beforeAll(() => {
  const g = globalThis as Record<string, unknown>;
  g.GPUMapMode ??= { READ: 1, WRITE: 2 };
  g.GPUBufferUsage ??= { MAP_READ: 1, COPY_SRC: 4, COPY_DST: 8, QUERY_RESOLVE: 512 };
});

function stagingBuffer(stamps?: bigint[]) {
  return {
    mapAsync: jest.fn().mockResolvedValue(undefined),
    getMappedRange: jest.fn((_offset = 0, size = QUERY_COUNT * 8) => {
      const buf = new ArrayBuffer(size);
      if (stamps) new BigUint64Array(buf).set(stamps.slice(0, size / 8));
      return buf;
    }),
    unmap: jest.fn(),
    destroy: jest.fn(),
  };
}

function enabledTiming(overrides: Partial<WebGPUTimestampQueries> = {}): WebGPUTimestampQueries {
  const timing = createDisabledTimestampQueries();
  timing.supportsTimestampQuery = true;
  timing.querySet = { destroy: jest.fn() } as unknown as GPUQuerySet;
  timing.queryBuffer = { destroy: jest.fn() } as unknown as GPUBuffer;
  timing.stagingRing = [stagingBuffer(), stagingBuffer()] as unknown as GPUBuffer[];
  timing.stagingBusy = [false, false];
  timing.timestampPeriodNs = 1;
  Object.assign(timing, overrides);
  return timing;
}

const encoderStub = () => ({
  resolveQuerySet: jest.fn(),
  copyBufferToBuffer: jest.fn(),
}) as unknown as GPUCommandEncoder & { resolveQuerySet: jest.Mock; copyBufferToBuffer: jest.Mock };

const compute = (slot: number, nodeId: string, mode: 'parallel' | 'chained' = 'chained'): PassProfileMeta => ({
  kind: 'compute',
  label: `graph-${nodeId}`,
  mode,
  slot,
  shaderId: 'g',
  entry: `g-${nodeId}`,
  nodeId,
});

describe('timestampDeltaMs', () => {
  it('converts ns deltas to ms and clamps reversed / zero-period stamps', () => {
    expect(timestampDeltaMs(1_000_000n, 3_500_000n, 1)).toBe(2.5);
    expect(timestampDeltaMs(10n, 5n, 1)).toBe(0);
    expect(timestampDeltaMs(0n, 100n, 0)).toBe(0);
  });
});

describe('profilePass', () => {
  it('hands each pass its own begin/end pair in frame order', () => {
    const timing = enabledTiming();
    const a = profilePass(timing, compute(0, 'a'));
    const b = profilePass(timing, { kind: 'present', label: 'present' });
    expect(a).toMatchObject({ beginningOfPassWriteIndex: 0, endOfPassWriteIndex: 1 });
    expect(b).toMatchObject({ beginningOfPassWriteIndex: 2, endOfPassWriteIndex: 3 });
    expect(timing.frame.passes.map((p) => p.label)).toEqual(['graph-a', 'present']);
  });

  it('never writes a query index twice in a frame, and overflows cleanly', () => {
    const timing = enabledTiming();
    const indices = new Set<number>();
    for (let i = 0; i < MAX_PROFILED_PASSES + 5; i++) {
      const w = profilePass(timing, compute(0, `n${i}`));
      if (!w) continue;
      const begin = w.beginningOfPassWriteIndex ?? -1;
      const end = w.endOfPassWriteIndex ?? -1;
      expect(indices.has(begin)).toBe(false);
      expect(indices.has(end)).toBe(false);
      expect(begin).toBeLessThan(end);
      indices.add(begin);
      indices.add(end);
    }
    expect(indices.size).toBe(QUERY_COUNT);
    expect(timing.frame.overflow).toBe(5);
  });

  it('returns nothing when timing is disabled', () => {
    const timing = createDisabledTimestampQueries();
    expect(profilePass(timing, compute(0, 'a'))).toBeUndefined();
    expect(timing.frame.passes).toHaveLength(0);
  });
});

describe('decodePassTimings', () => {
  it('sums graph iterations per node and derives parallel / chained / total spans', () => {
    const passes: PassProfileMeta[] = [
      compute(0, 'p', 'parallel'),
      compute(1, 'step'),
      compute(1, 'step'),
      compute(1, 'render'),
      { kind: 'present', label: 'present' },
    ];
    const stamps = new BigUint64Array([
      1_000_000n, 2_000_000n, // p: 1 ms
      2_000_000n, 3_000_000n, // step: 1 ms
      3_000_000n, 5_000_000n, // step: 2 ms
      5_000_000n, 5_500_000n, // render: 0.5 ms
      6_000_000n, 6_250_000n, // present: 0.25 ms
    ]);
    const decoded = decodePassTimings(stamps, passes, 1);
    expect(decoded.valid).toBe(true);
    expect(decoded.passes.map((p) => [p.key, p.gpuMs, p.iterations])).toEqual([
      ['0:p', 1, 1],
      ['1:step', 3, 2],
      ['1:render', 0.5, 1],
      ['present', 0.25, 1],
    ]);
    expect(decoded.timings).toEqual({ parallelTime: 1, chainedTime: 3.5, totalTime: 5.25 });
    expect(computeGpuMs(decoded.passes)).toBe(4.5);
    expect(heaviestComputePass(decoded.passes)?.key).toBe('1:step');
  });

  it('is invalid when every stamp is zero (quantized / blocked timestamps)', () => {
    const decoded = decodePassTimings(new BigUint64Array(4), [compute(0, 'a'), compute(0, 'b')], 1);
    expect(decoded.valid).toBe(false);
    expect(decoded.passes.every((p) => p.gpuMs === 0)).toBe(true);
  });
});

describe('smoothPassTimings', () => {
  it('moves toward new values and drops passes that stopped running', () => {
    const prev = decodePassTimings(new BigUint64Array([0n, 0n]), [], 1).passes;
    expect(prev).toEqual([]);
    const a = { key: 'a', label: 'a', kind: 'compute' as const, scale: 1, gpuMs: 10, iterations: 1 };
    const b = { ...a, key: 'b', label: 'b', gpuMs: 4 };
    const first = smoothPassTimings([], [a, b]);
    const second = smoothPassTimings(first, [{ ...a, gpuMs: 20 }], 0.5);
    expect(second).toEqual([{ ...a, gpuMs: 15 }]);
  });
});

describe('createTimestampQueries', () => {
  it('returns disabled state when the feature is absent', () => {
    const device = {
      features: { has: () => false },
      queue: {},
      createQuerySet: jest.fn(),
      createBuffer: jest.fn(),
    } as unknown as GPUDevice;
    expect(createTimestampQueries(device).supportsTimestampQuery).toBe(false);
    expect(device.createQuerySet).not.toHaveBeenCalled();
  });

  it('returns disabled when a legacy timestampPeriod is explicitly 0', () => {
    const device = {
      features: { has: (f: string) => f === 'timestamp-query' },
      queue: { timestampPeriod: 0 },
      createQuerySet: jest.fn(),
      createBuffer: jest.fn(),
    } as unknown as GPUDevice;
    expect(createTimestampQueries(device).supportsTimestampQuery).toBe(false);
  });

  it('treats an undefined timestampPeriod (current spec, Chrome) as 1 ns', () => {
    const device = {
      features: { has: (f: string) => f === 'timestamp-query' },
      queue: {},
      createQuerySet: jest.fn(() => ({ destroy: jest.fn() })),
      createBuffer: jest.fn(() => ({ destroy: jest.fn(), mapAsync: jest.fn() })),
    } as unknown as GPUDevice;
    const t = createTimestampQueries(device);
    expect(t.supportsTimestampQuery).toBe(true);
    expect(t.timestampPeriodNs).toBe(1);
    expect(t.stagingRing).toHaveLength(STAGING_RING_DEPTH);
    expect(device.createQuerySet).toHaveBeenCalledWith({ type: 'timestamp', count: QUERY_COUNT });
    destroyTimestampQueries(t);
    expect(t.supportsTimestampQuery).toBe(false);
  });
});

describe('encodeResolveAndCopy + scheduleTimestampReadback', () => {
  it('does nothing when no pass was stamped this frame', () => {
    const timing = enabledTiming();
    const encoder = encoderStub();
    expect(encodeResolveAndCopy(encoder, timing, 1000)).toBeNull();
    expect(encoder.resolveQuerySet).not.toHaveBeenCalled();
  });

  it('resolves every stamped frame but copies for readback at most every interval', () => {
    const timing = enabledTiming();
    profilePass(timing, compute(0, 'a'));
    const first = encoderStub();
    const ticket = encodeResolveAndCopy(first, timing, 1000);
    expect(first.resolveQuerySet).toHaveBeenCalledWith(timing.querySet, 0, 2, timing.queryBuffer, 0);
    expect(first.copyBufferToBuffer).toHaveBeenCalledTimes(1);
    expect(ticket?.passes).toHaveLength(1);

    const soon = encoderStub();
    expect(encodeResolveAndCopy(soon, timing, 1000 + READBACK_INTERVAL_MS - 1)).toBeNull();
    expect(soon.resolveQuerySet).toHaveBeenCalled();
    expect(soon.copyBufferToBuffer).not.toHaveBeenCalled();

    const later = encoderStub();
    expect(encodeResolveAndCopy(later, timing, 1000 + READBACK_INTERVAL_MS)).not.toBeNull();
  });

  it('resolves without copy when every staging slot is busy', () => {
    const timing = enabledTiming({ stagingBusy: [true, true] });
    profilePass(timing, compute(0, 'a'));
    const encoder = encoderStub();
    expect(encodeResolveAndCopy(encoder, timing, 1000)).toBeNull();
    expect(encoder.resolveQuerySet).toHaveBeenCalled();
    expect(encoder.copyBufferToBuffer).not.toHaveBeenCalled();
  });

  it('decodes a readback into smoothed pass timings and flips the honesty gate', async () => {
    const staging = stagingBuffer([1_000_000n, 3_000_000n, 3_000_000n, 3_500_000n]);
    const timing = enabledTiming({ stagingRing: [staging, staging] as unknown as GPUBuffer[] });
    profilePass(timing, compute(2, 'render'));
    profilePass(timing, { kind: 'present', label: 'present' });
    const ticket = encodeResolveAndCopy(encoderStub(), timing, 1000);
    if (!ticket) throw new Error('expected a readback ticket');

    scheduleTimestampReadback(timing, ticket);
    expect(timing.stagingBusy[0]).toBe(true);
    expect(staging.mapAsync).toHaveBeenCalledWith(GPUMapMode.READ, 0, 32);
    await Promise.resolve();
    await Promise.resolve();

    expect(timing.hasRealGpuTimings).toBe(true);
    expect(timing.stagingBusy[0]).toBe(false);
    expect(timing.passTimings.map((p) => [p.key, p.gpuMs])).toEqual([['2:render', 2], ['present', 0.5]]);
    expect(timing.gpuTimings.totalTime).toBe(2.5);

    const gt = buildGPUTimings(timing.gpuTimings, true, timing.hasRealGpuTimings, timing.passTimings);
    expect(gt).toMatchObject({ available: true, timingSource: 'gpu-timestamp' });
    expect(gt.passes).toHaveLength(2);
  });

  it('mapAsync rejection releases the slot and clears hasRealGpuTimings', async () => {
    const staging = stagingBuffer();
    staging.mapAsync.mockRejectedValue(new Error('device lost'));
    const timing = enabledTiming({
      hasRealGpuTimings: true,
      stagingRing: [staging] as unknown as GPUBuffer[],
      stagingBusy: [false],
    });
    profilePass(timing, compute(0, 'a'));
    scheduleTimestampReadback(timing, { slot: 0, passes: [...timing.frame.passes], overflow: 0 });
    await Promise.resolve();
    await Promise.resolve();
    expect(timing.readbackPending).toBe(false);
    expect(timing.stagingBusy[0]).toBe(false);
    expect(timing.hasRealGpuTimings).toBe(false);
  });
});

describe('buildGPUTimings honesty gate', () => {
  it('reports wall-clock (and no passes) until real stamps resolved', () => {
    const passes = [{ key: 'a', label: 'a', kind: 'compute' as const, scale: 1, gpuMs: 1, iterations: 1 }];
    const t = { parallelTime: 1, chainedTime: 2, totalTime: 3 };
    expect(buildGPUTimings(t, true, false, passes)).toEqual({ ...t, available: false, timingSource: 'wall-clock' });
    expect(buildGPUTimings(t, false, true, passes).available).toBe(false);
    expect(buildGPUTimings(t, true, true, passes).passes).toEqual(passes);
  });
});
