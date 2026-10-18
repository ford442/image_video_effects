/**
 * WebGPUTiming.ts
 *
 * Per-pass GPU profiler for the WebGPU renderer (#1314 WP-4). Every compute
 * and render pass of a frame (graph nodes, slot steps, video copy, input
 * scale, chores, present) gets a begin/end timestamp pair in one query set.
 * The set is resolved every frame that wrote stamps. A WebGPU query may not be
 * rewritten before it is resolved, and that rule made the old phase layout
 * flash black. The resolved block is copied to a staging ring for CPU
 * readback at most every READBACK_INTERVAL_MS, then smoothed per pass.
 *
 * Note: Chromium quantizes timestamps (100 µs buckets unless
 * --enable-webgpu-developer-features) and may zero them. Metrics use deltas.
 */

import { GPUTimings } from '../Renderer';
import type { PassKind, PassTiming } from '../passTimings';

/** Passes that get a timestamp pair per frame; later passes run unprofiled. */
export const MAX_PROFILED_PASSES = 128;
export const QUERY_COUNT = MAX_PROFILED_PASSES * 2;
export const STAGING_RING_DEPTH = 2;
/** Minimum spacing between CPU readbacks (resolve itself runs every frame). */
export const READBACK_INTERVAL_MS = 250;
/** Weight of the newest readback in the per-pass moving average. */
export const PASS_EMA_ALPHA = 0.3;

export type GpuTimingsState = {
  parallelTime: number;
  chainedTime: number;
  totalTime: number;
};

export type SlotTimingMode = 'parallel' | 'chained';

export interface PassProfileMeta {
  kind: PassKind;
  label: string;
  mode?: SlotTimingMode;
  slot?: number;
  shaderId?: string;
  entry?: string;
  nodeId?: string;
  scale?: number;
}

/** Passes stamped in the frame being encoded (index i → queries 2i, 2i+1). */
export class FramePassProfile {
  passes: PassProfileMeta[] = [];
  /** Passes that wanted a stamp after MAX_PROFILED_PASSES was reached. */
  overflow = 0;

  reset(): void {
    this.passes = [];
    this.overflow = 0;
  }
}

export interface WebGPUTimestampQueries {
  supportsTimestampQuery: boolean;
  querySet: GPUQuerySet | null;
  /** QUERY_RESOLVE | COPY_SRC — receives resolveQuerySet output. */
  queryBuffer: GPUBuffer | null;
  /** MAP_READ | COPY_DST ring for async readback. */
  stagingRing: GPUBuffer[];
  /** A busy slot must not be a copy destination until its map completes. */
  stagingBusy: boolean[];
  timestampPeriodNs: number;
  /** True while at least one staging slot is mapped (diagnostics). */
  readbackPending: boolean;
  ringIndex: number;
  /** Honesty signal: true only after a valid GPU stamp decode. */
  hasRealGpuTimings: boolean;
  frame: FramePassProfile;
  /** performance.now() of the last staging copy. */
  lastReadbackAt: number;
  gpuTimings: GpuTimingsState;
  /** Smoothed per-pass timings, in frame order. */
  passTimings: PassTiming[];
  /** Passes that went unprofiled last readback because the query set was full. */
  lastOverflow: number;
}

function emptyTimingState(overrides: Partial<WebGPUTimestampQueries> = {}): WebGPUTimestampQueries {
  return {
    supportsTimestampQuery: false,
    querySet: null,
    queryBuffer: null,
    stagingRing: [],
    stagingBusy: [],
    timestampPeriodNs: 0,
    readbackPending: false,
    ringIndex: 0,
    hasRealGpuTimings: false,
    frame: new FramePassProfile(),
    lastReadbackAt: Number.NEGATIVE_INFINITY,
    gpuTimings: { parallelTime: 0, chainedTime: 0, totalTime: 0 },
    passTimings: [],
    lastOverflow: 0,
    ...overrides,
  };
}

/** Disabled timing state for pre-init / no-feature paths. */
export function createDisabledTimestampQueries(): WebGPUTimestampQueries {
  return emptyTimingState();
}

/**
 * Nanoseconds per timestamp tick. The current spec resolves timestamps in ns
 * and dropped `GPUQueue.timestampPeriod`, so Chrome leaves it undefined → 1.
 * Only an implementation that still exposes the legacy field gets its value;
 * an explicit non-positive value means the stamps are unusable (→ 0).
 */
export function resolveTimestampPeriodNs(queue: GPUQueue): number {
  const legacy = (queue as GPUQueue & { timestampPeriod?: unknown }).timestampPeriod;
  if (legacy === undefined || legacy === null) return 1;
  return typeof legacy === 'number' && legacy > 0 ? legacy : 0;
}

