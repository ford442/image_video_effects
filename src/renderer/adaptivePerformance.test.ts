import { AdaptivePerformanceController } from './adaptivePerformance';
import {
  ADAPTIVE_SCALE_COOLDOWN_MS,
  ADAPTIVE_SCALE_STEP_DOWN,
  ADAPTIVE_SCALE_STREAK,
} from '../config/performancePolicy';

describe('AdaptivePerformanceController', () => {
  let now = 0;

  beforeEach(() => {
    now = 0;
    jest.spyOn(performance, 'now').mockImplementation(() => now);
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  function makeController(opts: {
    fps: number;
    scale: number;
    targetFps?: number;
  }) {
    let scale = opts.scale;
    const setScale = jest.fn((next: number) => {
      scale = next;
    });
    const controller = new AdaptivePerformanceController({
      getFps: () => opts.fps,
      getScale: () => scale,
      setScale,
    });
    controller.start({
      mode: 'auto',
      scale: opts.scale,
      maxActiveSlots: 3,
      maxPassesPerFrame: 8,
      targetFps: opts.targetFps ?? 60,
      adaptive: true,
      preferNonDeepVariants: false,
      colorFormat: 'rgba16float',
    });
    return { controller, setScale, getScale: () => scale };
  }

  it('does not change scale on a single low-FPS sample', () => {
    const { controller, setScale } = makeController({ fps: 20, scale: 1.0 });
    now = 1000;
    controller.sampleNow();
    expect(setScale).not.toHaveBeenCalled();
    controller.stop();
  });

  it('steps down after a sustained low streak', () => {
    const { controller, setScale, getScale } = makeController({ fps: 20, scale: 1.0 });
    for (let i = 0; i < ADAPTIVE_SCALE_STREAK; i++) {
      now = (i + 1) * 1000;
      controller.sampleNow();
    }
    expect(setScale).toHaveBeenCalledTimes(1);
    expect(getScale()).toBeCloseTo(1.0 - ADAPTIVE_SCALE_STEP_DOWN);
    controller.stop();
  });

  it('enforces cooldown between scale changes', () => {
    const { controller, setScale } = makeController({ fps: 20, scale: 1.0 });
    for (let i = 0; i < ADAPTIVE_SCALE_STREAK; i++) {
      now = (i + 1) * 1000;
      controller.sampleNow();
    }
    expect(setScale).toHaveBeenCalledTimes(1);

    // Stay well inside the cooldown window — no additional rebuilds.
    now += ADAPTIVE_SCALE_COOLDOWN_MS / 2;
    for (let i = 0; i < ADAPTIVE_SCALE_STREAK + 2; i++) {
      controller.sampleNow();
    }
    expect(setScale).toHaveBeenCalledTimes(1);

    now += ADAPTIVE_SCALE_COOLDOWN_MS + 1;
    for (let i = 0; i < ADAPTIVE_SCALE_STREAK; i++) {
      now += 1000;
      controller.sampleNow();
    }
    expect(setScale).toHaveBeenCalledTimes(2);
    controller.stop();
  });
});
