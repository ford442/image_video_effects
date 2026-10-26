import React, { useState, useEffect, useRef } from 'react';
import { RenderMode, SlotParams } from '../../../renderer/types';
import type { AIStatus } from '../../../types/aiVj';
import { loadVJHistory, clearVJHistory, VJHistoryEntry } from '../../../services/vjHistory';
import { VJPreset, loadPresets, deletePreset } from '../../../services/vjPresets';
import { MyVjSet, loadMyVjSets, deleteMyVjSet } from '../../../services/myVjSets';
import { PresetPackGallery } from '../../PresetPackGallery';
import { CommunityGallery } from '../../CommunityGallery';
import { decodeChain, buildSharedChain } from '../../../services/layerChainShare';
import type { SharedChain } from '../../../services/layerChainShare';
import { buildCatalog, CatalogShader } from '../../../services/shaderCatalog';
import { VariationGrid } from '../../VariationGrid';

export interface AiVjStudioPanelProps {
    modes: RenderMode[];
    slotParams: SlotParams[];
    isWebcamActive?: boolean;
    onStartWebcam?: () => void;
    onStopWebcam?: () => void;
    webcamError?: string | null;
    onUploadImageTrigger: () => void;
    onLoadModel: () => void;
    isModelLoaded: boolean;
    isAiVjMode: boolean;
    onToggleAiVj: () => void;
    aiVjStatus: AIStatus;
    aiVjMessage?: string;
    onGenerateFromVibe?: (vibe: string) => void;
    onUpdateStack?: (ids: string[]) => void;
    onUpdateParams?: (params: Record<string, number>[]) => void;
    onRandomizeParams?: () => void;
    onSavePreset?: (name: string) => void;
    onShareVjSet?: () => void;
    onSaveVjSet?: (name: string) => void;
    onApplySharedChain?: (chain: SharedChain) => void;
    getCurrentChain?: () => SharedChain | null;
    onCopyChainShareLink?: () => void;
    autoTransitionOpen: boolean;
    setAutoTransitionOpen: React.Dispatch<React.SetStateAction<boolean>>;
    autoTransitionEnabled: boolean;
    setAutoTransitionEnabled: React.Dispatch<React.SetStateAction<boolean>>;
    autoTransitionSource: 'timer' | 'beat';
    setAutoTransitionSource: React.Dispatch<React.SetStateAction<'timer' | 'beat'>>;
    autoTransitionIntervalMs: number;
    setAutoTransitionIntervalMs: React.Dispatch<React.SetStateAction<number>>;
    autoTransitionDurationMs: number;
    setAutoTransitionDurationMs: React.Dispatch<React.SetStateAction<number>>;
    autoTransitionMode: 'randomize' | 'cyclePresets';
    setAutoTransitionMode: React.Dispatch<React.SetStateAction<'randomize' | 'cyclePresets'>>;
}

function formatRelativeTime(timestamp: number): string {
    const seconds = Math.floor((Date.now() - timestamp) / 1000);
    if (seconds < 60) return `${seconds}s ago`;
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) return `${minutes} min ago`;
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return `${hours}h ago`;
    const days = Math.floor(hours / 24);
    return `${days}d ago`;
}