export function createTimestampQueries(device: GPUDevice): WebGPUTimestampQueries {
  if (!device.features.has('timestamp-query')) {
    return emptyTimingState();
  }

  const periodNs = resolveTimestampPeriodNs(device.queue);
  if (periodNs === 0) {
    console.warn(
      '[WebGPU] Timestamp queries: queue timestamp period is 0 — using wall-clock fallback',
    );
    return emptyTimingState();
  }

  try {
    const querySet = device.createQuerySet({ type: 'timestamp', count: QUERY_COUNT });
    const queryBuffer = device.createBuffer({
      label: 'timestamp-resolve',
      size: QUERY_COUNT * 8,
      usage: GPUBufferUsage.QUERY_RESOLVE | GPUBufferUsage.COPY_SRC,
    });
    const stagingRing: GPUBuffer[] = [];
    for (let i = 0; i < STAGING_RING_DEPTH; i++) {
      stagingRing.push(
        device.createBuffer({
          label: `timestamp-staging-${i}`,
          size: QUERY_COUNT * 8,
          usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST,
        }),
      );
    }
    console.log(`[WebGPU] Per-pass timestamp queries enabled (period=${periodNs} ns, ${MAX_PROFILED_PASSES} passes)`);
    return emptyTimingState({
      supportsTimestampQuery: true,
      querySet,
      queryBuffer,
      stagingRing,
      stagingBusy: stagingRing.map(() => false),
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
  for (const resource of [timing.querySet, timing.queryBuffer, ...timing.stagingRing]) {
    try {
      resource?.destroy();
    } catch {
      /* already destroyed */
    }
  }
  timing.querySet = null;
  timing.queryBuffer = null;
  timing.stagingRing = [];
  timing.stagingBusy = [];
  timing.supportsTimestampQuery = false;
  timing.hasRealGpuTimings = false;
  timing.readbackPending = false;
  timing.passTimings = [];
  timing.frame.reset();
}

/**
 * Reserve a begin/end timestamp pair for the next pass of this frame. Works for
 * compute and render passes (same descriptor shape). Undefined when timing is
 * off or the query set is full.
 */
export function profilePass(
  timing: WebGPUTimestampQueries,
  meta: PassProfileMeta,
): GPUComputePassTimestampWrites | undefined {
  if (!timing.supportsTimestampQuery || !timing.querySet) return undefined;
  const frame = timing.frame;
  if (frame.passes.length >= MAX_PROFILED_PASSES) {
    frame.overflow++;
    return undefined;
  }
  const index = frame.passes.length;
  frame.passes.push(meta);
  return {
    querySet: timing.querySet,
    beginningOfPassWriteIndex: index * 2,
    endOfPassWriteIndex: index * 2 + 1,
  };
}

/** Convert a GPU timestamp delta to milliseconds (mirrors timing.cpp TimestampDeltaMs). */
export function timestampDeltaMs(start: bigint, end: bigint, periodNs: number): number {
  if (periodNs === 0 || end <= start) return 0;
  // Deltas fit comfortably in Number; absolute stamps may not.
  return (Number(end - start) * periodNs) / 1e6;
}

export function passKey(meta: PassProfileMeta): string {
  return meta.kind === 'compute'
    ? `${meta.slot ?? '-'}:${meta.nodeId ?? meta.entry ?? meta.label}`
    : meta.label;
}

export interface DecodedPassTimings {
  timings: GpuTimingsState;
  /** One entry per key (iterations summed), in frame order. */
  passes: PassTiming[];
  valid: boolean;
}

/** Decode one resolved frame of stamps against the passes that wrote them. */
export function decodePassTimings(
  stamps: BigUint64Array,
  passes: readonly PassProfileMeta[],
  periodNs: number,
): DecodedPassTimings {
  const byKey = new Map<string, PassTiming>();
  const span: Record<SlotTimingMode | 'all', [bigint, bigint]> = {
    parallel: [0n, 0n],
    chained: [0n, 0n],
    all: [0n, 0n],
  };
  const widen = (name: SlotTimingMode | 'all', begin: bigint, end: bigint) => {
    const s = span[name];
    if (s[0] === 0n || begin < s[0]) s[0] = begin;
    if (end > s[1]) s[1] = end;
  };
  let valid = false;

  passes.forEach((meta, i) => {
    const begin = stamps[i * 2] ?? 0n;
    const end = stamps[i * 2 + 1] ?? 0n;
    const ok = begin > 0n && end > begin;
    if (ok) {
      valid = true;
      widen('all', begin, end);
      if (meta.mode) widen(meta.mode, begin, end);
    }
    const ms = ok ? timestampDeltaMs(begin, end, periodNs) : 0;
    const key = passKey(meta);
    const existing = byKey.get(key);
    if (existing) {
      existing.gpuMs += ms;
      existing.iterations++;
      return;
    }
    byKey.set(key, {
      key,
      label: meta.kind === 'compute' ? (meta.nodeId ?? meta.entry ?? meta.label) : meta.label,
      kind: meta.kind,
      slot: meta.slot,
      shaderId: meta.shaderId,
      entry: meta.entry,
      nodeId: meta.nodeId,
      scale: meta.scale ?? 1,
      gpuMs: ms,
      iterations: 1,
    });
  });

  const spanMs = (name: SlotTimingMode | 'all') => timestampDeltaMs(span[name][0], span[name][1], periodNs);
  return {
    timings: { parallelTime: spanMs('parallel'), chainedTime: spanMs('chained'), totalTime: spanMs('all') },
    passes: Array.from(byKey.values()),
    valid,
  };
}

/** Fold a fresh decode into the smoothed per-pass list (EMA; vanished passes drop out). */
export function smoothPassTimings(
  previous: readonly PassTiming[],
  next: readonly PassTiming[],
  alpha = PASS_EMA_ALPHA,
): PassTiming[] {
  const prev = new Map(previous.map((p) => [p.key, p]));
  return next.map((p) => {
    const old = prev.get(p.key);
    return old ? { ...p, gpuMs: old.gpuMs + (p.gpuMs - old.gpuMs) * alpha } : { ...p };
  });
}

export interface ReadbackTicket {
  slot: number;
  passes: PassProfileMeta[];
  overflow: number;
}

/**
 * Resolve this frame's stamps (always, when any were written) and, at most
 * every READBACK_INTERVAL_MS, copy them into a free staging slot. Returns the
 * readback ticket for scheduleTimestampReadback, or null.
 */
export function encodeResolveAndCopy(
  encoder: GPUCommandEncoder,
  timing: WebGPUTimestampQueries,
  now: number = performance.now(),
): ReadbackTicket | null {
  const count = timing.frame.passes.length;
  if (
    !timing.supportsTimestampQuery ||
    !timing.querySet ||
    !timing.queryBuffer ||
    timing.stagingRing.length === 0 ||
    count === 0
  ) {
    return null;
  }

  // Always resolve so the query indices may be written again next frame.
  encoder.resolveQuerySet(timing.querySet, 0, count * 2, timing.queryBuffer, 0);

  if (now - timing.lastReadbackAt < READBACK_INTERVAL_MS) return null;

  if (timing.stagingBusy.length !== timing.stagingRing.length) {
    timing.stagingBusy = timing.stagingRing.map(() => false);
  }
  let slot: number | null = null;
  let staging: GPUBuffer | undefined;
  for (let i = 0; i < timing.stagingRing.length; i++) {
    const candidate = (timing.ringIndex + i) % timing.stagingRing.length;
    staging = timing.stagingRing[candidate];
    if (!timing.stagingBusy[candidate] && staging) {
      slot = candidate;
      break;
    }
  }
  if (slot === null || !staging) return null;

  encoder.copyBufferToBuffer(timing.queryBuffer, 0, staging, 0, count * 2 * 8);
  timing.lastReadbackAt = now;
  return { slot, passes: [...timing.frame.passes], overflow: timing.frame.overflow };
}

/**
 * Fire-and-forget mapAsync of a staging slot. Never await this from the frame.
 * On success, updates gpuTimings / passTimings / hasRealGpuTimings.
 */
export function scheduleTimestampReadback(
  timing: WebGPUTimestampQueries,
  ticket: ReadbackTicket,
): void {
  const staging = timing.stagingRing[ticket.slot];
  if (!staging) return;
  const periodNs = timing.timestampPeriodNs;
  const byteLength = ticket.passes.length * 2 * 8;

  timing.stagingBusy[ticket.slot] = true;
  timing.readbackPending = true;
  timing.ringIndex = (ticket.slot + 1) % timing.stagingRing.length;

  const release = () => {
    timing.stagingBusy[ticket.slot] = false;
    timing.readbackPending = timing.stagingBusy.some(Boolean);
  };

  staging
    .mapAsync(GPUMapMode.READ, 0, byteLength)
    .then(() => {
      try {
        const stamps = new BigUint64Array(staging.getMappedRange(0, byteLength).slice(0));
        const decoded = decodePassTimings(stamps, ticket.passes, periodNs);
        if (decoded.valid) {
          timing.gpuTimings.parallelTime = decoded.timings.parallelTime;
          timing.gpuTimings.chainedTime = decoded.timings.chainedTime;
          timing.gpuTimings.totalTime = decoded.timings.totalTime;
          timing.passTimings = smoothPassTimings(timing.passTimings, decoded.passes);
          timing.lastOverflow = ticket.overflow;
          timing.hasRealGpuTimings = true;
        }
      } finally {
        try {
          staging.unmap();
        } catch {
          /* device lost */
        }
        release();
      }
    })
    .catch(() => {
      release();
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
  passes?: readonly PassTiming[],
): GPUTimings {
  const real = supportsTimestampQuery && hasRealGpuTimings;
  return {
    ...gpuTimings,
    available: real,
    timingSource: real ? 'gpu-timestamp' : 'wall-clock',
    ...(real && passes && passes.length > 0 ? { passes: passes.map((p) => ({ ...p })) } : {}),
  };
}
