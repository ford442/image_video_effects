import {
  ADAPTIVE_FPS_HIGH_RATIO,
  ADAPTIVE_FPS_LOW_RATIO,
  ADAPTIVE_SCALE_COOLDOWN_MS,
  ADAPTIVE_SCALE_STEP_DOWN,
  ADAPTIVE_SCALE_STEP_UP,
  ADAPTIVE_SCALE_STREAK,
  MIN_RENDER_SCALE,
  MAX_RENDER_SCALE,
  ResolvedPerformancePolicy,
  snapRenderScale,
} from '../config/performancePolicy';

export interface AdaptivePerformanceCallbacks {
  getFps: () => number;
  getScale: () => number;
  setScale: (scale: number) => void;
}

/**
 * Once-per-second FPS sampler that nudges internal render scale when policy.adaptive is on.
 *
 * Scale changes rebuild GPU textures and are expensive — we require a short
 * streak of bad/good FPS and enforce a cooldown so the setInterval tick never
 * thrash-rebuilds every second.
 */
export class AdaptivePerformanceController {
  private intervalId: ReturnType<typeof setInterval> | null = null;
  private policy: ResolvedPerformancePolicy | null = null;
  /** Negative infinity so the first scale change is not blocked by cooldown. */
  private lastScaleChangeMs = Number.NEGATIVE_INFINITY;
  private lowStreak = 0;
  private highStreak = 0;

  constructor(private readonly callbacks: AdaptivePerformanceCallbacks) {}

  start(policy: ResolvedPerformancePolicy, sampleIntervalMs = 1000): void {
    this.policy = policy;
    this.stop();
    if (!policy.adaptive) return;

    this.lowStreak = 0;
    this.highStreak = 0;
    // Allow an immediate first adjustment after start if FPS is already bad.
    this.lastScaleChangeMs = Number.NEGATIVE_INFINITY;
    this.intervalId = setInterval(() => this.tick(), sampleIntervalMs);
  }

  /** Test seam: run one sample without waiting for the interval. */
  sampleNow(): void {
    this.tick();
  }

  stop(): void {
    if (this.intervalId !== null) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
  }

  updatePolicy(policy: ResolvedPerformancePolicy): void {
    if (policy.adaptive) {
      this.start(policy);
    } else {
      this.policy = policy;
      this.stop();
    }
  }

  private tick(): void {
    const policy = this.policy;
    if (!policy?.adaptive) return;

    const fps = this.callbacks.getFps();
    if (fps <= 0) return;

    const currentScale = this.callbacks.getScale();
    const ratio = fps / policy.targetFps;
    const now =
      typeof performance !== 'undefined' && typeof performance.now === 'function'
        ? performance.now()
        : Date.now();

    if (ratio < ADAPTIVE_FPS_LOW_RATIO) {
      this.lowStreak += 1;
      this.highStreak = 0;
    } else if (ratio > ADAPTIVE_FPS_HIGH_RATIO) {
      this.highStreak += 1;
      this.lowStreak = 0;
    } else {
      this.lowStreak = 0;
      this.highStreak = 0;
      return;
    }

    if (now - this.lastScaleChangeMs <= ADAPTIVE_SCALE_COOLDOWN_MS) {
      return;
    }

    if (this.lowStreak >= ADAPTIVE_SCALE_STREAK && currentScale > MIN_RENDER_SCALE) {
      const next = snapRenderScale(currentScale - ADAPTIVE_SCALE_STEP_DOWN);
      if (next !== currentScale) {
        this.applyScale(next, now);
      }
      this.lowStreak = 0;
      return;
    }

    if (this.highStreak >= ADAPTIVE_SCALE_STREAK && currentScale < MAX_RENDER_SCALE) {
      const next = snapRenderScale(currentScale + ADAPTIVE_SCALE_STEP_UP);
      if (next !== currentScale) {
        this.applyScale(next, now);
      }
      this.highStreak = 0;
    }
  }

  private applyScale(next: number, now: number): void {
    this.lastScaleChangeMs = now;
    this.callbacks.setScale(next);
  }
}
