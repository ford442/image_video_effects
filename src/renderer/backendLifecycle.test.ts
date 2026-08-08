import {
  createRendererForType,
  getRendererTypeFromURL,
  performBackendSwitch,
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
      expect(order.indexOf('webgpu.destroy')).toBeGreaterThanOrEqual(0);
      expect(order.indexOf('wasm.init')).toBeGreaterThan(order.indexOf('webgpu.destroy'));
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
