/**
 * #1311 WP-A item 4 — a WASM render loop that stops after repeated errors must surface
 * through reportError + onRenderLoopStopped, not only console.error.
 */
import { WASMRenderer } from '../renderer/WASMRenderer';
import { DEFAULT_CONFIG } from '../renderer/Renderer';
import * as ErrorHandling from '../renderer/ErrorHandling';
import * as WasmBridge from '../wasm/wasm_bridge';

jest.mock('../wasm/wasm_bridge', () => ({
  initWasmRenderer: jest.fn(),
  shutdownWasmRenderer: jest.fn(),
  updateUniforms: jest.fn(),
  getFPS: () => 0,
}));

describe('WASMRenderer render-loop stop (#1311 WP-A)', () => {
  const origRaf = global.requestAnimationFrame;
  afterEach(() => { global.requestAnimationFrame = origRaf; });

  it('reports a non-recoverable error once and notifies the owner', () => {
    const queue: FrameRequestCallback[] = [];
    (global as any).requestAnimationFrame = (cb: FrameRequestCallback) => { queue.push(cb); return queue.length; };
    (WasmBridge.updateUniforms as jest.Mock).mockImplementation(() => { throw new Error('boom'); });
    const report = jest.spyOn(ErrorHandling, 'reportError').mockImplementation(() => {});
    jest.spyOn(console, 'error').mockImplementation(() => {});

    const renderer = new WASMRenderer(DEFAULT_CONFIG);
    const onStopped = jest.fn();
    renderer.onRenderLoopStopped = onStopped;
    (renderer as any).initialized = true;
    (renderer as any).startRenderLoop();
    while (queue.length) queue.shift()!(0);

    const stops = report.mock.calls.filter(([e]) => e.type === 'wasm-device-lost');
    expect(stops).toHaveLength(1);
    expect(stops[0][0].recoverable).toBe(false);
    expect(onStopped).toHaveBeenCalledTimes(1);
    expect(onStopped.mock.calls[0][0].message).toMatch(/boom/);
  });
});
