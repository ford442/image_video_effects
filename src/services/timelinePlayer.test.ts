import { applyEase, keyframeValueAt, sourceMediaTimeSec, TimelinePlayer } from './timelinePlayer';
import { applyEvents, diffSnapshot, firstEventAfter, takeSnapshot, type RecorderSnapshot } from './vjSetRecorder';
import { sanitizeTimeline, type TimelineKeyframe, type VjTimeline, type VjTimelineEvent } from './vjSetExport';

/** A set recorded the way useSetRecorder does: 20 Hz samples, diffed. */
function record(samples: Array<{ t: number; snap: RecorderSnapshot }>): VjTimeline {
  const events: VjTimelineEvent[] = [];
  let last: RecorderSnapshot | null = null;
  for (const { t, snap } of samples) {
    const diff = diffSnapshot(last, snap, t);
    last = last ? applyEvents(last, diff) : snap;
    events.push(...diff);
  }
  return { hz: 20, durationMs: samples.at(-1)?.t ?? 0, events };
}

const snap = (mode: string, p1: number, extra: Partial<Record<string, number>> = {}) =>
  takeSnapshot([mode, 'none'], [{ zoomParam1: p1, zoomParam2: 0.5, ...extra }, {}]);

describe('TimelinePlayer (#1401)', () => {
  it('without interpolation, stateAt(t) is exactly applyEvents over the events up to t', () => {
    const samples = Array.from({ length: 40 }, (_, i) => ({
      t: i * 50,
      snap: snap(i < 20 ? 'liquid' : 'plasma', Math.sin(i / 5) * 0.5 + 0.5),
    }));
    const tl = record(samples);
    const player = new TimelinePlayer(tl, { interpolate: false });
    for (const t of [0, 49, 50, 777, 999, 1000, 1001, 1950, 5000]) {
      const expected = applyEvents({ modes: [], params: [] }, tl.events.slice(0, firstEventAfter(tl.events, t)));
      const got = player.stateAt(t);
      expect(got.modes).toEqual(expected.modes);
      expect(got.params).toEqual(expected.params);
    }
  });

  it('interpolates recorded motion between adjacent samples (no 20 Hz stair-steps at 60 fps)', () => {
    const tl = record([
      { t: 0, snap: snap('liquid', 0) },
      { t: 50, snap: snap('liquid', 0.5) },
      { t: 100, snap: snap('liquid', 1) },
    ]);
    const player = new TimelinePlayer(tl);
    expect(player.stateAt(25).params[0]?.zoomParam1).toBeCloseTo(0.25);
    expect(player.stateAt(1000 / 60).params[0]?.zoomParam1).toBeCloseTo(1 / 6, 6);
    expect(player.stateAt(100).params[0]?.zoomParam1).toBe(1);
    expect(player.stateAt(400).params[0]?.zoomParam1).toBe(1);
  });

  it('holds a param that sat still and then jumped (no invented ramp across the gap)', () => {
    const tl: VjTimeline = {
      hz: 20,
      durationMs: 5000,
      events: [
        { t: 0, slot: 0, kind: 'param', key: 'zoomParam1', value: 0.2 },
        { t: 5000, slot: 0, kind: 'param', key: 'zoomParam1', value: 0.9 },
      ],
    };
    const player = new TimelinePlayer(tl);
    expect(player.stateAt(4999).params[0]?.zoomParam1).toBe(0.2);
    expect(player.stateAt(5000).params[0]?.zoomParam1).toBe(0.9);
  });

  it('is pure: frames in any order give the same state', () => {
    const tl = record(Array.from({ length: 30 }, (_, i) => ({ t: i * 50, snap: snap(i % 2 ? 'a' : 'b', i / 30) })));
    const player = new TimelinePlayer(tl);
    const forward = [0, 333, 666, 999, 1400].map((t) => player.stateAt(t));
    const backward = [1400, 999, 666, 333, 0].map((t) => player.stateAt(t)).reverse();
    expect(backward).toEqual(forward);
  });

  it('keyframes take over a param from their first keyframe, with per-segment easing', () => {
    const keyframes: TimelineKeyframe[] = [
      { t: 1000, slot: 0, key: 'zoomParam2', value: 0, ease: 'linear' },
      { t: 2000, slot: 0, key: 'zoomParam2', value: 1, ease: 'linear' },
      { t: 3000, slot: 0, key: 'zoomParam2', value: 0, ease: 'easeIn' },
      { t: 4000, slot: 0, key: 'zoomParam2', value: 1, ease: 'step' },
    ];
    const tl: VjTimeline = { ...record([{ t: 0, snap: snap('liquid', 0.3) }]), durationMs: 5000, keyframes };
    const player = new TimelinePlayer(tl);
    expect(player.stateAt(500).params[0]?.zoomParam2).toBe(0.5); // recorded value before the first key
    expect(player.stateAt(1500).params[0]?.zoomParam2).toBeCloseTo(0.5);
    expect(player.stateAt(2500).params[0]?.zoomParam2).toBeCloseTo(1 - 0.125); // easeIn: u³
    expect(player.stateAt(3999).params[0]?.zoomParam2).toBe(0); // step holds until the key
    expect(player.stateAt(4000).params[0]?.zoomParam2).toBe(1);
    expect(player.stateAt(9000).params[0]?.zoomParam2).toBe(1); // last value holds
    expect(player.stateAt(1500).params[0]?.zoomParam1).toBe(0.3); // other keys unaffected
  });

  it('keyframes work on a slot and key the recording never touched', () => {
    const tl = sanitizeTimeline({
      hz: 20,
      durationMs: 0,
      events: [],
      keyframes: [
        { t: 0, slot: 3, key: 'lightStrength', value: 1, ease: 'linear' },
        { t: 1000, slot: 3, key: 'lightStrength', value: 2, ease: 'linear' },
      ],
    });
    expect(tl).not.toBeNull();
    const state = new TimelinePlayer(tl!).stateAt(500);
    expect(state.params[3]).toEqual({ lightStrength: 1.5 });
    expect(state.params[0]).toEqual({});
  });

  it('reports the source in effect and where its video is at t', () => {
    const tl: VjTimeline = {
      hz: 20,
      durationMs: 4000,
      events: [
        { t: 0, slot: 0, kind: 'source', value: { type: 'image', url: 'https://x/a.jpg' } },
        { t: 1000, slot: 0, kind: 'source', value: { type: 'video', url: 'https://x/v.mp4', seekSec: 12 } },
      ],
    };
    const player = new TimelinePlayer(tl);
    expect(player.stateAt(500).source).toEqual({ type: 'image', url: 'https://x/a.jpg' });
    const later = player.stateAt(2500);
    expect(later.source?.type).toBe('video');
    expect(later.sourceSinceMs).toBe(1000);
    expect(sourceMediaTimeSec(later, 2500)).toBeCloseTo(13.5);
    expect(player.sources().map((s) => s.type)).toEqual(['image', 'video']);
  });

  it('lists every shader to compile up front, from the base and the events', () => {
    const tl = record([{ t: 0, snap: snap('liquid', 0) }, { t: 50, snap: snap('plasma', 0) }]);
    const player = new TimelinePlayer(tl, { base: { modes: ['vortex', 'none'], params: [] } });
    expect(player.shaderIds().sort()).toEqual(['liquid', 'plasma', 'vortex']);
  });

  it('eases are monotonic from 0 to 1', () => {
    for (const ease of ['linear', 'easeIn', 'easeOut', 'easeInOut'] as const) {
      expect(applyEase(ease, 0)).toBe(0);
      expect(applyEase(ease, 1)).toBe(1);
      expect(applyEase(ease, 0.25)).toBeLessThan(applyEase(ease, 0.75));
    }
    expect(keyframeValueAt([], 10)).toBeUndefined();
  });
});

