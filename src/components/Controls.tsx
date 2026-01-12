
import React from 'react';
import { RenderMode, ShaderEntry, ShaderCategory, InputSource, SlotParams } from '../renderer/types';
import { AIStatus } from '../AutoDJ'; // Import AIStatus

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
    // AI VJ Props
    isAiVjMode,
    onToggleAiVj,
    aiVjStatus
}) => {
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
                            onChange={() => setInputSource('image')}
                        /> Image
                    </label>
                    <label>
                        <input
                            type="radio"
                            value="video"
                            checked={inputSource === 'video'}
                            onChange={() => setInputSource('video')}
                        /> Video
                    </label>
                    <label>
                        <input
                            type="radio"
                            value="webcam"
                            checked={inputSource === 'webcam'}
                            onChange={() => setInputSource('webcam')}
                        /> Webcam
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
                    <div key={i} className={`stack-slot ${activeSlot === i ? 'active' : ''}`} onClick={() => setActiveSlot(i)}>
                        <div style={{ display: 'flex', alignItems: 'center', marginBottom: '5px' }}>
                            <input
                                type="radio"
                                checked={activeSlot === i}
                                onChange={() => setActiveSlot(i)}
                                style={{ marginRight: '8px' }}
                            />
                            <span style={{ fontWeight: activeSlot === i ? 'bold' : 'normal' }}>Slot {i + 1}:</span>
                        </div>
                        <select
                            value={modes[i]}
                            onChange={(e) => setMode(i, e.target.value as RenderMode)}
                            style={{ width: '100%' }}
                        >
                            <option value="none">None</option>
                            {currentModes.map(mode => (
                                <option key={mode.id} value={mode.id}>{mode.name}</option>
                            ))}
                        </select>
                    </div>
                ))}
            </div>

            {/* --- Source Specific Controls --- */}
            {inputSource === 'image' && (
                <>
                    <div className="control-group" style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px' }}>
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
                <div className="control-group">
                    <label>Select Video</label>
                    <div style={{display: 'flex', gap: '5px'}}>
                        <select
                            value={selectedVideo}
                            onChange={(e) => setSelectedVideo(e.target.value)}
                            style={{flex: 1}}
                        >
                            {videoList.map((v, i) => (
                                <option key={i} value={v}>{v.split('/').pop()}</option>
                            ))}
                        </select>
                        <button onClick={onUploadVideoTrigger}>Upload</button>
                    </div>
                    <div style={{marginTop: '10px'}}>
                         <label style={{display: 'flex', alignItems: 'center'}}>
                            <input type="checkbox" checked={isMuted} onChange={(e) => setIsMuted(e.target.checked)} style={{width: 'auto', marginRight: '5px'}}/>
                            Mute Audio
                         </label>
                    </div>
                </div>
            )}


            <hr />

            {/* --- Active Slot Parameter Controls --- */}
            <div style={{ fontWeight: 'bold', marginBottom: '10px', color: '#61dafb', fontSize: '14px' }}>
                Slot {activeSlot + 1} Settings
            </div>

            {currentParams && currentShaderEntry && currentShaderEntry.params && currentShaderEntry.params.map((param, index) => {
                 if (index >= 4) return null;
                 const valKey = `zoomParam${index + 1}` as keyof SlotParams;
                 const val = currentParams[valKey];

                 return (
                     <div key={param.id} className="control-group">
                         <label>{param.name}</label>
                         <input
                             type="range"
                             min={param.min}
                             max={param.max}
                             step="0.01"
                             value={val}
                             onChange={(e) => updateSlotParam(activeSlot, { [valKey]: parseFloat(e.target.value) })}
                         />
                     </div>
                 );
            })}

            {(!currentShaderEntry || !currentShaderEntry.params || currentShaderEntry.params.length === 0) && (
                <div style={{fontStyle: 'italic', color: '#888'}}>No parameters</div>
            )}
        </div>
    );
};

export default Controls;
