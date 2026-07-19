import React, { useState } from 'react';
import { RenderMode, SlotParams } from '../../../renderer/types';
import { SharedChain } from '../../../services/layerChainShare';
import { UseLiveControlReturn } from '../hooks/useLiveControl';
import { LiveControlPanel } from './LiveControlPanel';
import { loadMyVjSets, deleteMyVjSet, mergeMyVjSets } from '../../../services/myVjSets';
import { loadVJHistory, clearVJHistory, VJHistoryEntry } from '../../../services/vjHistory';
import { buildVjSetExport, parseVjSetExport, serializeVjSetExport } from '../../../services/vjSetExport';
import { decodeChain } from '../../../services/layerChainShare';
import { shouldShowMidiControls } from '../../../utils/deviceCapabilities';
import type { MyVjSet } from '../../../services/myVjSets';

export interface VjStudioPanelProps {
    studioOpen: boolean;
    setStudioOpen: React.Dispatch<React.SetStateAction<boolean>>;
    modes: RenderMode[];
    slotParams: SlotParams[];
    activeSlot: number;
    setActiveSlot: (index: number) => void;
    liveControl: UseLiveControlReturn;
    isAiVjMode: boolean;
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
    audioReactiveParams?: boolean;
    setAudioReactiveParams?: (enabled: boolean) => void;
    audioReactiveAmount?: number;
    setAudioReactiveAmount?: (amount: number) => void;
    onCopyChainShareLink?: () => void;
    onShareVjSet?: () => void;
    onSaveVjSet?: (name: string) => void;
    onApplySharedChain?: (chain: SharedChain) => void;
    getCurrentChain?: () => SharedChain | null;
    onUpdateStack?: (ids: string[]) => void;
    onUpdateParams?: (params: Record<string, number>[]) => void;
    onGenerateFromVibe?: (vibe: string) => void;
}

function formatRelativeTime(timestamp: number): string {
    const seconds = Math.floor((Date.now() - timestamp) / 1000);
    if (seconds < 60) return `${seconds}s ago`;
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) return `${minutes} min ago`;
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return `${hours}h ago`;
    return `${Math.floor(hours / 24)}d ago`;
}

