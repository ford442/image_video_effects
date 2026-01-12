import React, { useState, useEffect, useCallback, useRef } from 'react';
import WebGPUCanvas from './components/WebGPUCanvas';
import Controls from './components/Controls';
import { Renderer } from './renderer/Renderer';
import { RenderMode, ShaderEntry, ShaderCategory, InputSource, SlotParams } from './renderer/types';
import { Alucinate, AIStatus, ImageRecord, ShaderRecord } from './AutoDJ';
import { pipeline, env } from '@xenova/transformers';
import './style.css';

// --- Configuration ---
env.allowLocalModels = false;
env.backends.onnx.logLevel = 'warning';
const DEPTH_MODEL_ID = 'Xenova/dpt-hybrid-midas';
const API_BASE_URL = 'http://localhost:7860';
const IMAGE_MANIFEST_URL = `${API_BASE_URL}/api/songs?type=image`;
const IMAGE_SUGGESTIONS_URL = `/image_suggestions.md`;

function MainApp() {
    // --- State: General & Stacking ---
    const [shaderCategory, setShaderCategory] = useState<ShaderCategory>('image');
    const [modes, setModes] = useState<RenderMode[]>(['liquid', 'none', 'none']);
    const [activeSlot, setActiveSlot] = useState<number>(0);
    const [slotParams, setSlotParams] = useState<SlotParams[]>([]);

    // --- State: Global View ---
    const [zoom, setZoom] = useState(1.0);
    const [panX, setPanX] = useState(0.5);
    const [panY, setPanY] = useState(0.5);
    
    // --- State: Automation & Status ---
    const [autoChangeEnabled, setAutoChangeEnabled] = useState(false);
    const [autoChangeDelay, setAutoChangeDelay] = useState(10);
    const [status, setStatus] = useState('Ready.');
    
    // --- State: AI Models & VJ ---
    const [depthEstimator, setDepthEstimator] = useState<any>(null);
    const [aiVj, setAiVj] = useState<Alucinate | null>(null);
    const [aiVjStatus, setAiVjStatus] = useState<AIStatus>('idle');
    const [aiVjMessage, setAiVjMessage] = useState('AI VJ is offline.');
    const [isAiVjMode, setIsAiVjMode] = useState(false);

    // --- State: Content ---
    const [imageManifest, setImageManifest] = useState<ImageRecord[]>([]);
    const [currentImageUrl, setCurrentImageUrl] = useState<string | undefined>();
    const [availableModes, setAvailableModes] = useState<ShaderEntry[]>([]);
    const [inputSource, setInputSource] = useState<InputSource>('image');
    const [videoSourceUrl, setVideoSourceUrl] = useState<string | undefined>(undefined);
    const [isMuted, setIsMuted] = useState(true);

    // --- State: Layout ---
    const [showSidebar, setShowSidebar] = useState(true);

    // --- Refs ---
    const rendererRef = useRef<Renderer | null>(null);
    const fileInputImageRef = useRef<HTMLInputElement>(null);
    const fileInputVideoRef = useRef<HTMLInputElement>(null);

    // --- Helpers ---
    const setMode = (index: number, mode: RenderMode) => {
        setModes(prev => {
            const next = [...prev];
            next[index] = mode;
            return next;
        });
    };

    // --- Effects & Initializers ---
    useEffect(() => {
        // Fetch the dynamic image manifest from the backend on startup
        const fetchImageManifest = async () => {
            try {
                const response = await fetch(IMAGE_MANIFEST_URL);
                if (!response.ok) throw new Error('Failed to fetch image manifest');
                const data = await response.json();
                const manifest = data.map((item: any) => ({
                    url: item.url,
                    tags: item.description ? item.description.toLowerCase().split(/[\s,]+/) : [],
                    description: item.description || ''
                }));
                setImageManifest(manifest);
            } catch (error) {
                console.error(error);
                setStatus('Error: Could not load image manifest from backend.');
            }
        };
        fetchImageManifest();
    }, []);

    // --- Image Loading ---
    const runDepthAnalysis = useCallback(async (imageUrl: string) => {
        if (!depthEstimator || !rendererRef.current) return;
        setStatus('Analyzing image with depth model...');
        try {
            const result = await depthEstimator(imageUrl);
            const { data, dims } = result.predicted_depth;
            const [height, width] = [dims[dims.length-2], dims[dims.length-1]];
            const normalizedData = new Float32Array(data.length);
            let min = Infinity, max = -Infinity;
            data.forEach((v:number) => { min = Math.min(min, v); max = Math.max(max, v); });
            const range = max - min;
            for (let i = 0; i < data.length; ++i) {
                normalizedData[i] = 1.0 - ((data[i] - min) / range);
            }
            rendererRef.current.updateDepthMap(normalizedData, width, height);
            setStatus('Depth map updated.');
        } catch (e: any) {
            console.error("Error during analysis:", e);
            setStatus(`Failed to analyze image: ${e.message}`);
        }
    }, [depthEstimator]);

    const handleLoadImage = useCallback(async (url: string) => {
        if (!rendererRef.current) return;
        const newImageUrl = await rendererRef.current.loadImage(url);
        if (newImageUrl) {
            setCurrentImageUrl(newImageUrl);
            if (depthEstimator) {
                await runDepthAnalysis(newImageUrl);
            }
        }
    }, [depthEstimator, runDepthAnalysis]);

    const handleNewRandomImage = useCallback(async () => {
        if (imageManifest.length === 0) {
            setStatus("Image manifest not loaded yet.");
            return;
        };
        const randomImage = imageManifest[Math.floor(Math.random() * imageManifest.length)];
        if (randomImage) {
            await handleLoadImage(randomImage.url);
        }
    }, [imageManifest, handleLoadImage]);

    const loadDepthModel = useCallback(async () => {
        if (depthEstimator) { setStatus('Depth model already loaded.'); return; }
        try {
            setStatus('Loading depth model...');
            const estimator = await pipeline('depth-estimation', DEPTH_MODEL_ID, {
                progress_callback: (p: any) => setStatus(`Loading depth model: ${p.status}...`),
            });
            setDepthEstimator(() => estimator);
            setStatus('Depth model loaded.');
            if (currentImageUrl) await runDepthAnalysis(currentImageUrl);
        } catch (e: any) {
            console.error(e);
            setStatus(`Failed to load depth model: ${e.message}`);
        }
    }, [depthEstimator, currentImageUrl, runDepthAnalysis]);
    
    // --- AI VJ Mode ---
    const toggleAiVj = useCallback(async () => {
        if (!aiVj) {
            if (imageManifest.length === 0 || availableModes.length === 0) {
                setStatus("Content not loaded yet, cannot start AI VJ.");
                return;
            }
            const vj = new Alucinate(
                (url) => handleLoadImage(url),
                (id) => setMode(0, id),
                () => { // This now correctly reads from state
                    const imgRecord = imageManifest.find(img => img.url === currentImageUrl) || null;
                    const shaderRecord = availableModes.find(m => m.id === modes[0]) || null;
                    return { currentImage: imgRecord, currentShader: shaderRecord };
                }
            );
            vj.onStatusChange = (s, m) => { setAiVjStatus(s); setAiVjMessage(m); };
            setAiVj(vj);
            setIsAiVjMode(true);
            await vj.initialize(imageManifest, availableModes, IMAGE_SUGGESTIONS_URL);
            if (vj.status === 'ready') {
                vj.start();
            }
        } else {
            if (isAiVjMode) {
                aiVj.stop();
                setIsAiVjMode(false);
            } else {
                if (aiVj.status === 'ready') {
                    aiVj.start();
                    setIsAiVjMode(true);
                } else { // Re-initialize if it failed or hasn't been run
                    await aiVj.initialize(imageManifest, availableModes, IMAGE_SUGGESTIONS_URL);
                     if (aiVj.status === 'ready') {
                        aiVj.start();
                        setIsAiVjMode(true);
                    }
                }
            }
        }
    }, [aiVj, isAiVjMode, availableModes, modes, handleLoadImage, imageManifest, currentImageUrl]);
    
    const onInitCanvas = useCallback(() => {
        if(rendererRef.current) {
            setAvailableModes(rendererRef.current.getAvailableModes());
            handleNewRandomImage();
        }
    }, [handleNewRandomImage]);

    return (
        <div className="App">
            <header className="header">
                <div className="logo-section">
                    <div className="logo-text">Pixelocity</div>
                    <div className="subtitle-text">AI VJ Image Playground</div>
                </div>
                <div className="header-controls">
                    <button className="toggle-sidebar-btn" onClick={() => setShowSidebar(!showSidebar)}>
                        {showSidebar ? 'Hide Controls' : 'Show Controls'}
                    </button>
                </div>
            </header>
            <div className="main-container">
                <aside className={`sidebar ${!showSidebar ? 'hidden' : ''}`}>
                    <Controls
                        // ... pass all props to Controls component
                        modes={modes} setMode={setMode} activeSlot={activeSlot} setActiveSlot={setActiveSlot}
                        slotParams={slotParams} updateSlotParam={()=>{}} shaderCategory={shaderCategory}
                        setShaderCategory={setShaderCategory} zoom={zoom} setZoom={setZoom} panX={panX}
                        setPanX={setPanX} panY={panY} setPanY={setPanY} onNewImage={handleNewRandomImage}
                        autoChangeEnabled={autoChangeEnabled} setAutoChangeEnabled={setAutoChangeEnabled}
                        autoChangeDelay={autoChangeDelay} setAutoChangeDelay={setAutoChangeDelay}
                        onLoadModel={loadDepthModel} isModelLoaded={!!depthEstimator} availableModes={availableModes}
                        inputSource={inputSource} setInputSource={setInputSource} videoList={[]}
                        selectedVideo={""} setSelectedVideo={()=>{}} isMuted={isMuted} setIsMuted={setIsMuted}
                        onUploadImageTrigger={() => fileInputImageRef.current?.click()}
                        onUploadVideoTrigger={() => fileInputVideoRef.current?.click()}
                        isAiVjMode={isAiVjMode} onToggleAiVj={toggleAiVj} aiVjStatus={aiVjStatus}
                    />
                </aside>
                <main className="canvas-container">
                    <WebGPUCanvas
                        modes={modes} slotParams={slotParams} zoom={zoom} panX={panX} panY={panY}
                        rendererRef={rendererRef} farthestPoint={{x:0.5, y:0.5}}
                        mousePosition={{x:-1, y:-1}} setMousePosition={()=>{}}
                        isMouseDown={false} setIsMouseDown={()=>{}} onInit={onInitCanvas}
                        inputSource={inputSource} videoSourceUrl={videoSourceUrl}
                        isMuted={isMuted} setInputSource={setInputSource}
                    />
                    <div className="status-bar">
                        {isAiVjMode ? `[AI VJ]: ${aiVjMessage}` : status}
                    </div>
                </main>
            </div>
            <input type="file" ref={fileInputImageRef} accept="image/*" style={{display:'none'}} onChange={() => {}} />
            <input type="file" ref={fileInputVideoRef} accept="video/*" style={{display:'none'}} onChange={() => {}} />
        </div>
    );
}

export default MainApp;