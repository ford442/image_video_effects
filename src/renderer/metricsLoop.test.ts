import { createMetricsLoop } from './metricsLoop';

describe('createMetricsLoop', () => {
  const origRaf = global.requestAnimationFrame;
  const origCaf = global.cancelAnimationFrame;
  let live: Map<number, FrameRequestCallback>;
  beforeEach(() => {
    let id = 1;
    live = new Map();
    (global as any).requestAnimationFrame = (cb: FrameRequestCallback) => { live.set(id, cb); return id++; };
    (global as any).cancelAnimationFrame = (i: number) => { live.delete(i); };
  });
  afterEach(() => {
    global.requestAnimationFrame = origRaf;
    global.cancelAnimationFrame = origCaf;
  });

  it('restarting never stacks loops and stop() cancels', () => {
    const tick = jest.fn();
    const loop = createMetricsLoop(tick);
    for (let i = 0; i < 10; i++) loop.start();
    expect(live.size).toBe(1);
    expect(loop.isRunning()).toBe(true);
    loop.stop();
    expect(live.size).toBe(0);
    expect(loop.isRunning()).toBe(false);
  });
});
