import React, { useState, useEffect, useMemo } from 'react';
import { RenderMode, ShaderEntry, ShaderCategory, InputSource, SlotParams } from '../renderer/types';
import { AIStatus } from '../AutoDJ';
// @ts-ignore
import shaderCoordinates from '../shader_coordinates.json';
import { ShaderMegaMenu } from './ShaderMegaMenu';
import type { ShaderMegaMenuOption } from './ShaderMegaMenu';
import '../styles/gold-glass-theme.css';

// --- Types for Coordinate System ---
interface ShaderCoordData {
  coordinate: number;
  name: string;
  category: string;
  features: string[];
  tags: string[];
}

interface ControlsProps {
    modes: RenderMode[];
    setMode: (index: number, mode: RenderMode) => void;
    activeSlot: number;
    setActiveSlot: (index: number) => void;
    slotParams: SlotParams[];
    updateSlotParam: (slotIndex: number, updates: Partial<SlotParams>) => void;
    slotShaderStatus?: Array<'idle' | 'loading' | 'error'>;
    shaderCategory: ShaderCategory;
    setShaderCategory: (category: ShaderCategory) => void;
    zoom: number;
    setZoom: (zoom: number) => void;
    panX: number;
    setPanX: (panX: number) => void;
    panY: number;
    setPanY: (panY: number) => void;
    onNewImage: () => void;
    autoChangeEnabled: boolean;
    setAutoChangeEnabled: (enabled: boolean) => void;
    autoChangeDelay: number;
    setAutoChangeDelay: (delay: number) => void;
    onLoadModel: () => void;
    isModelLoaded: boolean;
    availableModes: ShaderEntry[];
    inputSource: InputSource;
    setInputSource: (source: InputSource) => void;
    videoList: string[];
    selectedVideo: string;
    setSelectedVideo: (video: string) => void;
    isMuted: boolean;
    setIsMuted: (muted: boolean) => void;
    onUploadImageTrigger: () => void;
    onUploadVideoTrigger: () => void;
    // Generative Props
    activeGenerativeShader?: string;
    setActiveGenerativeShader?: (id: string) => void;
    // AI VJ Props
    isAiVjMode: boolean;
    onToggleAiVj: () => void;
    aiVjStatus: AIStatus;
    // Webcam Props
    isWebcamActive?: boolean;
    onStartWebcam?: () => void;
    onStopWebcam?: () => void;
    webcamError?: string | null;
    showWebcamShaderSuggestions?: boolean;
    webcamFunShaders?: string[];
    onApplyWebcamShader?: (shaderId: string) => void;
    // Roulette Props
    onRoulette?: () => void;
    onRandomizeAllSlots?: () => void;
    isRouletteActive?: boolean;
    chaosModeEnabled?: boolean;
    setChaosModeEnabled?: (enabled: boolean) => void;
    // Recording Props
    isRecording?: boolean;
    recordingCountdown?: number;
    onStartRecording?: () => void;
    onStopRecording?: () => void;
    // Live Stream Props
    liveStreamUrl?: string;
    onLiveStreamLoaded?: (url: string) => void;
    onExitLiveStream?: () => void;
    // Dev Tools Props
    onOpenShaderScanner?: () => void;
    // Storage Browser Props
    onOpenStorageBrowser?: () => void;
}

// Helper function to fetch Bilibili live stream URL
async function getBilibiliLiveM3U8(roomId: string): Promise<string> {
    try {
        const res = await fetch(`https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo?room_id=${roomId}&protocol=0,1&format=0,1,2&codec=0,1&qn=10000&platform=web`);
        const data = await res.json();
        if (data.code !== 0 || !data.data?.play_url_list?.[0]) {
            throw new Error('Failed to get stream URL');
        }
        const playUrl = data.data.play_url_list[0];
        const host = playUrl.url_info?.[0]?.host;
        const extra = playUrl.url_info?.[0]?.extra;
        if (!host || !extra) {
            throw new Error('Invalid stream data');
        }
        return host + extra;
    } catch (err) {
        console.error('Bilibili API error:', err);
        throw err;
    }
}

