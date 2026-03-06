/**
 * RendererContext - Global state for switching between JS WebGPU and C++ WASM renderers
 * 
 * Usage:
 *   // Wrap your app:
 *   <RendererProvider>
 *     <App />
 *   </RendererProvider>
 *   
 *   // Use in components:
 *   const { currentRenderer, switchRenderer, isWasmAvailable } = useRenderer();
 */

import React, { createContext, useContext, useState, useCallback, useEffect, ReactNode } from 'react';
import { getRendererStatus, RendererStatus } from '../../services/shaderApi';

type RendererType = 'js-webgpu' | 'cpp-wasm';

interface RendererContextValue {
  // Current state
  currentRenderer: RendererType;
  isSwitching: boolean;
  isWasmAvailable: boolean;
  wasmLoading: boolean;
  wasmError: Error | null;
  
  // Actions
  switchRenderer: (renderer: RendererType) => Promise<void>;
  toggleRenderer: () => Promise<void>;
  
  // WASM module reference
  wasmModule: any | null;
  
  // Status
  rendererStatus: RendererStatus | null;
}

const RendererContext = createContext<RendererContextValue | null>(null);

interface RendererProviderProps {
  children: ReactNode;
  defaultRenderer?: RendererType;
}

export const RendererProvider: React.FC<RendererProviderProps> = ({
  children,
  defaultRenderer = 'js-webgpu',
}) => {
  const [currentRenderer, setCurrentRenderer] = useState<RendererType>(defaultRenderer);
  const [isSwitching, setIsSwitching] = useState(false);
  const [isWasmAvailable, setIsWasmAvailable] = useState(false);
  const [wasmLoading, setWasmLoading] = useState(false);
  const [wasmError, setWasmError] = useState<Error | null>(null);
  const [wasmModule, setWasmModule] = useState<any | null>(null);
  const [rendererStatus, setRendererStatus] = useState<RendererStatus | null>(null);

  // Fetch renderer status on mount
  useEffect(() => {
    getRendererStatus()
      .then(status => {
        setRendererStatus(status);
        setIsWasmAvailable(status.wasm_available);
      })
      .catch(err => {
        console.warn('[RendererContext] Failed to fetch status:', err);
      });
  }, []);

  // Load WASM module when needed
  const loadWasmModule = useCallback(async () => {
    if (wasmModule) return wasmModule;
    
    setWasmLoading(true);
    setWasmError(null);
    
    try {
      // Dynamic import of WASM module from public/wasm directory
      // This is where the build script copies the compiled module
      const module = await import('/wasm/wasm_renderer_test.js');
      
      // Initialize the module
      if (module.default) {
        await module.default();
      }
      
      setWasmModule(module);
      setIsWasmAvailable(true);
      setWasmLoading(false);
      
      console.log('[RendererContext] WASM module loaded successfully');
      return module;
    } catch (err) {
      const error = err instanceof Error ? err : new Error(String(err));
      console.error('[RendererContext] Failed to load WASM module:', error);
      setWasmError(error);
      setWasmLoading(false);
      setIsWasmAvailable(false);
      throw error;
    }
  }, [wasmModule]);

  const switchRenderer = useCallback(async (renderer: RendererType) => {
    if (renderer === currentRenderer) return;
    
    setIsSwitching(true);
    
    try {
      if (renderer === 'cpp-wasm') {
        // Ensure WASM is loaded
        await loadWasmModule();
      }
      
      setCurrentRenderer(renderer);
      console.log(`[RendererContext] Switched to ${renderer}`);
    } finally {
      setIsSwitching(false);
    }
  }, [currentRenderer, loadWasmModule]);

  const toggleRenderer = useCallback(async () => {
    const next = currentRenderer === 'js-webgpu' ? 'cpp-wasm' : 'js-webgpu';
    await switchRenderer(next);
  }, [currentRenderer, switchRenderer]);

  const value: RendererContextValue = {
    currentRenderer,
    isSwitching,
    isWasmAvailable,
    wasmLoading,
    wasmError,
    switchRenderer,
    toggleRenderer,
    wasmModule,
    rendererStatus,
  };

  return (
    <RendererContext.Provider value={value}>
      {children}
    </RendererContext.Provider>
  );
};

export const useRenderer = (): RendererContextValue => {
  const context = useContext(RendererContext);
  if (!context) {
    throw new Error('useRenderer must be used within a RendererProvider');
  }
  return context;
};

export default RendererContext;
