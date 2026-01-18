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
const API_BASE_URL = 'https://ford442-storage-manager.hf.space';
const IMAGE_MANIFEST_URL = `${API_BASE_URL}/api/songs?type=image`;
const LOCAL_MANIFEST_URL = `./image_manifest.json`;

// UPDATED: Pointing directly to your bucket
const BUCKET_BASE_URL = `https://storage.googleapis.com/my-sd35-space-images-2025`;
const IMAGE_SUGGESTIONS_URL = `/image_suggestions.md`;

const FALLBACK_IMAGES = [
    "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?q=80&w=2564&auto=format&fit=crop", // Liquid Metal
    "https://images.unsplash.com/photo-1518709268805-4e9042af9f23?q=80&w=2568&auto=format&fit=crop", // Cyberpunk City
    "https://images.unsplash.com/photo-1550684848-fac1c5b4e853?q=80&w=2670&auto=format&fit=crop", // Fluid Gradient
    "https://images.unsplash.com/photo-1534447677768-be436bb09401?q=80&w=2694&auto=format&fit=crop", // Grid Landscape
    "https://images.unsplash.com/photo-1475924156734-496f6cac6ec1?q=80&w=2670&auto=format&fit=crop", // Nature
    "https://images.unsplash.com/photo-1614850523060-8da1d56ae167?q=80&w=2670&auto=format&fit=crop", // Neon
    "https://images.unsplash.com/photo-1605218427306-633ba8546381?q=80&w=2669&auto=format&fit=crop"  // Geometry
];

const defaultSlotParams: SlotParams = {
    zoomParam1: 0.99,
    zoomParam2: 1.01,
    zoomParam3: 0.5,
    zoomParam4: 0.5,
    lightStrength: 1.0,
    ambient: 0.2,
    normalStrength: 0.1,
    fogFalloff: 4.0,
    depthThreshold: 0.5,
};

