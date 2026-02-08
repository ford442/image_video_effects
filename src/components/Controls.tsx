import React from 'react';
import { RenderMode, ShaderEntry, ShaderCategory, InputSource, SlotParams } from '../renderer/types';
import { AIStatus } from '../AutoDJ';

interface ControlsProps {
    modes: RenderMode[];
    setMode: (index: number, mode: RenderMode) => void;
    activeSlot: number;
    setActiveSlot: (index: number) => void;
    slotParams: SlotParams[];
    updateSlotParam: (slotIndex: number, updates: Partial<SlotParams>) => void;
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
}

const Controls: React.FC<ControlsProps> = ({
    modes, setMode,
    activeSlot, setActiveSlot,
    slotParams, updateSlotParam,
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
    aiVjStatus
}) => {
    // Filter modes based on category
    const shaderEntries = availableModes.filter(entry => entry.category === 'shader');
    const imageEntries = availableModes.filter(entry => entry.category === 'image');

    const getCurrentCategoryModes = () => {
        return shaderCategory === 'shader' ? shaderEntries : imageEntries;
    };

    const currentModes = getCurrentCategoryModes();
    const currentMode = modes[activeSlot];
    const currentParams = slotParams[activeSlot];
    const currentShaderEntry = availableModes.find(m => m.id === currentMode);

    const getAiVjButtonText = () => {
        if (isAiVjMode) return 'Stop AI VJ';
        if (aiVjStatus === 'loading-models' || aiVjStatus === 'generating') return 'AI is working...';
        return 'Start AI VJ';
    };

    return (
        <div className="controls">
            {/* --- Input Source Selection --- */}
            <div className="control-group">
                <label>Input Source</label>
                <div className="radio-group">
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
                </div>
            </div>

            <div className="control-group">
                <label htmlFor="category-select">Effect Filter</label>
                <select id="category-select" value={shaderCategory} onChange={(e) => setShaderCategory(e.target.value as ShaderCategory)}>
                    <option value="image">Effects / Filters</option>
                    <option value="shader">Procedural Generation</option>
                </select>
            </div>

            {/* --- Stack / Slot Selection --- */}
            <div className="stack-controls">
                {[0, 1, 2].map(i => (
                    <div
                        key={i}
                        className={`stack-slot ${activeSlot === i ? 'active' : ''}`}
                        onClick={() => setActiveSlot(i)}
                        style={{
                            padding: '8px',
                            border: activeSlot === i ? '1px solid #61dafb' : '1px solid #333',
                            marginBottom: '5px',
                            background: activeSlot === i ? 'rgba(97, 218, 251, 0.1)' : 'transparent',
                            cursor: 'pointer'
                        }}
                    >
                        <div style={{marginBottom: '4px', fontSize: '12px', color: activeSlot === i ? '#61dafb' : '#888'}}>Slot {i + 1}</div>
                        <select
                            value={modes[i]}
                            onChange={(e) => setMode(i, e.target.value)}
                            onClick={(e) => e.stopPropagation()}
                            style={{width: '100%'}}
                        >
                            <option value="none">None</option>
                            {currentModes.map(m => (
                                <option key={m.id} value={m.id}>{m.name}</option>
                            ))}
                            {/* Always include current mode if it's not in the list (to avoid it disappearing) */}
                            {modes[i] !== 'none' && !currentModes.find(m => m.id === modes[i]) && (
                                <option value={modes[i]}>{availableModes.find(m => m.id === modes[i])?.name || modes[i]}</option>
                            )}
                        </select>
                    </div>
                ))}
            </div>

            {/* --- Source Specific Controls --- */}
            {inputSource === 'image' && (
                <>
                    <div className="control-group" style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px', marginTop: '10px' }}>
                        <button onClick={onUploadImageTrigger}>Upload Img</button>
                        <button onClick={onNewImage}>Random Img</button>
                    </div>
                     <hr style={{borderColor: 'rgba(255, 255, 255, 0.1)', margin: '15px 0'}}/>
                    <div className="control-group">
                        <div style={{fontWeight: 'bold', marginBottom: '8px', color: '#61dafb', fontSize: '13px'}}>Automation</div>
                         <button onClick={onLoadModel} disabled={isModelLoaded}>
                            {isModelLoaded ? 'Depth Model Loaded' : 'Load Depth Model'}
                        </button>
                    </div>

                    <div className="control-group">
                        <button onClick={onToggleAiVj} disabled={aiVjStatus === 'loading-models' || aiVjStatus === 'generating'}>
                            {getAiVjButtonText()}
                        </button>
                    </div>

                    <div className="control-group" style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between'}}>
                        <label htmlFor="auto-change-toggle" style={{marginBottom: 0, color: isAiVjMode ? '#666' : '#ccc' }} title={isAiVjMode ? 'Disabled while AI VJ is active' : ''}>Manual Auto-Switch</label>
                        <input type="checkbox" id="auto-change-toggle" checked={autoChangeEnabled} onChange={(e) => setAutoChangeEnabled(e.target.checked)} disabled={isAiVjMode} style={{width: 'auto'}} />
                    </div>

                    {autoChangeEnabled && !isAiVjMode && (
                        <div className="control-group">
                            <label htmlFor="delay-slider">Switch Delay: {autoChangeDelay}s</label>
                            <input type="range" id="delay-slider" min="1" max="10" step="1" value={autoChangeDelay} onChange={(e) => setAutoChangeDelay(Number(e.target.value))} />
                        </div>
                    )}
                </>
            )}
            
            {inputSource === 'video' && (
                <div className="control-group" style={{marginTop: '10px'}}>
                     <div style={{marginBottom: '5px'}}>Select Video:</div>
                     <select
                        value={selectedVideo}
                        onChange={(e) => {
                            setSelectedVideo(e.target.value);
                            setInputSource('video');
                        }}
                        className="control-select"
                        style={{width: '100%', marginBottom: '8px'}}
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
                     <button onClick={onUploadVideoTrigger} style={{width: '100%', marginBottom: '8px'}}>Upload Video</button>
                     <label style={{display: 'flex', alignItems: 'center'}}>
                        <input type="checkbox" checked={isMuted} onChange={(e) => setIsMuted(e.target.checked)} style={{marginRight: '5px'}}/> Mute Audio
                     </label>
                </div>
            )}

            {inputSource === 'generative' && activeGenerativeShader && setActiveGenerativeShader && (
                <div className="control-group" style={{marginTop: '10px'}}>
                     <div style={{marginBottom: '5px'}}>Input Source:</div>
                     <select value={activeGenerativeShader} onChange={(e) => setActiveGenerativeShader(e.target.value)} style={{width: '100%', marginBottom: '8px'}}>
                        {availableModes.filter(m => m.category === 'generative').map(g => (
                             <option key={g.id} value={g.id}>{g.name}</option>
                        ))}
                     </select>
                     <div style={{fontSize: '11px', color: '#888', fontStyle: 'italic', padding: '5px 0'}}>
                         Move mouse to interact. Click/Drag for more effects.
                     </div>
                </div>
            )}


            <hr style={{borderColor: 'rgba(255, 255, 255, 0.1)', margin: '15px 0'}}/>

            {/* --- View Controls (Zoom/Pan) --- */}
            <div style={{ fontWeight: 'bold', marginBottom: '8px', color: '#61dafb', fontSize: '14px' }}>
                View Controls
            </div>
            <div className="control-group view-controls-grid">
                <label>Zoom: {zoom.toFixed(2)}x</label>
                <input type="range" min="0.1" max="5.0" step="0.01" value={zoom} onChange={(e) => setZoom(parseFloat(e.target.value))} />
            </div>
            <div className="control-group view-controls-grid">
                <label>Pan X: {panX.toFixed(2)}</label>
                <input type="range" min="-2.0" max="2.0" step="0.01" value={panX} onChange={(e) => setPanX(parseFloat(e.target.value))} />
            </div>
            <div className="control-group view-controls-grid">
                <label>Pan Y: {panY.toFixed(2)}</label>
                <input type="range" min="-2.0" max="2.0" step="0.01" value={panY} onChange={(e) => setPanY(parseFloat(e.target.value))} />
            </div>

            <hr style={{borderColor: 'rgba(255, 255, 255, 0.1)', margin: '15px 0'}}/>

            {/* --- Slot Parameter Controls --- */}
            <div style={{ fontWeight: 'bold', marginBottom: '8px', color: '#61dafb', fontSize: '14px' }}>
                Shader Parameters
                <span style={{fontWeight: 'normal', color: '#888', marginLeft: '8px', fontSize: '12px'}}>
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
                        <label htmlFor={`param-${param.id}`} style={{display: 'flex', justifyContent: 'space-between'}}>
                            <span>{param.name}</span>
                            <span style={{opacity: 0.7, fontSize: '11px'}}>{val.toFixed(2)}</span>
                        </label>
                        <input
                            id={`param-${param.id}`}
                            type="range"
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
                <div style={{color: '#888', fontStyle: 'italic', padding: '5px 0', fontSize: '11px', textAlign: 'center'}}>
                    +{currentShaderEntry.params.length - 6} more params available in shader file
                </div>
            )}
            
            {!currentShaderEntry && (
                <div style={{color: '#888', fontStyle: 'italic', padding: '10px'}}>
                    Select an effect for this slot to see parameters.
                </div>
            )}
        </div>
    );
};

export default Controls;
