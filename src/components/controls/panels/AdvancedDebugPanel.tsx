import React, { useState } from 'react';
import { ShadertoyImportPanel } from './ShadertoyImportPanel';

/** Backend health shown in the debug panel — see WASM_BACKEND_POLICY.md (Tier B triage). */
export interface RendererDiagnosticsSummary {
    backend: 'webgpu' | 'wasm' | 'js';
    fps?: number;
    /** Active backend adapter identity (vendor | architecture | device). */
    adapterInfo?: string;
    adapterAttemptLabel?: string | null;
    /** WASM only: 'ready' / 'partial at <stage>' / 'failed at <stage>' + adapter. */
    wasmInitSummary?: string;
    wasmAdapterInfo?: string;
    wasmFailedStageName?: string;
    wasmLastInitError?: string;
    graphShaderId?: string | null;
    graphRequested?: number;
    graphExecuted?: number;
    graphTruncated?: number;
    graphCap?: number;
    graphErrors?: string[];
    gpuComputeAvailable?: boolean;
    gpuChoresReason?: string;
    gpuChoresLastOp?: string | null;
    gpuChoresBackend?: string;
    gpuChoresEv?: number;
}

export interface AdvancedDebugPanelProps {
    onOpenShaderScanner?: () => void;
    activeRendererType?: 'webgpu' | 'wasm' | 'js';
    onSwitchRenderer?: (type: 'webgpu' | 'wasm' | 'js') => Promise<void>;
    onOpenCoordinateBrowser: () => void;
    onOpenStorageBrowser?: () => void;
    onPreviewImportShader?: (id: string, wgsl: string, name: string) => void;
    onImportStatus?: (message: string) => void;
    /** Live backend diagnostics. Rendered whenever provided — no console required. */
    diagnostics?: RendererDiagnosticsSummary | null;
}

export const AdvancedDebugPanel: React.FC<AdvancedDebugPanelProps> = ({
    onOpenShaderScanner,
    activeRendererType = 'webgpu',
    onSwitchRenderer,
    onOpenCoordinateBrowser,
    onOpenStorageBrowser,
    onPreviewImportShader,
    onImportStatus,
    diagnostics,
}) => {
    const [devToolsOpen, setDevToolsOpen] = useState(false);

    return (
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
                            <ShadertoyImportPanel
                                onPreviewShader={onPreviewImportShader}
                                onStatus={onImportStatus}
                            />
                        </div>
                    )}
                </div>
            )}

            {diagnostics && (
                <div
                    className="control-group"
                    data-testid="renderer-diagnostics"
                    style={{
                        fontSize: '10px',
                        color: '#a0a0b0',
                        fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
                        lineHeight: 1.6,
                        wordBreak: 'break-word',
                    }}
                >
                    <div style={{ color: '#FFD700', marginBottom: '4px' }}>Renderer diagnostics</div>
                    <div>
                        backend: {diagnostics.backend}
                        {diagnostics.backend === 'wasm' && ' (experimental)'}
                        {diagnostics.fps !== undefined && ` · ${Math.round(diagnostics.fps)} FPS`}
                    </div>
                    <div>adapter: {diagnostics.adapterInfo?.trim() || 'unreported'}</div>
                    {diagnostics.adapterAttemptLabel && (
                        <div>adapter ladder: {diagnostics.adapterAttemptLabel}</div>
                    )}
                    {diagnostics.wasmInitSummary && (
                        <div>wasm init: {diagnostics.wasmInitSummary}</div>
                    )}
                    {diagnostics.backend !== 'wasm' && diagnostics.wasmAdapterInfo && (
                        <div>wasm adapter: {diagnostics.wasmAdapterInfo}</div>
                    )}
                    {diagnostics.wasmLastInitError && (
                        <div style={{ color: '#ff9d9d' }}>
                            wasm error: {diagnostics.wasmLastInitError}
                        </div>
                    )}
                    {(diagnostics.graphRequested !== undefined || (diagnostics.graphErrors && diagnostics.graphErrors.length > 0)) && (
                        <div data-testid="graph-run-report" style={{ marginTop: '6px' }}>
                            <div style={{ color: '#FFD700' }}>GraphRunner</div>
                            {diagnostics.graphShaderId && <div>id: {diagnostics.graphShaderId}</div>}
                            {diagnostics.graphRequested !== undefined && (
                                <div>
                                    truncated steps: {diagnostics.graphTruncated ?? 0} / requested {diagnostics.graphRequested}
                                    {diagnostics.graphExecuted !== undefined && ` · executed ${diagnostics.graphExecuted}`}
                                    {diagnostics.graphCap !== undefined && ` · cap ${diagnostics.graphCap}`}
                                </div>
                            )}
                            {diagnostics.graphErrors && diagnostics.graphErrors.length > 0 && (
                                <div style={{ color: '#ff9d9d' }}>
                                    graph invalid: {diagnostics.graphErrors.join('; ')}
                                </div>
                            )}
                        </div>
                    )}
                    {(diagnostics.gpuComputeAvailable !== undefined || diagnostics.gpuChoresReason) && (
                        <div data-testid="gpu-chores-breadcrumbs" style={{ marginTop: '6px' }}>
                            <div style={{ color: '#FFD700' }}>gpu-chores (Tier 4b)</div>
                            <div>
                                gpuComputeAvailable: {diagnostics.gpuComputeAvailable ? 'yes' : 'no'}
                                {diagnostics.gpuChoresBackend && ` · ${diagnostics.gpuChoresBackend}`}
                                {diagnostics.gpuChoresLastOp && ` · last ${diagnostics.gpuChoresLastOp}`}
                            </div>
                            {diagnostics.gpuChoresEv !== undefined && Number.isFinite(diagnostics.gpuChoresEv) && (
                                <div>auto-exposure EV: {diagnostics.gpuChoresEv.toFixed(2)}</div>
                            )}
                            {diagnostics.gpuChoresReason && (
                                <div>reason: {diagnostics.gpuChoresReason}</div>
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
};

export default AdvancedDebugPanel;
