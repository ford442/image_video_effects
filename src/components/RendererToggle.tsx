import React, { useState, useEffect } from 'react';

interface RendererToggleProps {
  /** Controlled WASM state (optional - if not provided, component manages its own state) */
  isWASM?: boolean;
  /** Callback when toggle changes (optional) */
  onToggle?: (useWasm: boolean) => void | Promise<void>;
  /** Loading state (optional) */
  isLoading?: boolean;
  /** Additional CSS class */
  className?: string;
}

function RendererToggleComponent({ 
  isWASM: controlledWasm,
  onToggle,
  isLoading: controlledLoading,
  className = ''
}: RendererToggleProps = {}) {
  const [internalWasm, setInternalWasm] = useState(false);
  const [internalLoading, setInternalLoading] = useState(false);
  const [wasmModule, setWasmModule] = useState<any>(null);

  // Use controlled or internal state
  const useWasm = controlledWasm !== undefined ? controlledWasm : internalWasm;
  const isLoading = controlledLoading !== undefined ? controlledLoading : internalLoading;

  // Load WASM module when toggle is turned ON (only for internal mode)
  useEffect(() => {
    if (controlledWasm !== undefined) return; // Skip if controlled
    
    if (useWasm && !wasmModule) {
      setInternalLoading(true);
      
      // Dynamic import from public folder
      const script = document.createElement('script');
      script.src = '/wasm/pixelocity_wasm.js';
      script.async = true;
      script.onload = () => {
        // The WASM module should be available on window.Module or similar
        // For emscripten-generated JS, it creates a global Module
        if ((window as any).Module) {
          setWasmModule((window as any).Module);
          console.log('🚀 C++ WASM Renderer loaded');
        }
        setInternalLoading(false);
      };
      script.onerror = (err) => {
        console.error('Failed to load WASM module:', err);
        setInternalLoading(false);
      };
      document.body.appendChild(script);
      
      return () => {
        document.body.removeChild(script);
      };
    }
  }, [useWasm, wasmModule, controlledWasm]);

  const toggle = async () => {
    const newState = !useWasm;
    
    // If controlled, call onToggle
    if (onToggle) {
      await onToggle(newState);
    } else {
      // Internal state mode
      setInternalWasm(newState);

      if (newState && wasmModule) {
        console.log('⚡ Switched to C++ WASM — renderer ready');
      } else if (!newState) {
        console.log('🔄 Switched back to JS WebGPU');
      }
    }
  };

  return (
    <div className={`fixed bottom-8 right-8 z-50 flex items-center gap-3 bg-[#0f172a] border border-[#334155] rounded-2xl px-5 py-3 shadow-2xl ${className}`}>
      <span className="text-xs text-white/70 font-mono">RENDERER</span>
      
      <label className="relative inline-flex items-center cursor-pointer">
        <input
          type="checkbox"
          checked={useWasm}
          onChange={toggle}
          disabled={isLoading}
          className="sr-only peer"
        />
        <div className={`w-11 h-6 bg-[#1e2937] peer-focus:outline-none peer-focus:ring-2 peer-focus:ring-[#e94560] rounded-full peer peer-checked:bg-[#e94560] ${isLoading ? 'opacity-50' : ''}`}></div>
        <div className="absolute left-0.5 top-0.5 bg-white w-5 h-5 rounded-full transition-all peer-checked:translate-x-5"></div>
      </label>

      <span className="text-sm font-medium min-w-[110px]">
        {isLoading ? (
          <span className="text-white/50">Loading...</span>
        ) : useWasm ? (
          <span className="text-[#e94560]">C++ WASM ⚡</span>
        ) : (
          <span className="text-white/80">JS WebGPU</span>
        )}
      </span>
    </div>
  );
}

// Default export
export default RendererToggleComponent;

// Named export for compatibility with existing imports
export { RendererToggleComponent as RendererToggle };
