import React, { useState, useCallback } from 'react';

interface RendererToggleProps {
  isWASM: boolean;
  onToggle: (useWasm: boolean) => Promise<void>;
  isLoading: boolean;
  jsFps?: number;
  wasmFps?: number;
}

export const RendererToggle: React.FC<RendererToggleProps> = ({
  isWASM,
  onToggle,
  isLoading,
  jsFps = 0,
  wasmFps = 0,
}) => {
  const [isSwitching, setIsSwitching] = useState(false);

  const handleToggle = useCallback(async () => {
    if (isLoading || isSwitching) return;
    
    setIsSwitching(true);
    try {
      await onToggle(!isWASM);
    } finally {
      setIsSwitching(false);
    }
  }, [isWASM, onToggle, isLoading, isSwitching]);

  const disabled = isLoading || isSwitching;

  return (
    <div style={styles.container}>
      {/* JS Side */}
      <div style={styles.side}>
        <span style={styles.label}>JS WebGPU</span>
        <span style={styles.fps}>{jsFps > 0 ? `${jsFps} FPS` : '--'}</span>
      </div>

      {/* Toggle Switch */}
      <button
        onClick={handleToggle}
        disabled={disabled}
        style={{
          ...styles.toggle,
          background: isWASM 
            ? 'linear-gradient(135deg, #00c853, #64dd17)' 
            : 'linear-gradient(135deg, #2979ff, #448aff)',
          opacity: disabled ? 0.6 : 1,
          cursor: disabled ? 'not-allowed' : 'pointer',
        }}
      >
        <div style={{
          ...styles.knob,
          transform: isWASM ? 'translateX(28px)' : 'translateX(0)',
        }} />
      </button>

      {/* WASM Side */}
      <div style={styles.side}>
        <span style={styles.label}>C++ WASM</span>
        <span style={styles.fps}>{wasmFps > 0 ? `${wasmFps} FPS` : '--'}</span>
      </div>

      {/* Status Badge */}
      <div style={{
        ...styles.badge,
        background: isWASM ? 'rgba(0, 200, 83, 0.2)' : 'rgba(41, 121, 255, 0.2)',
        color: isWASM ? '#00c853' : '#448aff',
      }}>
        {disabled ? '⏳ Switching...' : isWASM ? '⚡ WASM Active' : '🔄 JS Active'}
      </div>
    </div>
  );
};

const styles: { [key: string]: React.CSSProperties } = {
  container: {
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
    padding: '8px 16px',
    background: 'rgba(0, 0, 0, 0.3)',
    borderRadius: '12px',
    border: '1px solid rgba(255, 255, 255, 0.1)',
  },
  side: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    minWidth: '80px',
  },
  label: {
    fontSize: '11px',
    fontWeight: 600,
    color: '#8b8ba7',
    textTransform: 'uppercase',
  },
  fps: {
    fontSize: '13px',
    fontWeight: 700,
    color: '#fff',
    fontFamily: 'monospace',
  },
  toggle: {
    width: '56px',
    height: '28px',
    borderRadius: '14px',
    border: 'none',
    padding: '2px',
    position: 'relative',
    transition: 'all 0.2s ease',
    boxShadow: '0 2px 8px rgba(0,0,0,0.3)',
  },
  knob: {
    width: '24px',
    height: '24px',
    borderRadius: '50%',
    background: '#fff',
    boxShadow: '0 1px 3px rgba(0,0,0,0.3)',
    transition: 'transform 0.2s ease',
  },
  badge: {
    padding: '4px 10px',
    borderRadius: '12px',
    fontSize: '11px',
    fontWeight: 600,
    marginLeft: '8px',
  },
};

export default RendererToggle;
