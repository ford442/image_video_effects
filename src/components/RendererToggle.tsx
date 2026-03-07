import React, { useState, useEffect } from 'react';

export default function RendererToggle() {
  const [useWasm, setUseWasm] = useState(false);
  const [wasmModule, setWasmModule] = useState<any>(null);
  const [currentWgsl, setCurrentWgsl] = useState(''); // ← We'll wire this in next step

  // Load WASM module when toggle is turned ON
  useEffect(() => {
    if (useWasm && !wasmModule) {
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
      };
      script.onerror = (err) => {
        console.error('Failed to load WASM module:', err);
      };
      document.body.appendChild(script);
      
      return () => {
        document.body.removeChild(script);
      };
    }
  }, [useWasm]);

  const toggle = async () => {
    const newState = !useWasm;
    setUseWasm(newState);

    if (newState && wasmModule && currentWgsl) {
      // Call the exported C function via ccall
      if (wasmModule.ccall) {
        wasmModule.ccall('initWasmRenderer', null, ['string'], [currentWgsl]);
        console.log('⚡ Switched to C++ WASM Renderer');
      }
    } else if (!newState) {
      console.log('🔄 Switched back to JS WebGPU');
    }
  };

  return (
    <div className="fixed bottom-8 right-8 z-50 flex items-center gap-3 bg-[#0f172a] border border-[#334155] rounded-2xl px-5 py-3 shadow-2xl">
      <span className="text-xs text-white/70 font-mono">RENDERER</span>
      
      <label className="relative inline-flex items-center cursor-pointer">
        <input
          type="checkbox"
          checked={useWasm}
          onChange={toggle}
          className="sr-only peer"
        />
        <div className="w-11 h-6 bg-[#1e2937] peer-focus:outline-none peer-focus:ring-2 peer-focus:ring-[#e94560] rounded-full peer peer-checked:bg-[#e94560]"></div>
        <div className="absolute left-0.5 top-0.5 bg-white w-5 h-5 rounded-full transition-all peer-checked:translate-x-5"></div>
      </label>

      <span className="text-sm font-medium min-w-[110px]">
        {useWasm ? (
          <span className="text-[#e94560]">C++ WASM ⚡</span>
        ) : (
          <span className="text-white/80">JS WebGPU</span>
        )}
      </span>
    </div>
  );
}
