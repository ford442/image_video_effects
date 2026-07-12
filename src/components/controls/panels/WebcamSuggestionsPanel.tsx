import React from 'react';
import { RenderMode, ShaderEntry } from '../../../renderer/types';

export interface WebcamSuggestionsPanelProps {
    availableModes: ShaderEntry[];
    webcamFunShaders?: string[];
    modes: RenderMode[];
    onApplyWebcamShader?: (shaderId: string) => void;
}

export const WebcamSuggestionsPanel: React.FC<WebcamSuggestionsPanelProps> = ({
    availableModes,
    webcamFunShaders,
    modes,
    onApplyWebcamShader,
}) => (
    <div className="glass-panel" style={{ padding: '15px', marginTop: '15px' }}>
        <div className="gold-section-header" style={{ fontSize: '12px', marginTop: '0' }}>
            <span>✨ Fun Effects for Webcam</span>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: '8px' }}>
            {availableModes
                .filter(m => webcamFunShaders?.includes(m.id))
                .slice(0, 12)
                .map(shader => (
                    <button
                        key={shader.id}
                        className={`shader-chip-gold ${modes[0] === shader.id ? 'active' : ''}`}
                        onClick={() => onApplyWebcamShader?.(shader.id)}
                        title={shader.description || shader.name}
                    >
                        {shader.name}
                    </button>
                ))}
        </div>
    </div>
);

export default WebcamSuggestionsPanel;
