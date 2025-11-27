import React from 'react';
import { RenderMode, ShaderEntry, ShaderCategory } from '../renderer/types';

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
    availableModes = []
}) => {
    const shaderModes = availableModes.filter(entry => entry.category === 'shader');
    const imageModes = availableModes.filter(entry => entry.category === 'image');
    const videoModes = availableModes.filter(entry => entry.category === 'video');

    const handleCategoryChange = (newCategory: ShaderCategory) => {
        setShaderCategory(newCategory);
        // Set default shader for the category
        let defaultMode: string;
        switch (newCategory) {
            case 'shader':
                defaultMode = shaderModes.length > 0 ? shaderModes[0].id : 'shader';
                break;
            case 'image':
                defaultMode = imageModes.length > 0 ? imageModes[0].id : 'image';
                break;
            case 'video':
                defaultMode = videoModes.length > 0 ? videoModes[0].id : 'video';
                break;
        }
        setMode(defaultMode);
    };

    const getCurrentCategoryModes = () => {
        switch (shaderCategory) {
            case 'shader':
                return shaderModes;
            case 'image':
                return imageModes;
            case 'video':
                return videoModes;
            default:
                return [];
        }
    };

    const currentModes = getCurrentCategoryModes();

    return (
        <div className="controls">
            <div className="control-group">
                <label htmlFor="category-select">Mode:</label>
                <select 
                    id="category-select" 
                    value={shaderCategory} 
                    onChange={(e) => handleCategoryChange(e.target.value as ShaderCategory)}
                >
                    <option value="shader">Shader (Procedural)</option>
                    <option value="image">Image Input Shader</option>
                    <option value="video">Video Input Shader</option>
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
            <div className="control-group">
                <button onClick={onLoadModel} disabled={isModelLoaded}>
                    {isModelLoaded ? 'AI Model Loaded' : 'Load AI Model'}
                </button>
                <button onClick={onNewImage}>Load New Random Image</button>
            </div>
            <>
                <div className="control-group">
                    <label></label>
                    <button onClick={onNewImage}>New Random Image</button>
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
