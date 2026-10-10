import { applyEvents, diffSnapshot, firstEventAfter, takeSnapshot } from './vjSetRecorder';
import type { VjTimelineEvent } from './vjSetExport';

describe('vjSetRecorder', () => {
  const a = takeSnapshot(['liquid-metal', 'none'], [{ zoomParam1: 0.5, zoomParam2: 0.25 }, { zoomParam1: 0.1 }]);

  it('emits the full state for the first sample', () => {
    const events = diffSnapshot(null, a, 0);
    expect(events).toEqual([
      { t: 0, slot: 0, kind: 'shader', value: 'liquid-metal' },
      { t: 0, slot: 0, kind: 'param', key: 'zoomParam1', value: 0.5 },
      { t: 0, slot: 0, kind: 'param', key: 'zoomParam2', value: 0.25 },
      { t: 0, slot: 1, kind: 'shader', value: 'none' },
      { t: 0, slot: 1, kind: 'param', key: 'zoomParam1', value: 0.1 },
    ]);
  });

  it('emits only changes beyond epsilon', () => {
    const b = takeSnapshot(['liquid-metal', 'neon-grid'], [{ zoomParam1: 0.5004, zoomParam2: 0.3 }, { zoomParam1: 0.1 }]);
    expect(diffSnapshot(a, b, 50)).toEqual([
      { t: 50, slot: 0, kind: 'param', key: 'zoomParam2', value: 0.3 },
      { t: 50, slot: 1, kind: 'shader', value: 'neon-grid' },
    ]);
  });

  it('accumulates slow drifts against the last recorded value', () => {
    let recorded = a;
    let total: VjTimelineEvent[] = [];
    for (let i = 1; i <= 5; i++) {
      const snap = takeSnapshot(a.modes, [{ zoomParam1: 0.5 + i * 0.0004, zoomParam2: 0.25 }, { zoomParam1: 0.1 }]);
      const diff = diffSnapshot(recorded, snap, i * 50);
      recorded = applyEvents(recorded, diff);
      total = total.concat(diff);
    }
    // 0.0004/step is under epsilon each time, but crosses it cumulatively.
    expect(total.length).toBeGreaterThan(0);
    expect(total[0]).toMatchObject({ slot: 0, key: 'zoomParam1' });
  });

  it('snapshots are detached copies', () => {
    const params = [{ zoomParam1: 0.2 }];
    const snap = takeSnapshot(['x'], params);
    params[0]!.zoomParam1 = 0.9;
    expect(snap.params[0]!.zoomParam1).toBe(0.2);
  });

  it('firstEventAfter binary-searches the playback cursor', () => {
    const events = [0, 0, 50, 100, 100, 150].map((t) => ({ t, slot: 0, kind: 'shader' as const, value: 'x' }));
    expect(firstEventAfter(events, -1)).toBe(0);
    expect(firstEventAfter(events, 0)).toBe(2);
    expect(firstEventAfter(events, 99)).toBe(3);
    expect(firstEventAfter(events, 100)).toBe(5);
    expect(firstEventAfter(events, 1000)).toBe(6);
  });
});
