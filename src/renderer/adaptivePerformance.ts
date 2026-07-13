import {
  ADAPTIVE_FPS_HIGH_RATIO,
  ADAPTIVE_FPS_LOW_RATIO,
  ADAPTIVE_SCALE_STEP_DOWN,
  ADAPTIVE_SCALE_STEP_UP,
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
 */
export class AdaptivePerformanceController {
  private intervalId: ReturnType<typeof setInterval> | null = null;
  private policy: ResolvedPerformancePolicy | null = null;

  constructor(private readonly callbacks: AdaptivePerformanceCallbacks) {}

  start(policy: ResolvedPerformancePolicy): void {
    this.policy = policy;
    this.stop();
    if (!policy.adaptive) return;

    this.intervalId = setInterval(() => this.tick(), 1000);
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

    if (ratio < ADAPTIVE_FPS_LOW_RATIO && currentScale > MIN_RENDER_SCALE) {
      const next = snapRenderScale(currentScale - ADAPTIVE_SCALE_STEP_DOWN);
      if (next !== currentScale) {
        this.callbacks.setScale(next);
      }
      return;
    }

    if (ratio > ADAPTIVE_FPS_HIGH_RATIO && currentScale < MAX_RENDER_SCALE) {
      const next = snapRenderScale(currentScale + ADAPTIVE_SCALE_STEP_UP);
      if (next !== currentScale) {
        this.callbacks.setScale(next);
      }
    }
  }
}
