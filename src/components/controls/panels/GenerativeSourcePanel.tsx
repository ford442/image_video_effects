import React, { useState } from 'react';
import type { ShaderMegaMenuOption } from '../../ShaderMegaMenu';
import { ShaderMegaMenu } from '../../ShaderMegaMenu';
import { ShaderGallery } from '../../ShaderGallery';

export interface GenerativeSourcePanelProps {
    activeGenerativeShader: string;
    setActiveGenerativeShader: (id: string) => void;
    generativeMenuOptions: ShaderMegaMenuOption[];
    generativeShowcaseActive?: boolean;
    generativeShowcaseLocked?: boolean;
    generativeShowcaseDelay?: number;
    onStartGenerativeShowcase?: () => void;
    onStopGenerativeShowcase?: () => void;
    onSetGenerativeShowcaseDelay?: (seconds: number) => void;
}

export const GenerativeSourcePanel: React.FC<GenerativeSourcePanelProps> = ({
    activeGenerativeShader,
    setActiveGenerativeShader,
    generativeMenuOptions,
    generativeShowcaseActive = false,
    generativeShowcaseLocked = false,
    generativeShowcaseDelay = 12,
    onStartGenerativeShowcase,
    onStopGenerativeShowcase,
    onSetGenerativeShowcaseDelay,
}) => {
    const [galleryOpen, setGalleryOpen] = useState(false);

    return (
        <>
            <div className="control-group glass-panel" style={{ marginTop: '10px', padding: '12px' }}>
                <div className="gold-section-header" style={{ fontSize: '12px', marginTop: '0' }}>Generative Shader</div>
                <div style={{ display: 'flex', gap: '6px', alignItems: 'center' }}>
                    <div style={{ flex: 1 }}>
                        <ShaderMegaMenu
                            options={generativeMenuOptions}
                            value={activeGenerativeShader}
                            onChange={setActiveGenerativeShader}
                            includeNone={false}
                        />
                    </div>
                    <button
                        className="gold-badge"
                        title="Browse shader thumbnails"
                        onClick={() => setGalleryOpen(true)}
                        style={{ cursor: 'pointer', fontSize: '13px', padding: '6px 8px' }}
                    >
                        🖼️
                    </button>
                </div>

                <div className="chaos-mode-toggle" style={{ marginTop: '10px' }}>
                    <label className="chaos-label">
                        <input
                            type="checkbox"
                            checked={generativeShowcaseActive}
                            onChange={(e) => {
                                if (e.target.checked) {
                                    onStartGenerativeShowcase?.();
                                } else {
                                    onStopGenerativeShowcase?.();
                                }
                            }}
                        />
                        <span className="chaos-text">
                            🎨 Attract Mode
                            <small>Rotate showcase shaders (G)</small>
                        </span>
                    </label>
                </div>

                {generativeShowcaseActive && (
                    <div style={{ fontSize: '11px', color: generativeShowcaseLocked ? '#4ade80' : '#00d4ff', marginTop: '6px' }}>
                        {generativeShowcaseLocked ? '🔒 Locked — you have control' : '● Auto-rotating — move mouse or MIDI to engage'}
                    </div>
                )}

                {generativeShowcaseActive && onSetGenerativeShowcaseDelay && (
                    <div style={{ marginTop: '8px' }}>
                        <label style={{ fontSize: '11px', color: '#a0a0b0' }}>
                            Switch every: {generativeShowcaseDelay}s
                        </label>
                        <input
                            type="range"
                            className="glass-range"
                            min={6}
                            max={30}
                            step={1}
                            value={generativeShowcaseDelay}
                            onChange={(e) => onSetGenerativeShowcaseDelay(Number(e.target.value))}
                        />
                    </div>
                )}

                <div style={{ fontSize: '11px', color: '#a0a0b0', fontStyle: 'italic', padding: '8px 0 0 0' }}>
                    Move mouse to interact. Space locks/unlocks attract rotation.
                </div>
            </div>

            {galleryOpen && (
                <ShaderGallery
                    options={generativeMenuOptions}
                    value={activeGenerativeShader}
                    onSelect={(id) => { setActiveGenerativeShader(id); setGalleryOpen(false); }}
                    onClose={() => setGalleryOpen(false)}
                />
            )}
        </>
    );
};

export default GenerativeSourcePanel;
