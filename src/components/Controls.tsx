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
}) => {
    const shaderModes = availableModes.filter(entry => entry.category !== 'image'); // Assuming 'image' category is for filters vs generators? Or vice versa?
    // Actually, based on previous code: shaderModes = category=='shader', imageModes = category=='image'.
    // Let's stick to that logic but allow user to pick any shader for the slots?
    // User said "3 slots to stack shaders".
    // Usually stacking implies image filters.
    // Let's allow all modes in the dropdown for flexibility, or filter based on category.
    // The previous UI had a Category selector.
    // Maybe we keep the Category selector to filter the options in the dropdowns?

    const shaderEntries = availableModes.filter(entry => entry.category === 'shader');
    const imageEntries = availableModes.filter(entry => entry.category === 'image'); // Most effects seem to be here
    // const videoEntries = availableModes.filter(entry => entry.category === 'video');

    const getCurrentCategoryModes = () => {
        // If the user selects a category, should it filter ALL 3 dropdowns? Yes, simplest.
        switch (shaderCategory) {
            case 'shader':
                return shaderEntries;
            case 'image':
                return imageEntries;
            default:
                return imageEntries; // Default to image effects which are the stackable ones
        }
    };

    const currentModes = getCurrentCategoryModes();

    // Helper to get params for active slot
    const currentParams = slotParams[activeSlot];
    const currentMode = modes[activeSlot];

    return (
        <div className="controls">
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
                    <label style={{ cursor: 'pointer' }}>
                        <input
                            type="radio"
                            name="inputSource"
                            value="video"
                            checked={inputSource === 'video'}
                            onChange={() => setInputSource('video')}
                        /> Video
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

            {inputSource === 'video' && (
                <div className="control-group">
                    <label htmlFor="video-select">Video:</label>
                    <select
                        id="video-select"
                        value={selectedVideo}
                        onChange={(e) => setSelectedVideo(e.target.value)}
                    >
                        {videoList.length === 0 ? <option value="" disabled>No videos found</option> :
                            videoList.map(v => <option key={v} value={v}>{v}</option>)
                        }
                    </select>
                    <label style={{ marginLeft: '10px' }}>
                        <input type="checkbox" checked={isMuted} onChange={(e) => setIsMuted(e.target.checked)} /> Mute
                    </label>
                </div>
            )}

            {inputSource === 'image' && (
                <>
                    <div className="control-group">
                        <button onClick={onLoadModel} disabled={isModelLoaded}>
                            {isModelLoaded ? 'AI Model Loaded' : 'Load AI Model'}
                        </button>
                        <button onClick={onNewImage}>Load New Random Image</button>
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

            <hr style={{ borderColor: '#444', margin: '15px 0' }} />
            <div style={{ fontWeight: 'bold', marginBottom: '10px' }}>
                Slot {activeSlot + 1} Controls ({modes[activeSlot] === 'none' ? 'Empty' : modes[activeSlot]})
            </div>

            {currentMode === 'rain' && (
                <>
                    <div className="control-group">
                        <label>Rain Speed: {currentParams.zoomParam1?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={currentParams.zoomParam1} onChange={(e) => updateSlotParam(activeSlot, { zoomParam1: parseFloat(e.target.value) })} />
                    </div>
                    <div className="control-group">
                        <label>Rain Density: {currentParams.zoomParam2?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={currentParams.zoomParam2} onChange={(e) => updateSlotParam(activeSlot, { zoomParam2: parseFloat(e.target.value) })} />
                    </div>
                    <div className="control-group">
                        <label>Wind: {currentParams.zoomParam3?.toFixed(2)}</label>
                        <input type="range" min="0" max="4" step="0.1" value={currentParams.zoomParam3} onChange={(e) => updateSlotParam(activeSlot, { zoomParam3: parseFloat(e.target.value) })} />
                    </div>
                    <div className="control-group">
                        <label>Splash/Flow: {currentParams.zoomParam4?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={currentParams.zoomParam4} onChange={(e) => updateSlotParam(activeSlot, { zoomParam4: parseFloat(e.target.value) })} />
                    </div>
                </>
            )}

            {currentMode === 'chromatic-manifold' && (
                <>
                    <div className="control-group">
                        <label>Warp Strength: {currentParams.zoomParam1?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={currentParams.zoomParam1} onChange={(e) => updateSlotParam(activeSlot, { zoomParam1: parseFloat(e.target.value) })} />
                    </div>
                    <div className="control-group">
                        <label>Curvature Strength: {currentParams.zoomParam2?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={currentParams.zoomParam2} onChange={(e) => updateSlotParam(activeSlot, { zoomParam2: parseFloat(e.target.value) })} />
                    </div>
                    <div className="control-group">
                        <label>Hue Weight: {currentParams.zoomParam3?.toFixed(2)}</label>
                        <input type="range" min="0" max="2" step="0.01" value={currentParams.zoomParam3} onChange={(e) => updateSlotParam(activeSlot, { zoomParam3: parseFloat(e.target.value) })} />
                    </div>
                    <div className="control-group">
                        <label>Feedback Strength: {currentParams.zoomParam4?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={currentParams.zoomParam4} onChange={(e) => updateSlotParam(activeSlot, { zoomParam4: parseFloat(e.target.value) })} />
                    </div>
                </>
            )}

            {currentMode === 'digital-decay' && (
                <>
                    <div className="control-group">
                        <label>Decay Intensity: {currentParams.zoomParam1?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={currentParams.zoomParam1} onChange={(e) => updateSlotParam(activeSlot, { zoomParam1: parseFloat(e.target.value) })} />
                    </div>
                    <div className="control-group">
                        <label>Block Size: {currentParams.zoomParam2?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={currentParams.zoomParam2} onChange={(e) => updateSlotParam(activeSlot, { zoomParam2: parseFloat(e.target.value) })} />
                    </div>
                    <div className="control-group">
                        <label>Corruption Speed: {currentParams.zoomParam3?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={currentParams.zoomParam3} onChange={(e) => updateSlotParam(activeSlot, { zoomParam3: parseFloat(e.target.value) })} />
                    </div>
                    <div className="control-group">
                        <label>Depth Focus: {currentParams.zoomParam4?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={currentParams.zoomParam4} onChange={(e) => updateSlotParam(activeSlot, { zoomParam4: parseFloat(e.target.value) })} />
                    </div>
                </>
            )}

            {currentMode === 'spectral-vortex' && (
                <>
                    <div className="control-group">
                        <label>Twist Strength: {currentParams.zoomParam1?.toFixed(2)}</label>
                        <input type="range" min="0" max="10" step="0.1" value={currentParams.zoomParam1} onChange={(e) => updateSlotParam(activeSlot, { zoomParam1: parseFloat(e.target.value) })} />
                    </div>
                    <div className="control-group">
                        <label>Distortion Step: {currentParams.zoomParam2?.toFixed(3)}</label>
                        <input type="range" min="0" max="0.1" step="0.001" value={currentParams.zoomParam2} onChange={(e) => updateSlotParam(activeSlot, { zoomParam2: parseFloat(e.target.value) })} />
                    </div>
                    <div className="control-group">
                        <label>Color Shift: {currentParams.zoomParam3?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={currentParams.zoomParam3} onChange={(e) => updateSlotParam(activeSlot, { zoomParam3: parseFloat(e.target.value) })} />
                    </div>
                </>
            )}

            {currentMode === 'quantum-fractal' && (
                <>
                    <div className="control-group">
                        <label>Fractal Scale: {currentParams.zoomParam1?.toFixed(2)}</label>
                        <input type="range" min="0.1" max="10" step="0.1" value={currentParams.zoomParam1} onChange={(e) => updateSlotParam(activeSlot, { zoomParam1: parseFloat(e.target.value) })} />
                    </div>
                    <div className="control-group">
                        <label>Iterations: {currentParams.zoomParam2?.toFixed(0)}</label>
                        <input type="range" min="10" max="200" step="1" value={currentParams.zoomParam2} onChange={(e) => updateSlotParam(activeSlot, { zoomParam2: parseFloat(e.target.value) })} />
                    </div>
                    <div className="control-group">
                        <label>Entanglement: {currentParams.zoomParam3?.toFixed(2)}</label>
                        <input type="range" min="0" max="2" step="0.01" value={currentParams.zoomParam3} onChange={(e) => updateSlotParam(activeSlot, { zoomParam3: parseFloat(e.target.value) })} />
                    </div>
                </>
            )}

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

            {/* Fallback for other modes that use generic params */}
            {!['rain', 'chromatic-manifold', 'digital-decay', 'spectral-vortex', 'quantum-fractal', 'infinite-zoom', 'none'].includes(currentMode) && modes[activeSlot] !== 'none' && (
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
        </div>
    );
};

export default Controls;
