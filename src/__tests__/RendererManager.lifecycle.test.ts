import { RendererManager } from '../renderer/RendererManager';
import { WebGPURenderer } from '../renderer/WebGPURenderer';
import { WASMRenderer } from '../renderer/WASMRenderer';
import { JSRenderer } from '../renderer/JSRenderer';
import { DEFAULT_CONFIG } from '../renderer/Renderer';

jest.mock('../renderer/WebGPURenderer');
jest.mock('../renderer/WASMRenderer');
jest.mock('../renderer/JSRenderer');
jest.mock('../wasm/wasm_bridge', () => ({
  initWasmRenderer: jest.fn().mockResolvedValue(true),
  shutdownWasmRenderer: jest.fn(),
}));

function mockBackend(fps: number) {
  return {
    init: jest.fn().mockResolvedValue(true),
    destroy: jest.fn(),
    releaseExclusiveGpu: jest.fn().mockResolvedValue(undefined),
    setInputSource: jest.fn(),
    getInputSource: jest.fn().mockReturnValue('image'),
    updateVideoFrame: jest.fn(),
    setVideo: jest.fn(),
    getVideo: jest.fn().mockReturnValue(null),
    loadImage: jest.fn().mockResolvedValue(''),
    getFPS: jest.fn().mockReturnValue(fps),
  };
}

/** Fake rAF queue: tracks live (requested, not cancelled, not yet fired) callbacks. */
function installFakeRaf() {
  let nextId = 1;
  const live = new Map<number, FrameRequestCallback>();
  const raf = jest.fn((cb: FrameRequestCallback) => {
    const id = nextId++;
    live.set(id, cb);
    return id;
  });
  const caf = jest.fn((id: number) => { live.delete(id); });
  (global as any).requestAnimationFrame = raf;
  (global as any).cancelAnimationFrame = caf;
  return {
    live,
    flush() {
      const cbs = [...live.values()];
      live.clear();
      cbs.forEach((cb) => cb(0));
    },
  };
}

describe('RendererManager lifecycle (#1311 WP-A)', () => {
  const origRaf = global.requestAnimationFrame;
  const origCaf = global.cancelAnimationFrame;
  afterEach(() => {
    global.requestAnimationFrame = origRaf;
    global.cancelAnimationFrame = origCaf;
  });

  it('10 backend toggles leave exactly one live metrics rAF loop; destroy() stops it', async () => {
    const fake = installFakeRaf();
    (WebGPURenderer as jest.Mock).mockImplementation(() => mockBackend(60));
    (WASMRenderer as jest.Mock).mockImplementation(() => mockBackend(55));
    (JSRenderer as jest.Mock).mockImplementation(() => mockBackend(30));
    const onMetrics = jest.fn();
    const manager = new RendererManager(DEFAULT_CONFIG, onMetrics);
    await manager.init(document.createElement('canvas'));
    for (let i = 0; i < 10; i++) {
      expect(await manager.switchRenderer(i % 2 === 0 ? 'wasm' : 'webgpu')).toBe(true);
    }
    expect(fake.live.size).toBe(1);
    onMetrics.mockClear();
    fake.flush();
    expect(onMetrics).toHaveBeenCalledTimes(1);
    expect(fake.live.size).toBe(1);

    await manager.destroy();
    expect(fake.live.size).toBe(0);
  });
});
