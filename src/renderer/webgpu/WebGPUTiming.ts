/**
 * WebGPUTiming.ts
 *
 * GPU timestamp query setup and timing readback for the WebGPU renderer.
 * Mirrors wasm_renderer/timing.cpp / wasm_internal.h index layout.
 *
 * Note: Chromium may quantize or zero absolute timestamp values for
 * fingerprinting mitigation. Metrics use deltas × timestampPeriod only.
 */

import { GPUTimings } from '../Renderer';

/** Keep in sync with wasm_renderer/wasm_internal.h */
export const TS_QUERY_COUNT = 8;
export const kTsFrameStart = 0;
export const kTsComputeEnd = 1;
export const kTsParallelStart = 2;
export const kTsParallelEnd = 3;
export const kTsChainedStart = 4;
export const kTsChainedEnd = 5;
export const kTsPresentStart = 6;
export const kTsPresentEnd = 7;

export const STAGING_RING_DEPTH = 2;

export type GpuTimingsState = {
  parallelTime: number;
  chainedTime: number;
  totalTime: number;
};

export type SlotTimingMode = 'parallel' | 'chained';

export class TimestampPhaseTracker {
  tsFrameStartWritten = false;
  tsParallelStartWritten = false;
  tsChainedStartWritten = false;
  /** True if at least one parallel compute pass was encoded this frame. */
  hadParallel = false;
  /** True if at least one chained compute pass was encoded this frame. */
  hadChained = false;

  reset(): void {
    this.tsFrameStartWritten = false;
    this.tsParallelStartWritten = false;
    this.tsChainedStartWritten = false;
    this.hadParallel = false;
    this.hadChained = false;
  }
}

export interface WebGPUTimestampQueries {
  supportsTimestampQuery: boolean;
  querySet: GPUQuerySet | null;
  /** QUERY_RESOLVE | COPY_SRC — receives resolveQuerySet output. */
  queryBuffer: GPUBuffer | null;
  /** 2-deep MAP_READ | COPY_DST ring for async readback. */
  stagingRing: GPUBuffer[];
  timestampPeriodNs: number;
  readbackPending: boolean;
  ringIndex: number;
  /** Honesty signal: true only after a valid GPU stamp decode. */
  hasRealGpuTimings: boolean;
  tracker: TimestampPhaseTracker;
  gpuTimings: GpuTimingsState;
}

function emptyTimingState(overrides: Partial<WebGPUTimestampQueries> = {}): WebGPUTimestampQueries {
  return {
    supportsTimestampQuery: false,
    querySet: null,
    queryBuffer: null,
    stagingRing: [],
    timestampPeriodNs: 0,
    readbackPending: false,
    ringIndex: 0,
    hasRealGpuTimings: false,
    tracker: new TimestampPhaseTracker(),
    gpuTimings: { parallelTime: 0, chainedTime: 0, totalTime: 0 },
    ...overrides,
  };
}

/** Disabled timing state for pre-init / no-feature paths. */
export function createDisabledTimestampQueries(): WebGPUTimestampQueries {
  return emptyTimingState();
}

export function createTimestampQueries(device: GPUDevice): WebGPUTimestampQueries {
  const featurePresent = device.features.has('timestamp-query');
  if (!featurePresent) {
    return emptyTimingState();
  }

  const periodNs = (device.queue as GPUQueue & { timestampPeriod?: number }).timestampPeriod ?? 0;
  if (periodNs === 0) {
    console.warn(
      '[WebGPU] Timestamp queries: queue timestamp period is 0 — using wall-clock fallback',
    );
    return emptyTimingState();
  }

  try {
    const querySet = device.createQuerySet({
      type: 'timestamp',
      count: TS_QUERY_COUNT,
    });
    const queryBuffer = device.createBuffer({
      size: TS_QUERY_COUNT * 8,
      usage: GPUBufferUsage.QUERY_RESOLVE | GPUBufferUsage.COPY_SRC,
    });
    const stagingRing: GPUBuffer[] = [];
    for (let i = 0; i < STAGING_RING_DEPTH; i++) {
      stagingRing.push(
        device.createBuffer({
          label: `timestamp-staging-${i}`,
          size: TS_QUERY_COUNT * 8,
          usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST,
        }),
      );
    }
    console.log(`[WebGPU] Timestamp queries enabled (period=${periodNs} ns)`);
    return emptyTimingState({
      supportsTimestampQuery: true,
      querySet,
      queryBuffer,
      stagingRing,
      timestampPeriodNs: periodNs,
    });
  } catch (e) {
    console.warn('[WebGPU] Timestamp query creation failed:', e);
    return emptyTimingState();
  }
}

