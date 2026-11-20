/**
 * timelinePlayer.ts — the exact state of a recorded VJ set at any time (#1401).
 *
 * Offline export asks "what was on screen at t?" for every output frame, in order, at a
 * frame rate unrelated to the 20 Hz the set was recorded at. `stateAt(t)` answers it
 * without any running state, so frames can be rendered (or re-rendered) in any order:
 *
 *   1. Recorded events: the last shader / source / param value at or before `t` — the same
 *      RecorderSnapshot that `applyEvents` (vjSetRecorder.ts) builds from the events up to `t`.
 *   2. Interpolation: a param that was moving (two samples of it no more than two recorder
 *      periods apart) is interpolated linearly between them, so a 60 fps export does not
 *      stair-step at 20 Hz. A param that sat still and then jumped is held, not ramped.
 *   3. Keyframes: from the first keyframe of a (slot, key) on, its curve replaces the
 *      recorded value (each keyframe's `ease` shapes the segment that ends at it; the last
 *      value holds afterwards).
 */

import type { RecorderSnapshot } from './vjSetRecorder';
import type {
  KeyframeEase,
  TimelineKeyframe,
  TimelineParamKey,
  TimelineSource,
  VjTimeline,
} from './vjSetExport';

export interface PlayerState extends RecorderSnapshot {
  /** The source in effect at `t` (null until the first source event, unless the base had one). */
  source: TimelineSource | null;
  /** When that source took effect (ms on the timeline); the base source counts as 0. */
  sourceSinceMs: number;
}

export interface TimelinePlayerOptions {
  /** State before the first event of each track (e.g. the set's chain); default empty. */
  base?: RecorderSnapshot;
  /** Interpolate recorded param motion (default true). False gives the step-held recording. */
  interpolate?: boolean;
}

interface ParamTrack {
  slot: number;
  key: TimelineParamKey;
  t: number[];
  v: number[];
}

interface StepTrack<T> {
  t: number[];
  v: T[];
}

/** Index of the last entry with `times[i] <= t`, or -1. */
function lastAtOrBefore(times: readonly number[], t: number): number {
  let lo = 0;
  let hi = times.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if ((times[mid] ?? Infinity) <= t) lo = mid + 1;
    else hi = mid;
  }
  return lo - 1;
}

export function applyEase(ease: KeyframeEase, u: number): number {
  const x = Math.min(1, Math.max(0, u));
  switch (ease) {
    case 'step':
      return x >= 1 ? 1 : 0;
    case 'easeIn':
      return x * x * x;
    case 'easeOut':
      return 1 - (1 - x) ** 3;
    case 'easeInOut':
      return x < 0.5 ? 4 * x * x * x : 1 - (-2 * x + 2) ** 3 / 2;
    default:
      return x;
  }
}

/** Value of a sorted keyframe track at `t`, or undefined before its first keyframe. */
export function keyframeValueAt(track: readonly TimelineKeyframe[], t: number): number | undefined {
  const first = track[0];
  if (!first || t < first.t) return undefined;
  let lo = 0;
  let hi = track.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if ((track[mid]?.t ?? Infinity) <= t) lo = mid + 1;
    else hi = mid;
  }
  const a = track[lo - 1] ?? first;
  const b = track[lo];
  if (!b) return a.value;
  const span = b.t - a.t;
  if (span <= 0) return b.value;
  return a.value + (b.value - a.value) * applyEase(b.ease, (t - a.t) / span);
}

const trackKey = (slot: number, key: string) => `${slot}:${key}`;

export class TimelinePlayer {
  readonly durationMs: number;
  private readonly shaderTracks = new Map<number, StepTrack<string>>();
  private readonly paramTracks: ParamTrack[] = [];
  private readonly sourceTrack: StepTrack<TimelineSource> = { t: [], v: [] };
  private readonly keyframeTracks = new Map<string, { slot: number; key: TimelineParamKey; frames: TimelineKeyframe[] }>();
  private readonly base: RecorderSnapshot;
  private readonly interpolate: boolean;
  /** Longest gap between two samples of a param that still counts as continuous motion. */
  private readonly maxGapMs: number;

