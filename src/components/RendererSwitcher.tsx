import React, { useState } from 'react';

type RendererType = 'webgpu' | 'wasm' | 'js';

interface RendererSwitcherProps {
  activeRendererType: RendererType;
  onSwitchRenderer: (type: RendererType) => void | Promise<void>;
}

export const RendererSwitcher: React.FC<RendererSwitcherProps> = ({
  activeRendererType,
  onSwitchRenderer,
}) => {
  const [isSwitching, setIsSwitching] = useState(false);

  const handleSwitch = async (type: RendererType) => {
    if (isSwitching || activeRendererType === type) return;
    setIsSwitching(true);
    try {
      const result = onSwitchRenderer(type);
      if (result instanceof Promise) {
        await result;
      }
    } finally {
      setIsSwitching(false);
    }
  };

  const renderers: { type: RendererType; icon: string; label: string; desc: string; experimental?: boolean }[] = [
    { type: 'webgpu', icon: '🔷', label: 'WebGPU', desc: 'Recommended (default)' },
    { type: 'wasm', icon: '⚡', label: 'WASM', desc: 'C++ compute — experimental', experimental: true },
    { type: 'js', icon: '🎨', label: 'Canvas2D', desc: 'Fallback' },
  ];

  return (
    <div style={styles.container}>
      <div style={styles.header}>
        <span style={styles.title}>🎬 Renderer</span>
      </div>

      <div style={styles.grid}>
        {renderers.map(renderer => (
          <button
            key={renderer.type}
            onClick={() => handleSwitch(renderer.type)}
            disabled={isSwitching}
            style={{
              ...styles.button,
              ...(activeRendererType === renderer.type
                ? styles.buttonActive
                : styles.buttonInactive),
              ...(isSwitching ? styles.buttonDisabled : {}),
            }}
          >
            <div style={styles.buttonIcon}>{renderer.icon}</div>
            <div style={styles.buttonLabel}>
              {renderer.label}
              {renderer.experimental && (
                <span style={styles.experimentalTag}>EXP</span>
              )}
            </div>
            <div style={styles.buttonDesc}>{renderer.desc}</div>
            {activeRendererType === renderer.type && (
              <div style={styles.activeBadge}>✓</div>
            )}
          </button>
        ))}
      </div>

      {activeRendererType === 'wasm' && (
        <div style={styles.experimentalBanner} title="See WASM_BACKEND_POLICY.md">
          ⚠️ Experimental C++ backend — TypeScript WebGPU is the supported default. Report issues with
          diagnostics from the console.
        </div>
      )}

      {isSwitching && (
        <div style={styles.status}>
          <span style={styles.spinner}>⏳</span> Switching...
        </div>
      )}
    </div>
  );
};

const styles: { [key: string]: React.CSSProperties } = {
  container: {
    background: 'rgba(20, 20, 30, 0.6)',
    backdropFilter: 'blur(12px)',
    border: '1px solid rgba(255, 215, 0, 0.15)',
    borderRadius: '12px',
    padding: '16px',
    marginBottom: '12px',
  },
  header: {
    marginBottom: '12px',
  },
  title: {
    fontSize: '13px',
    fontWeight: '600',
    color: '#FFD700',
    letterSpacing: '0.5px',
  },
  grid: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr 1fr',
    gap: '8px',
    marginBottom: '12px',
  },
  button: {
    position: 'relative',
    padding: '12px 8px',
    borderRadius: '8px',
    border: '1px solid',
    cursor: 'pointer',
    transition: 'all 0.2s ease',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: '80px',
    fontSize: '12px',
    fontWeight: '500',
  },
  buttonActive: {
    background: 'linear-gradient(135deg, rgba(255, 215, 0, 0.2) 0%, rgba(255, 215, 0, 0.05) 100%)',
    borderColor: 'rgba(255, 215, 0, 0.4)',
    color: '#FFD700',
    boxShadow: '0 0 16px rgba(255, 215, 0, 0.2)',
  },
  buttonInactive: {
    background: 'rgba(255, 255, 255, 0.02)',
    borderColor: 'rgba(255, 215, 0, 0.1)',
    color: 'rgba(255, 255, 255, 0.6)',
  },
  buttonDisabled: {
    opacity: 0.5,
    cursor: 'not-allowed',
  },
  buttonIcon: {
    fontSize: '24px',
    marginBottom: '4px',
  },
  buttonLabel: {
    fontSize: '11px',
    fontWeight: '600',
    letterSpacing: '0.05em',
    textTransform: 'uppercase',
    display: 'flex',
    alignItems: 'center',
    gap: '4px',
  },
  experimentalTag: {
    fontSize: '8px',
    fontWeight: '700',
    padding: '1px 4px',
    borderRadius: '3px',
    background: 'rgba(255, 140, 0, 0.25)',
    color: '#ffb347',
    border: '1px solid rgba(255, 140, 0, 0.5)',
    letterSpacing: '0.08em',
  },
  experimentalBanner: {
    marginTop: '10px',
    padding: '8px 10px',
    fontSize: '10px',
    lineHeight: 1.4,
    color: 'rgba(255, 180, 100, 0.95)',
    background: 'rgba(255, 100, 0, 0.08)',
    border: '1px solid rgba(255, 140, 0, 0.25)',
    borderRadius: '6px',
  },
  buttonDesc: {
    fontSize: '9px',
    opacity: 0.7,
    marginTop: '2px',
  },
  activeBadge: {
    position: 'absolute',
    top: '4px',
    right: '4px',
    width: '16px',
    height: '16px',
    background: '#FFD700',
    color: '#0a0a0f',
    borderRadius: '50%',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontSize: '11px',
    fontWeight: '700',
  },
  status: {
    textAlign: 'center',
    fontSize: '11px',
    color: 'rgba(255, 255, 255, 0.6)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: '6px',
  },
  spinner: {
    display: 'inline-block',
    animation: 'spin 1s linear infinite',
  },
};

export default RendererSwitcher;
