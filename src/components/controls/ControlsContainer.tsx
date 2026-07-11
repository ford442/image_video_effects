import React, { useState, useEffect, useMemo } from 'react';
import { RenderMode, ShaderEntry, ShaderCategory, InputSource, SlotParams } from '../../renderer/types';
import { AIStatus } from '../../AutoDJ';
// @ts-ignore
import shaderCoordinates from '../../shader_coordinates.json';
import type { ShaderMegaMenuOption } from '../ShaderMegaMenu';
import { ShaderMegaMenu } from '../ShaderMegaMenu';
import { ShaderGallery } from '../ShaderGallery';
import { ShaderStarRating } from '../ShaderStarRating';
import { useShaderRatings } from '../../services/ShaderRatingIntegration';
import { LiveStreamPanel } from '../LiveStreamPanel';
import { loadVJHistory, clearVJHistory, VJHistoryEntry } from '../../services/vjHistory';
import { VJPreset, loadPresets, deletePreset } from '../../services/vjPresets';
import { MyVjSet, loadMyVjSets, deleteMyVjSet } from '../../services/myVjSets';
import { PresetPackGallery } from '../PresetPackGallery';
import { decodeChain, buildSharedChain } from '../../services/layerChainShare';
import type { SharedChain } from '../../services/layerChainShare';
import { buildCatalog, CatalogShader } from '../../services/shaderCatalog';
import { VariationGrid } from '../VariationGrid';
import { RendererBackendPanel } from './panels/RendererBackendPanel';
import { ParamSlidersPanel } from './panels/ParamSlidersPanel';
import { SlotStackPanel } from './panels/SlotStackPanel';
import { InputSourcePanel } from './panels/InputSourcePanel';
import { RecordingSharePanel } from './panels/RecordingSharePanel';
import { LiveControlPanel } from './panels/LiveControlPanel';
import { RoulettePanel } from './panels/RoulettePanel';
import { CoordinateBrowserOverlay } from './panels/CoordinateBrowserOverlay';
import { AdvancedDebugPanel } from './panels/AdvancedDebugPanel';
import { useLiveControl } from './hooks/useLiveControl';
import type { ControlsProps, ShaderCoordData } from './types';
import '../../styles/gold-glass-theme.css';