function MainApp() {
    // --- State: General & Stacking ---
    const [shaderCategory, setShaderCategory] = useState<ShaderCategory>('image');
    const [modes, setModes] = useState<RenderMode[]>(['liquid', 'none', 'none']);
    const [activeSlot, setActiveSlot] = useState<number>(0);
    const [slotParams, setSlotParams] = useState<SlotParams[]>([
        defaultSlotParams,
        defaultSlotParams,
        defaultSlotParams
    ]);

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
    const [videoList, setVideoList] = useState<string[]>([]); // New Video List State
    const [currentImageUrl, setCurrentImageUrl] = useState<string | undefined>();
    const [availableModes, setAvailableModes] = useState<ShaderEntry[]>([]);
    const [inputSource, setInputSource] = useState<InputSource>('image');
    const [activeGenerativeShader, setActiveGenerativeShader] = useState<string>('gen-orb');
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const [videoSourceUrl, setVideoSourceUrl] = useState<string | undefined>(undefined);
    const [isMuted, setIsMuted] = useState(true);
    const [selectedVideo, setSelectedVideo] = useState<string>("");

    // --- State: Layout ---
    const [showSidebar, setShowSidebar] = useState(true);

    // --- State: Mouse Interaction ---
    const [mousePosition, setMousePosition] = useState<{ x: number; y: number }>({ x: -1, y: -1 });
    const [isMouseDown, setIsMouseDown] = useState(false);

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

    const updateSlotParam = useCallback((slotIndex: number, updates: Partial<SlotParams>) => {
        setSlotParams(prev => {
            const next = [...prev];
            next[slotIndex] = { ...next[slotIndex], ...updates };
            return next;
        });
    }, []);

    // --- EFFECT: Auto-Switch Generative Mode ---
    // This fixes the issue where generative mode wouldn't replace image/video input
    useEffect(() => {
        if (shaderCategory === 'shader') {
            // When user selects "Procedural Generation", force input source to generative
            setInputSource('generative');
            setStatus('Switched to Generative Input');
        } else {
            // When user goes back to "Effects / Filters", default back to image (if currently generative)
            if (inputSource === 'generative') {
                setInputSource('image');
                setStatus('Switched to Image Input');
            }
        }
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [shaderCategory]); // Only depend on shaderCategory, not inputSource

    // --- Effects & Initializers ---
    useEffect(() => {
        // Fetch the dynamic image manifest from the backend on startup
        const fetchImageManifest = async () => {
            let manifest: ImageRecord[] = [];
            let videos: string[] = [];

            // 1. Try API
            try {
                const response = await fetch(IMAGE_MANIFEST_URL);
                if (response.ok) {
                    const data = await response.json();
                    manifest = data.map((item: any) => ({
                        url: item.url,
                        tags: item.description ? item.description.toLowerCase().split(/[\s,]+/) : [],
                        description: item.description || ''
                    }));
                }
            } catch (error) {
                console.warn("Backend API failed, trying local manifest...", error);
            }

            // 2. Try Local Manifest (Bucket Images & Videos) if API Empty
            if (manifest.length === 0) {
                try {
                    const response = await fetch(LOCAL_MANIFEST_URL);
                    if (response.ok) {
                        const data = await response.json();

                        // Process Images
                        manifest = (data.images || []).map((item: any) => {
                            // Fix double bucket names if they exist in the manifest already
                            const cleanUrl = item.url.replace('my-sd35-space-images-2025/', '');
                            return {
                                url: item.url.startsWith('http') ? item.url : `${BUCKET_BASE_URL}/${cleanUrl}`,
                                tags: item.tags || [],
                                description: item.tags ? item.tags.join(', ') : ''
                            };
                        });

                        // Process Videos
                        videos = (data.videos || []).map((item: any) => {
                            const cleanUrl = item.url.replace('my-sd35-space-images-2025/', '');
                            return item.url.startsWith('http') ? item.url : `${BUCKET_BASE_URL}/${cleanUrl}`;
                        });

                        console.log("Loaded local manifest:", manifest.length, "images,", videos.length, "videos");
                    }
                } catch (e) {
                    console.warn("Failed to load local manifest:", e);
                }
            }

            // 3. Last Resort: Robust Unsplash Fallback
            if (manifest.length === 0) {
                console.warn("Image manifest empty. Using robust Unsplash fallback.");
                manifest = FALLBACK_IMAGES.map(url => ({
                    url,
                    tags: ['fallback', 'unsplash', 'demo'],
                    description: 'Demo Image'
                }));
            }

            setImageManifest(manifest);
            setVideoList(videos); // Update Video List State

            // Push to Renderer
            if (rendererRef.current) {
                rendererRef.current.setImageList(manifest.map(m => m.url));
                // If the renderer has a setVideoList method, call it here.
                // Currently assuming Controls handles the selection via `selectedVideo` prop.
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
                (ids) => {
                    setModes(prev => {
                        const next = [...prev];
                        if (ids.length > 0) next[0] = ids[0];
                        if (ids.length > 1) next[1] = ids[1];
                        if (ids.length > 2) next[2] = ids[2];
                        return next;
                    });
                },
                () => { // This now correctly reads from state
                    const imgRecord = imageManifest.find(img => img.url === currentImageUrl) || null;
                    const shaderEntry = availableModes.find(m => m.id === modes[0]) || null;
                    const shaderRecord: ShaderRecord | null = shaderEntry ? {
                        id: shaderEntry.id,
                        name: shaderEntry.name,
                        description: shaderEntry.description,
                        tags: shaderEntry.tags || [],
                    } : null;
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
                    if (aiVj.start()) {
                        setIsAiVjMode(true);
                    }
                } else { // Re-initialize if it failed or hasn't been run
                    await aiVj.initialize(imageManifest, availableModes, IMAGE_SUGGESTIONS_URL);
                    if (aiVj.start()) {
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
                        slotParams={slotParams} updateSlotParam={updateSlotParam} shaderCategory={shaderCategory}
                        setShaderCategory={setShaderCategory} zoom={zoom} setZoom={setZoom} panX={panX}
                        setPanX={setPanX} panY={panY} setPanY={setPanY} onNewImage={handleNewRandomImage}
                        autoChangeEnabled={autoChangeEnabled} setAutoChangeEnabled={setAutoChangeEnabled}
                        autoChangeDelay={autoChangeDelay} setAutoChangeDelay={setAutoChangeDelay}
                        onLoadModel={loadDepthModel} isModelLoaded={!!depthEstimator} availableModes={availableModes}
                        inputSource={inputSource} setInputSource={setInputSource} videoList={videoList}
                        selectedVideo={selectedVideo} setSelectedVideo={setSelectedVideo} isMuted={isMuted} setIsMuted={setIsMuted}
                        activeGenerativeShader={activeGenerativeShader} setActiveGenerativeShader={setActiveGenerativeShader}
                        onUploadImageTrigger={() => fileInputImageRef.current?.click()}
                        onUploadVideoTrigger={() => fileInputVideoRef.current?.click()}
                        isAiVjMode={isAiVjMode} onToggleAiVj={toggleAiVj} aiVjStatus={aiVjStatus}
                    />
                </aside>
                <main className="canvas-container">
                    <WebGPUCanvas
                        modes={modes} slotParams={slotParams} zoom={zoom} panX={panX} panY={panY}
                        rendererRef={rendererRef} farthestPoint={{x:0.5, y:0.5}}
                        mousePosition={mousePosition} setMousePosition={setMousePosition}
                        isMouseDown={isMouseDown} setIsMouseDown={setIsMouseDown} onInit={onInitCanvas}
                        inputSource={inputSource} videoSourceUrl={videoSourceUrl}
                        isMuted={isMuted} setInputSource={setInputSource}
                        activeGenerativeShader={activeGenerativeShader}
                        selectedVideo={selectedVideo}
                        apiBaseUrl={API_BASE_URL}
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
