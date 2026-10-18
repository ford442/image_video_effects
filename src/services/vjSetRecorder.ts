/**
 * vjSetRecorder.ts — pure helpers for the VJ set recorder (useSetRecorder).
 * Records what is on screen (slot shaders + the four sliders) as diffs.
 */

import type { TimelineParamKey, VjTimelineEvent } from './vjSetExport';

export const RECORDER_HZ = 20;
export const PARAM_EPSILON = 1e-3;
const PARAM_KEYS: TimelineParamKey[] = ['zoomParam1', 'zoomParam2', 'zoomParam3', 'zoomParam4'];

export interface RecorderSnapshot {
  modes: string[];
  params: Array<Partial<Record<TimelineParamKey, number>>>;
}

const round3 = (v: number) => Math.round(v * 1000) / 1000;

/**
 * Events needed to go from `prev` to `next` at time `t`. With `prev === null`
 * every slot is emitted, so playback starts from the recorded state.
 */
export function diffSnapshot(prev: RecorderSnapshot | null, next: RecorderSnapshot, t: number): VjTimelineEvent[] {
  const out: VjTimelineEvent[] = [];
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
export function takeSnapshot(modes: readonly string[], params: ReadonlyArray<Partial<Record<TimelineParamKey, number>> | undefined>): RecorderSnapshot {
  return {
    modes: [...modes],
    params: params.map(p => {
      const o: Partial<Record<TimelineParamKey, number>> = {};
      for (const k of PARAM_KEYS) if (typeof p?.[k] === 'number') o[k] = p[k];
      return o;
    }),
  };
}

/**
 * Snapshot of the last-recorded values (`prev` side of diffs): only update
 * keys that were actually emitted, so slow drifts below epsilon accumulate
 * instead of being lost sample-to-sample.
 */
export function applyEvents(base: RecorderSnapshot, events: VjTimelineEvent[]): RecorderSnapshot {
  const next: RecorderSnapshot = { modes: [...base.modes], params: base.params.map(p => ({ ...p })) };
  for (const e of events) {
    if (e.kind === 'shader') next.modes[e.slot] = e.value;
    else (next.params[e.slot] ??= {})[e.key] = e.value;
  }
  return next;
}

/** Index of the first event with `t > time` (events sorted by t). */
export function firstEventAfter(events: VjTimelineEvent[], time: number): number {
  let lo = 0;
  let hi = events.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (events[mid]!.t <= time) lo = mid + 1;
    else hi = mid;
  }
  return lo;
}
