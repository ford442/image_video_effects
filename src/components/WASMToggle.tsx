import React, { useState, useCallback } from 'react';

interface WASMToggleProps {
  onToggle: (useWasm: boolean) => void;
  defaultMode?: 'wasm' | 'js';
}

export const WASMToggle: React.FC<WASMToggleProps> = ({
  onToggle,
  defaultMode = 'js',
}) => {
  const [mode, setMode] = useState<'wasm' | 'js'>(defaultMode);
  const [isLoading, setIsLoading] = useState(false);

  const toggle = useCallback(async () => {
    setIsLoading(true);
    const newMode = mode === 'js' ? 'wasm' : 'js';
    
    try {
      await onToggle(newMode === 'wasm');
      setMode(newMode);
    } catch (err) {
      console.error('Toggle failed:', err);
    } finally {
      setIsLoading(false);
    }
  }, [mode, onToggle]);

  return (
    <button
      onClick={toggle}
      disabled={isLoading}
      style={{
        position: 'fixed',
        bottom: '20px',
        right: '20px',
        padding: '12px 24px',
        background: mode === 'wasm' 
          ? 'linear-gradient(135deg, #00c853, #64dd17)' 
          : 'linear-gradient(135deg, #2979ff, #448aff)',
        color: 'white',
        border: 'none',
        borderRadius: '8px',
        cursor: isLoading ? 'wait' : 'pointer',
        fontWeight: 'bold',
        fontSize: '14px',
        boxShadow: '0 4px 12px rgba(0,0,0,0.3)',
        opacity: isLoading ? 0.7 : 1,
        transition: 'all 0.2s',
      }}
    >
      {isLoading ? '⏳ Switching...' : mode === 'wasm' ? '⚡ C++ WASM' : '🔄 JS WebGPU'}
    </button>
  );
};

export default WASMToggle;
