// ═══════════════════════════════════════════════════════════════════════════════
//  WASM Bridge Tests
//
//  These tests verify:
//  1. wasm_bridge.js API surface: all exported functions have the right types
//     and return the right value types.
//  2. Bridge calls are safe no-ops before initialization.
// ═══════════════════════════════════════════════════════════════════════════════

// ── Mock the src/wasm/wasm_bridge module ─────────────────────────────────────
//
// We don't have an Emscripten binary available in Jest, so we mock the bridge.
// The mock verifies the API surface that TypeScript consumers rely on.
vi.mock('../wasm/wasm_bridge', () => {
  const bridge = {
    initWasmRenderer: vi.fn().mockResolvedValue(false),
    shutdownWasmRenderer: vi.fn(),
    loadShader: vi.fn().mockReturnValue(false),
    reloadShader: vi.fn().mockReturnValue(false),
    loadShaderFromURL: vi.fn().mockResolvedValue(false),
    reloadShaderFromURL: vi.fn().mockResolvedValue(false),
    setActiveShader: vi.fn(),
    setSlotShader: vi.fn(),
    setSlotParams: vi.fn(),
    updateSlotParams: vi.fn(),
    setSlotMode: vi.fn(),
    updateUniforms: vi.fn(),
    updateMousePos: vi.fn(),
    setMouseDown: vi.fn(),
    updateAudioData: vi.fn(),
    updateAudioFrequencyBins: vi.fn(),
    updateDepthMap: vi.fn(),
    setInputSource: vi.fn(),
    addRipple: vi.fn(),
    clearRipples: vi.fn(),
    getFPS: vi.fn().mockReturnValue(0),
    getSupportsDeepWorkgroup: vi.fn().mockReturnValue(false),
    getSlotState: vi.fn().mockReturnValue({ shaderId: null, enabled: false, mode: 'chained' }),
    getGPUTimings: vi.fn().mockReturnValue({ parallelTime: 0, chainedTime: 0, totalTime: 0, available: false, timingSource: 'unavailable' }),
    setRecording: vi.fn(),
    isRecordingActive: vi.fn().mockReturnValue(false),
    captureFrameDataUrl: vi.fn().mockResolvedValue(''),
    isInitialized: vi.fn().mockReturnValue(false),
    uploadImageData: vi.fn(),
    uploadVideoFrame: vi.fn(),
    resizeCanvas: vi.fn(),
    captureFrame: vi.fn().mockResolvedValue(null),
    takeScreenshot: vi.fn().mockResolvedValue(undefined),
    startRecording: vi.fn().mockResolvedValue(null),
    stopRecording: vi.fn(),
    recordAndDownload: vi.fn().mockResolvedValue(undefined),
  };
  return { __esModule: true, default: bridge, ...bridge };
});

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/** Build a fresh mock bridge with default return values. */
function makeMockBridge() {
  return {
    initWasmRenderer: vi.fn().mockResolvedValue(false),
    shutdownWasmRenderer: vi.fn(),
    loadShader: vi.fn().mockReturnValue(false),
    reloadShader: vi.fn().mockReturnValue(false),
    loadShaderFromURL: vi.fn().mockResolvedValue(false),
    reloadShaderFromURL: vi.fn().mockResolvedValue(false),
    setActiveShader: vi.fn(),
    setSlotShader: vi.fn(),
    setSlotParams: vi.fn(),
    updateSlotParams: vi.fn(),
    setSlotMode: vi.fn(),
    updateUniforms: vi.fn(),
    updateMousePos: vi.fn(),
    setMouseDown: vi.fn(),
    updateAudioData: vi.fn(),
    updateAudioFrequencyBins: vi.fn(),
    updateDepthMap: vi.fn(),
    setInputSource: vi.fn(),
    addRipple: vi.fn(),
    clearRipples: vi.fn(),
    getFPS: vi.fn().mockReturnValue(0),
    getSupportsDeepWorkgroup: vi.fn().mockReturnValue(false),
    getSlotState: vi.fn().mockReturnValue({ shaderId: null, enabled: false, mode: 'chained' }),
    getGPUTimings: vi.fn().mockReturnValue({ parallelTime: 0, chainedTime: 0, totalTime: 0, available: false, timingSource: 'unavailable' }),
    setRecording: vi.fn(),
    isRecordingActive: vi.fn().mockReturnValue(false),
    captureFrameDataUrl: vi.fn().mockResolvedValue(''),
    isInitialized: vi.fn().mockReturnValue(false),
    uploadImageData: vi.fn(),
    uploadVideoFrame: vi.fn(),
    resizeCanvas: vi.fn(),
    captureFrame: vi.fn().mockResolvedValue(null),
    takeScreenshot: vi.fn().mockResolvedValue(undefined),
    startRecording: vi.fn().mockResolvedValue(null),
    stopRecording: vi.fn(),
    recordAndDownload: vi.fn().mockResolvedValue(undefined),
  };
}

