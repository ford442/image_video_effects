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
    isMuted, setIsMuted
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

    return (
        <div className="controls">
             <div className="control-group">
                <label>Input Source:</label>
                <div style={{display: 'inline-block', marginLeft: '10px'}}>
                    <label style={{marginRight: '10px', cursor: 'pointer'}}>
                        <input
                            type="radio"
                            name="inputSource"
                            value="image"
                            checked={inputSource === 'image'}
                            onChange={() => setInputSource('image')}
                        /> Image
                    </label>
                    <label style={{cursor: 'pointer'}}>
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
                    <label style={{marginLeft: '10px'}}>
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
        </div>
    );
};

export default Controls;
