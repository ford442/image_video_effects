import React from 'react';

export interface AdvancedDebugPanelProps {
    devToolsOpen: boolean;
    setDevToolsOpen: (open: boolean | ((prev: boolean) => boolean)) => void;
    onOpenShaderScanner?: () => void;
    activeRendererType?: 'webgpu' | 'wasm' | 'js';
    onSwitchRenderer?: (type: 'webgpu' | 'wasm' | 'js') => Promise<void>;
    onOpenCoordinateBrowser: () => void;
    onOpenStorageBrowser?: () => void;
}

export const AdvancedDebugPanel: React.FC<AdvancedDebugPanelProps> = ({
    devToolsOpen,
    setDevToolsOpen,
    onOpenShaderScanner,
    activeRendererType = 'webgpu',
    onSwitchRenderer,
    onOpenCoordinateBrowser,
    onOpenStorageBrowser,
}) => (
    <>
        {onOpenShaderScanner && (
            <div className="dev-tools-container">
                <button
                    className="dev-tools-toggle"
                    onClick={() => setDevToolsOpen(!devToolsOpen)}
                >
                    🔧 Dev Tools {devToolsOpen ? '▼' : '▶'}
                </button>
                {devToolsOpen && (
                    <div className="dev-tools-gold">
                        <button onClick={onOpenShaderScanner}>
                            🔍 Scan Shaders for Errors
                        </button>
                        <div style={{
                            marginTop: '6px',
                            fontSize: '10px',
                            color: '#a0a0b0',
                            textAlign: 'center',
                        }}>
                            Tests WGSL compilation on all shaders
                        </div>
                        {onSwitchRenderer && (
                            <div style={{ marginTop: '10px' }}>
                                <div style={{ fontSize: '10px', color: '#a0a0b0', marginBottom: '5px', textAlign: 'center' }}>
                                    Renderer Backend
                                </div>
                                <div style={{ display: 'flex', gap: '4px' }}>
                                    {(['webgpu', 'wasm', 'js'] as const).map(type => (
                                        <button
                                            key={type}
                                            onClick={() => onSwitchRenderer(type)}
                                            style={{
                                                flex: 1,
                                                fontSize: '10px',
                                                padding: '4px 0',
                                                background: activeRendererType === type
                                                    ? 'rgba(255,215,0,0.25)'
                                                    : 'transparent',
                                                border: `1px solid ${activeRendererType === type ? '#FFD700' : 'rgba(255,215,0,0.3)'}`,
                                                color: activeRendererType === type ? '#FFD700' : '#a0a0b0',
                                                borderRadius: '4px',
                                                cursor: 'pointer',
                                                textTransform: 'uppercase',
                                                letterSpacing: '0.05em',
                                            }}
                                        >
                                            {type === 'wasm' ? 'wasm (exp)' : type}
                                        </button>
                                    ))}
                                </div>
                            </div>
                        )}
                    </div>
                )}
            </div>
        )}

        <hr className="gold-divider" />

        <div className="control-group">
            <button onClick={onOpenCoordinateBrowser} className="coord-browser-btn">
                <span>🗂️</span>
                <span>Browse by Coordinate (B)</span>
            </button>
            <div style={{ fontSize: '11px', color: '#a0a0b0', marginTop: '6px', textAlign: 'center' }}>
                Tip: Type any number to jump to that shader
            </div>
        </div>

        {onOpenStorageBrowser && (
            <div className="control-group">
                <button onClick={onOpenStorageBrowser} className="storage-btn">
                    <span>📦</span>
                    <span>VPS Storage Browser</span>
                </button>
                <div style={{ fontSize: '11px', color: '#a0a0b0', marginTop: '6px', textAlign: 'center' }}>
                    Browse shaders, images & videos from VPS
                </div>
            </div>
        )}
    </>
);

export default AdvancedDebugPanel;
