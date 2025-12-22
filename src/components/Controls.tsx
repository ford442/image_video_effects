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
                <label>Input Source:</label>
                <div style={{ display: 'inline-block', marginLeft: '10px' }}>
                    <label style={{ marginRight: '10px', cursor: 'pointer' }}>
                        <input
                            type="radio"
                            name="inputSource"
                            value="image"
                            checked={inputSource === 'image'}
                            onChange={() => setInputSource('image')}
                        /> Image
                    </label>
                    <label style={{ marginRight: '10px', cursor: 'pointer' }}>
                        <input
                            type="radio"
                            name="inputSource"
                            value="video"
                            checked={inputSource === 'video'}
                            onChange={() => setInputSource('video')}
                        /> Video
                    </label>
                    <label style={{ cursor: 'pointer' }}>
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
                <label htmlFor="category-select">Effect Filter:</label>
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
            <div className="stack-controls" style={{border: '1px solid #444', padding: '10px', margin: '10px 0', borderRadius: '5px'}}>
                <div style={{fontWeight: 'bold', marginBottom: '5px'}}>Effect Stack</div>
                {[0, 1, 2].map(index => (
                    <div key={index} className="control-group" style={{ display: 'flex', alignItems: 'center', backgroundColor: activeSlot === index ? '#334' : 'transparent', padding: '5px', borderRadius: '4px' }}>
                        <input
                            type="radio"
                            name="activeSlot"
                            checked={activeSlot === index}
                            onChange={() => setActiveSlot(index)}
                            style={{marginRight: '10px'}}
                        />
                        <label style={{width: '60px'}}>Slot {index + 1}:</label>
                        <select
                            value={modes[index]}
                            onChange={(e) => setMode(index, e.target.value as RenderMode)}
                            style={{flexGrow: 1}}
                        >
                            <option value="none">None</option>
                            {currentModes.map(entry => (
                                <option key={entry.id} value={entry.id}>{entry.name}</option>
                            ))}
                        </select>
                    </div>
                ))}
            </div>

            {/* --- Source Specific Controls --- */}
            {inputSource === 'video' && (
                <div className="control-group" style={{alignItems: 'flex-start', flexDirection: 'column'}}>
                      <div style={{marginBottom: '5px'}}>
                        <button onClick={onUploadVideoTrigger} style={{marginRight: '10px'}}>Upload Video</button>
                        <label style={{ marginLeft: '10px' }}>
                            <input type="checkbox" checked={isMuted} onChange={(e) => setIsMuted(e.target.checked)} /> Mute
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
                    <div className="control-group">
                        <button onClick={onUploadImageTrigger}>Upload Image</button>
                        <button onClick={onNewImage}>Load Random Image</button>
                        <button onClick={onLoadModel} disabled={isModelLoaded}>
                            {isModelLoaded ? 'AI Model Loaded' : 'Load AI Model'}
                        </button>
                    </div>
                    <div className="control-group">
                        <label htmlFor="auto-change-toggle">Auto Change:</label>
                        <input type="checkbox" id="auto-change-toggle" checked={autoChangeEnabled} onChange={(e) => setAutoChangeEnabled(e.target.checked)} />
                    </div>
                    {autoChangeEnabled && (
                        <div className="control-group">
                            <label htmlFor="delay-slider">Delay ({autoChangeDelay}s):</label>
                            <input type="range" id="delay-slider" min="1" max="10" step="1" value={autoChangeDelay} onChange={(e) => setAutoChangeDelay(Number(e.target.value))} />
                        </div>
                    )}
                </>
            )}

            {/* --- Global View Controls --- */}
            <div className="control-group">
                <label htmlFor="zoom-slider">Zoom:</label>
                <input type="range" id="zoom-slider" min="50" max="200" value={zoom * 100} onChange={(e) => setZoom(parseFloat(e.target.value) / 100)} />
            </div>
            <div className="control-group">
                <label htmlFor="pan-x-slider">Pan X:</label>
                <input type="range" id="pan-x-slider" min="0" max="200" value={panX * 100} onChange={(e) => setPanX(parseFloat(e.target.value) / 100)} />
            </div>
            <div className="control-group">
                <label htmlFor="pan-y-slider">Pan Y:</label>
                <input type="range" id="pan-y-slider" min="0" max="200" value={panY * 100} onChange={(e) => setPanY(parseFloat(e.target.value) / 100)} />
            </div>

            {/* --- Active Slot Parameter Controls --- */}
            <hr style={{ borderColor: '#444', margin: '15px 0' }} />
            <div style={{ fontWeight: 'bold', marginBottom: '10px' }}>
                Slot {activeSlot + 1} Controls ({modes[activeSlot] === 'none' ? 'Empty' : modes[activeSlot]})
            </div>

            {currentMode === 'infinite-zoom' && (
                <>
                    <div className="control-group">
                        <label>Light Strength: {currentParams.lightStrength?.toFixed(1)}</label>
                        <input type="range" min="0" max="5" step="0.1" value={currentParams.lightStrength} onChange={(e) => updateSlotParam(activeSlot, { lightStrength: parseFloat(e.target.value) })} />
                    </div>
                    <div className="control-group">
                        <label>Ambient: {currentParams.ambient?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.05" value={currentParams.ambient} onChange={(e) => updateSlotParam(activeSlot, { ambient: parseFloat(e.target.value) })} />
                    </div>
                    <div className="control-group">
                        <label>Normal Strength: {currentParams.normalStrength?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={currentParams.normalStrength} onChange={(e) => updateSlotParam(activeSlot, { normalStrength: parseFloat(e.target.value) })} />
                    </div>
                    <div className="control-group">
                        <label>Fog Falloff: {currentParams.fogFalloff?.toFixed(1)}</label>
                        <input type="range" min="0.1" max="10" step="0.1" value={currentParams.fogFalloff} onChange={(e) => updateSlotParam(activeSlot, { fogFalloff: parseFloat(e.target.value) })} />
                    </div>
                    <div className="control-group">
                        <label>Depth Threshold: {currentParams.depthThreshold?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={currentParams.depthThreshold} onChange={(e) => updateSlotParam(activeSlot, { depthThreshold: parseFloat(e.target.value) })} />
                    </div>
                </>
            )}

            {currentMode !== 'none' && currentMode !== 'infinite-zoom' && currentShaderEntry && (
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
                                <label>{param.name}: {val?.toFixed(2)}</label>
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
                    
                    {/* Fallback for shaders without metadata (should not happen often) */}
                    {(!currentShaderEntry.params || currentShaderEntry.params.length === 0) && (
                         <>
                            <div className="control-group">
                                <label>Param 1: {currentParams.zoomParam1?.toFixed(2)}</label>
                                <input type="range" min="0" max="1" step="0.01" value={currentParams.zoomParam1} onChange={(e) => updateSlotParam(activeSlot, { zoomParam1: parseFloat(e.target.value) })} />
                            </div>
                            <div className="control-group">
                                <label>Param 2: {currentParams.zoomParam2?.toFixed(2)}</label>
                                <input type="range" min="0" max="1" step="0.01" value={currentParams.zoomParam2} onChange={(e) => updateSlotParam(activeSlot, { zoomParam2: parseFloat(e.target.value) })} />
                            </div>
                            <div className="control-group">
                                <label>Param 3: {currentParams.zoomParam3?.toFixed(2)}</label>
                                <input type="range" min="0" max="1" step="0.01" value={currentParams.zoomParam3} onChange={(e) => updateSlotParam(activeSlot, { zoomParam3: parseFloat(e.target.value) })} />
                            </div>
                            <div className="control-group">
                                <label>Param 4: {currentParams.zoomParam4?.toFixed(2)}</label>
                                <input type="range" min="0" max="1" step="0.01" value={currentParams.zoomParam4} onChange={(e) => updateSlotParam(activeSlot, { zoomParam4: parseFloat(e.target.value) })} />
                            </div>
                         </>
                    )}
                </>
            )}
        </div>
    );
};

export default Controls;