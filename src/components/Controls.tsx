import React from 'react';
import { RenderMode, ShaderEntry, ShaderCategory, InputSource, SlotParams } from '../renderer/types';

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
    // New Props
    inputSource: InputSource;
    setInputSource: (source: InputSource) => void;
    videoList: string[];
    selectedVideo: string;
    setSelectedVideo: (video: string) => void;
    isMuted: boolean;
    setIsMuted: (muted: boolean) => void;
    // New Upload Triggers
    onUploadImageTrigger: () => void;
    onUploadVideoTrigger: () => void;
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
    onUploadVideoTrigger
}) => {
    const shaderEntries = availableModes.filter(entry => entry.category === 'shader');
    const imageEntries = availableModes.filter(entry => entry.category === 'image');

    const getCurrentCategoryModes = () => {
        switch (shaderCategory) {
            case 'shader':
                return shaderEntries;
            case 'image':
                return imageEntries;
            default:
                return imageEntries;
        }
    };

    const currentModes = getCurrentCategoryModes();
    
    // Determine the configuration for the currently active slot
    const currentMode = modes[activeSlot];
    const currentParams = slotParams[activeSlot];
    const currentShaderEntry = availableModes.find(m => m.id === currentMode);

    return (
        <div className="controls">
            {/* --- Input Source Selection --- */}
            <div className="control-group">
                <label>Input Source</label>
                <div style={{ display: 'flex', gap: '10px' }}>
                    <label style={{ cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '5px', color: '#ccc', fontSize: '12px' }}>
                        <input
                            type="radio"
                            name="inputSource"
                            value="image"
                            checked={inputSource === 'image'}
                            onChange={() => setInputSource('image')}
                        /> Image
                    </label>
                    <label style={{ cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '5px', color: '#ccc', fontSize: '12px' }}>
                        <input
                            type="radio"
                            name="inputSource"
                            value="video"
                            checked={inputSource === 'video'}
                            onChange={() => setInputSource('video')}
                        /> Video
                    </label>
                    <label style={{ cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '5px', color: '#ccc', fontSize: '12px' }}>
                        <input
                            type="radio"
                            name="inputSource"
                            value="webcam"
                            checked={inputSource === 'webcam'}
                            onChange={() => setInputSource('webcam')}
                        /> Webcam
                    </label>
                </div>
            </div>

            <div className="control-group">
                <label htmlFor="category-select">Effect Filter</label>
                <select
                    id="category-select"
                    value={shaderCategory}
                    onChange={(e) => setShaderCategory(e.target.value as ShaderCategory)}
                >
                    <option value="image">Effects / Filters</option>
                    <option value="shader">Procedural Generation</option>
                </select>
            </div>

            {/* --- Stack / Slot Selection --- */}
            <div className="stack-controls">
                <div style={{fontWeight: 'bold', marginBottom: '8px', color: '#61dafb', fontSize: '13px'}}>Effect Stack</div>
                {[0, 1, 2].map(index => (
                    <div key={index} style={{ display: 'flex', alignItems: 'center', backgroundColor: activeSlot === index ? 'rgba(97, 218, 251, 0.15)' : 'transparent', padding: '6px', borderRadius: '4px', marginBottom: '4px' }}>
                        <input
                            type="radio"
                            name="activeSlot"
                            checked={activeSlot === index}
                            onChange={() => setActiveSlot(index)}
                            style={{marginRight: '10px', width: 'auto', height: 'auto'}}
                        />
                        <div style={{flexGrow: 1}}>
                             <select
                                value={modes[index]}
                                onChange={(e) => setMode(index, e.target.value as RenderMode)}
                                style={{fontSize: '12px', padding: '4px'}}
                            >
                                <option value="none">Empty Slot {index + 1}</option>
                                {currentModes.map(entry => (
                                    <option key={entry.id} value={entry.id}>{entry.name}</option>
                                ))}
                            </select>
                        </div>
                    </div>
                ))}
            </div>

            {/* --- Source Specific Controls --- */}
            {inputSource === 'video' && (
                <div className="control-group">
                    <div style={{ display: 'flex', gap: '8px', marginBottom: '8px' }}>
                        <button onClick={onUploadVideoTrigger} style={{flex: 1}}>Upload Video</button>
                        <label style={{ display: 'flex', alignItems: 'center', cursor: 'pointer', fontSize: '12px' }}>
                            <input type="checkbox" checked={isMuted} onChange={(e) => setIsMuted(e.target.checked)} style={{marginRight: '5px', width: 'auto'}} /> Mute
                        </label>
                    </div>
                    <div>
                        <label htmlFor="video-select">Or Select Stock:</label>
                        <select
                            id="video-select"
                            value={selectedVideo}
                            onChange={(e) => setSelectedVideo(e.target.value)}
                        >
                            {videoList.length === 0 ? <option value="" disabled>No videos found</option> :
                                videoList.map(v => <option key={v} value={v}>{v}</option>)
                            }
                        </select>
                    </div>
                </div>
            )}

            {inputSource === 'image' && (
                <>
                    <div className="control-group" style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px' }}>
                        <button onClick={onUploadImageTrigger}>Upload Img</button>
                        <button onClick={onNewImage}>Random Img</button>
                        <button onClick={onLoadModel} disabled={isModelLoaded} style={{gridColumn: 'span 2'}}>
                            {isModelLoaded ? 'AI Model Active' : 'Enable AI Depth'}
                        </button>
                    </div>

                    <div className="control-group" style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between'}}>
                        <label htmlFor="auto-change-toggle" style={{marginBottom: 0}}>Auto-Switch Image</label>
                        <input type="checkbox" id="auto-change-toggle" checked={autoChangeEnabled} onChange={(e) => setAutoChangeEnabled(e.target.checked)} style={{width: 'auto'}} />
                    </div>

                    {autoChangeEnabled && (
                        <div className="control-group">
                            <label htmlFor="delay-slider">Switch Delay: {autoChangeDelay}s</label>
                            <input type="range" id="delay-slider" min="1" max="10" step="1" value={autoChangeDelay} onChange={(e) => setAutoChangeDelay(Number(e.target.value))} />
                        </div>
                    )}
                </>
            )}

            <hr />

            {/* --- Active Slot Parameter Controls --- */}
            <div style={{ fontWeight: 'bold', marginBottom: '10px', color: '#61dafb', fontSize: '14px' }}>
                Slot {activeSlot + 1} Settings
            </div>

            {currentMode !== 'none' && currentMode !== 'infinite-zoom' && currentShaderEntry ? (
                <>
                    {/* Dynamic Shader Params based on metadata */}
                    {currentShaderEntry.params && currentShaderEntry.params.map((param, i) => {
                        let val = 0;
                        if (i === 0) val = currentParams.zoomParam1 ?? param.default;
                        if (i === 1) val = currentParams.zoomParam2 ?? param.default;
                        if (i === 2) val = currentParams.zoomParam3 ?? param.default;
                        if (i === 3) val = currentParams.zoomParam4 ?? param.default;

                        const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
                            const v = parseFloat(e.target.value);
                            if (i === 0) updateSlotParam(activeSlot, { zoomParam1: v });
                            if (i === 1) updateSlotParam(activeSlot, { zoomParam2: v });
                            if (i === 2) updateSlotParam(activeSlot, { zoomParam3: v });
                            if (i === 3) updateSlotParam(activeSlot, { zoomParam4: v });
                        };

                        return (
                             <div className="control-group" key={param.id}>
                                <label style={{display: 'flex', justifyContent: 'space-between'}}>
                                    <span>{param.name}</span>
                                    <span>{val?.toFixed(2)}</span>
                                </label>
                                <input
                                    type="range"
                                    min={param.min}
                                    max={param.max}
                                    step={param.step || 0.01}
                                    value={val}
                                    onChange={handleChange}
                                />
                            </div>
                        );
                    })}
                    
                    {/* Fallback for shaders without metadata */}
                    {(!currentShaderEntry.params || currentShaderEntry.params.length === 0) && (
                         <div style={{fontSize: '12px', color: '#888', fontStyle: 'italic'}}>
                             No adjustable parameters for this effect.
                         </div>
                    )}
                </>
            ) : currentMode === 'infinite-zoom' ? (
                <>
                     <div className="control-group">
                        <label>Light Strength: {currentParams.lightStrength?.toFixed(1)}</label>
                        <input type="range" min="0" max="5" step="0.1" value={currentParams.lightStrength} onChange={(e) => updateSlotParam(activeSlot, { lightStrength: parseFloat(e.target.value) })} />
                    </div>
                     <div className="control-group">
                        <label>Ambient: {currentParams.ambient?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.05" value={currentParams.ambient} onChange={(e) => updateSlotParam(activeSlot, { ambient: parseFloat(e.target.value) })} />
                    </div>
                </>
            ) : (
                <div style={{fontSize: '13px', color: '#666', padding: '20px 0', textAlign: 'center'}}>
                    Select an effect for this slot to see options.
                </div>
            )}

            <hr />

            {/* --- Global View Controls --- */}
            <div className="control-group">
                <label style={{display: 'flex', justifyContent: 'space-between'}}>
                    <span>Zoom</span>
                    <span>{(zoom * 100).toFixed(0)}%</span>
                </label>
                <input type="range" id="zoom-slider" min="50" max="200" value={zoom * 100} onChange={(e) => setZoom(parseFloat(e.target.value) / 100)} />
            </div>
            <div className="control-group">
                <label style={{display: 'flex', justifyContent: 'space-between'}}>
                    <span>Pan X</span>
                    <span>{(panX * 100).toFixed(0)}%</span>
                </label>
                <input type="range" id="pan-x-slider" min="0" max="200" value={panX * 100} onChange={(e) => setPanX(parseFloat(e.target.value) / 100)} />
            </div>
            <div className="control-group">
                <label style={{display: 'flex', justifyContent: 'space-between'}}>
                    <span>Pan Y</span>
                    <span>{(panY * 100).toFixed(0)}%</span>
                </label>
                <input type="range" id="pan-y-slider" min="0" max="200" value={panY * 100} onChange={(e) => setPanY(parseFloat(e.target.value) / 100)} />
            </div>
        </div>
    );
};

export default Controls;