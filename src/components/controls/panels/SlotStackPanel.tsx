import React, { useState } from 'react';
import { RenderMode } from '../../../renderer/types';
import { ShaderMegaMenu } from '../../ShaderMegaMenu';
import type { ShaderMegaMenuOption } from '../../ShaderMegaMenu';
import { ShaderGallery } from '../../ShaderGallery';

export interface SlotStackPanelProps {
    modes: RenderMode[];
    setMode: (index: number, mode: RenderMode) => void;
    activeSlot: number;
    setActiveSlot: (index: number) => void;
    slotShaderStatus?: Array<'idle' | 'loading' | 'error'>;
    slotMenuOptions: ShaderMegaMenuOption[];
}

export const SlotStackPanel: React.FC<SlotStackPanelProps> = ({
    modes,
    setMode,
    activeSlot,
    setActiveSlot,
    slotShaderStatus = ['idle', 'idle', 'idle', 'idle', 'idle', 'idle'],
    slotMenuOptions,
}) => {
    const [galleryOpenFor, setGalleryOpenFor] = useState<number | null>(null);

    return (
        <>
            <div className="glass-panel" style={{ padding: '12px' }}>
                <div className="gold-section-header" style={{ fontSize: '12px', marginTop: '0' }}>Shader Slots</div>
                {modes.map((_, i) => {
                    const slotStatus = slotShaderStatus[i] || 'idle';
                    const borderColor = slotStatus === 'error' ? '#ff4757'
                        : slotStatus === 'loading' ? '#ffa502'
                        : activeSlot === i ? '#FFD700' : 'rgba(255,215,0,0.08)';
                    const glowStyle = activeSlot === i
                        ? { boxShadow: '0 0 20px rgba(255, 215, 0, 0.2)' }
                        : {};
                    return (
                        <div
                            key={i}
                            className={`glass-card ${activeSlot === i ? 'gold-active' : ''}`}
                            onClick={() => setActiveSlot(i)}
                            style={{
                                padding: '10px',
                                marginBottom: '8px',
                                cursor: 'pointer',
                                borderColor,
                                ...glowStyle,
                            }}
                        >
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '6px' }}>
                                <span style={{ fontSize: '12px', color: activeSlot === i ? '#FFD700' : '#a0a0b0', fontWeight: 600 }}>Slot {i + 1}</span>
                                {slotStatus === 'loading' && (
                                    <span className="gold-badge" style={{ color: '#ffa502', borderColor: 'rgba(255,165,2,0.3)', background: 'rgba(255,165,2,0.1)' }}>
                                        <span className="gold-spinner" style={{ width: '12px', height: '12px' }}></span>
                                        COMPILING
                                    </span>
                                )}
                                {slotStatus === 'error' && (
                                    <span style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                                        <span
                                            className="gold-badge"
                                            title="Shader failed to compile or load. Retry if it was a transient network error, or pick a different shader below."
                                            style={{ color: '#ff4757', borderColor: 'rgba(255,71,87,0.3)', background: 'rgba(255,71,87,0.1)' }}
                                        >
                                            ✕ FAILED
                                        </span>
                                        <button
                                            title="Retry loading this shader (useful for transient network errors)"
                                            onClick={(e) => { e.stopPropagation(); setMode(i, modes[i]); }}
                                            style={{
                                                background: 'rgba(255,71,87,0.15)',
                                                border: '1px solid rgba(255,71,87,0.4)',
                                                borderRadius: '4px',
                                                color: '#ff4757',
                                                cursor: 'pointer',
                                                fontSize: '10px',
                                                padding: '2px 6px',
                                                lineHeight: 1.4,
                                            }}
                                        >
                                            ↺ Retry
                                        </button>
                                    </span>
                                )}
                            </div>
                            <div style={{ display: 'flex', gap: '6px', alignItems: 'center' }}>
                                <div style={{ flex: 1 }}>
                                    <ShaderMegaMenu
                                        options={slotMenuOptions}
                                        value={modes[i]}
                                        onChange={(id) => setMode(i, id as RenderMode)}
                                        includeNone={true}
                                        onClick={(e) => e.stopPropagation()}
                                    />
                                </div>
                                <button
                                    className="gold-badge"
                                    title="Browse shader thumbnails"
                                    onClick={(e) => { e.stopPropagation(); setGalleryOpenFor(i); }}
                                    style={{ cursor: 'pointer', fontSize: '13px', padding: '6px 8px' }}
                                >
                                    🖼️
                                </button>
                            </div>
                        </div>
                    );
                })}
            </div>

            {galleryOpenFor !== null && (
                <ShaderGallery
                    options={slotMenuOptions}
                    value={modes[galleryOpenFor]}
                    onSelect={(id) => { setMode(galleryOpenFor, id as RenderMode); setGalleryOpenFor(null); }}
                    onClose={() => setGalleryOpenFor(null)}
                />
            )}
        </>
    );
};

export default SlotStackPanel;
