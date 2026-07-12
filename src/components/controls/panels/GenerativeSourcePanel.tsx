import React, { useState } from 'react';
import type { ShaderMegaMenuOption } from '../../ShaderMegaMenu';
import { ShaderMegaMenu } from '../../ShaderMegaMenu';
import { ShaderGallery } from '../../ShaderGallery';

export interface GenerativeSourcePanelProps {
    activeGenerativeShader: string;
    setActiveGenerativeShader: (id: string) => void;
    generativeMenuOptions: ShaderMegaMenuOption[];
}

export const GenerativeSourcePanel: React.FC<GenerativeSourcePanelProps> = ({
    activeGenerativeShader,
    setActiveGenerativeShader,
    generativeMenuOptions,
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
                <div style={{ fontSize: '11px', color: '#a0a0b0', fontStyle: 'italic', padding: '8px 0 0 0' }}>
                    Move mouse to interact. Click/Drag for more effects.
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
