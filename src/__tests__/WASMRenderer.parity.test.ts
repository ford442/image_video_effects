jest.mock('../wasm/wasm_bridge.js', () => ({
  initWasmRenderer: jest.fn().mockResolvedValue(true),
  shutdownWasmRenderer: jest.fn(),
  setInputSource: jest.fn(),
  updateAudioFrequencyBins: jest.fn(),
  updateSlotParams: jest.fn(),
  getSupportsDeepWorkgroup: () => true,
  getSlotState: () => ({ shaderId: 'rain', enabled: true, mode: 'chained' }),
  getGPUTimings: () => ({ parallelTime: 1, chainedTime: 2, totalTime: 3, available: false }),
  captureFrameDataUrl: async () => 'data:image/png;base64,abc',
  setRecording: jest.fn(),
  updateUniforms: jest.fn(),
  getFPS: () => 60,
}));

import * as WasmBridge from '../wasm/wasm_bridge.js';
import { WASMRenderer } from '../renderer/WASMRenderer';
import { DEFAULT_CONFIG } from '../renderer/Renderer';

describe('WASMRenderer Phase 3 parity methods', () => {
  let renderer: WASMRenderer;

  beforeEach(() => {
    jest.clearAllMocks();
    renderer = new WASMRenderer(DEFAULT_CONFIG);
  });

  it('forwards updateAudioFrequencyBins to bridge', () => {
    const bins = new Float32Array([0.1, 0.5, 0.9]);
    renderer.updateAudioFrequencyBins(bins);
    expect(WasmBridge.updateAudioFrequencyBins).toHaveBeenCalledWith(bins);
  });

  it('uses bridge updateSlotParams for partial aggregate updates', () => {
    renderer.updateSlotParams({ zoomParam1: 0.7 }, 1);
    expect(WasmBridge.updateSlotParams).toHaveBeenCalledWith(1, { zoomParam1: 0.7 });
  });

  it('exposes slot state, GPU timings, and deep-workgroup queries', () => {
    expect(renderer.getSupportsDeepWorkgroup()).toBe(true);
    expect(renderer.getSlotState(0)).toEqual({ shaderId: 'rain', enabled: true, mode: 'chained' });
    expect(renderer.getGPUTimings()).toEqual({
      parallelTime: 1,
      chainedTime: 2,
      totalTime: 3,
      available: false,
    });
  });

  it('caches frame image data URL and supports recording flag', async () => {
    expect(renderer.getFrameImage()).toBe('');
    const url = await renderer.refreshFrameImage();
    expect(url).toBe('data:image/png;base64,abc');
    expect(renderer.getFrameImage()).toBe('data:image/png;base64,abc');

    renderer.setRecording(true);
    expect(WasmBridge.setRecording).toHaveBeenCalledWith(true);
  });
});
