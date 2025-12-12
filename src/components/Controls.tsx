import React from 'react';
import { RenderMode, ShaderEntry, ShaderCategory, InputSource } from '../renderer/types';

interface ControlsProps {
    mode: RenderMode;
    setMode: (mode: RenderMode) => void;
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
    // Infinite Zoom
    lightStrength?: number;
    setLightStrength?: (val: number) => void;
    ambient?: number;
    setAmbient?: (val: number) => void;
    normalStrength?: number;
    setNormalStrength?: (val: number) => void;
    fogFalloff?: number;
    setFogFalloff?: (val: number) => void;
    depthThreshold?: number;
    setDepthThreshold?: (val: number) => void;
    // Generic Params
    zoomParam1?: number;
    setZoomParam1?: (val: number) => void;
    zoomParam2?: number;
    setZoomParam2?: (val: number) => void;
    zoomParam3?: number;
    setZoomParam3?: (val: number) => void;
    zoomParam4?: number;
    setZoomParam4?: (val: number) => void;
}

const Controls: React.FC<ControlsProps> = ({
    mode, setMode,
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
    lightStrength, setLightStrength,
    ambient, setAmbient,
    normalStrength, setNormalStrength,
    fogFalloff, setFogFalloff,
    depthThreshold, setDepthThreshold,
    zoomParam1, setZoomParam1,
    zoomParam2, setZoomParam2,
    zoomParam3, setZoomParam3,
    zoomParam4, setZoomParam4
}) => {
    const shaderModes = availableModes.filter(entry => entry.category === 'shader');
    const imageModes = availableModes.filter(entry => entry.category === 'image');
    // const videoModes = availableModes.filter(entry => entry.category === 'video');

    const handleCategoryChange = (newCategory: ShaderCategory) => {
        setShaderCategory(newCategory);
        // Set default shader for the category
        let modes: ShaderEntry[];
        switch (newCategory) {
            case 'shader':
                modes = shaderModes;
                break;
            case 'image':
                modes = imageModes;
                break;
            default:
                modes = imageModes;
                break;
        }
        // Only change mode if there are shaders available in this category
        if (modes.length > 0) {
            setMode(modes[0].id);
        }
    };

    const getCurrentCategoryModes = () => {
        switch (shaderCategory) {
            case 'shader':
                return shaderModes;
            case 'image':
                return imageModes;
            default:
                return [];
        }
    };

    const currentModes = getCurrentCategoryModes();
    const activeShader = availableModes.find(m => m.id === mode);

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
                <label htmlFor="category-select">Effect Type:</label>
                <select
                    id="category-select"
                    value={shaderCategory}
                    onChange={(e) => handleCategoryChange(e.target.value as ShaderCategory)}
                >
                    <option value="image">Effects / Filters</option>
                    <option value="shader">Procedural Generation</option>
                </select>
            </div>

            <div className="control-group">
                <label htmlFor="shader-select">Shader:</label>
                <select
                    id="shader-select"
                    value={mode}
                    onChange={(e) => setMode(e.target.value as RenderMode)}
                >
                    {currentModes.map(entry => (
                        <option key={entry.id} value={entry.id}>{entry.name}</option>
                    ))}
                    {currentModes.length === 0 && (
                        <option value="" disabled>No shaders available</option>
                    )}
                </select>
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

            {activeShader?.params && activeShader.params.length > 0 && (
                <>
                    <hr style={{ borderColor: '#444', margin: '15px 0' }} />
                    <div style={{ fontWeight: 'bold', marginBottom: '10px' }}>{activeShader.name} Controls</div>
                    {activeShader.params.map((param, index) => {
                         let val = 0.5;
                         let setVal: ((v: number) => void) | undefined = undefined;
                         if (index === 0) { val = zoomParam1 ?? param.default; setVal = setZoomParam1; }
                         else if (index === 1) { val = zoomParam2 ?? param.default; setVal = setZoomParam2; }
                         else if (index === 2) { val = zoomParam3 ?? param.default; setVal = setZoomParam3; }
                         else if (index === 3) { val = zoomParam4 ?? param.default; setVal = setZoomParam4; }

                         if (!setVal) return null;

                         return (
                            <div className="control-group" key={param.id}>
                                <label>{param.name}: {val.toFixed(2)}</label>
                                <input type="range"
                                       min={param.min} max={param.max} step={param.step || 0.01}
                                       value={val}
                                       onChange={(e) => setVal!(parseFloat(e.target.value))} />
                            </div>
                         );
                    })}
                </>
            )}

            {mode === 'rain' && (
                <>
                    <hr style={{ borderColor: '#444', margin: '15px 0' }} />
                    <div style={{ fontWeight: 'bold', marginBottom: '10px' }}>Rain Controls</div>
                    <div className="control-group">
                        <label>Rain Speed: {zoomParam1?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={zoomParam1 || 0.5} onChange={(e) => setZoomParam1 && setZoomParam1(parseFloat(e.target.value))} />
                    </div>
                    <div className="control-group">
                        <label>Rain Density: {zoomParam2?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={zoomParam2 || 0.5} onChange={(e) => setZoomParam2 && setZoomParam2(parseFloat(e.target.value))} />
                    </div>
                    <div className="control-group">
                        <label>Wind: {zoomParam3?.toFixed(2)}</label>
                        <input type="range" min="0" max="4" step="0.1" value={zoomParam3 || 2.0} onChange={(e) => setZoomParam3 && setZoomParam3(parseFloat(e.target.value))} />
                    </div>
                    <div className="control-group">
                        <label>Splash/Flow: {zoomParam4?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={zoomParam4 || 0.5} onChange={(e) => setZoomParam4 && setZoomParam4(parseFloat(e.target.value))} />
                    </div>
                </>
            )}

            {mode === 'chromatic-manifold' && (
                <>
                    <hr style={{ borderColor: '#444', margin: '15px 0' }} />
                    <div style={{ fontWeight: 'bold', marginBottom: '10px' }}>Chromatic Manifold Controls</div>
                    <div className="control-group">
                        <label>Warp Strength: {zoomParam1?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={zoomParam1 || 0.5} onChange={(e) => setZoomParam1 && setZoomParam1(parseFloat(e.target.value))} />
                    </div>
                    <div className="control-group">
                        <label>Curvature Strength: {zoomParam2?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={zoomParam2 || 0.5} onChange={(e) => setZoomParam2 && setZoomParam2(parseFloat(e.target.value))} />
                    </div>
                    <div className="control-group">
                        <label>Hue Weight: {zoomParam3?.toFixed(2)}</label>
                        <input type="range" min="0" max="2" step="0.01" value={zoomParam3 || 1.0} onChange={(e) => setZoomParam3 && setZoomParam3(parseFloat(e.target.value))} />
                    </div>
                    <div className="control-group">
                        <label>Feedback Strength: {zoomParam4?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={zoomParam4 || 0.9} onChange={(e) => setZoomParam4 && setZoomParam4(parseFloat(e.target.value))} />
                    </div>
                </>
            )}

            {mode === 'digital-decay' && (
                <>
                    <hr style={{ borderColor: '#444', margin: '15px 0' }} />
                    <div style={{ fontWeight: 'bold', marginBottom: '10px' }}>Digital Decay Controls</div>
                    <div className="control-group">
                        <label>Decay Intensity: {zoomParam1?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={zoomParam1 || 0.5} onChange={(e) => setZoomParam1 && setZoomParam1(parseFloat(e.target.value))} />
                    </div>
                    <div className="control-group">
                        <label>Block Size: {zoomParam2?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={zoomParam2 || 0.5} onChange={(e) => setZoomParam2 && setZoomParam2(parseFloat(e.target.value))} />
                    </div>
                    <div className="control-group">
                        <label>Corruption Speed: {zoomParam3?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={zoomParam3 || 0.5} onChange={(e) => setZoomParam3 && setZoomParam3(parseFloat(e.target.value))} />
                    </div>
                    <div className="control-group">
                        <label>Depth Focus: {zoomParam4?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={zoomParam4 || 0.5} onChange={(e) => setZoomParam4 && setZoomParam4(parseFloat(e.target.value))} />
                    </div>
                </>
            )}

            {mode === 'spectral-vortex' && (
                <>
                    <hr style={{ borderColor: '#444', margin: '15px 0' }} />
                    <div style={{ fontWeight: 'bold', marginBottom: '10px' }}>Spectral Vortex Controls</div>
                    <div className="control-group">
                        <label>Twist Strength: {zoomParam1?.toFixed(2)}</label>
                        <input type="range" min="0" max="10" step="0.1" value={zoomParam1 || 2.0} onChange={(e) => setZoomParam1 && setZoomParam1(parseFloat(e.target.value))} />
                    </div>
                    <div className="control-group">
                        <label>Distortion Step: {zoomParam2?.toFixed(3)}</label>
                        <input type="range" min="0" max="0.1" step="0.001" value={zoomParam2 || 0.02} onChange={(e) => setZoomParam2 && setZoomParam2(parseFloat(e.target.value))} />
                    </div>
                    <div className="control-group">
                        <label>Color Shift: {zoomParam3?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={zoomParam3 || 0.1} onChange={(e) => setZoomParam3 && setZoomParam3(parseFloat(e.target.value))} />
                    </div>
                </>
            )}

            {mode === 'quantum-fractal' && (
                <>
                    <hr style={{ borderColor: '#444', margin: '15px 0' }} />
                    <div style={{ fontWeight: 'bold', marginBottom: '10px' }}>Quantum Fractal Controls</div>
                    <div className="control-group">
                        <label>Fractal Scale: {zoomParam1?.toFixed(2)}</label>
                        <input type="range" min="0.1" max="10" step="0.1" value={zoomParam1 || 3.0} onChange={(e) => setZoomParam1 && setZoomParam1(parseFloat(e.target.value))} />
                    </div>
                    <div className="control-group">
                        <label>Iterations: {zoomParam2?.toFixed(0)}</label>
                        <input type="range" min="10" max="200" step="1" value={zoomParam2 || 100} onChange={(e) => setZoomParam2 && setZoomParam2(parseFloat(e.target.value))} />
                    </div>
                    <div className="control-group">
                        <label>Entanglement: {zoomParam3?.toFixed(2)}</label>
                        <input type="range" min="0" max="2" step="0.01" value={zoomParam3 || 1.0} onChange={(e) => setZoomParam3 && setZoomParam3(parseFloat(e.target.value))} />
                    </div>
                </>
            )}

            {mode === 'infinite-zoom' && (
                <>
                    <hr style={{ borderColor: '#444', margin: '15px 0' }} />
                    <div style={{ fontWeight: 'bold', marginBottom: '10px' }}>Lighting & Depth</div>
                    <div className="control-group">
                        <label>Light Strength: {lightStrength?.toFixed(1)}</label>
                        <input type="range" min="0" max="5" step="0.1" value={lightStrength || 1.0} onChange={(e) => setLightStrength && setLightStrength(parseFloat(e.target.value))} />
                    </div>
                    <div className="control-group">
                        <label>Ambient: {ambient?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.05" value={ambient || 0.2} onChange={(e) => setAmbient && setAmbient(parseFloat(e.target.value))} />
                    </div>
                    <div className="control-group">
                        <label>Normal Strength: {normalStrength?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={normalStrength || 0.1} onChange={(e) => setNormalStrength && setNormalStrength(parseFloat(e.target.value))} />
                    </div>
                    <div className="control-group">
                        <label>Fog Falloff: {fogFalloff?.toFixed(1)}</label>
                        <input type="range" min="0.1" max="10" step="0.1" value={fogFalloff || 4.0} onChange={(e) => setFogFalloff && setFogFalloff(parseFloat(e.target.value))} />
                    </div>
                    <div className="control-group">
                        <label>Depth Threshold: {depthThreshold?.toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={depthThreshold || 0.5} onChange={(e) => setDepthThreshold && setDepthThreshold(parseFloat(e.target.value))} />
                    </div>
                </>
            )}
            {mode === 'chromatic-manifold' && (
                <>
                    <hr style={{ borderColor: '#444', margin: '15px 0' }} />
                    <div style={{ fontWeight: 'bold', marginBottom: '10px' }}>Chromatic Manifold Controls</div>
                    <div className="control-group">
                        <label>Hue Weight: {(zoomParam1 || 0.5).toFixed(2)}</label>
                        <input type="range" min="0" max="2" step="0.01" value={zoomParam1 || 0.5} onChange={(e) => setZoomParam1 && setZoomParam1(parseFloat(e.target.value))} />
                    </div>
                    <div className="control-group">
                        <label>Warp Strength: {(zoomParam2 || 0.5).toFixed(2)}</label>
                        <input type="range" min="0" max="1" step="0.01" value={zoomParam2 || 0.5} onChange={(e) => setZoomParam2 && setZoomParam2(parseFloat(e.target.value))} />
                    </div>
                    <div className="control-group">
                        <label>Tear Threshold: {(zoomParam3 || 0.8).toFixed(2)}</label>
                        <input type="range" min="0" max="3" step="0.01" value={zoomParam3 || 0.8} onChange={(e) => setZoomParam3 && setZoomParam3(parseFloat(e.target.value))} />
                    </div>
                    <div className="control-group">
                        <label>Curvature Strength: {(zoomParam4 || 0.5).toFixed(2)}</label>
                        <input type="range" min="0" max="2" step="0.01" value={zoomParam4 || 0.5} onChange={(e) => setZoomParam4 && setZoomParam4(parseFloat(e.target.value))} />
                    </div>
                </>
            )}
        </div>
    );
};

export default Controls;