  constructor(timeline: VjTimeline, options: TimelinePlayerOptions = {}) {
    this.durationMs = timeline.durationMs;
    this.base = options.base ?? { modes: [], params: [] };
    this.interpolate = options.interpolate ?? true;
    this.maxGapMs = 2000 / (timeline.hz > 0 ? timeline.hz : 20);

    const params = new Map<string, ParamTrack>();
    for (const e of timeline.events) {
      if (e.kind === 'shader') {
        let track = this.shaderTracks.get(e.slot);
        if (!track) this.shaderTracks.set(e.slot, (track = { t: [], v: [] }));
        track.t.push(e.t);
        track.v.push(e.value);
      } else if (e.kind === 'param') {
        const id = trackKey(e.slot, e.key);
        let track = params.get(id);
        if (!track) params.set(id, (track = { slot: e.slot, key: e.key, t: [], v: [] }));
        track.t.push(e.t);
        track.v.push(e.value);
      } else {
        this.sourceTrack.t.push(e.t);
        this.sourceTrack.v.push(e.value);
      }
    }
    this.paramTracks.push(...params.values());
    for (const k of timeline.keyframes ?? []) {
      const id = trackKey(k.slot, k.key);
      let track = this.keyframeTracks.get(id);
      if (!track) this.keyframeTracks.set(id, (track = { slot: k.slot, key: k.key, frames: [] }));
      track.frames.push(k);
    }
    for (const track of this.keyframeTracks.values()) track.frames.sort((a, b) => a.t - b.t);
  }

  /** The state at `tMs` (clamped to ≥ 0). Pure: any order of calls gives the same answers. */
  stateAt(tMs: number): PlayerState {
    const t = Number.isFinite(tMs) ? Math.max(0, tMs) : 0;
    const modes = [...this.base.modes];
    const params = this.base.params.map((p) => ({ ...p }));

    for (const [slot, track] of this.shaderTracks) {
      const mode = track.v[lastAtOrBefore(track.t, t)];
      if (mode !== undefined) modes[slot] = mode;
    }

    for (const track of this.paramTracks) {
      const i = lastAtOrBefore(track.t, t);
      const t0 = track.t[i];
      let value = track.v[i];
      if (t0 === undefined || value === undefined) continue;
      const t1 = track.t[i + 1];
      const v1 = track.v[i + 1];
      if (this.interpolate && t1 !== undefined && v1 !== undefined && t1 > t0 && t1 - t0 <= this.maxGapMs) {
        value += (v1 - value) * ((t - t0) / (t1 - t0));
      }
      (params[track.slot] ??= {})[track.key] = value;
    }

    for (const track of this.keyframeTracks.values()) {
      const value = keyframeValueAt(track.frames, t);
      if (value !== undefined) (params[track.slot] ??= {})[track.key] = value;
    }

    // Holes from sparse slot indices are empty slots, not undefined entries.
    for (let i = 0; i < params.length; i++) params[i] ??= {};

    const s = lastAtOrBefore(this.sourceTrack.t, t);
    const recorded = this.sourceTrack.v[s];
    const source = recorded ? { ...recorded } : this.base.source ? { ...this.base.source } : null;
    const sourceSinceMs = recorded ? this.sourceTrack.t[s] ?? 0 : 0;
    return { modes, params, source, sourceSinceMs };
  }

  /** Every distinct shader id the set uses (to compile before the first frame). */
  shaderIds(): string[] {
    const ids = new Set<string>(this.base.modes.filter((m) => !!m && m !== 'none'));
    for (const track of this.shaderTracks.values()) for (const id of track.v) if (id && id !== 'none') ids.add(id);
    return [...ids];
  }

  /** Every source the set switches to, in order (to preload before the first frame). */
  sources(): TimelineSource[] {
    return this.sourceTrack.v.map((s) => ({ ...s }));
  }
}

/** Video time (s) of `source` at timeline time `tMs`: its seek point plus the time since it started. */
export function sourceMediaTimeSec(state: Pick<PlayerState, 'source' | 'sourceSinceMs'>, tMs: number): number {
  const seek = state.source?.seekSec ?? 0;
  return seek + Math.max(0, tMs - state.sourceSinceMs) / 1000;
}