const Controls: React.FC<ControlsProps> = ({
    modes, setMode,
    activeSlot, setActiveSlot,
    slotParams, updateSlotParam,
    slotShaderStatus = ['idle', 'idle', 'idle'],
    shaderCategory, setShaderCategory,
    zoom, setZoom,
    panX, setPanX,
    panY, setPanY,
    onNewImage,
    autoChangeEnabled, setAutoChangeEnabled,
    autoChangeDelay, setAutoChangeDelay,
    onLoadModel, isModelLoaded,
    availableModes = [],
    inputSource, setInputSource,
    videoList, selectedVideo, setSelectedVideo,
    isMuted, setIsMuted,
    onUploadImageTrigger,
    onUploadVideoTrigger,
    activeGenerativeShader, setActiveGenerativeShader,
    isAiVjMode,
    onToggleAiVj,
    aiVjStatus,
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
    isRecording = false,
    recordingCountdown = 8,
    onStartRecording,
    onStopRecording,
    liveStreamUrl,
    onLiveStreamLoaded,
    onExitLiveStream,
    onOpenShaderScanner,
    onOpenStorageBrowser
}) => {
    // --- Coordinate System State ---
    const [showCoordinateBrowser, setShowCoordinateBrowser] = useState(false);
    const [typedNumber, setTypedNumber] = useState('');
    const [showNumberOverlay, setShowNumberOverlay] = useState(false);
    const numberTimeoutRef = React.useRef<NodeJS.Timeout | null>(null);

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

    const currentModes = useMemo(() => {
        if (shaderCategory === 'generative') {
            return availableModes.filter(entry => entry.category === 'generative');
        }

        return availableModes.filter(entry => entry.category !== 'generative');
    }, [availableModes, shaderCategory]);
    const currentMode = modes[activeSlot];
    const currentParams = slotParams[activeSlot];

    const slotMenuOptions = useMemo(
        () => currentModes.map((m): ShaderMegaMenuOption => ({
            id: m.id,
            name: m.name,
            coordinate: coordMap[m.id]?.coordinate ?? null,
            category: coordMap[m.id]?.category ?? m.category,
        })),
        [currentModes, coordMap]
    );

    const generativeMenuOptions = useMemo(
        () => availableModes
            .filter(m => m.category === 'generative')
            .map((m): ShaderMegaMenuOption => ({
                id: m.id,
                name: m.name,
                coordinate: coordMap[m.id]?.coordinate ?? null,
                category: coordMap[m.id]?.category ?? m.category,
            })),
        [availableModes, coordMap]
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
            {/* Number Jump Overlay */}
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

            {/* Coordinate Browser Modal */}
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

                        {/* Spectrum Bar */}
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

                        {/* Shader Grid by Zone */}
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

            {/* --- Input Source Selection --- */}
            <div className="control-group">
                <label className="gold-section-header">Input Source</label>
                <div className="gold-radio-group">
                    <label>
                        <input
                            type="radio"
                            value="image"
                            checked={inputSource === 'image'}
                            onChange={() => {
                                setInputSource('image');
                                setShaderCategory('image');
                            }}
                        /> Image
                    </label>
                    <label>
                        <input
                            type="radio"
                            value="video"
                            checked={inputSource === 'video'}
                            onChange={() => {
                                setInputSource('video');
                                setShaderCategory('image');
                            }}
                        /> Video
                    </label>
                    <label>
                        <input
                            type="radio"
                            value="webcam"
                            checked={inputSource === 'webcam'}
                            onChange={() => {
                                setInputSource('webcam');
                                setShaderCategory('image');
                            }}
                        /> Webcam
                    </label>
                    <label>
                        <input
                            type="radio"
                            value="generative"
                            checked={inputSource === 'generative'}
                            onChange={() => {
                                setInputSource('generative');
                            }}
                        /> Generative
                    </label>
                    <label>
                        <input
                            type="radio"
                            value="live"
                            checked={inputSource === 'live'}
                            onChange={() => {
                                setInputSource('live');
                            }}
                        /> 🔴 Live
                    </label>
                </div>
            </div>

            <div className="control-group">
                <label htmlFor="category-select" className="gold-section-header" style={{fontSize: '13px'}}>Effect Filter</label>
                <select id="category-select" className="glass-select" value={shaderCategory} onChange={(e) => setShaderCategory(e.target.value as ShaderCategory)}>
                    <option value="image">Effects / Filters</option>
                    <option value="generative">Procedural Generation</option>
                </select>
            </div>

            {/* --- Coordinate Browser Button --- */}
            <div className="control-group">
                <button 
                    onClick={() => setShowCoordinateBrowser(true)}
                    className="coord-browser-btn"
                >
                    <span>🗂️</span>
                    <span>Browse by Coordinate (B)</span>
                </button>
                <div style={{ fontSize: '11px', color: '#a0a0b0', marginTop: '6px', textAlign: 'center' }}>
                    Tip: Type any number to jump to that shader
                </div>
            </div>

            {/* --- VPS Storage Browser Button --- */}
            {onOpenStorageBrowser && (
                <div className="control-group">
                    <button 
                        onClick={onOpenStorageBrowser}
                        className="storage-btn"
                    >
                        <span>📦</span>
                        <span>VPS Storage Browser</span>
                    </button>
                    <div style={{ fontSize: '11px', color: '#a0a0b0', marginTop: '6px', textAlign: 'center' }}>
                        Browse shaders, images & videos from VPS
                    </div>
                </div>
            )}

            {/* --- 🎰 Roulette Section --- */}
            <div className="glass-panel" style={{margin: '15px 0', padding: '15px'}}>
                <div style={{ position: 'relative', zIndex: 1 }}>
                    <button
                        onClick={onRoulette}
                        className={`gold-btn ${isRouletteActive ? 'spinning' : ''}`}
                        title="Randomize active slot shader + sliders (R)"
                        style={{width: '100%', marginBottom: '8px'}}
                    >
                        <span>🎰</span>
                        <span>Randomize Slot {activeSlot + 1}</span>
                    </button>

                    <button
                        onClick={onRandomizeAllSlots}
                        className={`gold-outline-btn ${isRouletteActive ? 'spinning' : ''}`}
                        title="Randomize all 3 shader slots + sliders"
                        style={{ width: '100%', marginTop: '8px' }}
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

                    <div className="roulette-shortcut-hint" style={{color: '#a0a0b0'}}>
                        Press <kbd style={{background: 'rgba(255,215,0,0.15)', borderColor: 'rgba(255,215,0,0.3)', color: '#FFD700'}}>R</kbd> to spin
                    </div>
                </div>
            </div>

            {/* --- ⏺️ Record & Share Section --- */}
            <div className="glass-panel" style={{padding: '15px', marginBottom: '15px'}}>
                <button 
                    onClick={isRecording ? onStopRecording : onStartRecording}
                    className={`record-btn-gold ${isRecording ? 'recording' : ''}`}
                    disabled={isRecording && recordingCountdown <= 0}
                >
                    {isRecording ? (
                        <>
                            <span>⏹️</span>
                            <span>
                                Recording {recordingCountdown}s
                            </span>
                            <span className="gold-spinner"></span>
                        </>
                    ) : (
                        <>
                            <span>⏺️</span>
                            <span>Record 8s Clip</span>
                        </>
                    )}
                </button>
                
                {isRecording && (
                    <div style={{marginTop: '10px', height: '4px', background: 'rgba(255,255,255,0.1)', borderRadius: '2px', overflow: 'hidden'}}>
                        <div 
                            style={{ 
                                height: '100%', 
                                background: 'linear-gradient(90deg, #FFD700, #D4AF37)',
                                transition: 'width 0.3s ease',
                                width: `${((8 - recordingCountdown) / 8) * 100}%` 
                            }}
                        />
                    </div>
                )}
                
                <div style={{fontSize: '11px', color: '#a0a0b0', textAlign: 'center', marginTop: '8px'}}>
                    Capture & share your creation
                </div>
            </div>

            {/* --- Stack / Slot Selection --- */}
            <div className="glass-panel" style={{padding: '12px'}}>
                <div className="gold-section-header" style={{fontSize: '12px', marginTop: '0'}}>Shader Slots</div>
                {[0, 1, 2].map(i => {
                    const slotStatus = slotShaderStatus[i] || 'idle';
                    const borderColor = slotStatus === 'error' ? '#ff4757'
                        : slotStatus === 'loading' ? '#ffa502'
                        : activeSlot === i ? '#FFD700' : 'rgba(255,215,0,0.08)';
                    const glowStyle = activeSlot === i ? 
                        {boxShadow: '0 0 20px rgba(255, 215, 0, 0.2)'} : {};
                    return (
                    <div
                        key={i}
                        className={`glass-card ${activeSlot === i ? 'gold-active' : ''}`}
                        onClick={() => setActiveSlot(i)}
                        style={{
                            padding: '10px',
                            marginBottom: '8px',
                            cursor: 'pointer',
                            borderColor: borderColor,
                            ...glowStyle
                        }}
                    >
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '6px' }}>
                            <span style={{ fontSize: '12px', color: activeSlot === i ? '#FFD700' : '#a0a0b0', fontWeight: 600 }}>Slot {i + 1}</span>
                            {slotStatus === 'loading' && (
                                <span className="gold-badge" style={{color: '#ffa502', borderColor: 'rgba(255,165,2,0.3)', background: 'rgba(255,165,2,0.1)'}}>
                                    <span className="gold-spinner" style={{width: '12px', height: '12px'}}></span>
                                    COMPILING
                                </span>
                            )}
                            {slotStatus === 'error' && (
                                <span className="gold-badge" style={{color: '#ff4757', borderColor: 'rgba(255,71,87,0.3)', background: 'rgba(255,71,87,0.1)'}}>
                                    ✕ FAILED
                                </span>
                            )}
                        </div>
                        <ShaderMegaMenu
                            options={slotMenuOptions}
                            value={modes[i]}
                            onChange={(id) => setMode(i, id as RenderMode)}
                            includeNone={true}
                            onClick={(e) => e.stopPropagation()}
                        />
                    </div>
                    );
                })}
            </div>

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
                </div>
            )}

            {/* --- Source Specific Controls --- */}
            {inputSource === 'image' && (
                <>
                    <div className="control-group" style={{ marginTop: '10px' }}>
                        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px', marginBottom: '10px' }}>
                            <button className="gold-outline-btn" onClick={onUploadImageTrigger}>📁 Upload Img</button>
                            <button className="gold-outline-btn" onClick={onNewImage}>🎲 Random Img</button>
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

                    <div className="control-group" style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between'}}>
                        <label htmlFor="auto-change-toggle" style={{marginBottom: 0, color: isAiVjMode ? '#606070' : '#a0a0b0' }} title={isAiVjMode ? 'Disabled while AI VJ is active' : ''}>Manual Auto-Switch</label>
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
            
            {inputSource === 'video' && (
                <div className="control-group glass-panel" style={{marginTop: '10px', padding: '12px'}}>
                     <div className="gold-section-header" style={{fontSize: '12px', marginTop: '0'}}>Select Video</div>
                     <select
                        value={selectedVideo}
                        onChange={(e) => {
                            setSelectedVideo(e.target.value);
                            setInputSource('video');
                        }}
                        className="glass-select"
                        style={{marginBottom: '10px'}}
                     >
                        <option value="" disabled>Select a Video...</option>
                        {videoList.map((v) => {
                            const fileName = v.split('/').pop() || v;
                            return (
                                <option key={v} value={v}>
                                    {fileName}
                                </option>
                            );
                        })}
                     </select>
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
                     <ShaderMegaMenu
                        options={generativeMenuOptions}
                        value={activeGenerativeShader}
                        onChange={setActiveGenerativeShader}
                        includeNone={false}
                     />
                     <div style={{fontSize: '11px', color: '#a0a0b0', fontStyle: 'italic', padding: '8px 0 0 0'}}>
                         Move mouse to interact. Click/Drag for more effects.
                     </div>
                </div>
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


            <hr className="gold-divider" />

            {/* --- View Controls (Zoom/Pan) --- */}
            <div className="gold-section-header">
                View Controls
            </div>
            <div className="control-group view-controls-grid">
                <label style={{color: '#a0a0b0'}}>Zoom: <span style={{color: '#FFD700'}}>{zoom.toFixed(2)}x</span></label>
                <input type="range" className="glass-range" min="0.1" max="5.0" step="0.01" value={zoom} onChange={(e) => setZoom(parseFloat(e.target.value))} />
            </div>
            <div className="control-group view-controls-grid">
                <label style={{color: '#a0a0b0'}}>Pan X: <span style={{color: '#FFD700'}}>{panX.toFixed(2)}</span></label>
                <input type="range" className="glass-range" min="-2.0" max="2.0" step="0.01" value={panX} onChange={(e) => setPanX(parseFloat(e.target.value))} />
            </div>
            <div className="control-group view-controls-grid">
                <label style={{color: '#a0a0b0'}}>Pan Y: <span style={{color: '#FFD700'}}>{panY.toFixed(2)}</span></label>
                <input type="range" className="glass-range" min="-2.0" max="2.0" step="0.01" value={panY} onChange={(e) => setPanY(parseFloat(e.target.value))} />
            </div>

            <hr className="gold-divider" />

            {/* --- Slot Parameter Controls --- */}
            <div className="gold-section-header">
                Shader Parameters
                <span style={{fontWeight: 'normal', color: '#a0a0b0', marginLeft: '8px', fontSize: '12px'}}>
                    {currentShaderEntry?.name || 'None'}
                </span>
            </div>

            <div className="params-grid">
            {currentShaderEntry?.params?.map((param, index) => {
                if (index > 5) return null; // Support up to 6 params

                let val = 0;
                if (index === 0) val = currentParams.zoomParam1;
                else if (index === 1) val = currentParams.zoomParam2;
                else if (index === 2) val = currentParams.zoomParam3;
                else if (index === 3) val = currentParams.zoomParam4;

                return (
                    <div key={param.id} className="control-group">
                        <label htmlFor={`param-${param.id}`} style={{display: 'flex', justifyContent: 'space-between', color: '#a0a0b0'}}>
                            <span>{param.name}</span>
                            <span style={{color: '#FFD700', fontSize: '11px', fontWeight: 500}}>{val.toFixed(2)}</span>
                        </label>
                        <input
                            id={`param-${param.id}`}
                            type="range"
                            className="glass-range"
                            min={param.min}
                            max={param.max}
                            step={param.step || 0.01}
                            value={val}
                            onChange={(e) => {
                                const v = parseFloat(e.target.value);
                                const update: Partial<SlotParams> = {};
                                if (index === 0) update.zoomParam1 = v;
                                else if (index === 1) update.zoomParam2 = v;
                                else if (index === 2) update.zoomParam3 = v;
                                else if (index === 3) update.zoomParam4 = v;
                                updateSlotParam(activeSlot, update);
                            }}
                        />
                    </div>
                );
            })}
            </div>

            {currentShaderEntry?.params && currentShaderEntry.params.length > 6 && (
                <div style={{color: '#a0a0b0', fontStyle: 'italic', padding: '5px 0', fontSize: '11px', textAlign: 'center'}}>
                    +<span style={{color: '#FFD700'}}>{currentShaderEntry.params.length - 6}</span> more params available in shader file
                </div>
            )}
            
            {!currentShaderEntry && (
                <div className="glass-card" style={{textAlign: 'center', padding: '15px', color: '#a0a0b0', fontStyle: 'italic'}}>
                    Select an effect for this slot to see parameters.
                </div>
            )}

            {/* --- 🔧 Dev Tools Section --- */}
            {onOpenShaderScanner && (
                <div className="dev-tools-gold">
                    <h4>
                        🔧 Dev Tools
                    </h4>
                    <button
                        onClick={onOpenShaderScanner}
                    >
                        🔍 Scan Shaders for Errors
                    </button>
                    <div style={{
                        marginTop: '6px',
                        fontSize: '10px',
                        color: '#a0a0b0',
                        textAlign: 'center'
                    }}>
                        Tests WGSL compilation on all shaders
                    </div>
                </div>
            )}
        </div>
    );
};

// Live Stream Panel Component
interface LiveStreamPanelProps {
    liveStreamUrl?: string;
    onLiveStreamLoaded?: (url: string) => void;
    onExitLiveStream?: () => void;
}

const LiveStreamPanel: React.FC<LiveStreamPanelProps> = ({
    liveStreamUrl,
    onLiveStreamLoaded,
    onExitLiveStream
}) => {
    const [liveInput, setLiveInput] = useState('');
    const [isLoading, setIsLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);

    const handleStartStream = async () => {
        if (!liveInput.trim()) return;
        
        setIsLoading(true);
        setError(null);
        
        try {
            let url = liveInput.trim();
            
            // If it's just numbers, treat as Bilibili room ID
            if (/^\d+$/.test(url)) {
                url = await getBilibiliLiveM3U8(url);
            }
            
            onLiveStreamLoaded?.(url);
        } catch (err: any) {
            setError(err.message || 'Failed to load stream');
        } finally {
            setIsLoading(false);
        }
    };

    if (liveStreamUrl) {
        return (
            <div className="glass-panel" style={{
                marginTop: '10px',
                padding: '16px',
                borderColor: 'rgba(46, 213, 115, 0.3)',
            }}>
                <h3 style={{ 
                    color: '#2ed573', 
                    fontWeight: 'bold', 
                    marginBottom: '12px',
                    fontSize: '14px'
                }}>
                    🎥 Live Stream Active
                </h3>
                
                <div className="glass-card" style={{ 
                    marginBottom: '12px',
                    fontSize: '12px'
                }}>
                    <span style={{ color: '#2ed573' }}>● Connected</span>
                    <span style={{ color: '#a0a0b0', marginLeft: '8px', wordBreak: 'break-all' }}>
                        {liveStreamUrl.length > 35 ? liveStreamUrl.substring(0, 35) + '...' : liveStreamUrl}
                    </span>
                </div>
                
                <button 
                    onClick={() => {
                        onExitLiveStream?.();
                        setLiveInput('');
                    }}
                    className="record-btn-gold"
                >
                    ⏹ Disconnect
                </button>
            </div>
        );
    }

    return (
        <div className="glass-panel" style={{
            marginTop: '10px',
            padding: '16px',
        }}>
            <h3 style={{ 
                color: '#e94560', 
                fontWeight: 'bold', 
                marginBottom: '12px',
                fontSize: '14px'
            }}>
                🎥 Live Bilibili Stream
            </h3>
            
            <input
                type="text"
                className="glass-input"
                placeholder="Bilibili Room ID or direct .m3u8 URL"
                value={liveInput}
                onChange={(e) => setLiveInput(e.target.value)}
                onKeyPress={(e) => e.key === 'Enter' && handleStartStream()}
                style={{
                    marginBottom: '12px',
                }}
            />

            {error && (
                <div className="glass-card" style={{
                    borderColor: 'rgba(255, 71, 87, 0.3)',
                    background: 'rgba(255, 71, 87, 0.1)',
                    color: '#ff6b6b',
                    fontSize: '12px',
                    marginBottom: '12px'
                }}>
                    ⚠️ {error}
                </div>
            )}

            <button
                onClick={handleStartStream}
                disabled={isLoading || !liveInput.trim()}
                className="record-btn-gold"
                style={{
                    opacity: isLoading || !liveInput.trim() ? 0.7 : 1,
                }}
            >
                {isLoading ? '⏳ Loading...' : '▶️ Start Live Stream'}
            </button>
            
            <div className="glass-card" style={{
                marginTop: '12px',
                fontSize: '11px',
                color: '#a0a0b0'
            }}>
                <strong style={{ color: '#FFD700' }}>Tip:</strong> Try room IDs like <code style={{ background: 'rgba(255,215,0,0.1)', color: '#FFD700', padding: '2px 6px', borderRadius: '4px' }}>21495945</code> or paste a direct HLS URL
            </div>
        </div>
    );
};

export default Controls;