export const AiVjStudioPanel: React.FC<AiVjStudioPanelProps> = ({
    modes,
    slotParams,
    isWebcamActive = false,
    onStartWebcam,
    onStopWebcam,
    webcamError,
    onUploadImageTrigger,
    onLoadModel,
    isModelLoaded,
    isAiVjMode,
    onToggleAiVj,
    aiVjStatus,
    aiVjMessage,
    onGenerateFromVibe,
    onUpdateStack,
    onUpdateParams,
    onRandomizeParams,
    onSavePreset,
    onShareVjSet,
    onSaveVjSet,
    onApplySharedChain,
    getCurrentChain,
    onCopyChainShareLink,
    autoTransitionOpen,
    setAutoTransitionOpen,
    autoTransitionEnabled,
    setAutoTransitionEnabled,
    autoTransitionSource,
    setAutoTransitionSource,
    autoTransitionIntervalMs,
    setAutoTransitionIntervalMs,
    autoTransitionDurationMs,
    setAutoTransitionDurationMs,
    autoTransitionMode,
    setAutoTransitionMode,
}) => {
    const [vibeInput, setVibeInput] = useState('');
    const [history, setHistory] = useState<VJHistoryEntry[]>([]);
    const [historyOpen, setHistoryOpen] = useState(false);
    const prevAiVjStatusRef = useRef<AIStatus>(aiVjStatus);
    const [presets, setPresets] = useState<VJPreset[]>(() => loadPresets());
    const [presetsOpen, setPresetsOpen] = useState(false);
    const [myVjSets, setMyVjSets] = useState<MyVjSet[]>(() => loadMyVjSets());
    const [myVjSetsOpen, setMyVjSetsOpen] = useState(false);
    const [vjSetName, setVjSetName] = useState('');
    const [presetPacksOpen, setPresetPacksOpen] = useState(false);
    const [communityGalleryOpen, setCommunityGalleryOpen] = useState(false);
    const [presetName, setPresetName] = useState('');
    const [remixOpen, setRemixOpen] = useState(false);
    const [remixCatalog, setRemixCatalog] = useState<CatalogShader[] | null>(null);
    const [remixLoading, setRemixLoading] = useState(false);

    const activeShaderIds = modes;

    useEffect(() => {
        setHistory(loadVJHistory());
    }, []);

    useEffect(() => {
        if (prevAiVjStatusRef.current === 'generating' && aiVjStatus !== 'generating') {
            setHistory(loadVJHistory());
        }
        prevAiVjStatusRef.current = aiVjStatus;
    }, [aiVjStatus]);

    const getAiVjButtonText = () => {
        if (isAiVjMode) return 'Stop AI VJ';
        if (aiVjStatus === 'loading-models' || aiVjStatus === 'generating') return 'AI is working...';
        return 'Start AI VJ';
    };

    return (
        <>
            <div className="control-group" style={{ marginTop: '10px' }}>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr', gap: '8px', marginBottom: '10px' }}>
                    <button className="gold-outline-btn" onClick={onUploadImageTrigger}>📁 Upload Img</button>
                </div>
                <button
                    onClick={isWebcamActive ? onStopWebcam : onStartWebcam}
                    className={`webcam-btn-gold ${isWebcamActive ? 'active' : ''}`}
                >
                    {isWebcamActive ? '⏹️ Stop Webcam' : '📹 Use Webcam'}
                </button>
                {webcamError && (
                    <div className="webcam-error" style={{ borderColor: 'rgba(255,71,87,0.3)', background: 'rgba(255,71,87,0.1)', color: '#ff6b6b' }}>
                        ⚠️ {webcamError}
                    </div>
                )}
            </div>
            <hr className="gold-divider" />
            <div className="control-group">
                <div className="gold-section-header" style={{ fontSize: '12px' }}>Automation</div>
                <button className="ai-vj-btn" onClick={onLoadModel} disabled={isModelLoaded}>
                    {isModelLoaded ? '✓ Depth Model Loaded' : 'Load Depth Model'}
                </button>
            </div>

            <div className="control-group">
                <button className="ai-vj-btn" onClick={onToggleAiVj} disabled={aiVjStatus === 'loading-models' || aiVjStatus === 'generating'}>
                    {getAiVjButtonText()}
                </button>
            </div>

            {onGenerateFromVibe && (
                <div className="control-group glass-panel" style={{ padding: '12px', marginTop: '10px' }}>
                    <div className="gold-section-header" style={{ fontSize: '12px', marginTop: '0' }}>Vibe Prompt</div>
                    <div style={{ display: 'flex', gap: '8px', marginTop: '8px' }}>
                        <input
                            type="text"
                            className="glass-input"
                            placeholder="Describe the vibe..."
                            value={vibeInput}
                            onChange={(e) => setVibeInput(e.target.value)}
                            onKeyPress={(e) => {
                                if (e.key === 'Enter' && vibeInput.trim()) {
                                    onGenerateFromVibe(vibeInput.trim());
                                }
                            }}
                            disabled={aiVjStatus === 'loading-models' || aiVjStatus === 'generating'}
                            style={{ flex: 1 }}
                        />
                        <button
                            className="gold-outline-btn"
                            onClick={() => {
                                if (vibeInput.trim()) {
                                    onGenerateFromVibe(vibeInput.trim());
                                }
                            }}
                            disabled={aiVjStatus === 'loading-models' || aiVjStatus === 'generating' || !vibeInput.trim()}
                        >
                            Generate
                        </button>
                        <button
                            className="gold-outline-btn"
                            onClick={() => onRandomizeParams?.()}
                            disabled={!activeShaderIds || activeShaderIds.length === 0}
                        >
                            Randomize Params
                        </button>
                    </div>
                    {aiVjMessage && (
                        <div style={{ fontSize: '11px', color: '#a0a0b0', marginTop: '8px', fontStyle: 'italic' }}>
                            {aiVjMessage}
                        </div>
                    )}
                    <div style={{ display: 'flex', gap: '8px', marginTop: '10px' }}>
                        <input
                            type="text"
                            className="glass-input"
                            placeholder="Preset name…"
                            value={presetName}
                            onChange={(e) => setPresetName(e.target.value)}
                            style={{ flex: 1 }}
                        />
                        <button
                            className="gold-outline-btn"
                            onClick={() => {
                                if (presetName.trim() && onSavePreset) {
                                    onSavePreset(presetName.trim());
                                    setPresets(loadPresets());
                                    setPresetName('');
                                }
                            }}
                            disabled={!presetName.trim()}
                        >
                            Save Preset
                        </button>
                    </div>

                    {(onShareVjSet || onSaveVjSet) && (
                        <div style={{ display: 'flex', gap: '8px', marginTop: '10px' }}>
                            {onShareVjSet && (
                                <button
                                    className="gold-outline-btn"
                                    onClick={() => onShareVjSet()}
                                    disabled={!activeShaderIds || activeShaderIds.length === 0}
                                    title="Create a shareable link for the current VJ stack"
                                    style={{ flex: 1 }}
                                >
                                    🔗 Share this VJ set
                                </button>
                            )}
                            {onSaveVjSet && (
                                <button
                                    className="gold-outline-btn"
                                    onClick={() => {
                                        if (!vjSetName.trim()) return;
                                        onSaveVjSet(vjSetName.trim());
                                        setMyVjSets(loadMyVjSets());
                                        setVjSetName('');
                                    }}
                                    disabled={!vjSetName.trim() || !activeShaderIds || activeShaderIds.length === 0}
                                    title="Save the current VJ stack to My VJ Sets"
                                    style={{ flex: 1 }}
                                >
                                    💾 Save as My VJ Set
                                </button>
                            )}
                        </div>
                    )}
                    {onSaveVjSet && (
                        <div style={{ display: 'flex', gap: '8px', marginTop: '8px' }}>
                            <input
                                type="text"
                                className="glass-input"
                                placeholder="My VJ set name…"
                                value={vjSetName}
                                onChange={(e) => setVjSetName(e.target.value)}
                                style={{ flex: 1 }}
                            />
                        </div>
                    )}
                </div>
            )}

            {onApplySharedChain && (
                <div className="control-group glass-panel" style={{ padding: '12px', marginTop: '10px' }}>
                    <div
                        className="gold-section-header"
                        style={{ fontSize: '12px', marginTop: '0', display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer' }}
                        onClick={() => {
                            setMyVjSetsOpen(o => !o);
                            if (!myVjSetsOpen) setMyVjSets(loadMyVjSets());
                        }}
                    >
                        <span>My VJ Sets</span>
                        <span style={{ transform: myVjSetsOpen ? 'rotate(180deg)' : 'rotate(0deg)', transition: 'transform 0.2s' }}>▼</span>
                    </div>
                    {myVjSetsOpen && (
                        <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', marginTop: '8px', maxHeight: '300px', overflowY: 'auto' }}>
                            {myVjSets.length === 0 && (
                                <div style={{ fontSize: '12px', color: '#a0a0b0', fontStyle: 'italic', textAlign: 'center' }}>
                                    No saved sets yet
                                </div>
                            )}
                            {myVjSets.map(set => {
                                const vibeDisplay = set.vibePrompt
                                    ? (set.vibePrompt.length > 60 ? set.vibePrompt.slice(0, 60) + '…' : set.vibePrompt)
                                    : '(no vibe prompt)';
                                return (
                                    <div key={set.id} style={{
                                        background: 'rgba(20, 20, 30, 0.6)',
                                        border: '1px solid rgba(255, 215, 0, 0.1)',
                                        borderRadius: '6px',
                                        padding: '8px',
                                    }}>
                                        <div style={{ fontSize: '12px', fontWeight: 600, color: '#ffd700' }}>{set.name}</div>
                                        <div style={{ fontSize: '11px', color: '#a0a0b0', fontStyle: 'italic', margin: '4px 0' }}>{vibeDisplay}</div>
                                        <div style={{ display: 'flex', gap: '6px', marginTop: '6px' }}>
                                            <button
                                                className="gold-outline-btn"
                                                style={{ fontSize: '11px', padding: '4px 10px', flex: 1 }}
                                                onClick={() => {
                                                    const chain = decodeChain(set.chainString);
                                                    if (chain) onApplySharedChain(chain);
                                                }}
                                            >
                                                Load
                                            </button>
                                            <button
                                                className="gold-outline-btn"
                                                style={{ fontSize: '11px', padding: '4px 10px' }}
                                                onClick={() => {
                                                    deleteMyVjSet(set.id);
                                                    setMyVjSets(loadMyVjSets());
                                                }}
                                            >
                                                🗑
                                            </button>
                                        </div>
                                    </div>
                                );
                            })}
                        </div>
                    )}
                </div>
            )}

            <div className="control-group glass-panel" style={{ padding: '12px', marginTop: '10px' }}>
                <div
                    className="gold-section-header"
                    style={{ fontSize: '12px', marginTop: '0', display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer' }}
                    onClick={() => setAutoTransitionOpen(o => !o)}
                >
                    <span>Auto Transition</span>
                    <span style={{ transform: autoTransitionOpen ? 'rotate(180deg)' : 'rotate(0deg)', transition: 'transform 0.2s' }}>▼</span>
                </div>
                {autoTransitionOpen && (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', marginTop: '8px' }}>
                        <label style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: '12px' }}>
                            <span>Enabled</span>
                            <input
                                type="checkbox"
                                checked={autoTransitionEnabled}
                                onChange={(e) => setAutoTransitionEnabled(e.target.checked)}
                                disabled={!isAiVjMode}
                            />
                        </label>
                        <label style={{ fontSize: '12px' }}>
                            Source
                            <select
                                className="glass-select"
                                value={autoTransitionSource}
                                onChange={(e) => setAutoTransitionSource(e.target.value as 'timer' | 'beat')}
                            >
                                <option value="timer">Timer</option>
                                <option value="beat">Audio Beat</option>
                            </select>
                        </label>
                        {autoTransitionSource === 'timer' && (
                            <label style={{ fontSize: '12px' }}>
                                Interval: {(autoTransitionIntervalMs / 1000).toFixed(1)}s
                                <input
                                    type="range"
                                    min={1000}
                                    max={20000}
                                    step={250}
                                    value={autoTransitionIntervalMs}
                                    onChange={(e) => setAutoTransitionIntervalMs(Number(e.target.value))}
                                    style={{ width: '100%' }}
                                />
                            </label>
                        )}
                        <label style={{ fontSize: '12px' }}>
                            Duration: {(autoTransitionDurationMs / 1000).toFixed(1)}s
                            <input
                                type="range"
                                min={200}
                                max={10000}
                                step={100}
                                value={autoTransitionDurationMs}
                                onChange={(e) => setAutoTransitionDurationMs(Number(e.target.value))}
                                style={{ width: '100%' }}
                            />
                        </label>
                        <label style={{ fontSize: '12px' }}>
                            Mode
                            <select
                                className="glass-select"
                                value={autoTransitionMode}
                                onChange={(e) => setAutoTransitionMode(e.target.value as 'randomize' | 'cyclePresets')}
                            >
                                <option value="randomize">Randomize</option>
                                <option value="cyclePresets">Cycle Presets</option>
                            </select>
                        </label>
                    </div>
                )}
            </div>

            <div className="control-group glass-panel" style={{ padding: '12px', marginTop: '10px' }}>
                <div
                    className="gold-section-header"
                    style={{ fontSize: '12px', marginTop: '0', display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer' }}
                    onClick={() => setHistoryOpen(o => !o)}
                >
                    <span>VJ History</span>
                    <span style={{ transform: historyOpen ? 'rotate(180deg)' : 'rotate(0deg)', transition: 'transform 0.2s' }}>▼</span>
                </div>
                {historyOpen && (
                    <>
                        <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: '8px', marginBottom: '8px' }}>
                            <button
                                className="gold-outline-btn"
                                style={{ fontSize: '11px', padding: '4px 10px' }}
                                onClick={() => {
                                    clearVJHistory();
                                    setHistory([]);
                                }}
                            >
                                Clear History
                            </button>
                        </div>
                        <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', maxHeight: '300px', overflowY: 'auto' }}>
                            {history.length === 0 && (
                                <div style={{ fontSize: '12px', color: '#a0a0b0', fontStyle: 'italic', textAlign: 'center' }}>
                                    No history yet
                                </div>
                            )}
                            {history.map(entry => {
                                const vibeDisplay = entry.vibeText.length > 60 ? entry.vibeText.slice(0, 60) + '…' : entry.vibeText;
                                const idDisplay = entry.shaderIds.slice(0, 3).join(', ') + (entry.shaderIds.length > 3 ? ` …+${entry.shaderIds.length - 3}` : '');
                                return (
                                    <div key={entry.id} style={{
                                        background: 'rgba(20, 20, 30, 0.6)',
                                        border: '1px solid rgba(255, 215, 0, 0.1)',
                                        borderRadius: '6px',
                                        padding: '8px',
                                    }}>
                                        <div style={{ fontSize: '12px', color: '#FFD700', fontWeight: 500, marginBottom: '4px' }}>
                                            {vibeDisplay}
                                        </div>
                                        <div style={{ fontSize: '10px', color: 'rgba(255,255,255,0.5)', marginBottom: '6px' }}>
                                            {idDisplay} • {formatRelativeTime(entry.timestamp)}
                                        </div>
                                        <div style={{ display: 'flex', gap: '6px' }}>
                                            <button
                                                className="gold-outline-btn"
                                                style={{ fontSize: '11px', padding: '3px 8px', flex: 1 }}
                                                onClick={() => {
                                                    if (onUpdateStack) onUpdateStack(entry.shaderIds);
                                                    if (onUpdateParams) onUpdateParams(entry.params);
                                                }}
                                            >
                                                Restore
                                            </button>
                                            <button
                                                className="gold-outline-btn"
                                                style={{ fontSize: '11px', padding: '3px 8px', flex: 1 }}
                                                onClick={() => {
                                                    if (onGenerateFromVibe) onGenerateFromVibe(entry.vibeText);
                                                }}
                                            >
                                                Regen
                                            </button>
                                        </div>
                                    </div>
                                );
                            })}
                        </div>
                    </>
                )}
            </div>

            <div className="control-group glass-panel" style={{ padding: '12px', marginTop: '10px' }}>
                <div
                    className="gold-section-header"
                    style={{ fontSize: '12px', marginTop: '0', display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer' }}
                    onClick={() => setPresetsOpen(o => !o)}
                >
                    <span>Presets</span>
                    <span style={{ transform: presetsOpen ? 'rotate(180deg)' : 'rotate(0deg)', transition: 'transform 0.2s' }}>▼</span>
                </div>
                {presetsOpen && (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', maxHeight: '300px', overflowY: 'auto', marginTop: '8px' }}>
                        {presets.length === 0 && (
                            <div style={{ fontSize: '12px', color: '#a0a0b0', fontStyle: 'italic', textAlign: 'center' }}>
                                No presets saved yet
                            </div>
                        )}
                        {presets.map(preset => {
                            const idDisplay = preset.shaderIds.slice(0, 3).join(', ') + (preset.shaderIds.length > 3 ? ` …+${preset.shaderIds.length - 3}` : '');
                            return (
                                <div key={preset.id} style={{
                                    background: 'rgba(20, 20, 30, 0.6)',
                                    border: '1px solid rgba(255, 215, 0, 0.1)',
                                    borderRadius: '6px',
                                    padding: '8px',
                                }}>
                                    <div style={{ fontSize: '12px', color: '#FFD700', fontWeight: 500, marginBottom: '4px' }}>
                                        {preset.name}
                                    </div>
                                    <div style={{ fontSize: '10px', color: 'rgba(255,255,255,0.5)', marginBottom: '6px' }}>
                                        {idDisplay} • {formatRelativeTime(preset.timestamp)}
                                    </div>
                                    <div style={{ display: 'flex', gap: '6px' }}>
                                        <button
                                            className="gold-outline-btn"
                                            style={{ fontSize: '11px', padding: '3px 8px', flex: 1 }}
                                            onClick={() => {
                                                if (onUpdateStack) onUpdateStack(preset.shaderIds);
                                                if (onUpdateParams) onUpdateParams(preset.params);
                                            }}
                                        >
                                            Restore
                                        </button>
                                        <button
                                            className="gold-outline-btn"
                                            style={{ fontSize: '11px', padding: '3px 8px', flex: 1 }}
                                            onClick={() => {
                                                deletePreset(preset.id);
                                                setPresets(loadPresets());
                                            }}
                                        >
                                            Delete
                                        </button>
                                    </div>
                                </div>
                            );
                        })}
                    </div>
                )}
            </div>

            {onCopyChainShareLink && (
                <button
                    className="gold-outline-btn"
                    style={{ width: '100%', marginTop: '10px' }}
                    onClick={onCopyChainShareLink}
                    title="Copy a link that restores this entire shader chain"
                >
                    🔗 Copy Chain Share Link
                </button>
            )}
            {onApplySharedChain && (
                <button
                    className="gold-outline-btn"
                    style={{ width: '100%', marginTop: '10px' }}
                    onClick={async () => {
                        setRemixOpen(true);
                        if (!remixCatalog) {
                            setRemixLoading(true);
                            try {
                                const catalog = await buildCatalog();
                                setRemixCatalog(catalog);
                            } catch (e) {
                                console.error('[Controls] Failed to load catalog for remix:', e);
                            } finally {
                                setRemixLoading(false);
                            }
                        }
                    }}
                    title="Generate A/B variations of the current chain"
                >
                    🔀 Remix Chain
                </button>
            )}
            {onApplySharedChain && (
                <PresetPackGallery
                    open={presetPacksOpen}
                    onToggle={() => setPresetPacksOpen(o => !o)}
                    onApplyPack={(chain: SharedChain) => onApplySharedChain(chain)}
                />
            )}
            {onApplySharedChain && getCurrentChain && (
                <CommunityGallery
                    open={communityGalleryOpen}
                    onToggle={() => setCommunityGalleryOpen(o => !o)}
                    onApplySharedChain={onApplySharedChain}
                    getCurrentChain={getCurrentChain}
                />
            )}

            {remixOpen && remixCatalog && (
                <VariationGrid
                    baseChain={buildSharedChain(modes, slotParams)}
                    catalog={remixCatalog}
                    count={6}
                    options={{ paramJitter: true, shaderSwap: 'sameCategory' }}
                    onAdopt={(chain: SharedChain) => {
                        onApplySharedChain?.(chain);
                        setRemixOpen(false);
                    }}
                    onClose={() => setRemixOpen(false)}
                />
            )}

            {remixOpen && !remixCatalog && (
                <div
                    style={{
                        position: 'fixed',
                        inset: 0,
                        background: 'rgba(0,0,0,0.85)',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        zIndex: 1000,
                    }}
                >
                    <div className="glass-panel" style={{ padding: '24px', borderRadius: '12px' }}>
                        <p style={{ color: '#FFD700', margin: 0 }}>
                            {remixLoading ? 'Loading shader catalog…' : 'Preparing remix explorer…'}
                        </p>
                    </div>
                </div>
            )}
        </>
    );
};

export default AiVjStudioPanel;