export const ControlsContainer: React.FC<ControlsProps> = ({
    modes, setMode,
    activeSlot, setActiveSlot,
    slotParams, updateSlotParam,
    slotShaderStatus = ['idle', 'idle', 'idle', 'idle', 'idle', 'idle'],
    shaderCategory, setShaderCategory,
    onNewImage,
    autoChangeEnabled, setAutoChangeEnabled,
    autoChangeDelay, setAutoChangeDelay,
    onLoadModel, isModelLoaded,
    availableModes = [],
    inputSource, setInputSource,
    videoList, selectedVideo, setSelectedVideo,
    videoB3hdMode, setVideoB3hdMode,
    b3hdSegmentLength, setB3hdSegmentLength,
    b3hdIntervalSeconds, setB3hdIntervalSeconds,
    currentSegment,
    isMuted, setIsMuted,
    onUploadImageTrigger,
    onUploadVideoTrigger,
    activeGenerativeShader, setActiveGenerativeShader,
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
    onStartAutoTransition,
    onStopAutoTransition,
    isWebcamActive = false,
    onStartWebcam,
    onStopWebcam,
    webcamError,
    showWebcamShaderSuggestions = false,
    webcamFunShaders = [],
    onApplyWebcamShader,
    onRoulette,
    onRandomizeAllSlots,
    isRouletteActive = false,
    chaosModeEnabled = false,
    setChaosModeEnabled,
    // Audio-Reactive Props
    audioReactiveParams = false,
    setAudioReactiveParams,
    audioReactiveAmount = 0.8,
    setAudioReactiveAmount,
    isRecording = false,
    recordingCountdown = 8,
    onStartRecording,
    onStopRecording,
    onTakeScreenshot,
    liveStreamUrl,
    onLiveStreamLoaded,
    onExitLiveStream,
    onOpenShaderScanner,
    activeRendererType = 'webgpu',
    onSwitchRenderer,
    onOpenStorageBrowser,
    onCopyChainShareLink,
    onApplySharedChain,
    onTriggerNextTransition,
    onRandomizeSlot,
    onSetSlotParam,
}) => {
    // --- Coordinate System State ---
    const [showCoordinateBrowser, setShowCoordinateBrowser] = useState(false);
    const [galleryOpenFor, setGalleryOpenFor] = useState<number | 'generative' | null>(null);
    const [typedNumber, setTypedNumber] = useState('');
    const [showNumberOverlay, setShowNumberOverlay] = useState(false);
    const numberTimeoutRef = React.useRef<NodeJS.Timeout | null>(null);

    // --- Vibe Prompt State ---
    const [vibeInput, setVibeInput] = useState('');

    // --- VJ History State ---
    const [history, setHistory] = useState<VJHistoryEntry[]>([]);
    const [historyOpen, setHistoryOpen] = useState(false);
    const prevAiVjStatusRef = React.useRef<AIStatus>(aiVjStatus);

    // --- Dev Tools Visibility State ---
    const [devToolsOpen, setDevToolsOpen] = useState(false);

    // --- Presets State ---
    const [presets, setPresets] = useState<VJPreset[]>(() => loadPresets());
    const [presetsOpen, setPresetsOpen] = useState(false);

    // --- My VJ Sets State ---
    const [myVjSets, setMyVjSets] = useState<MyVjSet[]>(() => loadMyVjSets());
    const [myVjSetsOpen, setMyVjSetsOpen] = useState(false);
    const [vjSetName, setVjSetName] = useState('');

    // --- Preset Pack Gallery State ---
    const [presetPacksOpen, setPresetPacksOpen] = useState(false);
    const [presetName, setPresetName] = useState('');
    const [autoTransitionOpen, setAutoTransitionOpen] = useState(false);
    const [autoTransitionEnabled, setAutoTransitionEnabled] = useState(false);
    const [autoTransitionSource, setAutoTransitionSource] = useState<'timer' | 'beat'>('timer');
    const [autoTransitionIntervalMs, setAutoTransitionIntervalMs] = useState(8000);
    const [autoTransitionDurationMs, setAutoTransitionDurationMs] = useState(2000);
    const [autoTransitionMode, setAutoTransitionMode] = useState<'randomize' | 'cyclePresets'>('randomize');

    // --- Chain Remix Explorer State ---
    const [remixOpen, setRemixOpen] = useState(false);
    const [remixCatalog, setRemixCatalog] = useState<CatalogShader[] | null>(null);
    const [remixLoading, setRemixLoading] = useState(false);

    const liveControl = useLiveControl({
        isAiVjMode,
        autoTransitionEnabled,
        setAutoTransitionEnabled,
        onSetSlotParam,
        onRandomizeSlot,
        onRandomizeAllSlots,
        onTriggerNextTransition,
        onStartAutoTransition,
        onStopAutoTransition,
        autoTransitionSource,
        autoTransitionIntervalMs,
        autoTransitionDurationMs,
        autoTransitionMode,
    });

    useEffect(() => {
        setHistory(loadVJHistory());
    }, []);

    useEffect(() => {
        if (prevAiVjStatusRef.current === 'generating' && aiVjStatus !== 'generating') {
            setHistory(loadVJHistory());
        }
        prevAiVjStatusRef.current = aiVjStatus;
    }, [aiVjStatus]);

    const formatRelativeTime = (timestamp: number): string => {
        const seconds = Math.floor((Date.now() - timestamp) / 1000);
        if (seconds < 60) return `${seconds}s ago`;
        const minutes = Math.floor(seconds / 60);
        if (minutes < 60) return `${minutes} min ago`;
        const hours = Math.floor(minutes / 60);
        if (hours < 24) return `${hours}h ago`;
        const days = Math.floor(hours / 24);
        return `${days}d ago`;
    };

    // --- Star Ratings ---
    const { shaders: ratedShaders, rateShader } = useShaderRatings();
    const ratingMap = useMemo(() => {
        const map = new Map<string, { stars: number; ratingCount: number }>();
        for (const s of ratedShaders) {
            map.set(s.id, { stars: s.stars, ratingCount: s.ratingCount });
        }
        return map;
    }, [ratedShaders]);

    // Prepare coordinate data
    const coordMap = useMemo(() => shaderCoordinates as Record<string, ShaderCoordData>, []);
    
    // Get coordinate for a shader ID
    const getShaderCoordinate = (id: string): number | null => {
        return coordMap[id]?.coordinate ?? null;
    };

    // Find shader by coordinate (closest match)
    const findShaderByCoordinate = React.useCallback((targetCoord: number): string | null => {
        let closestId: string | null = null;
        let minDiff = Infinity;
        
        for (const [id, data] of Object.entries(coordMap)) {
            const diff = Math.abs(data.coordinate - targetCoord);
            if (diff < minDiff) {
                minDiff = diff;
                closestId = id;
            }
        }
        
        return closestId;
    }, [coordMap]);

    // Keyboard navigation: type number to jump
    useEffect(() => {
        const handleKeyDown = (e: KeyboardEvent) => {
            // Ignore if typing in an input
            if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) {
                return;
            }

            const key = e.key;

            // Number keys 0-9
            if (/^[0-9]$/.test(key)) {
                e.preventDefault();
                
                if (numberTimeoutRef.current) {
                    clearTimeout(numberTimeoutRef.current);
                }

                const newNumber = typedNumber + key;
                setTypedNumber(newNumber);
                setShowNumberOverlay(true);

                numberTimeoutRef.current = setTimeout(() => {
                    const coord = parseInt(newNumber, 10);
                    if (!isNaN(coord) && coord >= 0 && coord <= 1000) {
                        const shaderId = findShaderByCoordinate(coord);
                        if (shaderId) {
                            // Check if shader is available in current modes
                            const isAvailable = availableModes.some(m => m.id === shaderId);
                            if (isAvailable) {
                                setMode(activeSlot, shaderId);
                            }
                        }
                    }
                    setTypedNumber('');
                    setShowNumberOverlay(false);
                }, 800);

            } else if (key === 'Escape') {
                if (numberTimeoutRef.current) {
                    clearTimeout(numberTimeoutRef.current);
                }
                setTypedNumber('');
                setShowNumberOverlay(false);
                setShowCoordinateBrowser(false);
            } else if (key === 'b' || key === 'B') {
                // 'B' to open coordinate browser
                if (!(e.target instanceof HTMLInputElement)) {
                    setShowCoordinateBrowser(prev => !prev);
                }
            }
        };

        window.addEventListener('keydown', handleKeyDown);
        return () => {
            window.removeEventListener('keydown', handleKeyDown);
            if (numberTimeoutRef.current) {
                clearTimeout(numberTimeoutRef.current);
            }
        };
    }, [typedNumber, availableModes, activeSlot, setMode, findShaderByCoordinate]);

    const activeShaderIds = modes;

    const currentModes = useMemo(() => {
        if (shaderCategory === 'image') {
            // 'image' shows all non-generative shaders (the "Effects / Filters" bucket)
            return availableModes.filter(entry => entry.category !== 'generative');
        }
        // Any other specific category — show only that category
        return availableModes.filter(entry => entry.category === shaderCategory);
    }, [availableModes, shaderCategory]);
    const currentMode = modes[activeSlot];
    const currentParams = slotParams[activeSlot];

    const slotMenuOptions = useMemo(
        () => currentModes.map((m): ShaderMegaMenuOption => {
            const rating = ratingMap.get(m.id);
            return {
                id: m.id,
                name: m.name,
                coordinate: coordMap[m.id]?.coordinate ?? null,
                category: coordMap[m.id]?.category ?? m.category,
                stars: rating?.stars,
                ratingCount: rating?.ratingCount,
            };
        }),
        [currentModes, coordMap, ratingMap]
    );

    const generativeMenuOptions = useMemo(
        () => availableModes
            .filter(m => m.category === 'generative')
            .map((m): ShaderMegaMenuOption => {
                const rating = ratingMap.get(m.id);
                return {
                    id: m.id,
                    name: m.name,
                    coordinate: coordMap[m.id]?.coordinate ?? null,
                    category: coordMap[m.id]?.category ?? m.category,
                    stars: rating?.stars,
                    ratingCount: rating?.ratingCount,
                };
            }),
        [availableModes, coordMap, ratingMap]
    );
    const currentShaderEntry = availableModes.find(m => m.id === currentMode);
    const currentCoordinate = getShaderCoordinate(currentMode);

    const getAiVjButtonText = () => {
        if (isAiVjMode) return 'Stop AI VJ';
        if (aiVjStatus === 'loading-models' || aiVjStatus === 'generating') return 'AI is working...';
        return 'Start AI VJ';
    };

    // Zone colors for coordinate display
    const getZoneColor = (coord: number): string => {
        if (coord < 100) return '#1a5276'; // Ambient
        if (coord < 250) return '#1e8449'; // Organic
        if (coord < 400) return '#2874a6'; // Interactive
        if (coord < 550) return '#8e44ad'; // Artistic
        if (coord < 700) return '#c0392b'; // Visual FX
        if (coord < 850) return '#d35400'; // Retro
        return '#7d3c98'; // Extreme
    };

    // Group shaders by zone for browser
    const shadersByZone = useMemo(() => {
        const zones = [
            { label: '🌊 Ambient', min: 0, max: 100, color: '#1a5276', shaders: [] as {id: string, data: ShaderCoordData}[] },
            { label: '🌿 Organic', min: 100, max: 250, color: '#1e8449', shaders: [] as {id: string, data: ShaderCoordData}[] },
            { label: '👆 Interactive', min: 250, max: 400, color: '#2874a6', shaders: [] as {id: string, data: ShaderCoordData}[] },
            { label: '🎨 Artistic', min: 400, max: 550, color: '#8e44ad', shaders: [] as {id: string, data: ShaderCoordData}[] },
            { label: '✨ Visual FX', min: 550, max: 700, color: '#c0392b', shaders: [] as {id: string, data: ShaderCoordData}[] },
            { label: '📺 Retro', min: 700, max: 850, color: '#d35400', shaders: [] as {id: string, data: ShaderCoordData}[] },
            { label: '🌀 Extreme', min: 850, max: 1000, color: '#7d3c98', shaders: [] as {id: string, data: ShaderCoordData}[] },
        ];

        for (const [id, data] of Object.entries(coordMap)) {
            const zone = zones.find(z => data.coordinate >= z.min && data.coordinate < z.max);
            if (zone) {
                zone.shaders.push({ id, data });
            }
        }

        // Sort shaders within each zone by coordinate
        zones.forEach(z => z.shaders.sort((a, b) => a.data.coordinate - b.data.coordinate));

        return zones.filter(z => z.shaders.length > 0);
    }, [coordMap]);

    return (
        <div className="controls gold-scroll">
            <CoordinateBrowserOverlay
                showNumberOverlay={showNumberOverlay}
                typedNumber={typedNumber}
                findShaderByCoordinate={findShaderByCoordinate}
                coordMap={coordMap}
                showCoordinateBrowser={showCoordinateBrowser}
                setShowCoordinateBrowser={setShowCoordinateBrowser}
                shadersByZone={shadersByZone}
                availableModes={availableModes}
                currentMode={currentMode}
                activeSlot={activeSlot}
                setMode={setMode}
            />

            <InputSourcePanel
                inputSource={inputSource}
                setInputSource={setInputSource}
                setShaderCategory={setShaderCategory}
            />

            <LiveControlPanel
                {...liveControl}
                modes={modes}
            />

            {/* --- Renderer Switcher --- */}
            {onSwitchRenderer && activeRendererType && (
                <RendererBackendPanel
                    activeRendererType={activeRendererType}
                    onSwitchRenderer={onSwitchRenderer}
                />
            )}

            {inputSource === 'image' && (
                <>
                    <div className="control-group">
                        <button className="gold-outline-btn" onClick={onNewImage} style={{width: '100%'}}>
                            🎲 Random Image
                        </button>
                    </div>

                    <div className="control-group" style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: '10px'}}>
                        <label htmlFor="auto-change-toggle" style={{marginBottom: 0, color: isAiVjMode ? '#606070' : '#a0a0b0' }} title={isAiVjMode ? 'Disabled while AI VJ is active' : ''}>Auto Switch</label>
                        <input type="checkbox" id="auto-change-toggle" className="gold-checkbox" checked={autoChangeEnabled} onChange={(e) => setAutoChangeEnabled(e.target.checked)} disabled={isAiVjMode} style={{width: 'auto'}} />
                    </div>

                    {autoChangeEnabled && !isAiVjMode && (
                        <div className="control-group">
                            <label htmlFor="delay-slider" style={{color: '#a0a0b0'}}>Switch Delay: <span style={{color: '#FFD700'}}>{autoChangeDelay}s</span></label>
                            <input type="range" id="delay-slider" className="glass-range" min="1" max="10" step="1" value={autoChangeDelay} onChange={(e) => setAutoChangeDelay(Number(e.target.value))} />
                        </div>
                    )}
                </>
            )}

            <div className="control-group">
                <label htmlFor="category-select" className="gold-section-header" style={{fontSize: '13px'}}>Effect Filter</label>
                <select id="category-select" className="glass-select" value={shaderCategory} onChange={(e) => setShaderCategory(e.target.value as ShaderCategory)}>
                    <option value="image">All Effects / Filters</option>
                    <option value="generative">Procedural Generation</option>
                    <option value="distortion">Distortion</option>
                    <option value="simulation">Simulation</option>
                    <option value="artistic">Artistic</option>
                    <option value="interactive-mouse">Interactive / Mouse</option>
                    <option value="lighting-effects">Lighting Effects</option>
                    <option value="liquid-effects">Liquid Effects</option>
                    <option value="retro-glitch">Retro / Glitch</option>
                    <option value="visual-effects">Visual Effects</option>
                    <option value="geometric">Geometric</option>
                    <option value="post-processing">Post-Processing</option>
                </select>
            </div>

            <RoulettePanel
                activeSlot={activeSlot}
                onRoulette={onRoulette}
                onRandomizeAllSlots={onRandomizeAllSlots}
                isRouletteActive={isRouletteActive}
                chaosModeEnabled={chaosModeEnabled}
                setChaosModeEnabled={setChaosModeEnabled}
                audioReactiveParams={audioReactiveParams}
                setAudioReactiveParams={setAudioReactiveParams}
                audioReactiveAmount={audioReactiveAmount}
                setAudioReactiveAmount={setAudioReactiveAmount}
            />

            <SlotStackPanel
                modes={modes}
                setMode={setMode}
                activeSlot={activeSlot}
                setActiveSlot={setActiveSlot}
                slotShaderStatus={slotShaderStatus}
                slotMenuOptions={slotMenuOptions}
            />

            <ParamSlidersPanel
                activeSlot={activeSlot}
                currentShaderEntry={currentShaderEntry}
                currentParams={currentParams}
                updateSlotParam={updateSlotParam}
            />

            {/* --- Current Shader Coordinate Display --- */}
            {currentCoordinate !== null && (
                <div className="glass-card" style={{
                    borderColor: getZoneColor(currentCoordinate),
                    background: `${getZoneColor(currentCoordinate)}15`,
                    marginBottom: '12px',
                }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <span style={{ fontSize: '12px', color: '#a0a0b0' }}>Current Shader</span>
                        <span className="coordinate-badge" style={{color: getZoneColor(currentCoordinate), borderColor: `${getZoneColor(currentCoordinate)}40`, background: `${getZoneColor(currentCoordinate)}15`}}>
                            #{currentCoordinate}
                        </span>
                    </div>
                    <div style={{ fontSize: '13px', color: '#f0f0f5', marginTop: '6px', fontWeight: 500 }}>
                        {currentShaderEntry?.name}
                    </div>
                    {currentMode && (
                        <div style={{ marginTop: '8px' }}>
                            <ShaderStarRating
                                shaderId={currentMode}
                                stars={ratingMap.get(currentMode)?.stars || 0}
                                ratingCount={ratingMap.get(currentMode)?.ratingCount || 0}
                                onRate={async (id, stars) => {
                                    await rateShader(id, stars);
                                }}
                                size="small"
                            />
                        </div>
                    )}
                </div>
            )}

            <RecordingSharePanel
                isRecording={isRecording}
                recordingCountdown={recordingCountdown}
                onStartRecording={onStartRecording}
                onStopRecording={onStopRecording}
                onTakeScreenshot={onTakeScreenshot}
            />

            {/* --- Source Specific Controls --- */}
            {inputSource === 'image' && (
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
                            <div className="webcam-error" style={{borderColor: 'rgba(255,71,87,0.3)', background: 'rgba(255,71,87,0.1)', color: '#ff6b6b'}}>
                                ⚠️ {webcamError}
                            </div>
                        )}
                    </div>
                     <hr className="gold-divider" />
                    <div className="control-group">
                        <div className="gold-section-header" style={{fontSize: '12px'}}>Automation</div>
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
                        <div className="control-group glass-panel" style={{padding: '12px', marginTop: '10px'}}>
                            <div className="gold-section-header" style={{fontSize: '12px', marginTop: '0'}}>Vibe Prompt</div>
                            <div style={{display: 'flex', gap: '8px', marginTop: '8px'}}>
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
                                    style={{flex: 1}}
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
                                <div style={{fontSize: '11px', color: '#a0a0b0', marginTop: '8px', fontStyle: 'italic'}}>
                                    {aiVjMessage}
                                </div>
                            )}
                            <div style={{display: 'flex', gap: '8px', marginTop: '10px'}}>
                                <input
                                    type="text"
                                    className="glass-input"
                                    placeholder="Preset name…"
                                    value={presetName}
                                    onChange={(e) => setPresetName(e.target.value)}
                                    style={{flex: 1}}
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

                            {/* Share / save the live VJ stack as a shareable chain */}
                            {(onShareVjSet || onSaveVjSet) && (
                                <div style={{display: 'flex', gap: '8px', marginTop: '10px'}}>
                                    {onShareVjSet && (
                                        <button
                                            className="gold-outline-btn"
                                            onClick={() => onShareVjSet()}
                                            disabled={!activeShaderIds || activeShaderIds.length === 0}
                                            title="Create a shareable link for the current VJ stack"
                                            style={{flex: 1}}
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
                                            style={{flex: 1}}
                                        >
                                            💾 Save as My VJ Set
                                        </button>
                                    )}
                                </div>
                            )}
                            {onSaveVjSet && (
                                <div style={{display: 'flex', gap: '8px', marginTop: '8px'}}>
                                    <input
                                        type="text"
                                        className="glass-input"
                                        placeholder="My VJ set name…"
                                        value={vjSetName}
                                        onChange={(e) => setVjSetName(e.target.value)}
                                        style={{flex: 1}}
                                    />
                                </div>
                            )}
                        </div>
                    )}

                    {/* My VJ Sets */}
                    {onApplySharedChain && (
                        <div className="control-group glass-panel" style={{padding: '12px', marginTop: '10px'}}>
                            <div
                                className="gold-section-header"
                                style={{fontSize: '12px', marginTop: '0', display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer'}}
                                onClick={() => {
                                    setMyVjSetsOpen(o => !o);
                                    if (!myVjSetsOpen) setMyVjSets(loadMyVjSets());
                                }}
                            >
                                <span>My VJ Sets</span>
                                <span style={{transform: myVjSetsOpen ? 'rotate(180deg)' : 'rotate(0deg)', transition: 'transform 0.2s'}}>▼</span>
                            </div>
                            {myVjSetsOpen && (
                                <div style={{display: 'flex', flexDirection: 'column', gap: '8px', marginTop: '8px', maxHeight: '300px', overflowY: 'auto'}}>
                                    {myVjSets.length === 0 && (
                                        <div style={{fontSize: '12px', color: '#a0a0b0', fontStyle: 'italic', textAlign: 'center'}}>
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
                                                <div style={{fontSize: '12px', fontWeight: 600, color: '#ffd700'}}>{set.name}</div>
                                                <div style={{fontSize: '11px', color: '#a0a0b0', fontStyle: 'italic', margin: '4px 0'}}>{vibeDisplay}</div>
                                                <div style={{display: 'flex', gap: '6px', marginTop: '6px'}}>
                                                    <button
                                                        className="gold-outline-btn"
                                                        style={{fontSize: '11px', padding: '4px 10px', flex: 1}}
                                                        onClick={() => {
                                                            const chain = decodeChain(set.chainString);
                                                            if (chain) onApplySharedChain(chain);
                                                        }}
                                                    >
                                                        Load
                                                    </button>
                                                    <button
                                                        className="gold-outline-btn"
                                                        style={{fontSize: '11px', padding: '4px 10px'}}
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

                    <div className="control-group glass-panel" style={{padding: '12px', marginTop: '10px'}}>
                        <div
                            className="gold-section-header"
                            style={{fontSize: '12px', marginTop: '0', display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer'}}
                            onClick={() => setAutoTransitionOpen(o => !o)}
                        >
                            <span>Auto Transition</span>
                            <span style={{transform: autoTransitionOpen ? 'rotate(180deg)' : 'rotate(0deg)', transition: 'transform 0.2s'}}>▼</span>
                        </div>
                        {autoTransitionOpen && (
                            <div style={{display: 'flex', flexDirection: 'column', gap: '8px', marginTop: '8px'}}>
                                <label style={{display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: '12px'}}>
                                    <span>Enabled</span>
                                    <input
                                        type="checkbox"
                                        checked={autoTransitionEnabled}
                                        onChange={(e) => setAutoTransitionEnabled(e.target.checked)}
                                        disabled={!isAiVjMode}
                                    />
                                </label>
                                <label style={{fontSize: '12px'}}>
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
                                    <label style={{fontSize: '12px'}}>
                                        Interval: {(autoTransitionIntervalMs / 1000).toFixed(1)}s
                                        <input
                                            type="range"
                                            min={1000}
                                            max={20000}
                                            step={250}
                                            value={autoTransitionIntervalMs}
                                            onChange={(e) => setAutoTransitionIntervalMs(Number(e.target.value))}
                                            style={{width: '100%'}}
                                        />
                                    </label>
                                )}
                                <label style={{fontSize: '12px'}}>
                                    Duration: {(autoTransitionDurationMs / 1000).toFixed(1)}s
                                    <input
                                        type="range"
                                        min={200}
                                        max={10000}
                                        step={100}
                                        value={autoTransitionDurationMs}
                                        onChange={(e) => setAutoTransitionDurationMs(Number(e.target.value))}
                                        style={{width: '100%'}}
                                    />
                                </label>
                                <label style={{fontSize: '12px'}}>
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

                    {/* VJ History */}
                    <div className="control-group glass-panel" style={{padding: '12px', marginTop: '10px'}}>
                        <div
                            className="gold-section-header"
                            style={{fontSize: '12px', marginTop: '0', display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer'}}
                            onClick={() => setHistoryOpen(o => !o)}
                        >
                            <span>VJ History</span>
                            <span style={{transform: historyOpen ? 'rotate(180deg)' : 'rotate(0deg)', transition: 'transform 0.2s'}}>▼</span>
                        </div>
                        {historyOpen && (
                            <>
                                <div style={{display: 'flex', justifyContent: 'flex-end', marginTop: '8px', marginBottom: '8px'}}>
                                    <button
                                        className="gold-outline-btn"
                                        style={{fontSize: '11px', padding: '4px 10px'}}
                                        onClick={() => {
                                            clearVJHistory();
                                            setHistory([]);
                                        }}
                                    >
                                        Clear History
                                    </button>
                                </div>
                                <div style={{display: 'flex', flexDirection: 'column', gap: '8px', maxHeight: '300px', overflowY: 'auto'}}>
                                    {history.length === 0 && (
                                        <div style={{fontSize: '12px', color: '#a0a0b0', fontStyle: 'italic', textAlign: 'center'}}>
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
                                                <div style={{fontSize: '12px', color: '#FFD700', fontWeight: 500, marginBottom: '4px'}}>
                                                    {vibeDisplay}
                                                </div>
                                                <div style={{fontSize: '10px', color: 'rgba(255,255,255,0.5)', marginBottom: '6px'}}>
                                                    {idDisplay} • {formatRelativeTime(entry.timestamp)}
                                                </div>
                                                <div style={{display: 'flex', gap: '6px'}}>
                                                    <button
                                                        className="gold-outline-btn"
                                                        style={{fontSize: '11px', padding: '3px 8px', flex: 1}}
                                                        onClick={() => {
                                                            if (onUpdateStack) onUpdateStack(entry.shaderIds);
                                                            if (onUpdateParams) onUpdateParams(entry.params);
                                                        }}
                                                    >
                                                        Restore
                                                    </button>
                                                    <button
                                                        className="gold-outline-btn"
                                                        style={{fontSize: '11px', padding: '3px 8px', flex: 1}}
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

                    {/* Presets Panel */}
                    <div className="control-group glass-panel" style={{padding: '12px', marginTop: '10px'}}>
                        <div
                            className="gold-section-header"
                            style={{fontSize: '12px', marginTop: '0', display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer'}}
                            onClick={() => setPresetsOpen(o => !o)}
                        >
                            <span>Presets</span>
                            <span style={{transform: presetsOpen ? 'rotate(180deg)' : 'rotate(0deg)', transition: 'transform 0.2s'}}>▼</span>
                        </div>
                        {presetsOpen && (
                            <div style={{display: 'flex', flexDirection: 'column', gap: '8px', maxHeight: '300px', overflowY: 'auto', marginTop: '8px'}}>
                                {presets.length === 0 && (
                                    <div style={{fontSize: '12px', color: '#a0a0b0', fontStyle: 'italic', textAlign: 'center'}}>
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
                                            <div style={{fontSize: '12px', color: '#FFD700', fontWeight: 500, marginBottom: '4px'}}>
                                                {preset.name}
                                            </div>
                                            <div style={{fontSize: '10px', color: 'rgba(255,255,255,0.5)', marginBottom: '6px'}}>
                                                {idDisplay} • {formatRelativeTime(preset.timestamp)}
                                            </div>
                                            <div style={{display: 'flex', gap: '6px'}}>
                                                <button
                                                    className="gold-outline-btn"
                                                    style={{fontSize: '11px', padding: '3px 8px', flex: 1}}
                                                    onClick={() => {
                                                        if (onUpdateStack) onUpdateStack(preset.shaderIds);
                                                        if (onUpdateParams) onUpdateParams(preset.params);
                                                    }}
                                                >
                                                    Restore
                                                </button>
                                                <button
                                                    className="gold-outline-btn"
                                                    style={{fontSize: '11px', padding: '3px 8px', flex: 1}}
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

                    {/* Multi-Slot Chain Sharing */}
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
            )}

            {inputSource === 'video' && (
                <div className="control-group glass-panel" style={{marginTop: '10px', padding: '12px'}}>
                     <div className="gold-section-header" style={{fontSize: '12px', marginTop: '0'}}>Select Video</div>
                     <select
                        value={selectedVideo}
                        onChange={(e) => {
                            setSelectedVideo(e.target.value);
                            setInputSource('video');
                            if (setVideoB3hdMode) setVideoB3hdMode(false);
                        }}
                        className="glass-select"
                        style={{marginBottom: '10px'}}
                     >
                        <option value="" disabled>Select a Video...</option>
                        {videoList.map((v) => {
                            const fileName = v.title || v.url.split('/').pop() || v.url;
                            const durationLabel = typeof v.duration === 'number' ? ` (${Math.round(v.duration)}s)` : '';
                            return (
                                <option key={v.url} value={v.url}>
                                    {fileName}{durationLabel}
                                </option>
                            );
                        })}
                     </select>

                     {/* B3HD Mode Toggle */}
                     {setVideoB3hdMode && (
                        <label style={{display: 'flex', alignItems: 'center', color: '#a0a0b0', fontSize: '13px', marginBottom: '10px'}}>
                            <input type="checkbox" className="gold-checkbox" checked={!!videoB3hdMode} onChange={(e) => setVideoB3hdMode(e.target.checked)} style={{marginRight: '8px'}}/> B3HD Rotation Mode
                        </label>
                     )}

                     {/* B3HD Controls */}
                     {videoB3hdMode && setB3hdSegmentLength && setB3hdIntervalSeconds && (
                        <>
                            <div style={{marginBottom: '10px'}}>
                                <label style={{display: 'block', color: '#a0a0b0', fontSize: '12px', marginBottom: '4px'}}>
                                    Clip Duration: {b3hdSegmentLength}s
                                </label>
                                <input type="range" className="glass-range" min="1" max="60" step="1"
                                    value={b3hdSegmentLength}
                                    onChange={(e) => setB3hdSegmentLength(Number(e.target.value))}
                                    style={{width: '100%'}}
                                />
                            </div>
                            <div style={{marginBottom: '10px'}}>
                                <label style={{display: 'block', color: '#a0a0b0', fontSize: '12px', marginBottom: '4px'}}>
                                    Time Between Clips: {b3hdIntervalSeconds}s
                                </label>
                                <input type="range" className="glass-range" min="0" max="10" step="0.5"
                                    value={b3hdIntervalSeconds}
                                    onChange={(e) => setB3hdIntervalSeconds(Number(e.target.value))}
                                    style={{width: '100%'}}
                                />
                            </div>
                            {currentSegment && (
                                <div style={{color: '#888', fontSize: '11px', marginBottom: '8px'}}>
                                    Now playing: {currentSegment.video.title || currentSegment.video.url.split('/').pop()}<br/>
                                    Segment: {currentSegment.start.toFixed(1)}s – {currentSegment.end.toFixed(1)}s
                                </div>
                            )}
                        </>
                     )}

                     <button className="gold-outline-btn" onClick={onUploadVideoTrigger} style={{width: '100%', marginBottom: '10px'}}>Upload Video</button>
                     <label style={{display: 'flex', alignItems: 'center', color: '#a0a0b0', fontSize: '13px'}}>
                        <input type="checkbox" className="gold-checkbox" checked={isMuted} onChange={(e) => setIsMuted(e.target.checked)} style={{marginRight: '8px'}}/> Mute Audio
                     </label>
                </div>
            )}

            {/* --- Webcam Shader Suggestions --- */}
            {showWebcamShaderSuggestions && isWebcamActive && (
                <div className="glass-panel" style={{padding: '15px', marginTop: '15px'}}>
                    <div className="gold-section-header" style={{fontSize: '12px', marginTop: '0'}}>
                        <span>✨ Fun Effects for Webcam</span>
                    </div>
                    <div style={{display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: '8px'}}>
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
            )}

            {inputSource === 'generative' && activeGenerativeShader && setActiveGenerativeShader && (
                <div className="control-group glass-panel" style={{marginTop: '10px', padding: '12px'}}>
                     <div className="gold-section-header" style={{fontSize: '12px', marginTop: '0'}}>Generative Shader</div>
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
                            onClick={() => setGalleryOpenFor('generative')}
                            style={{ cursor: 'pointer', fontSize: '13px', padding: '6px 8px' }}
                         >
                            🖼️
                         </button>
                     </div>
                     <div style={{fontSize: '11px', color: '#a0a0b0', fontStyle: 'italic', padding: '8px 0 0 0'}}>
                         Move mouse to interact. Click/Drag for more effects.
                     </div>
                </div>
            )}

            {galleryOpenFor === 'generative' && (
                <ShaderGallery
                    options={generativeMenuOptions}
                    value={activeGenerativeShader}
                    onSelect={(id) => { setActiveGenerativeShader?.(id); setGalleryOpenFor(null); }}
                    onClose={() => setGalleryOpenFor(null)}
                />
            )}

            {/* --- Live Stream Section --- */}
            {/* Live Stream Tab */}
            {inputSource === 'live' && (
                <LiveStreamPanel 
                    liveStreamUrl={liveStreamUrl}
                    onLiveStreamLoaded={onLiveStreamLoaded}
                    onExitLiveStream={onExitLiveStream}
                />
            )}




            <AdvancedDebugPanel
                devToolsOpen={devToolsOpen}
                setDevToolsOpen={setDevToolsOpen}
                onOpenShaderScanner={onOpenShaderScanner}
                activeRendererType={activeRendererType}
                onSwitchRenderer={onSwitchRenderer}
                onOpenCoordinateBrowser={() => setShowCoordinateBrowser(true)}
                onOpenStorageBrowser={onOpenStorageBrowser}
            />

        </div>
    );
};


export default ControlsContainer;
