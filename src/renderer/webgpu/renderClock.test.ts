import { createRealtimeClock, createSteppedClock, isSteppedClock } from './renderClock';
import { WebGPUFrameRenderer } from './frame';
import type { WebGPUFrameState } from './frameState';

describe('RenderClock (#1401)', () => {
  it('realtime: seconds of wall time since the clock was created', () => {
    let wall = 100;
    const clock = createRealtimeClock({ wall: () => wall });
    expect(clock.mode).toBe('realtime');
    expect(clock.now()).toBe(0);
    wall = 102.5;
    expect(clock.now()).toBeCloseTo(2.5);
    expect(clock.advance).toBeUndefined();
    expect(isSteppedClock(clock)).toBe(false);
  });

  it('stepped: exactly 1/fps per step, without float drift over long renders', () => {
    const clock = createSteppedClock(60);
    expect(clock.now()).toBe(0);
    for (let i = 0; i < 60 * 600; i++) clock.step();
    expect(clock.frame).toBe(36_000);
    expect(clock.now()).toBe(600);
    expect(isSteppedClock(clock)).toBe(true);
  });

  it('stepped: seek and advance keep the frame index in step', () => {
    const clock = createSteppedClock(30, 1);
    clock.seek(2);
    expect(clock.now()).toBe(2);
    expect(clock.frame).toBe(30);
    clock.advance(0.5);
    expect(clock.now()).toBe(2.5);
    expect(clock.frame).toBe(45);
    clock.step();
    expect(clock.now()).toBeCloseTo(1 + 46 / 30, 12);
    clock.seek(Number.NaN);
    expect(clock.frame).toBe(46);
  });

  it('rejects a non-positive fps', () => {
    expect(() => createSteppedClock(0)).toThrow(RangeError);
    expect(() => createSteppedClock(Number.NaN)).toThrow(RangeError);
  });

  it('the frame loop takes currentTime from the state clock, not performance.now()', () => {
    const queued: Array<() => void> = [];
    vi.spyOn(window, 'requestAnimationFrame').mockImplementation((cb) => {
      queued.push(() => cb(0));
      return queued.length;
    });
    const clock = createSteppedClock(24, 10);
    const state = { initialized: true, clock, currentTime: 0, animationId: null } as unknown as WebGPUFrameState;
    const renderer = new WebGPUFrameRenderer();
    const seen: number[] = [];
    vi.spyOn(renderer, 'renderFrame').mockImplementation((s) => {
      seen.push(s.currentTime);
    });
    renderer.startRenderLoop(state);
    clock.step();
    queued.shift()?.();
    expect(seen).toEqual([10, 10 + 1 / 24]);
    renderer.stopRenderLoop(state);
    vi.restoreAllMocks();
  });
});
