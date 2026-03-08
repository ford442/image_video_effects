import React, { useState } from 'react';

interface RendererToggleProps {
  onToggle?: (useWasm: boolean) => void;
  className?: string;
  /** Show text labels instead of just emojis */
  showLabels?: boolean;
  /** Position as fixed (default) or inline */
  fixed?: boolean;
}

export const RendererToggle: React.FC<RendererToggleProps> = ({
  onToggle,
  className = '',
  showLabels = false,
  fixed = true
}) => {
  const [useWasm, setUseWasm] = useState(false);
  const [isLoading, setIsLoading] = useState(false);

  const toggle = async () => {
    setIsLoading(true);
    const newValue = !useWasm;
    
    try {
      if (newValue) {
        // Load WASM renderer
        const wasmUrl = '/wasm/wasm_renderer_test.js';
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const wasm: any = await import(/* webpackIgnore: true */ wasmUrl);
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

  const buttonText = isLoading
    ? '⏳ Loading...'
    : showLabels
      ? (useWasm ? 'Switch to JS WebGPU' : 'Switch to C++ WASM')
      : (useWasm ? '🔄 JS WebGPU' : '⚡ C++ WASM (Native Speed)');

  const positionClasses = fixed
    ? 'fixed bottom-8 right-8'
    : '';

  return (
    <button 
      onClick={toggle}
      disabled={isLoading}
      className={`${positionClasses} px-8 py-4 bg-gradient-to-r ${
        useWasm ? 'from-green-600 to-emerald-600' : 'from-purple-600 to-pink-600'
      } disabled:opacity-50 rounded-2xl font-bold shadow-xl hover:scale-105 transition-transform ${className}`}
    >
      {buttonText}
    </button>
  );
};

export default RendererToggle;
