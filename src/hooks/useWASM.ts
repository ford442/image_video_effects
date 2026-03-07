import { useState, useCallback, useRef } from 'react';

interface WASMModule {
  _initWasmRenderer: (width: number, height: number, agentCount: number) => void;
  _toggleRenderer: (useWasm: number) => void;
  _updateAudioData: (bass: number, mid: number, treble: number) => void;
  _updateMousePos: (x: number, y: number) => void;
  default?: () => Promise<void>;
}

export const useWASM = () => {
  const [isLoaded, setIsLoaded] = useState(false);
  const [isWASM, setIsWASM] = useState(false);
  const moduleRef = useRef<WASMModule | null>(null);

  const loadWASM = useCallback(async () => {
    if (moduleRef.current) return true;
    
    try {
      // Load WASM module from public folder using dynamic script injection
      const wasmUrl = '/wasm/pixelocity_wasm.js';
      const script = document.createElement('script');
      script.src = wasmUrl;
      script.async = true;
      
      await new Promise<void>((resolve, reject) => {
        script.onload = () => resolve();
        script.onerror = () => reject(new Error('Failed to load WASM script'));
        document.head.appendChild(script);
      });
      
      // The WASM module is available on window.Module (Emscripten default)
      const wasm = (window as any).Module;
      if (!wasm) {
        throw new Error('WASM module not found on window.Module');
      }
      
      moduleRef.current = wasm as unknown as WASMModule;
      setIsLoaded(true);
      console.log('✅ WASM module loaded');
      return true;
    } catch (err) {
      console.error('❌ WASM load failed:', err);
      return false;
    }
  }, []);

  const initRenderer = useCallback((width: number, height: number, agentCount: number) => {
    if (moduleRef.current) {
      moduleRef.current._initWasmRenderer(width, height, agentCount);
    }
  }, []);

  const toggle = useCallback((useWasm: boolean) => {
    if (moduleRef.current) {
      moduleRef.current._toggleRenderer(useWasm ? 1 : 0);
      setIsWASM(useWasm);
    }
  }, []);

  const updateAudio = useCallback((bass: number, mid: number, treble: number) => {
    if (moduleRef.current) {
      moduleRef.current._updateAudioData(bass, mid, treble);
    }
  }, []);

  const updateMouse = useCallback((x: number, y: number) => {
    if (moduleRef.current) {
      moduleRef.current._updateMousePos(x, y);
    }
  }, []);

  return {
    isLoaded,
    isWASM,
    loadWASM,
    initRenderer,
    toggle,
    updateAudio,
    updateMouse,
  };
};

export default useWASM;
