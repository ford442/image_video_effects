import React, { useState } from 'react';

interface RendererToggleProps {
  onToggle?: (useWasm: boolean) => void;
  className?: string;
}

export const RendererToggle: React.FC<RendererToggleProps> = ({ onToggle, className = '' }) => {
  const [useWasm, setUseWasm] = useState(false);
  const [isLoading, setIsLoading] = useState(false);

  const toggle = async () => {
    setIsLoading(true);
    const newValue = !useWasm;
    
    try {
      if (newValue) {
        // Load WASM renderer
        const wasm = await import('/wasm/wasm_renderer_test.js');
        await wasm.default();
        console.log('✅ C++ WASM Renderer activated');
      }
      
      setUseWasm(newValue);
      onToggle?.(newValue);
    } catch (err) {
      console.error('Failed to toggle renderer:', err);
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <button 
      onClick={toggle}
      disabled={isLoading}
      className={`fixed bottom-8 right-8 px-8 py-4 bg-gradient-to-r ${
        useWasm ? 'from-green-600 to-emerald-600' : 'from-purple-600 to-pink-600'
      } disabled:opacity-50 rounded-2xl font-bold shadow-xl hover:scale-105 transition-transform ${className}`}
    >
      {isLoading ? '⏳ Loading...' : useWasm ? '🔄 JS WebGPU' : '⚡ C++ WASM (Native Speed)'}
    </button>
  );
};

export default RendererToggle;
