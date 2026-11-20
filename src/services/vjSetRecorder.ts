/**
 * vjSetRecorder.ts — pure helpers for the VJ set recorder (useSetRecorder).
 * Records what is on screen (slot shaders, every slot param and the input source) as diffs.
 */

import {
  TIMELINE_PARAM_KEYS,
  type TimelineParamKey,
  type TimelineSource,
  type VjTimelineEvent,
} from './vjSetExport';

export const RECORDER_HZ = 20;
export const PARAM_EPSILON = 1e-3;
const PARAM_KEYS = TIMELINE_PARAM_KEYS;

export interface RecorderSnapshot {
  modes: string[];
  params: Array<Partial<Record<TimelineParamKey, number>>>;
  /** The input source (#1401); absent / null when the recorder was not told. */
  source?: TimelineSource | null;
}

const round3 = (v: number) => Math.round(v * 1000) / 1000;

export function sameSource(a: TimelineSource | null | undefined, b: TimelineSource | null | undefined): boolean {
  if (!a || !b) return !a && !b;
  return a.type === b.type && a.url === b.url && a.shader === b.shader;
}

/**
 * Events needed to go from `prev` to `next` at time `t`. With `prev === null`
 * every slot is emitted, so playback starts from the recorded state.
 */
export function diffSnapshot(prev: RecorderSnapshot | null, next: RecorderSnapshot, t: number): VjTimelineEvent[] {
  const out: VjTimelineEvent[] = [];
  // A source change comes first: shaders swapped at the same instant read the new source.
  // A seek alone (same type / url / shader) is playback, not a change.
  if (next.source && (!prev || !sameSource(prev.source, next.source))) {
    out.push({ t, slot: 0, kind: 'source', value: { ...next.source } });
  }
  const slots = Math.min(6, Math.max(next.modes.length, next.params.length));
  for (let slot = 0; slot < slots; slot++) {
    const mode = next.modes[slot];
    if (typeof mode === 'string' && mode && (!prev || prev.modes[slot] !== mode)) {
      out.push({ t, slot, kind: 'shader', value: mode });
    }
    const p = next.params[slot] ?? {};
    const q = prev?.params[slot] ?? {};
    for (const key of PARAM_KEYS) {
      const v = p[key];
      if (typeof v !== 'number' || !Number.isFinite(v)) continue;
      const before = q[key];
      if (prev && typeof before === 'number' && Math.abs(v - before) < PARAM_EPSILON) continue;
      out.push({ t, slot, kind: 'param', key, value: round3(v) });
    }
  }
  return out;
}

/** Copy only what the recorder compares, so later mutation can't leak in. */
export function takeSnapshot(
  modes: readonly string[],
  params: ReadonlyArray<Partial<Record<TimelineParamKey, number>> | undefined>,
  source?: TimelineSource | null,
): RecorderSnapshot {
  return {
    modes: [...modes],
    params: params.map(p => {
      const o: Partial<Record<TimelineParamKey, number>> = {};
      for (const k of PARAM_KEYS) if (typeof p?.[k] === 'number') o[k] = p[k];
      return o;
    }),
    ...(source !== undefined ? { source: source ? { ...source } : null } : {}),
  };
}

/**
 * Snapshot of the last-recorded values (`prev` side of diffs): only update
 * keys that were actually emitted, so slow drifts below epsilon accumulate
 * instead of being lost sample-to-sample.
 */
export function applyEvents(base: RecorderSnapshot, events: VjTimelineEvent[]): RecorderSnapshot {
  const next: RecorderSnapshot = {
    modes: [...base.modes],
    params: base.params.map(p => ({ ...p })),
    ...(base.source !== undefined ? { source: base.source } : {}),
  };
  for (const e of events) {
    if (e.kind === 'shader') next.modes[e.slot] = e.value;
    else if (e.kind === 'param') (next.params[e.slot] ??= {})[e.key] = e.value;
    else next.source = { ...e.value };
  }
  return next;
}

/** Index of the first event with `t > time` (events sorted by t). */
export function firstEventAfter(events: ReadonlyArray<{ t: number }>, time: number): number {
  let lo = 0;
  let hi = events.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (events[mid]!.t <= time) lo = mid + 1;
    else hi = mid;
  }
  return lo;
}
