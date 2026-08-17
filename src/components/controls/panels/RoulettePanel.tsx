import React from 'react';

export interface RoulettePanelProps {
    activeSlot: number;
    onRoulette?: () => void;
    onRandomizeAllSlots?: () => void;
    isRouletteActive?: boolean;
    chaosModeEnabled?: boolean;
    setChaosModeEnabled?: (enabled: boolean) => void;
    audioReactiveParams?: boolean;
    setAudioReactiveParams?: (enabled: boolean) => void;
    audioReactiveAmount?: number;
    setAudioReactiveAmount?: (amount: number) => void;
}

export const RoulettePanel: React.FC<RoulettePanelProps> = ({
    activeSlot,
    onRoulette,
    onRandomizeAllSlots,
    isRouletteActive = false,
    chaosModeEnabled = false,
    setChaosModeEnabled,
    audioReactiveParams = false,
    setAudioReactiveParams,
    audioReactiveAmount = 0.8,
    setAudioReactiveAmount,
}) => (
    <div className="glass-panel" style={{ margin: '15px 0', padding: '15px' }}>
        <div style={{ position: 'relative', zIndex: 1 }}>
            {/* Per-slot randomize lives in the top menubar; keep bulk + modes here. */}
            <div style={{ fontSize: '12px', color: '#a0a0b0', marginBottom: '10px' }}>
                Slot {activeSlot + 1} randomize is in the menubar (or press <kbd style={{ background: 'rgba(255,215,0,0.15)', borderColor: 'rgba(255,215,0,0.3)', color: '#FFD700', padding: '0 4px', borderRadius: 3 }}>R</kbd>)
            </div>
            <button
                onClick={onRandomizeAllSlots}
                className={`gold-outline-btn ${isRouletteActive ? 'spinning' : ''}`}
                title="Randomize all 3 shader slots + sliders"
                style={{ width: '100%' }}
            >
                <span>🎲</span>
                <span>Randomize All Slots</span>
            </button>

            <div className="chaos-mode-toggle">
                <label className="chaos-label">
                    <input
                        type="checkbox"
                        checked={chaosModeEnabled}
                        onChange={(e) => setChaosModeEnabled?.(e.target.checked)}
                    />
                    <span className="chaos-text">
                        🔥 Chaos Mode
                        <small>Auto-switch every 6-10s</small>
                    </span>
                </label>
            </div>

            <div className="audio-reactive-toggle">
                <label className="chaos-label">
                    <input
                        type="checkbox"
                        checked={audioReactiveParams}
                        onChange={(e) => setAudioReactiveParams?.(e.target.checked)}
                    />
                    <span className="chaos-text">
                        🔊 Audio-Reactive
                        <small>Modulates zoom params by audio</small>
                    </span>
                </label>
                {audioReactiveParams && (
                    <div style={{ marginTop: '8px', paddingLeft: '24px' }}>
                        <label style={{ fontSize: '11px', color: '#a0a0b0', display: 'block', marginBottom: '4px' }}>
                            React Amount: {Math.round(audioReactiveAmount * 100)}%
                        </label>
                        <input
                            type="range"
                            min={0}
                            max={1}
                            step={0.05}
                            value={audioReactiveAmount}
                            onChange={(e) => setAudioReactiveAmount?.(parseFloat(e.target.value))}
                            style={{ width: '100%' }}
                        />
                    </div>
                )}
            </div>

            <div className="roulette-shortcut-hint" style={{ color: '#a0a0b0' }}>
                Press <kbd style={{ background: 'rgba(255,215,0,0.15)', borderColor: 'rgba(255,215,0,0.3)', color: '#FFD700' }}>R</kbd> to spin
                {audioReactiveParams && (
                    <span>
                        {' '}· <kbd style={{ background: 'rgba(0,212,255,0.15)', borderColor: 'rgba(0,212,255,0.3)', color: '#00d4ff' }}>A</kbd> toggle audio · <kbd style={{ background: 'rgba(0,212,255,0.15)', borderColor: 'rgba(0,212,255,0.3)', color: '#00d4ff' }}>[ ]</kbd> amount
                    </span>
                )}
            </div>
        </div>
    </div>
);

export default RoulettePanel;