export function setupTimestampQueries(device: GPUDevice): WebGPUTimestampQueries {
  return createTimestampQueries(device);
}

export function destroyTimestampQueries(timing: WebGPUTimestampQueries): void {
  try {
    timing.querySet?.destroy();
  } catch {
    /* already destroyed */
  }
  try {
    timing.queryBuffer?.destroy();
  } catch {
    /* already destroyed */
  }
  for (const buf of timing.stagingRing) {
    try {
      buf.destroy();
    } catch {
      /* already destroyed */
    }
  }
  timing.querySet = null;
  timing.queryBuffer = null;
  timing.stagingRing = [];
  timing.supportsTimestampQuery = false;
  timing.hasRealGpuTimings = false;
  timing.readbackPending = false;
}

/** Convert a GPU timestamp delta to milliseconds (mirrors timing.cpp TimestampDeltaMs). */
export function timestampDeltaMs(start: bigint, end: bigint, periodNs: number): number {
  if (periodNs === 0 || end <= start) return 0;
  // Deltas fit comfortably in Number; absolute stamps may not.
  return (Number(end - start) * periodNs) / 1e6;
}

/** Validate stamps the way C++ sets gpuTimingsResolved_. */
export function stampsIndicateRealGpuTimings(stamps: BigUint64Array): boolean {
  const frameStart = stamps[kTsFrameStart] ?? 0n;
  const presentEnd = stamps[kTsPresentEnd] ?? 0n;
  const computeEnd = stamps[kTsComputeEnd] ?? 0n;
  return (
    (frameStart > 0n && presentEnd > frameStart) ||
    (frameStart > 0n && computeEnd > frameStart)
  );
}

export function decodeGpuTimings(
  stamps: BigUint64Array,
  periodNs: number,
  tracker: Pick<TimestampPhaseTracker, 'hadParallel' | 'hadChained'>,
): { timings: GpuTimingsState; valid: boolean } {
  const frameStart = stamps[kTsFrameStart] ?? 0n;
  const computeEnd = stamps[kTsComputeEnd] ?? 0n;
  const presentEnd = stamps[kTsPresentEnd] ?? 0n;

  let parallelStart = stamps[kTsParallelStart] ?? 0n;
  let parallelEnd = stamps[kTsParallelEnd] ?? 0n;
  if (tracker.hadParallel) {
    if (parallelStart === 0n) parallelStart = frameStart;
    if (parallelEnd === 0n) parallelEnd = computeEnd;
  }

  let chainedStart = stamps[kTsChainedStart] ?? 0n;
  let chainedEnd = stamps[kTsChainedEnd] ?? 0n;
  if (tracker.hadChained) {
    if (chainedStart === 0n) {
      // First chained pass may have used frameStart as begin when it was also first of frame.
      chainedStart = stamps[kTsParallelEnd] > 0n ? stamps[kTsParallelEnd]! : frameStart;
    }
    if (chainedEnd === 0n) chainedEnd = computeEnd;
  }

  const frameToPresent = timestampDeltaMs(frameStart, presentEnd, periodNs);
  const computeOnly = timestampDeltaMs(frameStart, computeEnd, periodNs);

  return {
    timings: {
      parallelTime: tracker.hadParallel
        ? timestampDeltaMs(parallelStart, parallelEnd, periodNs)
        : 0,
      chainedTime: tracker.hadChained
        ? timestampDeltaMs(chainedStart, chainedEnd, periodNs)
        : 0,
      totalTime: frameToPresent > 0 ? frameToPresent : computeOnly,
    },
    valid: stampsIndicateRealGpuTimings(stamps),
  };
}

/**
 * Pick begin/end query indices for one compute pass.
 * Browser WebGPU allows one beginningOfPass + one endOfPass per pass.
 */
