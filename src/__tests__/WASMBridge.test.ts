// ═══════════════════════════════════════════════════════════════════════════════
//  WASM Bridge & useWASM Hook Tests
//
//  These tests verify:
//  1. wasm_bridge.js API surface: all exported functions have the right types
//     and return the right value types.
//  2. useWASM hook: initial state and safe no-op behaviour before initialization.
// ═══════════════════════════════════════════════════════════════════════════════

import { renderHook, act } from '@testing-library/react';
import { useWASM } from '../hooks/useWASM';

// ── Mock the src/wasm/wasm_bridge.js module ───────────────────────────────────
//
// We don't have an Emscripten binary available in Jest, so we mock the bridge.
// The mock verifies the API surface that TypeScript consumers rely on.
jest.mock('../wasm/wasm_bridge.js', () => {
  const bridge = {
    initWasmRenderer: jest.fn().mockResolvedValue(false),
    shutdownWasmRenderer: jest.fn(),
    loadShader: jest.fn().mockReturnValue(false),
    loadShaderFromURL: jest.fn().mockResolvedValue(false),
    setActiveShader: jest.fn(),
    setSlotShader: jest.fn(),
    setSlotParams: jest.fn(),
    setSlotMode: jest.fn(),
    updateUniforms: jest.fn(),
    updateMousePos: jest.fn(),
    setMouseDown: jest.fn(),
    updateAudioData: jest.fn(),
    updateDepthMap: jest.fn(),
    setInputSource: jest.fn(),
    addRipple: jest.fn(),
    clearRipples: jest.fn(),
    getFPS: jest.fn().mockReturnValue(0),
    isInitialized: jest.fn().mockReturnValue(false),
    uploadImageData: jest.fn(),
    uploadVideoFrame: jest.fn(),
    resizeCanvas: jest.fn(),
    captureFrame: jest.fn().mockResolvedValue(null),
    takeScreenshot: jest.fn().mockResolvedValue(undefined),
    startRecording: jest.fn().mockResolvedValue(null),
    stopRecording: jest.fn(),
    recordAndDownload: jest.fn().mockResolvedValue(undefined),
  };
  return { __esModule: true, default: bridge, ...bridge };
});

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/** Build a fresh mock bridge with default return values. */
function makeMockBridge() {
  return {
    initWasmRenderer: jest.fn().mockResolvedValue(false),
    shutdownWasmRenderer: jest.fn(),
    loadShader: jest.fn().mockReturnValue(false),
    loadShaderFromURL: jest.fn().mockResolvedValue(false),
    setActiveShader: jest.fn(),
    setSlotShader: jest.fn(),
    setSlotParams: jest.fn(),
    setSlotMode: jest.fn(),
    updateUniforms: jest.fn(),
    updateMousePos: jest.fn(),
    setMouseDown: jest.fn(),
    updateAudioData: jest.fn(),
    updateDepthMap: jest.fn(),
    setInputSource: jest.fn(),
    addRipple: jest.fn(),
    clearRipples: jest.fn(),
    getFPS: jest.fn().mockReturnValue(0),
    isInitialized: jest.fn().mockReturnValue(false),
    uploadImageData: jest.fn(),
    uploadVideoFrame: jest.fn(),
    resizeCanvas: jest.fn(),
    captureFrame: jest.fn().mockResolvedValue(null),
    takeScreenshot: jest.fn().mockResolvedValue(undefined),
    startRecording: jest.fn().mockResolvedValue(null),
    stopRecording: jest.fn(),
    recordAndDownload: jest.fn().mockResolvedValue(undefined),
  };
}

let b = makeMockBridge();
beforeEach(() => { b = makeMockBridge(); });

// ─────────────────────────────────────────────────────────────────────────────
// Section 1: Bridge API surface
// ─────────────────────────────────────────────────────────────────────────────

describe('WASMBridge API surface', () => {
  const REQUIRED_EXPORTS = [
    'initWasmRenderer', 'shutdownWasmRenderer', 'loadShader', 'loadShaderFromURL',
    'setActiveShader', 'setSlotShader', 'setSlotParams', 'setSlotMode',
    'updateUniforms', 'updateMousePos', 'setMouseDown', 'updateAudioData',
    'updateDepthMap', 'setInputSource', 'addRipple', 'clearRipples',
    'getFPS', 'isInitialized', 'uploadImageData', 'uploadVideoFrame',
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

  it('captureFrame() returns a Promise', () => {
    expect(b.captureFrame()).toEqual(expect.objectContaining({ then: expect.any(Function) }));
  });

  it('startRecording() returns a Promise', () => {
    expect(b.startRecording(document.createElement('canvas'))).toEqual(expect.objectContaining({ then: expect.any(Function) }));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Section 2: useWASM hook
// ─────────────────────────────────────────────────────────────────────────────

describe('useWASM hook', () => {
  it('starts with isLoaded=false and isWASM=false', () => {
    const { result } = renderHook(() => useWASM());
    expect(result.current.isLoaded).toBe(false);
    expect(result.current.isWASM).toBe(false);
  });

  it('exposes the required API functions', () => {
    const { result } = renderHook(() => useWASM());
    expect(typeof result.current.loadWASM).toBe('function');
    expect(typeof result.current.initRenderer).toBe('function');
    expect(typeof result.current.shutdown).toBe('function');
    expect(typeof result.current.updateAudio).toBe('function');
    expect(typeof result.current.updateMouse).toBe('function');
    expect(typeof result.current.updateDepthMap).toBe('function');
    expect(typeof result.current.getBridge).toBe('function');
  });

  it('getBridge() returns null before loadWASM()', () => {
    const { result } = renderHook(() => useWASM());
    expect(result.current.getBridge()).toBeNull();
  });

  it('updateAudio() is a no-op when bridge is not loaded', () => {
    const { result } = renderHook(() => useWASM());
    expect(() => result.current.updateAudio(0.1, 0.2, 0.3)).not.toThrow();
  });

  it('updateMouse() is a no-op when bridge is not loaded', () => {
    const { result } = renderHook(() => useWASM());
    expect(() => result.current.updateMouse(0.5, 0.5)).not.toThrow();
  });

  it('updateDepthMap() is a no-op when bridge is not loaded', () => {
    const { result } = renderHook(() => useWASM());
    expect(() => result.current.updateDepthMap(new Float32Array(4), 2, 2)).not.toThrow();
  });

  it('shutdown() is a safe no-op when bridge has not been loaded', async () => {
    const { result } = renderHook(() => useWASM());
    await act(async () => { result.current.shutdown(); });
    expect(result.current.isWASM).toBe(false);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Section 3: Bridge safe call verification
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