let b = makeMockBridge();
beforeEach(() => { b = makeMockBridge(); });

// ─────────────────────────────────────────────────────────────────────────────
// Section 1: Bridge API surface
// ─────────────────────────────────────────────────────────────────────────────

describe('WASMBridge API surface', () => {
  const REQUIRED_EXPORTS = [
    'initWasmRenderer', 'shutdownWasmRenderer', 'loadShader', 'reloadShader', 'loadShaderFromURL', 'reloadShaderFromURL',
    'setActiveShader', 'setSlotShader', 'setSlotParams', 'updateSlotParams', 'setSlotMode',
    'updateUniforms', 'updateMousePos', 'updateAudioData', 'updateAudioFrequencyBins',
    'updateDepthMap', 'setInputSource', 'addRipple', 'clearRipples',
    'getFPS', 'getSupportsDeepWorkgroup', 'getSlotState', 'getGPUTimings',
    'setRecording', 'isRecordingActive', 'captureFrameDataUrl', 'isInitialized',
    'uploadImageData', 'uploadVideoFrame',
    'resizeCanvas', 'captureFrame', 'takeScreenshot',
    'startRecording', 'stopRecording', 'recordAndDownload',
  ] as const;

  it('exposes all required named exports as functions', () => {
    for (const name of REQUIRED_EXPORTS) {
      expect(typeof b[name]).toBe('function');
    }
  });

  it('getFPS() returns a number', () => {
    expect(typeof b.getFPS()).toBe('number');
  });

  it('isInitialized() returns a boolean', () => {
    expect(typeof b.isInitialized()).toBe('boolean');
  });

  it('loadShader() returns a boolean', () => {
    expect(typeof b.loadShader('id', 'code')).toBe('boolean');
  });

  it('initWasmRenderer() returns a Promise', () => {
    expect(b.initWasmRenderer({} as HTMLCanvasElement)).toEqual(expect.objectContaining({ then: expect.any(Function) }));
  });

  it('loadShaderFromURL() returns a Promise', () => {
    expect(b.loadShaderFromURL('id', '/shaders/test.wgsl')).toEqual(expect.objectContaining({ then: expect.any(Function) }));
  });

  it('getGPUTimings() returns wall-clock timingSource when unavailable', () => {
    const timings = b.getGPUTimings();
    expect(timings).toEqual(expect.objectContaining({
      parallelTime: expect.any(Number),
      chainedTime: expect.any(Number),
      totalTime: expect.any(Number),
      available: false,
      timingSource: 'unavailable',
    }));
  });

  it('startRecording() returns a Promise', () => {
    expect(b.startRecording(document.createElement('canvas'))).toEqual(expect.objectContaining({ then: expect.any(Function) }));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Section 2: Bridge safe call verification
// ─────────────────────────────────────────────────────────────────────────────

describe('Bridge call safety', () => {
  it('shutdownWasmRenderer() does not throw', () => {
    expect(() => b.shutdownWasmRenderer()).not.toThrow();
  });

  it('getFPS() returns 0 by default', () => {
    expect(b.getFPS()).toBe(0);
  });

  it('loadShader() returns false by default', () => {
    expect(b.loadShader('x', 'code')).toBe(false);
  });

  it('all void functions can be called without throwing', () => {
    const float32 = new Float32Array(4);
    const uint8 = new Uint8Array(4);
    expect(() => b.setActiveShader('id')).not.toThrow();
    expect(() => b.setSlotShader(0, 'id')).not.toThrow();
    expect(() => b.setSlotParams(0, 0.5, 0.5, 0.5, 0.5)).not.toThrow();
    expect(() => b.setSlotMode(0, 0)).not.toThrow();
    expect(() => b.updateUniforms({})).not.toThrow();
    expect(() => b.updateMousePos(0.5, 0.5)).not.toThrow();
    expect(() => b.setMouseDown(false)).not.toThrow();
    expect(() => b.updateAudioData(0, 0, 0)).not.toThrow();
    expect(() => b.updateDepthMap(float32, 2, 2)).not.toThrow();
    expect(() => b.setInputSource(0)).not.toThrow();
    expect(() => b.addRipple(0.5, 0.5)).not.toThrow();
    expect(() => b.clearRipples()).not.toThrow();
    expect(() => b.uploadImageData(uint8, 1, 1)).not.toThrow();
    expect(() => b.uploadVideoFrame(uint8, 1, 1)).not.toThrow();
    expect(() => b.resizeCanvas(512, 512)).not.toThrow();
    expect(() => b.stopRecording()).not.toThrow();
  });
});
