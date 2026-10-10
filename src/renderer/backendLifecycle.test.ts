import {
  createRendererForType,
  getRendererTypeFromURL,
  isWasmForcedByURL,
  getRenderThreadFromURL,
  resolveRenderThread,
  supportsRenderWorker,
  performBackendSwitch,
  releaseRendererGpu,
  resolveInitBackendPreference,
  usesExclusiveWebGpu,
  yieldForGpuRelease,
} from './backendLifecycle';
import { JSRenderer } from './JSRenderer';
import { WASMRenderer } from './WASMRenderer';
import { WebGPURenderer } from './WebGPURenderer';
import { DEFAULT_CONFIG } from './Renderer';

jest.mock('./WebGPURenderer');
jest.mock('./WASMRenderer');
jest.mock('./JSRenderer');
jest.mock('../wasm/wasm_bridge', () => ({
  initWasmRenderer: jest.fn().mockResolvedValue(true),
  shutdownWasmRenderer: jest.fn(),
}));

describe('backendLifecycle', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('getRendererTypeFromURL', () => {
    it('returns wasm when ?renderer=wasm', () => {
      const original = window.location;
      Object.defineProperty(window, 'location', {
        value: { ...original, search: '?renderer=wasm' },
        configurable: true,
      });
      expect(getRendererTypeFromURL()).toBe('wasm');
      Object.defineProperty(window, 'location', { value: original, configurable: true });
    });

    it('returns null for unknown renderer param', () => {
      const original = window.location;
      Object.defineProperty(window, 'location', {
        value: { ...original, search: '?renderer=metal' },
        configurable: true,
      });
      expect(getRendererTypeFromURL()).toBeNull();
      Object.defineProperty(window, 'location', { value: original, configurable: true });
    });
  });

  describe('isWasmForcedByURL (#1080)', () => {
    it.each([
      ['?renderer=wasm', true],
      ['?renderer=webgpu', false],
      ['?renderer=js', false],
      ['?renderer=main', false],
      ['', false],
    ])('%s → %s', (search, expected) => {
      const original = window.location;
      Object.defineProperty(window, 'location', { value: { ...original, search }, configurable: true });
      try {
        expect(isWasmForcedByURL()).toBe(expected);
      } finally {
        Object.defineProperty(window, 'location', { value: original, configurable: true });
      }
    });
  });

  describe('render thread selection (#1314)', () => {
    const withSearch = (search: string, fn: () => void) => {
      const original = window.location;
      Object.defineProperty(window, 'location', { value: { ...original, search }, configurable: true });
      try {
        fn();
      } finally {
        Object.defineProperty(window, 'location', { value: original, configurable: true });
      }
    };

    it('?renderer=worker / main select the TS WebGPU backend on that thread', () => {
      withSearch('?renderer=worker', () => {
        expect(getRendererTypeFromURL()).toBe('webgpu');
        expect(getRenderThreadFromURL()).toBe('worker');
        expect(resolveRenderThread()).toBe('worker');
      });
      withSearch('?renderer=main', () => {
        expect(getRendererTypeFromURL()).toBe('webgpu');
        expect(resolveRenderThread()).toBe('main');
      });
    });

    it('other renderer values do not pick a thread from the URL', () => {
      withSearch('?renderer=wasm', () => expect(getRenderThreadFromURL()).toBeNull());
    });

    it('defaults to the worker only where Worker + OffscreenCanvas + transfer + WebGPU exist', () => {
      // jsdom: no Worker / OffscreenCanvas → the page.
      expect(supportsRenderWorker()).toBe(false);
      withSearch('', () => expect(resolveRenderThread()).toBe('main'));

      const g = globalThis as Record<string, unknown>;
      const proto = HTMLCanvasElement.prototype as unknown as Record<string, unknown>;
      const saved = { Worker: g.Worker, OffscreenCanvas: g.OffscreenCanvas, transfer: proto.transferControlToOffscreen };
      const nav = navigator as unknown as { gpu?: unknown };
      const savedGpu = nav.gpu;
      g.Worker = class {};
      g.OffscreenCanvas = class {};
      proto.transferControlToOffscreen = () => ({});
      Object.defineProperty(navigator, 'gpu', { value: {}, configurable: true });
      try {
        expect(supportsRenderWorker()).toBe(true);
        withSearch('', () => expect(resolveRenderThread()).toBe('worker'));
        withSearch('?renderer=main', () => expect(resolveRenderThread()).toBe('main'));
      } finally {
        g.Worker = saved.Worker;
        g.OffscreenCanvas = saved.OffscreenCanvas;
        proto.transferControlToOffscreen = saved.transfer;
        Object.defineProperty(navigator, 'gpu', { value: savedGpu, configurable: true });
      }
    });
  });

  describe('usesExclusiveWebGpu', () => {
    it('marks webgpu and wasm as exclusive', () => {
      expect(usesExclusiveWebGpu('webgpu')).toBe(true);
      expect(usesExclusiveWebGpu('wasm')).toBe(true);
      expect(usesExclusiveWebGpu('js')).toBe(false);
    });
  });

  describe('resolveInitBackendPreference', () => {
    it('honours wasm URL without auto-fallback flag', () => {
      const original = window.location;
      Object.defineProperty(window, 'location', {
        value: { ...original, search: '?renderer=wasm' },
        configurable: true,
      });
      expect(resolveInitBackendPreference()).toEqual({ preferredType: 'wasm', wasmUrlFailed: false });
      Object.defineProperty(window, 'location', { value: original, configurable: true });
    });
  });

  describe('performBackendSwitch', () => {
    it('releases webgpu before wasm init on exclusive switch', async () => {
      const order: string[] = [];
      const canvas = document.createElement('canvas');
      const webgpu = {
        init: jest.fn().mockResolvedValue(true),
        destroy: jest.fn(() => order.push('webgpu.destroy')),
        releaseExclusiveGpu: jest.fn(async () => {
          order.push('webgpu.lost');
        }),
        setVideo: jest.fn(),
      };
      const wasm = {
        init: jest.fn(async () => {
          order.push('wasm.init');
          return true;
        }),
        destroy: jest.fn(),
        setVideo: jest.fn(),
      };
      (WebGPURenderer as jest.Mock).mockImplementation(() => webgpu);
      (WASMRenderer as jest.Mock).mockImplementation(() => wasm);

      const result = await performBackendSwitch({
        targetType: 'wasm',
        canvas,
        config: DEFAULT_CONFIG,
        previousType: 'webgpu',
        previousRenderer: webgpu as never,
      });

      expect(result.success).toBe(true);
      expect(webgpu.releaseExclusiveGpu).toHaveBeenCalled();
      expect(webgpu.destroy).not.toHaveBeenCalled();
      expect(order.indexOf('wasm.init')).toBeGreaterThan(order.indexOf('webgpu.lost'));
    });

    it('blocks wasm after a historyTex OOM this tab', async () => {
      sessionStorage.setItem('px_webgpu_oom_block_wasm', '1');
      const canvas = document.createElement('canvas');
      const webgpu = { init: jest.fn(), destroy: jest.fn(), setVideo: jest.fn() };
      const result = await performBackendSwitch({
        targetType: 'wasm',
        canvas,
        config: DEFAULT_CONFIG,
        previousType: 'webgpu',
        previousRenderer: webgpu as never,
      });
      expect(result.success).toBe(false);
      expect(result.restoreType).toBeNull();
      sessionStorage.removeItem('px_webgpu_oom_block_wasm');
    });

    it('requests restore type when wasm fails after exclusive release', async () => {
      const canvas = document.createElement('canvas');
      const webgpu = { init: jest.fn().mockResolvedValue(true), destroy: jest.fn(), setVideo: jest.fn() };
      const wasm = { init: jest.fn().mockResolvedValue(false), destroy: jest.fn(), setVideo: jest.fn() };
      (WASMRenderer as jest.Mock).mockImplementation(() => wasm);

      const result = await performBackendSwitch({
        targetType: 'wasm',
        canvas,
        config: DEFAULT_CONFIG,
        previousType: 'webgpu',
        previousRenderer: webgpu as never,
      });

      expect(result.success).toBe(false);
      expect(result.restoreType).toBe('webgpu');
      expect(result.failedWasmRenderer).toBe(wasm);
    });
  });

  describe('yieldForGpuRelease', () => {
    it('resolves after one animation frame when available', async () => {
      const raf = jest.fn((cb: FrameRequestCallback) => {
        cb(0);
        return 0;
      });
      const original = global.requestAnimationFrame;
      global.requestAnimationFrame = raf;
      await yieldForGpuRelease();
      expect(raf).toHaveBeenCalled();
      global.requestAnimationFrame = original;
    });
  });

  describe('releaseRendererGpu', () => {
    it('prefers releaseExclusiveGpu and does not call destroy separately', async () => {
      const renderer = {
        destroy: jest.fn(),
        releaseExclusiveGpu: jest.fn().mockResolvedValue(undefined),
      };
      await releaseRendererGpu(renderer as never);
      expect(renderer.releaseExclusiveGpu).toHaveBeenCalledTimes(1);
      expect(renderer.destroy).not.toHaveBeenCalled();
    });

    it('awaits an async destroy() and then yields a frame', async () => {
      const order: string[] = [];
      const renderer = {
        destroy: jest.fn(
          () => new Promise<void>((resolve) => setTimeout(() => { order.push('destroyed'); resolve(); }, 5)),
        ),
      };
      const original = global.requestAnimationFrame;
      global.requestAnimationFrame = jest.fn((cb: FrameRequestCallback) => {
        order.push('yield');
        cb(0);
        return 0;
      });
      await releaseRendererGpu(renderer as never);
      global.requestAnimationFrame = original;
      expect(order).toEqual(['destroyed', 'yield']);
    });
  });

  describe('createRendererForType', () => {
    it('instantiates the three backend classes', () => {
      (WebGPURenderer as jest.Mock).mockImplementation(() => ({ tag: 'webgpu' }));
      (WASMRenderer as jest.Mock).mockImplementation(() => ({ tag: 'wasm' }));
      (JSRenderer as jest.Mock).mockImplementation(() => ({ tag: 'js' }));

      expect(createRendererForType('webgpu', DEFAULT_CONFIG)).toEqual({ tag: 'webgpu' });
      expect(createRendererForType('wasm', DEFAULT_CONFIG)).toEqual({ tag: 'wasm' });
      expect(createRendererForType('js', DEFAULT_CONFIG)).toEqual({ tag: 'js' });
    });
  });
});
