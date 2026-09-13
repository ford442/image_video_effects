import { useState, useCallback, useRef } from 'react';
import type { WasmRenderer } from '../wasm/wasm_bridge';

// ── Bridge types ───────────────────────────────────────────────────────────────
//
// Types come from src/wasm/wasm_bridge.ts (typeof the TypeScript barrel).
// Edit src/wasm/bridge/*.ts. NEVER edit public/wasm/bridge/*.js or
// wasm_renderer/bridge/*.js — those are emitted copies.
// Runtime still loads the emitted /wasm/wasm_bridge.js (webpackIgnore).

export const useWASM = () => {
  const [isLoaded, setIsLoaded] = useState(false);
  const [isWASM, setIsWASM] = useState(false);
  const bridgeRef = useRef<WasmRenderer | null>(null);

  /**
   * Load the emitted ESM bridge from /wasm/wasm_bridge.js (copy of src/wasm).
   * Edit src/wasm/bridge/*.ts; never edit public/wasm/bridge/*.js.
   * Safe to call multiple times — subsequent calls are no-ops.
   */
  const loadWASM = useCallback(async () => {
    if (bridgeRef.current) return true;

    try {
      // @ts-ignore — emitted wasm_bridge.js lives in public/ and is not part of the
      // webpack bundle.  webpackIgnore prevents webpack from trying to resolve it.
      const bridge = await import(/* webpackIgnore: true */ '/wasm/wasm_bridge.js');
      // The bridge exports named functions and a default object with all of them.
      bridgeRef.current = (bridge.default ?? bridge) as WasmRenderer;
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
   * Automatically calls loadWASM() first if the bridge has not been loaded yet.
   */
  const initRenderer = useCallback(async (canvas: HTMLCanvasElement) => {
    if (!bridgeRef.current) {
      const loaded = await loadWASM();
      if (!loaded) return false;
    }
    const ok = await bridgeRef.current!.initWasmRenderer(canvas);
    if (ok) setIsWASM(true);
    return ok;
  }, [loadWASM]);

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
