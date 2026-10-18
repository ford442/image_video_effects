import { __resetAudioParamHold, baseFor, clearSlot, hold, isHeld, release, touch } from './audioParamHold';

describe('audioParamHold', () => {
  let t = 0;
  beforeEach(() => {
    t = 0;
    __resetAudioParamHold(() => t);
  });

  it('holds until release and records the released value as base', () => {
    hold(1, 'zoomParam2');
    expect(isHeld(1, 'zoomParam2')).toBe(true);
    expect(isHeld(0, 'zoomParam2')).toBe(false);
    release(1, 'zoomParam2', 0.7);
    expect(isHeld(1, 'zoomParam2')).toBe(false);
    expect(baseFor(1, 'zoomParam2')).toBe(0.7);
  });

  it('touch holds for a window and is renewed by each call', () => {
    touch(0, 'zoomParam1', 0.3, 500);
    t = 400;
    expect(isHeld(0, 'zoomParam1')).toBe(true);
    touch(0, 'zoomParam1', 0.35, 500);
    t = 800;
    expect(isHeld(0, 'zoomParam1')).toBe(true);
    t = 901;
    expect(isHeld(0, 'zoomParam1')).toBe(false);
    expect(baseFor(0, 'zoomParam1')).toBe(0.35);
  });

  it('ignores non-finite release values', () => {
    release(0, 'zoomParam1', NaN);
    expect(baseFor(0, 'zoomParam1')).toBeUndefined();
  });

  it('clearSlot forgets only that slot', () => {
    hold(2, 'zoomParam1');
    touch(2, 'zoomParam3', 0.9);
    touch(3, 'zoomParam1', 0.1);
    clearSlot(2);
    expect(isHeld(2, 'zoomParam1')).toBe(false);
    expect(baseFor(2, 'zoomParam3')).toBeUndefined();
    expect(baseFor(3, 'zoomParam1')).toBe(0.1);
  });
});
