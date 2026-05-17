import { useState, useCallback, useRef } from 'react';

// ── Bridge module interface ────────────────────────────────────────────────────
//
// This must remain in sync with the exports of public/wasm/wasm_bridge.js.
// The bridge wraps the raw Emscripten ccall API in safe, typed functions and
// handles WASM heap allocation/deallocation internally.
interface WASMBridge {
  initWasmRenderer: (canvas: HTMLCanvasElement) => Promise<boolean>;
  shutdownWasmRenderer: () => void;

  // Shader management
  loadShader: (id: string, wgslCode: string) => boolean;
  loadShaderFromURL: (id: string, url: string) => Promise<boolean>;
  setActiveShader: (id: string) => void;
  setSlotShader: (slotIndex: number, id: string) => void;
  setSlotParams: (slotIndex: number, p1: number, p2: number, p3: number, p4: number) => void;
  setSlotMode: (slotIndex: number, mode: number | 'chained' | 'parallel') => void;

  // Per-frame updates
  updateUniforms: (uniforms?: {
    time?: number;
    mouseX?: number;
    mouseY?: number;
    mouseDown?: boolean;
    zoom_params?: [number, number, number, number];
  }) => void;
  updateMousePos: (x: number, y: number) => void;
  setMouseDown: (down: boolean) => void;
  updateAudioData: (bass: number, mid: number, treble: number) => void;
  updateDepthMap: (float32Data: Float32Array, width: number, height: number) => void;

  // Input source
  setInputSource: (source: number | 'none' | 'image' | 'video' | 'webcam' | 'generative') => void;

  // Pixel uploads
  uploadImageData: (rgbaPixels: Uint8Array | Uint8ClampedArray, width: number, height: number) => void;
  uploadVideoFrame: (rgbaPixels: Uint8Array | Uint8ClampedArray, width: number, height: number) => void;

  // Interaction
  addRipple: (x: number, y: number) => void;
  clearRipples: () => void;

  // State queries
  getFPS: () => number;
  isInitialized: () => boolean;

  // Canvas resize
  resizeCanvas: (newWidth: number, newHeight: number) => void;

  // Frame capture
  captureFrame: () => Promise<ImageData>;
  takeScreenshot: (filename?: string) => Promise<void>;

  // Recording
  startRecording: (
    canvasElement: HTMLCanvasElement,
    options?: { durationMs?: number; frameRate?: number; videoBitsPerSecond?: number }
  ) => Promise<Blob>;
  stopRecording: () => void;
  recordAndDownload: (
    canvasElement: HTMLCanvasElement,
    durationMs?: number,
    filename?: string
  ) => Promise<void>;
}

export const useWASM = () => {
  const [isLoaded, setIsLoaded] = useState(false);
  const [isWASM, setIsWASM] = useState(false);
  const bridgeRef = useRef<WASMBridge | null>(null);

  /**
   * Load the WASM bridge module (from public/wasm/wasm_bridge.js).
   * Safe to call multiple times — subsequent calls are no-ops.
   */
  const loadWASM = useCallback(async () => {
    if (bridgeRef.current) return true;

    try {
      // @ts-ignore — wasm_bridge.js lives in public/ and is not part of the
      // webpack bundle.  webpackIgnore prevents webpack from trying to resolve it.
      const bridge = await import(/* webpackIgnore: true */ '/wasm/wasm_bridge.js');
      // The bridge exports named functions and a default object with all of them.
      bridgeRef.current = (bridge.default ?? bridge) as WASMBridge;
      setIsLoaded(true);
      console.log('✅ WASM bridge loaded');
      return true;
    } catch (err) {
      console.error('❌ WASM bridge load failed:', err);
      return false;
    }
  }, []);

  /**
   * Initialize the C++ renderer against a canvas element.
   * Must be called after loadWASM() succeeds.
   */
  const initRenderer = useCallback(async (canvas: HTMLCanvasElement) => {
    if (!bridgeRef.current) {
      console.error('[useWASM] initRenderer called before loadWASM()');
      return false;
    }
    const ok = await bridgeRef.current.initWasmRenderer(canvas);
    if (ok) setIsWASM(true);
    return ok;
  }, []);

  const shutdown = useCallback(() => {
    if (bridgeRef.current) {
      bridgeRef.current.shutdownWasmRenderer();
      setIsWASM(false);
    }
  }, []);

  const updateAudio = useCallback((bass: number, mid: number, treble: number) => {
    bridgeRef.current?.updateAudioData(bass, mid, treble);
  }, []);

  const updateMouse = useCallback((x: number, y: number) => {
    bridgeRef.current?.updateMousePos(x, y);
  }, []);

  const updateDepthMap = useCallback((data: Float32Array, width: number, height: number) => {
    bridgeRef.current?.updateDepthMap(data, width, height);
  }, []);

  /** Access the full bridge API for advanced usage. */
  const getBridge = useCallback(() => bridgeRef.current, []);

  return {
    isLoaded,
    isWASM,
    loadWASM,
    initRenderer,
    shutdown,
    updateAudio,
    updateMouse,
    updateDepthMap,
    getBridge,
  };
};

export default useWASM;
