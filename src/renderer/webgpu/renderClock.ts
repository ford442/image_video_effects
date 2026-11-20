/**
 * renderClock.ts
 *
 * Where the renderer's *simulation* time comes from (#1401). Shader `time`, ripple start
 * stamps, the modulation bus LFOs and the cue crossfade ramp all read the frame's
 * `currentTime`, and the frame loop takes that from the frame state's clock:
 *
 *   - realtime: wall time since the clock was created (the live, vsync-paced loop).
 *   - stepped:  advances only when told to — exactly `1 / fps` per rendered frame, or a seek
 *               to an absolute time (`renderFrameAt`). Offline export and golden frames use it,
 *               so the same inputs give the same frames however slowly the GPU renders them.
 *
 * Profiling (WebGPUTiming, wall-clock pass timings, the FPS counter) keeps `performance.now()`.
 */

export type RenderClockMode = 'realtime' | 'stepped';

export interface RenderClock {
  readonly mode: RenderClockMode;
  /** Simulation time in seconds. */
  now(): number;
  /** Stepped clocks only: move simulation time forward by `dtSec`. */
  advance?(dtSec: number): void;
}

export interface SteppedRenderClock extends RenderClock {
  readonly mode: 'stepped';
  readonly fps: number;
  /** Frames stepped (or sought to) since the clock started. */
  readonly frame: number;
  advance(dtSec: number): void;
  /** Advance exactly one frame: time becomes `startSec + frame / fps` (no float drift). */
  step(): void;
  /** Jump to an absolute time in seconds (the frame index follows, rounded). */
  seek(timeSec: number): void;
}

const wallSeconds = (): number =>
  (typeof performance !== 'undefined' && typeof performance.now === 'function' ? performance.now() : Date.now()) / 1000;

/** Wall time since creation (or since `originSec` on the `wall` timeline). */
export function createRealtimeClock(
  options: { wall?: () => number; originSec?: number } = {},
): RenderClock {
  const wall = options.wall ?? wallSeconds;
  const origin = options.originSec ?? wall();
  return {
    mode: 'realtime',
    now: () => wall() - origin,
  };
}

export function createSteppedClock(fps: number, startSec = 0): SteppedRenderClock {
  if (!Number.isFinite(fps) || fps <= 0) throw new RangeError(`stepped clock needs fps > 0 (got ${fps})`);
  const start = Number.isFinite(startSec) ? startSec : 0;
  let frame = 0;
  let time = start;
  return {
    mode: 'stepped',
    fps,
    get frame() {
      return frame;
    },
    now: () => time,
    advance(dtSec: number) {
      if (!Number.isFinite(dtSec)) return;
      time += dtSec;
      frame = Math.round((time - start) * fps);
    },
    step() {
      frame += 1;
      time = start + frame / fps;
    },
    seek(timeSec: number) {
      if (!Number.isFinite(timeSec)) return;
      time = timeSec;
      frame = Math.round((timeSec - start) * fps);
    },
  };
}

export function isSteppedClock(clock: RenderClock): clock is SteppedRenderClock {
  return clock.mode === 'stepped';
}
