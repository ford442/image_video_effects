import { AdaptivePerformanceController } from './adaptivePerformance';
import { adviseNodeDemotion, adviseNodePromotion, ScalableNodeState } from './nodeScaleAdvisor';
import type { PassTiming } from './passTimings';
import { QUALITY_PRESETS } from '../config/performancePolicy';

const pass = (over: Partial<PassTiming>): PassTiming => ({
  key: 'k', label: 'k', kind: 'compute', scale: 1, gpuMs: 1, iterations: 1, ...over,
});

const passes = [
  pass({ key: '0:tensor', slot: 0, nodeId: 'tensor', gpuMs: 6 }),
  pass({ key: '0:render', slot: 0, nodeId: 'render', gpuMs: 2 }),
  pass({ key: '1:plasma', slot: 1, entry: 'plasma', gpuMs: 2 }),
  pass({ key: 'present', kind: 'present', gpuMs: 50 }), // not compute: ignored
];

const node = (over: Partial<ScalableNodeState> = {}): ScalableNodeState => ({
  slot: 0, nodeId: 'tensor', minScale: 0.5, scale: 1, ...over,
});

describe('adviseNodeDemotion', () => {
  it('demotes the dominant scalable node by one step', () => {
    expect(adviseNodeDemotion(passes, [node()])).toEqual({ kind: 'node', slot: 0, nodeId: 'tensor', scale: 0.75 });
  });

  it('falls back to the global scale when the heaviest pass is not scalable or already at its floor', () => {
    expect(adviseNodeDemotion(passes, [node({ nodeId: 'render' })])).toEqual({ kind: 'global' });
    expect(adviseNodeDemotion(passes, [node({ scale: 0.5 })])).toEqual({ kind: 'global' });
  });

  it('does not single out a node with a small share of compute time', () => {
    const flat = [
      pass({ key: '0:tensor', slot: 0, nodeId: 'tensor', gpuMs: 3 }),
      pass({ key: '1:a', slot: 1, entry: 'a', gpuMs: 3 }),
      pass({ key: '2:b', slot: 2, entry: 'b', gpuMs: 3 }),
    ];
    expect(adviseNodeDemotion(flat, [node()])).toEqual({ kind: 'global' });
    expect(adviseNodeDemotion([], [node()])).toEqual({ kind: 'global' });
  });
});

describe('adviseNodePromotion', () => {
  it('undoes the most recent demotion first, then hands back to the global scale', () => {
    const nodes = [node({ scale: 0.75 }), node({ slot: 1, nodeId: 'blur', scale: 0.5 })];
    expect(adviseNodePromotion(nodes, ['1:blur', '0:tensor'])).toMatchObject({ slot: 0, nodeId: 'tensor', scale: 1 });
    expect(adviseNodePromotion(nodes, ['0:tensor', '1:blur'])).toMatchObject({ slot: 1, nodeId: 'blur', scale: 0.75 });
    expect(adviseNodePromotion([node()], [])).toEqual({ kind: 'global' });
  });
});

describe('AdaptivePerformanceController with per-node demotion', () => {
  beforeEach(() => jest.useFakeTimers());
  afterEach(() => jest.useRealTimers());

  it('shrinks the expensive node before the canvas, and restores it before scaling the canvas up', () => {
    let fps = 20;
    let scale = 1;
    const nodes = [node()];
    const setScale = jest.fn((s: number) => { scale = s; });
    const setNodeScale = jest.fn((_slot: number, _id: string, s: number) => { nodes[0].scale = s; });
    const ctl = new AdaptivePerformanceController({
      getFps: () => fps,
      getScale: () => scale,
      setScale,
      getPassTimings: () => passes,
      getScalableNodes: () => nodes,
      setNodeScale,
    });
    // Huge interval: only the explicit sampleNow() calls run; timers just move the clock.
    ctl.start({ ...QUALITY_PRESETS.balanced, mode: 'auto', adaptive: true, targetFps: 60 } as never, 1e9);

    ctl.sampleNow();
    ctl.sampleNow(); // low streak reached → node, not canvas
    expect(setNodeScale).toHaveBeenLastCalledWith(0, 'tensor', 0.75);
    expect(setScale).not.toHaveBeenCalled();

    jest.advanceTimersByTime(2500);
    ctl.sampleNow();
    ctl.sampleNow();
    expect(setNodeScale).toHaveBeenLastCalledWith(0, 'tensor', 0.5);
    expect(setScale).not.toHaveBeenCalled();

    jest.advanceTimersByTime(2500);
    ctl.sampleNow();
    ctl.sampleNow(); // node at its floor → the canvas scale steps down
    expect(setScale).toHaveBeenCalledTimes(1);

    fps = 75;
    jest.advanceTimersByTime(5000);
    ctl.sampleNow();
    ctl.sampleNow(); // recovering: node first
    expect(setNodeScale).toHaveBeenLastCalledWith(0, 'tensor', 0.75);
    expect(setScale).toHaveBeenCalledTimes(1);
    ctl.stop();
  });
});
