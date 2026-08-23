import React from 'react';

export interface ImageAutoSwitchPanelProps {
    onNewImage: () => void;
    autoChangeEnabled: boolean;
    setAutoChangeEnabled: (enabled: boolean) => void;
    autoChangeDelay: number;
    setAutoChangeDelay: (delay: number) => void;
    isAiVjMode: boolean;
}

export const ImageAutoSwitchPanel: React.FC<ImageAutoSwitchPanelProps> = ({
    onNewImage,
    autoChangeEnabled,
    setAutoChangeEnabled,
    autoChangeDelay,
    setAutoChangeDelay,
    isAiVjMode,
}) => (
    <>
        {/* Random Image lives in the top menubar; this panel keeps auto-switch only. */}
        <div className="control-group" style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: '4px' }}>
            <label
                htmlFor="auto-change-toggle"
                style={{ marginBottom: 0, color: isAiVjMode ? '#606070' : '#a0a0b0' }}
                title={isAiVjMode ? 'Disabled while AI VJ is active' : ''}
            >
                Auto Switch
            </label>
            <input
                type="checkbox"
                id="auto-change-toggle"
                className="gold-checkbox"
                checked={autoChangeEnabled}
                onChange={(e) => setAutoChangeEnabled(e.target.checked)}
                disabled={isAiVjMode}
                style={{ width: 'auto' }}
            />
        </div>

        {autoChangeEnabled && !isAiVjMode && (
            <div className="control-group">
                <label htmlFor="delay-slider" style={{ color: '#a0a0b0' }}>
                    Switch Delay: <span style={{ color: '#FFD700' }}>{autoChangeDelay}s</span>
                </label>
                <input
                    type="range"
                    id="delay-slider"
                    className="glass-range"
                    min="1"
                    max="10"
                    step="1"
                    value={autoChangeDelay}
                    onChange={(e) => setAutoChangeDelay(Number(e.target.value))}
                />
            </div>
        )}
    </>
);

export default ImageAutoSwitchPanel;