export function pickComputeTimestampWrites(
  tracker: TimestampPhaseTracker,
  querySet: GPUQuerySet,
  mode: SlotTimingMode,
  isLastComputeOfFrame: boolean,
): GPUComputePassTimestampWrites {
  let beginningOfPassWriteIndex: number | undefined;
  let endOfPassWriteIndex: number;

  if (!tracker.tsFrameStartWritten) {
    beginningOfPassWriteIndex = kTsFrameStart;
    tracker.tsFrameStartWritten = true;
  }

  if (mode === 'parallel') {
    tracker.hadParallel = true;
    if (!tracker.tsParallelStartWritten) {
      if (beginningOfPassWriteIndex === undefined) {
        beginningOfPassWriteIndex = kTsParallelStart;
      }
      tracker.tsParallelStartWritten = true;
    }
    endOfPassWriteIndex = kTsParallelEnd;
  } else {
    tracker.hadChained = true;
    if (!tracker.tsChainedStartWritten) {
      if (beginningOfPassWriteIndex === undefined) {
        beginningOfPassWriteIndex = kTsChainedStart;
      }
      tracker.tsChainedStartWritten = true;
    }
    endOfPassWriteIndex = kTsChainedEnd;
  }

  if (isLastComputeOfFrame) {
    endOfPassWriteIndex = kTsComputeEnd;
  }

  const writes: GPUComputePassTimestampWrites = {
    querySet,
    endOfPassWriteIndex,
  };
  if (beginningOfPassWriteIndex !== undefined) {
    writes.beginningOfPassWriteIndex = beginningOfPassWriteIndex;
  }
  return writes;
}

export function pickPresentTimestampWrites(
  tracker: TimestampPhaseTracker,
  querySet: GPUQuerySet,
): GPURenderPassTimestampWrites | undefined {
  if (!tracker.tsFrameStartWritten) return undefined;
  return {
    querySet,
    beginningOfPassWriteIndex: kTsPresentStart,
    endOfPassWriteIndex: kTsPresentEnd,
  };
}

/**
 * Encode resolve + copy into the next free staging ring slot.
 * Returns the ring slot index, or null if skipped (no feature / pending / no frame start).
 */
export function encodeResolveAndCopy(
  encoder: GPUCommandEncoder,
  timing: WebGPUTimestampQueries,
): number | null {
  if (
    !timing.supportsTimestampQuery ||
    !timing.querySet ||
    !timing.queryBuffer ||
    timing.stagingRing.length === 0
  ) {
    return null;
  }
  if (!timing.tracker.tsFrameStartWritten || timing.readbackPending) {
    return null;
  }

  const slot = timing.ringIndex % timing.stagingRing.length;
  const staging = timing.stagingRing[slot];
  if (!staging) return null;

  encoder.resolveQuerySet(timing.querySet, 0, TS_QUERY_COUNT, timing.queryBuffer, 0);
  encoder.copyBufferToBuffer(
    timing.queryBuffer,
    0,
    staging,
    0,
    TS_QUERY_COUNT * 8,
  );
  return slot;
}

/**
 * Fire-and-forget mapAsync on a staging ring slot. Never await this from the submit frame.
 * On success, updates timing.gpuTimings / hasRealGpuTimings. On failure, falls back cleanly.
 */
export function scheduleTimestampReadback(
  timing: WebGPUTimestampQueries,
  slot: number,
): void {
  const staging = timing.stagingRing[slot];
  if (!staging) return;

  // Snapshot tracker flags for this resolved frame (next frame will reset tracker).
  const hadParallel = timing.tracker.hadParallel;
  const hadChained = timing.tracker.hadChained;
  const periodNs = timing.timestampPeriodNs;

  timing.readbackPending = true;
  timing.ringIndex = (slot + 1) % timing.stagingRing.length;

  staging
    .mapAsync(GPUMapMode.READ)
    .then(() => {
      try {
        const copy = staging.getMappedRange().slice(0);
        const stamps = new BigUint64Array(copy);
        const decoded = decodeGpuTimings(stamps, periodNs, { hadParallel, hadChained });
        if (decoded.valid) {
          timing.gpuTimings.parallelTime = decoded.timings.parallelTime;
          timing.gpuTimings.chainedTime = decoded.timings.chainedTime;
          timing.gpuTimings.totalTime = decoded.timings.totalTime;
          timing.hasRealGpuTimings = true;
        }
      } finally {
        try {
          staging.unmap();
        } catch {
          /* device lost */
        }
        timing.readbackPending = false;
      }
    })
    .catch(() => {
      timing.readbackPending = false;
      timing.hasRealGpuTimings = false;
    });
}

/**
 * Honesty gate: available / gpu-timestamp only when real GPU durations were resolved.
 * Feature presence alone must not flip the flag (see #1030 / #1007).
 */
export function buildGPUTimings(
  gpuTimings: GpuTimingsState,
  supportsTimestampQuery: boolean,
  hasRealGpuTimings = false,
): GPUTimings {
  const real = supportsTimestampQuery && hasRealGpuTimings;
  return {
    ...gpuTimings,
    available: real,
    timingSource: real ? 'gpu-timestamp' : 'wall-clock',
  };
}