describe('timeline format additions (#1401)', () => {
  it('records every SlotParams key and source changes, not only the four zoomParams', () => {
    const a = takeSnapshot(['liquid'], [{ zoomParam1: 0.5, lightStrength: 1 }], { type: 'image', url: 'https://x/a.jpg' });
    const b = takeSnapshot(['liquid'], [{ zoomParam1: 0.5, lightStrength: 1.4 }], { type: 'video', url: 'https://x/v.mp4', seekSec: 3 });
    const first = diffSnapshot(null, a, 0);
    expect(first[0]).toEqual({ t: 0, slot: 0, kind: 'source', value: { type: 'image', url: 'https://x/a.jpg' } });
    const next = diffSnapshot(applyEvents(a, first), b, 50);
    expect(next).toEqual([
      { t: 50, slot: 0, kind: 'source', value: { type: 'video', url: 'https://x/v.mp4', seekSec: 3 } },
      { t: 50, slot: 0, kind: 'param', key: 'lightStrength', value: 1.4 },
    ]);
    // A seek alone is playback, not a change.
    const seeked = takeSnapshot(['liquid'], [{ zoomParam1: 0.5, lightStrength: 1.4 }], { type: 'video', url: 'https://x/v.mp4', seekSec: 9 });
    expect(diffSnapshot(applyEvents(b, next), seeked, 100)).toEqual([]);
  });

  it('sanitizes sources (no data:/blob: URLs), keyframes and the new param keys', () => {
    const tl = sanitizeTimeline({
      hz: 20,
      durationMs: 100,
      events: [
        { t: 0, slot: 0, kind: 'source', value: { type: 'image', url: 'data:image/png;base64,AAAA' } },
        { t: 0, slot: 0, kind: 'source', value: { type: 'bogus' } },
        { t: 10, slot: 1, kind: 'param', key: 'fogFalloff', value: 3 },
        { t: 20, slot: 1, kind: 'param', key: 'notAKey', value: 3 },
        { t: 30, slot: 0, kind: 'source', value: { type: 'video', url: 'blob:https://app/1', seekSec: -1 } },
      ],
      keyframes: [
        { t: 500, slot: 0, key: 'zoomParam1', value: 1, ease: 'easeOut' },
        { t: 200, slot: 0, key: 'zoomParam1', value: 0 },
        { t: 300, slot: 9, key: 'zoomParam1', value: 0 },
        { t: 300, slot: 0, key: 'zoomParam1', value: Number.NaN },
      ],
    });
    expect(tl?.events).toEqual([
      { t: 0, slot: 0, kind: 'source', value: { type: 'image' } },
      { t: 10, slot: 1, kind: 'param', key: 'fogFalloff', value: 3 },
      { t: 30, slot: 0, kind: 'source', value: { type: 'video' } },
    ]);
    expect(tl?.keyframes).toEqual([
      { t: 200, slot: 0, key: 'zoomParam1', value: 0, ease: 'linear' },
      { t: 500, slot: 0, key: 'zoomParam1', value: 1, ease: 'easeOut' },
    ]);
    expect(tl?.durationMs).toBe(500);
  });
});
