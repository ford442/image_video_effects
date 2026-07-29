import * as WasmBridge from '../wasm/wasm_bridge.js';
import { WASMRenderer } from '../renderer/WASMRenderer';
import { DEFAULT_CONFIG } from '../renderer/Renderer';

jest.mock('../wasm/wasm_bridge.js', () => ({
  initWasmRenderer: jest.fn().mockResolvedValue(true),
  shutdownWasmRenderer: jest.fn(),
  setInputSource: jest.fn(),
  updateAudioFrequencyBins: jest.fn(),
  updateAudioData: jest.fn(),
  updateSlotParams: jest.fn(),
  getSupportsDeepWorkgroup: () => true,
  getSlotState: () => ({ shaderId: 'rain', enabled: true, mode: 'chained' }),
  getGPUTimings: () => ({ parallelTime: 1, chainedTime: 2, totalTime: 3, available: false, timingSource: 'wall-clock' }),
  isRecordingActive: jest.fn().mockReturnValue(false),
  captureFrameDataUrl: async () => 'data:image/png;base64,abc',
  setRecording: jest.fn(),
  startRecording: jest.fn().mockResolvedValue(new Blob()),
  stopRecording: jest.fn(),
  updateUniforms: jest.fn(),
  getFPS: () => 60,
}));

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
      timingSource: 'wall-clock',
    });
  });

  it('caches audio data and FFT bins for getAudioData()', () => {
    const bins = new Float32Array([0.2, 0.4, 0.6]);
    renderer.updateAudioData(0.1, 0.5, 0.9);
    renderer.updateAudioFrequencyBins(bins);

    expect(WasmBridge.updateAudioData).toHaveBeenCalledWith(0.1, 0.5, 0.9);
    expect(WasmBridge.updateAudioFrequencyBins).toHaveBeenCalledWith(bins);

    const audio = renderer.getAudioData();
    expect(audio.bass).toBe(0.1);
    expect(audio.mid).toBe(0.5);
    expect(audio.treble).toBe(0.9);
    expect(audio.freqBins[0]).toBeCloseTo(0.2);
    expect(audio.freqBins[1]).toBeCloseTo(0.4);
    expect(audio.freqBins[2]).toBeCloseTo(0.6);
  });

  it('tracks recording mode and active state', () => {
    renderer.setRecordingMode('continuous');
    expect(renderer.getRecordingMode()).toBe('continuous');

    renderer.setRecording(true);
    expect(renderer.isRecording()).toBe(true);
    expect(WasmBridge.setRecording).toHaveBeenCalledWith(true);
  });

  it('caches frame image data URL', async () => {
    expect(renderer.getFrameImage()).toBe('');
    const url = await renderer.refreshFrameImage();
    expect(url).toBe('data:image/png;base64,abc');
    expect(renderer.getFrameImage()).toBe('data:image/png;base64,abc');
  });

  it('delegates startRecording and stopRecording to the bridge', async () => {
    const canvas = document.createElement('canvas');
    await renderer.startRecording(canvas, { durationMs: 5000 });
    expect(WasmBridge.startRecording).toHaveBeenCalledWith(canvas, { durationMs: 5000 });

    renderer.stopRecording();
    expect(WasmBridge.stopRecording).toHaveBeenCalled();
  });
});
