/**
 * metricsLoop.ts — single-owner rAF loop for RendererManager metrics (#1311 WP-A item 1).
 * start() cancels any previous loop first, so backend switches / StrictMode remounts never stack loops.
 */
export interface MetricsLoop {
  start(): void;
  stop(): void;
  isRunning(): boolean;
}

export function createMetricsLoop(tick: () => void): MetricsLoop {
  let rafId: number | null = null;
  const loop = () => {
    tick();
    rafId = requestAnimationFrame(loop);
  };
  const stop = () => {
    if (rafId !== null) cancelAnimationFrame(rafId);
    rafId = null;
  };
  return {
    start() {
      stop();
      loop();
    },
    stop,
    isRunning: () => rafId !== null,
  };
}
