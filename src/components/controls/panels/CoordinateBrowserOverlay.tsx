import React from 'react';
import { RenderMode, ShaderEntry } from '../../../renderer/types';
import type { ShaderCoordData } from '../types';

interface ZoneGroup {
    label: string;
    min: number;
    max: number;
    color: string;
    shaders: { id: string; data: ShaderCoordData }[];
}

export interface CoordinateBrowserOverlayProps {
    showNumberOverlay: boolean;
    typedNumber: string;
    findShaderByCoordinate: (coord: number) => string | null;
    coordMap: Record<string, ShaderCoordData>;
    showCoordinateBrowser: boolean;
    setShowCoordinateBrowser: (open: boolean) => void;
    shadersByZone: ZoneGroup[];
    availableModes: ShaderEntry[];
    currentMode: RenderMode;
    activeSlot: number;
    setMode: (index: number, mode: RenderMode) => void;
}

export const CoordinateBrowserOverlay: React.FC<CoordinateBrowserOverlayProps> = ({
    showNumberOverlay,
    typedNumber,
    findShaderByCoordinate,
    coordMap,
    showCoordinateBrowser,
    setShowCoordinateBrowser,
    shadersByZone,
    availableModes,
    currentMode,
    activeSlot,
    setMode,
}) => (
    <>
        {showNumberOverlay && (
            <div className="glass-overlay" style={{
                position: 'fixed',
                top: 0, left: 0, right: 0, bottom: 0,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                zIndex: 1000,
            }}>
                <div className="glass-modal" style={{
                    padding: '48px 64px',
                    textAlign: 'center',
                    minWidth: '300px',
                }}>
                    <div className="gold-text-glow" style={{
                        fontSize: '72px',
                        fontWeight: 700,
                        color: '#FFD700',
                        fontFamily: 'monospace',
                        letterSpacing: '8px',
                    }}>
                        {typedNumber}
                    </div>
                    <div style={{ color: '#a0a0b0', marginTop: '16px', fontSize: '14px' }}>
                        Type 0-1000, ESC to cancel
                    </div>
                    {typedNumber && (() => {
                        const coord = parseInt(typedNumber, 10);
                        const shaderId = findShaderByCoordinate(coord);
                        const shaderData = shaderId ? coordMap[shaderId] : null;
                        return shaderData ? (
                            <div style={{
                                marginTop: '16px',
                                padding: '12px 24px',
                                background: 'rgba(255,215,0,0.1)',
                                borderRadius: '8px',
                                color: '#FFD700',
                            }}>
                                → #{shaderData.coordinate} {shaderData.name}
                            </div>
                        ) : null;
                    })()}
                </div>
            </div>
        )}

        {showCoordinateBrowser && (
            <div className="glass-overlay" style={{
                position: 'fixed',
                top: 0, left: 0, right: 0, bottom: 0,
                zIndex: 999,
                overflow: 'auto',
                padding: '24px',
            }} onClick={() => setShowCoordinateBrowser(false)}>
                <div className="glass-modal" style={{
                    maxWidth: '1200px',
                    margin: '0 auto',
                    padding: '24px',
                }} onClick={e => e.stopPropagation()}>
                    <div style={{
                        display: 'flex',
                        justifyContent: 'space-between',
                        alignItems: 'center',
                        marginBottom: '24px',
                    }}>
                        <h2 style={{ margin: 0, color: '#FFD700' }}>Shader Browser (593 shaders)</h2>
                        <button
                            onClick={() => setShowCoordinateBrowser(false)}
                            className="gold-outline-btn"
                        >
                            Close (ESC)
                        </button>
                    </div>

                    <div style={{
                        display: 'flex',
                        height: '48px',
                        borderRadius: '8px',
                        overflow: 'hidden',
                        marginBottom: '24px',
                    }}>
                        {shadersByZone.map(zone => {
                            const width = ((zone.max - zone.min) / 1000) * 100;
                            return (
                                <div
                                    key={zone.label}
                                    style={{
                                        width: `${width}%`,
                                        backgroundColor: zone.color,
                                        display: 'flex',
                                        flexDirection: 'column',
                                        alignItems: 'center',
                                        justifyContent: 'center',
                                        fontSize: '11px',
                                        color: 'rgba(255,255,255,0.9)',
                                    }}
                                >
                                    <span>{zone.label}</span>
                                    <span style={{ opacity: 0.7 }}>{zone.shaders.length}</span>
                                </div>
                            );
                        })}
                    </div>

                    <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
                        {shadersByZone.map(zone => (
                            <div key={zone.label}>
                                <h3 style={{ color: zone.color, marginBottom: '12px' }}>
                                    {zone.label} ({zone.min}-{zone.max})
                                </h3>
                                <div style={{
                                    display: 'grid',
                                    gridTemplateColumns: 'repeat(auto-fill, minmax(180px, 1fr))',
                                    gap: '8px',
                                }}>
                                    {zone.shaders.map(({ id, data }) => {
                                        const isAvailable = availableModes.some(m => m.id === id);
                                        const isSelected = currentMode === id;
                                        return (
                                            <button
                                                key={id}
                                                onClick={() => {
                                                    if (isAvailable) {
                                                        setMode(activeSlot, id);
                                                        setShowCoordinateBrowser(false);
                                                    }
                                                }}
                                                disabled={!isAvailable}
                                                className={`glass-card ${isSelected ? 'gold-active' : ''}`}
                                                style={{
                                                    padding: '12px',
                                                    textAlign: 'left',
                                                    cursor: isAvailable ? 'pointer' : 'not-allowed',
                                                    opacity: isAvailable ? 1 : 0.5,
                                                }}
                                            >
                                                <div style={{ fontSize: '10px', color: '#FFD700', fontFamily: 'monospace' }}>
                                                    #{data.coordinate}
                                                </div>
                                                <div style={{ fontSize: '13px', fontWeight: 500, color: '#f0f0f5' }}>
                                                    {data.name}
                                                </div>
                                                {!isAvailable && (
                                                    <div style={{ fontSize: '10px', color: '#606070', marginTop: '4px' }}>
                                                        (not in current category)
                                                    </div>
                                                )}
                                            </button>
                                        );
                                    })}
                                </div>
                            </div>
                        ))}
                    </div>
                </div>
            </div>
        )}
    </>
);

export default CoordinateBrowserOverlay;
