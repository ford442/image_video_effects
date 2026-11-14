import * as WasmBridge from '../wasm/wasm_bridge';
import { WASMRenderer } from '../renderer/WASMRenderer';
import { DEFAULT_CONFIG } from '../renderer/Renderer';
import { startGpuEncodeSession } from '../recording/gpuEncodeSupport';

vi.mock('../wasm/wasm_bridge', () => ({
  initWasmRenderer: vi.fn().mockResolvedValue(true),
  shutdownWasmRenderer: vi.fn(),
  setInputSource: vi.fn(),
  updateAudioFrequencyBins: vi.fn(),
  updateAudioData: vi.fn(),
  updateSlotParams: vi.fn(),
  getSupportsDeepWorkgroup: () => true,
  getSlotState: () => ({ shaderId: 'rain', enabled: true, mode: 'chained' }),
  getGPUTimings: () => ({ parallelTime: 1, chainedTime: 2, totalTime: 3, available: false, timingSource: 'wall-clock' }),
  isRecordingActive: vi.fn().mockReturnValue(false),
  captureFrameDataUrl: async () => 'data:image/png;base64,abc',
  setRecording: vi.fn(),
  startRecording: vi.fn().mockResolvedValue(new Blob()),
  stopRecording: vi.fn(),
  updateUniforms: vi.fn(),
  getFPS: () => 60,
  getPresentCanvas: vi.fn().mockReturnValue(null),
  supportsCanvasCopySrc: vi.fn().mockReturnValue(true),
  setCanvasCopySrc: vi.fn().mockReturnValue(true),
}));

vi.mock('../recording/gpuEncodeSupport', () => ({
  startGpuEncodeSession: vi.fn().mockResolvedValue(null),
}));

describe('WASMRenderer Phase 3 parity methods', () => {
  let renderer: WASMRenderer;

  beforeEach(() => {
    vi.clearAllMocks();
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
    // WebCodecs is the default: WASMRenderer injects the shared encode session.
    expect(WasmBridge.startRecording).toHaveBeenCalledWith(canvas, {
      durationMs: 5000,
      gpuEncode: expect.any(Function),
    });

    renderer.stopRecording();
    expect(WasmBridge.stopRecording).toHaveBeenCalled();
  });

  it('records through the bridge with a WebCodecs starter wired to the C++ swapchain', async () => {
    const canvas = document.createElement('canvas');
    const present = document.createElement('canvas');
    vi.mocked(WasmBridge.getPresentCanvas).mockReturnValue(present);
    vi.mocked(WasmBridge.supportsCanvasCopySrc).mockReturnValue(true);
    vi.mocked(WasmBridge.setCanvasCopySrc).mockReturnValue(true);
    await renderer.startRecording(canvas, { durationMs: 1000 });

    const [passedCanvas, opts] = vi.mocked(WasmBridge.startRecording).mock.calls[0]!;
    expect(passedCanvas).toBe(canvas);
    expect(opts).toMatchObject({ durationMs: 1000 });
    const starter = (opts as { gpuEncode?: (c: () => Promise<ImageData>, o: unknown) => Promise<unknown> }).gpuEncode;
    expect(typeof starter).toBe('function');

    const capture = vi.fn();
    const encodeOpts = { width: 640, height: 360, fps: 60, bitrate: 1 };
    await starter!(capture, encodeOpts);
    const [frames, passedOpts] = vi.mocked(startGpuEncodeSession).mock.calls[0]!;
    expect(passedOpts).toBe(encodeOpts);
    // Same frame-source contract as the TS path: present canvas + COPY_SRC
    // toggle first, the RGBA readback as fallback.
    expect(frames.canvas).toBe(present);
    expect(frames.readback).toBe(capture);
    expect(frames.supportsCanvasCopySrc()).toBe(true);
    expect(frames.setCanvasCopySrc(true)).toBe(true);
    expect(WasmBridge.setCanvasCopySrc).toHaveBeenCalledWith(true);
  });

  it('falls back to the caller canvas when there is no present canvas', async () => {
    vi.mocked(WasmBridge.getPresentCanvas).mockReturnValue(null);
    const canvas = document.createElement('canvas');
    await renderer.startRecording(canvas);
    const opts = vi.mocked(WasmBridge.startRecording).mock.calls[0]![1] as {
      gpuEncode: (c: () => Promise<ImageData>, o: unknown) => Promise<unknown>;
    };
    await opts.gpuEncode(vi.fn(), {});
    expect(vi.mocked(startGpuEncodeSession).mock.calls[0]![0].canvas).toBe(canvas);
  });
});