export const VjStudioPanel: React.FC<VjStudioPanelProps> = ({
    studioOpen,
    setStudioOpen,
    modes,
    slotParams,
    activeSlot,
    setActiveSlot,
    liveControl,
    isAiVjMode,
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
    audioReactiveParams = false,
    setAudioReactiveParams,
    audioReactiveAmount = 0.8,
    setAudioReactiveAmount,
    onCopyChainShareLink,
    onShareVjSet,
    onSaveVjSet,
    onApplySharedChain,
    getCurrentChain,
    onUpdateStack,
    onUpdateParams,
    onGenerateFromVibe,
}) => {
    const [historyOpen, setHistoryOpen] = useState(false);
    const [setsOpen, setSetsOpen] = useState(false);
    const [shareOpen, setShareOpen] = useState(true);
    const [midiOpen, setMidiOpen] = useState(true);
    const [history, setHistory] = useState<VJHistoryEntry[]>([]);
    const [myVjSets, setMyVjSets] = useState<MyVjSet[]>([]);
    const [vjSetName, setVjSetName] = useState('');
    const [importStatus, setImportStatus] = useState<string | null>(null);
    const fileInputRef = React.useRef<HTMLInputElement>(null);

    const showMidi = shouldShowMidiControls();

    const handleExportJson = () => {
        const chain = getCurrentChain?.();
        if (!chain) {
            setImportStatus('No chain to export');
            return;
        }
        const payload = buildVjSetExport(vjSetName.trim() || 'VJ Set', chain, {
            bindings: liveControl.bindings,
        });
        const blob = new Blob([serializeVjSetExport(payload)], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `${payload.name.replace(/\s+/g, '-').toLowerCase()}.vjset.json`;
        a.click();
        URL.revokeObjectURL(url);
        setImportStatus('Exported JSON');
    };

    const handleImportJson = (file: File) => {
        const reader = new FileReader();
        reader.onload = () => {
            const parsed = parseVjSetExport(String(reader.result ?? ''));
            if (!parsed) {
                setImportStatus('Invalid VJ set file');
                return;
            }
            onApplySharedChain?.(parsed.chain);
            if (parsed.bindings?.length) {
                liveControl.setBindings(parsed.bindings);
            }
            const imported: MyVjSet = {
                id: crypto.randomUUID(),
                name: parsed.name,
                vibePrompt: parsed.vibePrompt ?? '',
                chainString: parsed.chainString,
                savedAt: parsed.savedAt,
            };
            mergeMyVjSets([imported]);
            setMyVjSets(loadMyVjSets());
            setImportStatus(`Imported "${parsed.name}"`);
        };
        reader.readAsText(file);
    };

    return (
        <div className="control-group glass-panel" style={{ padding: '12px', marginTop: '10px', border: '1px solid rgba(255,215,0,0.25)' }}>
            <div
                className="gold-section-header"
                style={{ fontSize: '13px', marginTop: 0, display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer' }}
                onClick={() => setStudioOpen(o => !o)}
            >
                <span>🎬 VJ Studio</span>
                <span style={{ transform: studioOpen ? 'rotate(180deg)' : 'rotate(0deg)', transition: 'transform 0.2s' }}>▼</span>
            </div>

            {studioOpen && (
                <div style={{ display: 'flex', flexDirection: 'column', gap: '12px', marginTop: '12px' }}>
                    {/* Slots overview */}
                    <div>
                        <div style={{ fontSize: '11px', color: '#a0a0b0', marginBottom: '6px' }}>Active slots</div>
                        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px' }}>
                            {modes.map((mode, i) => (
                                <button
                                    key={i}
                                    type="button"
                                    className={`gold-outline-btn ${activeSlot === i ? 'gold-active' : ''}`}
                                    style={{ fontSize: '10px', padding: '4px 8px' }}
                                    onClick={() => setActiveSlot(i)}
                                    title={mode || 'empty'}
                                    aria-label={`Slot ${i + 1}`}
                                >
                                    {i + 1}: {(mode || '—').slice(0, 12)}
                                </button>
                            ))}
                        </div>
                    </div>

                    {/* Transitions */}
                    <div>
                        <div
                            className="gold-section-header"
                            style={{ fontSize: '11px', marginTop: 0, cursor: 'pointer', display: 'flex', justifyContent: 'space-between' }}
                            onClick={() => setAutoTransitionOpen(o => !o)}
                        >
                            <span>Transitions</span>
                            <span>{autoTransitionOpen ? '▼' : '▶'}</span>
                        </div>
                        {autoTransitionOpen && (
                            <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', marginTop: '8px' }}>
                                <label style={{ display: 'flex', justifyContent: 'space-between', fontSize: '12px' }}>
                                    <span>Auto transition</span>
                                    <input
                                        type="checkbox"
                                        checked={autoTransitionEnabled}
                                        onChange={(e) => setAutoTransitionEnabled(e.target.checked)}
                                        disabled={!isAiVjMode}
                                    />
                                </label>
                                <label style={{ fontSize: '12px' }}>
                                    Source
                                    <select className="glass-select" value={autoTransitionSource} onChange={(e) => setAutoTransitionSource(e.target.value as 'timer' | 'beat')}>
                                        <option value="timer">Timer</option>
                                        <option value="beat">Audio beat</option>
                                    </select>
                                </label>
                                {autoTransitionSource === 'timer' && (
                                    <label style={{ fontSize: '12px' }}>
                                        Interval: {(autoTransitionIntervalMs / 1000).toFixed(1)}s
                                        <input type="range" min={1000} max={20000} step={250} value={autoTransitionIntervalMs} onChange={(e) => setAutoTransitionIntervalMs(Number(e.target.value))} style={{ width: '100%' }} />
                                    </label>
                                )}
                                <label style={{ fontSize: '12px' }}>
                                    Duration: {(autoTransitionDurationMs / 1000).toFixed(1)}s
                                    <input type="range" min={200} max={10000} step={100} value={autoTransitionDurationMs} onChange={(e) => setAutoTransitionDurationMs(Number(e.target.value))} style={{ width: '100%' }} />
                                </label>
                                <label style={{ fontSize: '12px' }}>
                                    Mode
                                    <select className="glass-select" value={autoTransitionMode} onChange={(e) => setAutoTransitionMode(e.target.value as 'randomize' | 'cyclePresets')}>
                                        <option value="randomize">Randomize</option>
                                        <option value="cyclePresets">Cycle presets</option>
                                    </select>
                                </label>
                            </div>
                        )}
                    </div>

                    {/* Audio reactive */}
                    {setAudioReactiveParams && (
                        <div style={{ fontSize: '12px' }}>
                            <label style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                                <input type="checkbox" checked={audioReactiveParams} onChange={(e) => setAudioReactiveParams(e.target.checked)} />
                                <span>Audio-reactive parameters</span>
                            </label>
                            {audioReactiveParams && setAudioReactiveAmount && (
                                <label style={{ display: 'block', marginTop: '8px' }}>
                                    Amount: {audioReactiveAmount.toFixed(2)}
                                    <input type="range" min={0} max={1} step={0.05} value={audioReactiveAmount} onChange={(e) => setAudioReactiveAmount(parseFloat(e.target.value))} style={{ width: '100%' }} />
                                </label>
                            )}
                        </div>
                    )}

                    {/* MIDI */}
                    <div>
                        <div
                            className="gold-section-header"
                            style={{ fontSize: '11px', marginTop: 0, cursor: 'pointer', display: 'flex', justifyContent: 'space-between' }}
                            onClick={() => setMidiOpen(o => !o)}
                        >
                            <span>{showMidi ? 'MIDI & keyboard' : 'Keyboard controls'}</span>
                            <span>{midiOpen ? '▼' : '▶'}</span>
                        </div>
                        {midiOpen && (
                            <LiveControlPanel
                                {...liveControl}
                                modes={modes}
                                learnTarget={liveControl.learnTarget}
                                cancelLearn={liveControl.cancelLearn}
                                confirmLearnBinding={liveControl.confirmLearnBinding}
                                embedded
                            />
                        )}
                        {showMidi && (
                            <div style={{ fontSize: '10px', color: '#a0a0b0', marginTop: '6px' }}>
                                Tip: click 🎛 on a parameter slider to map MIDI without the console.
                            </div>
                        )}
                    </div>

                    {/* Share & export */}
                    <div>
                        <div
                            className="gold-section-header"
                            style={{ fontSize: '11px', marginTop: 0, cursor: 'pointer', display: 'flex', justifyContent: 'space-between' }}
                            onClick={() => setShareOpen(o => !o)}
                        >
                            <span>Share & export</span>
                            <span>{shareOpen ? '▼' : '▶'}</span>
                        </div>
                        {shareOpen && (
                            <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', marginTop: '8px' }}>
                                {onCopyChainShareLink && (
                                    <button type="button" className="gold-outline-btn" style={{ width: '100%', fontSize: '11px' }} onClick={onCopyChainShareLink}>
                                        🔗 Copy chain URL
                                    </button>
                                )}
                                {onShareVjSet && (
                                    <button type="button" className="gold-outline-btn" style={{ width: '100%', fontSize: '11px' }} onClick={onShareVjSet}>
                                        Share VJ set link
                                    </button>
                                )}
                                <div style={{ display: 'flex', gap: '8px' }}>
                                    <input type="text" className="glass-input" placeholder="Set name for export…" value={vjSetName} onChange={(e) => setVjSetName(e.target.value)} style={{ flex: 1, fontSize: '11px' }} />
                                    <button type="button" className="gold-outline-btn" style={{ fontSize: '11px' }} onClick={handleExportJson} disabled={!getCurrentChain}>
                                        Export JSON
                                    </button>
                                </div>
                                <div style={{ display: 'flex', gap: '8px' }}>
                                    <button type="button" className="gold-outline-btn" style={{ flex: 1, fontSize: '11px' }} onClick={() => fileInputRef.current?.click()}>
                                        Import JSON
                                    </button>
                                    {onSaveVjSet && (
                                        <button
                                            type="button"
                                            className="gold-outline-btn"
                                            style={{ flex: 1, fontSize: '11px' }}
                                            disabled={!vjSetName.trim()}
                                            onClick={() => {
                                                onSaveVjSet(vjSetName.trim());
                                                setMyVjSets(loadMyVjSets());
                                                setVjSetName('');
                                            }}
                                        >
                                            Save to My Sets
                                        </button>
                                    )}
                                </div>
                                <input ref={fileInputRef} type="file" accept=".json,.vjset.json,application/json" style={{ display: 'none' }} onChange={(e) => {
                                    const f = e.target.files?.[0];
                                    if (f) handleImportJson(f);
                                    e.target.value = '';
                                }} />
                                {importStatus && <div style={{ fontSize: '10px', color: '#a0a0b0' }}>{importStatus}</div>}
                            </div>
                        )}
                    </div>

                    {/* My sets */}
                    {onApplySharedChain && (
                        <div>
                            <div
                                className="gold-section-header"
                                style={{ fontSize: '11px', marginTop: 0, cursor: 'pointer', display: 'flex', justifyContent: 'space-between' }}
                                onClick={() => {
                                    setSetsOpen(o => !o);
                                    if (!setsOpen) setMyVjSets(loadMyVjSets());
                                }}
                            >
                                <span>My VJ sets</span>
                                <span>{setsOpen ? '▼' : '▶'}</span>
                            </div>
                            {setsOpen && (
                                <div style={{ maxHeight: '160px', overflowY: 'auto', marginTop: '8px' }}>
                                    {myVjSets.length === 0 && <div style={{ fontSize: '11px', color: '#a0a0b0' }}>No saved sets</div>}
                                    {myVjSets.map(set => (
                                        <div key={set.id} style={{ display: 'flex', gap: '6px', marginBottom: '6px', fontSize: '11px' }}>
                                            <span style={{ flex: 1, color: '#ffd700' }}>{set.name}</span>
                                            <button type="button" className="gold-outline-btn" style={{ fontSize: '10px', padding: '2px 6px' }} onClick={() => {
                                                const chain = decodeChain(set.chainString);
                                                if (chain) onApplySharedChain(chain);
                                            }}>Load</button>
                                            <button type="button" className="gold-outline-btn" style={{ fontSize: '10px', padding: '2px 6px' }} onClick={() => {
                                                deleteMyVjSet(set.id);
                                                setMyVjSets(loadMyVjSets());
                                            }}>✕</button>
                                        </div>
                                    ))}
                                </div>
                            )}
                        </div>
                    )}

                    {/* History */}
                    <div>
                        <div
                            className="gold-section-header"
                            style={{ fontSize: '11px', marginTop: 0, cursor: 'pointer', display: 'flex', justifyContent: 'space-between' }}
                            onClick={() => {
                                setHistoryOpen(o => !o);
                                if (!historyOpen) setHistory(loadVJHistory());
                            }}
                        >
                            <span>VJ history</span>
                            <span>{historyOpen ? '▼' : '▶'}</span>
                        </div>
                        {historyOpen && (
                            <div style={{ maxHeight: '160px', overflowY: 'auto', marginTop: '8px' }}>
                                {history.length === 0 && <div style={{ fontSize: '11px', color: '#a0a0b0' }}>No history yet</div>}
                                {history.map(entry => (
                                    <div key={entry.id} style={{ marginBottom: '8px', fontSize: '11px', padding: '6px', background: 'rgba(20,20,30,0.5)', borderRadius: '4px' }}>
                                        <div style={{ color: '#ffd700' }}>{entry.vibeText.slice(0, 40)}…</div>
                                        <div style={{ color: '#888', fontSize: '10px' }}>{formatRelativeTime(entry.timestamp)}</div>
                                        <button type="button" className="gold-outline-btn" style={{ fontSize: '10px', marginTop: '4px', width: '100%' }} onClick={() => {
                                            onUpdateStack?.(entry.shaderIds);
                                            onUpdateParams?.(entry.params);
                                        }}>Restore</button>
                                    </div>
                                ))}
                                <button type="button" className="gold-outline-btn" style={{ fontSize: '10px', width: '100%' }} onClick={() => { clearVJHistory(); setHistory([]); }}>Clear history</button>
                            </div>
                        )}
                    </div>
                </div>
            )}
        </div>
    );
};

export default VjStudioPanel;
