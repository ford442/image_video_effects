import React, { useState, useEffect, useCallback, useRef } from 'react';
import WebGPUCanvas from './components/WebGPUCanvas';
import Controls from './components/Controls';
import { Renderer } from './renderer/Renderer';
import { RenderMode, ShaderEntry, ShaderCategory, InputSource, SlotParams } from './renderer/types';
import { SyncMessage, FullState, SYNC_CHANNEL_NAME } from './syncTypes';
import { pipeline, env } from '@xenova/transformers';
import './style.css';

// --- Configuration ---
env.allowLocalModels = false;
env.backends.onnx.logLevel = 'warning';
const model_loc = 'Xenova/dpt-hybrid-midas';

function MainApp() {
    // --- State: General & Stacking ---
    const [shaderCategory, setShaderCategory] = useState<ShaderCategory>('image');
    
    // Default Parameters for slots
    const DEFAULT_SLOT_PARAMS: SlotParams = {
        zoomParam1: 0.5, zoomParam2: 0.5, zoomParam3: 0.5, zoomParam4: 0.5,
        lightStrength: 1.0, ambient: 0.2, normalStrength: 0.1, fogFalloff: 4.0, depthThreshold: 0.5,
    };

    // Stacking State: We now track arrays for modes and params to support layers
    const [modes, setModes] = useState<RenderMode[]>(['liquid', 'none', 'none']);
    const [activeSlot, setActiveSlot] = useState<number>(0);
    const [slotParams, setSlotParams] = useState<SlotParams[]>([
        { ...DEFAULT_SLOT_PARAMS },
        { ...DEFAULT_SLOT_PARAMS },
        { ...DEFAULT_SLOT_PARAMS }
    ]);

    // Global View State
    const [zoom, setZoom] = useState(1.0);
    const [panX, setPanX] = useState(0.5);
    const [panY, setPanY] = useState(0.5);
    
    // Automation & status
    const [autoChangeEnabled, setAutoChangeEnabled] = useState(false);
    const [autoChangeDelay, setAutoChangeDelay] = useState(10);
    const [status, setStatus] = useState('Ready. Click "Load AI Model" for depth effects.');
    
    // AI / Depth State
    const [depthEstimator, setDepthEstimator] = useState<any>(null);
    const [depthMapResult, setDepthMapResult] = useState<any>(null);
    const [farthestPoint, setFarthestPoint] = useState({ x: 0.5, y: 0.5 });
    
    // Interaction
    const [mousePosition, setMousePosition] = useState({ x: -1, y: -1 });
    const [isMouseDown, setIsMouseDown] = useState(false);
    const [availableModes, setAvailableModes] = useState<ShaderEntry[]>([]);

    // Video/Input State
    const [inputSource, setInputSource] = useState<InputSource>('image');
    const [videoList, setVideoList] = useState<string[]>([]);
    const [selectedVideo, setSelectedVideo] = useState<string>(''); // For stock videos
    const [videoSourceUrl, setVideoSourceUrl] = useState<string | undefined>(undefined); // For uploaded videos
    const [isMuted, setIsMuted] = useState(true);

    // Layout State
    const [showSidebar, setShowSidebar] = useState(true);

    // Refs
    const rendererRef = useRef<Renderer | null>(null);
    const debugCanvasRef = useRef<HTMLCanvasElement>(null);
    const fileInputImageRef = useRef<HTMLInputElement>(null);
    const fileInputVideoRef = useRef<HTMLInputElement>(null);

    // --- Helpers for Controls ---
    const updateSlotParam = (index: number, updates: Partial<SlotParams>) => {
        setSlotParams(prev => {
            const next = [...prev];
            next[index] = { ...next[index], ...updates };
            return next;
        });
    };

    const setMode = (index: number, mode: RenderMode) => {
        setModes(prev => {
            const next = [...prev];
            next[index] = mode;
            return next;
        });
    };

    // --- AI Model Loading ---
    const loadModel = async () => {
        if (depthEstimator) { setStatus('Model already loaded.'); return; }
        try {
            setStatus('Loading model...');
            const estimator = await pipeline('depth-estimation', model_loc, {
                progress_callback: (progress: any) => {
                    if (progress.status === 'progress' && typeof progress.progress === 'number') {
                        setStatus(`Loading model... ${progress.progress.toFixed(2)}%`);
                    } else {
                        setStatus(progress.status);
                    }
                },
                quantized: false
            });
            setDepthEstimator(() => estimator);
            setStatus('Model Loaded. Processing initial image...');
            
            // Re-process current image if possible, but we need the URL. 
            // For now, next image load will trigger it, or user can click 'Load Random'.
        } catch (e: any) {
            console.error(e);
            setStatus(`Failed to load model: ${e.message}`);
        }
    };

    // --- Depth Analysis Logic ---
    const runDepthAnalysis = useCallback(async (imageUrl: string) => {
        if (!depthEstimator || !rendererRef.current) return;
        setStatus('Analyzing image with AI model...');
        try {
            const result = await depthEstimator(imageUrl);
            const { data, dims } = result.predicted_depth;
            const [height, width] = [dims[dims.length - 2], dims[dims.length - 1]];

            let min = Infinity, max = -Infinity;
            let minIndex = 0;
            data.forEach((v: number, i: number) => {
                if (v < min) {
                    min = v;
                    minIndex = i;
                }
                if (v > max) max = v;
            });

            const farthestY = Math.floor(minIndex / width);
            const farthestX = minIndex % width;
            setFarthestPoint({ x: farthestX / width, y: farthestY / height });

            const range = max - min;
            const normalizedData = new Float32Array(data.length);

            for (let i = 0; i < data.length; ++i) {
                normalizedData[i] = 1.0 - ((data[i] - min) / range);
            }

            setStatus('Updating depth map on GPU...');
            rendererRef.current.updateDepthMap(normalizedData, width, height);

            setDepthMapResult(result);
            setStatus('Ready.');
        } catch (e: any) {
            console.error("Error during analysis:", e);
            setStatus(`Failed to analyze image: ${e.message}`);
        }
    }, [depthEstimator]);

    // --- Handlers: Image/Video Loading ---
    const handleNewImage = useCallback(async () => {
        if (!rendererRef.current) return;
        setStatus('Loading random image...');
        const newImageUrl = await rendererRef.current.loadRandomImage();
        if (newImageUrl) {
            if (depthEstimator) {
                await runDepthAnalysis(newImageUrl);
            } else {
                setFarthestPoint({ x: 0.5, y: 0.5 });
                setStatus('Ready. Load AI model to add depth effects.');
            }
        } else {
            setStatus('Failed to load a random image.');
        }
    }, [depthEstimator, runDepthAnalysis]);

    const handleUploadImage = useCallback(async (event: React.ChangeEvent<HTMLInputElement>) => {
        const file = event.target.files?.[0];
        if (file && rendererRef.current) {
            const url = URL.createObjectURL(file);
            setStatus('Loading uploaded image...');
            await rendererRef.current.loadImage(url);
            setInputSource('image');
            if (depthEstimator) {
                await runDepthAnalysis(url);
            } else {
                setFarthestPoint({ x: 0.5, y: 0.5 });
                setStatus('Uploaded image loaded.');
            }
        }
    }, [depthEstimator, runDepthAnalysis]);

    const handleUploadVideo = useCallback((event: React.ChangeEvent<HTMLInputElement>) => {
        const file = event.target.files?.[0];
        if (file) {
            const url = URL.createObjectURL(file);
            setVideoSourceUrl(url);
            setInputSource('video');
            setStatus('Playing uploaded video.');
        }
    }, []);

    // --- Effects ---

    // Auto-change Image
    useEffect(() => {
        let intervalId: NodeJS.Timeout | null = null;
        if (autoChangeEnabled && inputSource === 'image') {
            intervalId = setInterval(handleNewImage, autoChangeDelay * 1000);
        }
        return () => { if (intervalId) clearInterval(intervalId); };
    }, [autoChangeEnabled, autoChangeDelay, handleNewImage, inputSource]);

    // Debug Canvas Update
    useEffect(() => {
        if (depthMapResult?.predicted_depth && debugCanvasRef.current) {
            const { data, dims } = depthMapResult.predicted_depth;
            const [height, width] = [dims[dims.length - 2], dims[dims.length - 1]];
            const canvas = debugCanvasRef.current;
            const context = canvas.getContext('2d');
            if (!width || !height || !context) return;

            canvas.width = width;
            canvas.height = height;
            const imageData = context.createImageData(width, height);

            let min = Infinity, max = -Infinity;
            data.forEach((v: number) => {
                if (v < min) min = v;
                if (v > max) max = v;
            });

            const range = max - min;
            for (let i = 0; i < data.length; ++i) {
                const val = (data[i] - min) / range;
                const idx = i * 4;
                const c = Math.floor(val * 255);
                imageData.data[idx] = c;
                imageData.data[idx + 1] = c;
                imageData.data[idx + 2] = c;
                imageData.data[idx + 3] = 255;
            }
            context.putImageData(imageData, 0, 0);
        }
    }, [depthMapResult]);

    // --- Sync Logic (Handling Commands from Remote) ---
    const broadcastState = useCallback((channel: BroadcastChannel) => {
        const state: FullState = {
            modes, activeSlot, slotParams, shaderCategory,
            zoom, panX, panY, inputSource,
            autoChangeEnabled, autoChangeDelay,
            isModelLoaded: !!depthEstimator,
            availableModes,
            videoList, selectedVideo, isMuted
        };
        channel.postMessage({ type: 'STATE_FULL', payload: state });
    }, [modes, activeSlot, slotParams, shaderCategory, zoom, panX, panY, inputSource, autoChangeEnabled, autoChangeDelay, depthEstimator, availableModes, videoList, selectedVideo, isMuted]);

    useEffect(() => {
        const channel = new BroadcastChannel(SYNC_CHANNEL_NAME);
        
        channel.onmessage = async (event) => {
             const msg = event.data as SyncMessage;
             switch (msg.type) {
                 case 'HELLO':
                     broadcastState(channel);
                     break;
                 case 'CMD_SET_MODE':
                     if (msg.payload) setMode(msg.payload.index, msg.payload.mode);
                     break;
                 case 'CMD_SET_ACTIVE_SLOT':
                     setActiveSlot(msg.payload);
                     break;
                 case 'CMD_UPDATE_SLOT_PARAM':
                     updateSlotParam(msg.payload.index, msg.payload.updates);
                     break;
                 case 'CMD_SET_SHADER_CATEGORY':
                     setShaderCategory(msg.payload);
                     break;
                 case 'CMD_SET_ZOOM':
                     setZoom(msg.payload);
                     break;
                 case 'CMD_SET_PAN_X':
                     setPanX(msg.payload);
                     break;
                 case 'CMD_SET_PAN_Y':
                     setPanY(msg.payload);
                     break;
                 case 'CMD_SET_INPUT_SOURCE':
                     setInputSource(msg.payload);
                     break;
                 case 'CMD_SET_AUTO_CHANGE':
                     setAutoChangeEnabled(msg.payload);
                     break;
                 case 'CMD_SET_AUTO_CHANGE_DELAY':
                     setAutoChangeDelay(msg.payload);
                     break;
                 case 'CMD_LOAD_RANDOM_IMAGE':
                     handleNewImage();
                     break;
                 case 'CMD_LOAD_MODEL':
                     loadModel();
                     break;
                 case 'CMD_SELECT_VIDEO':
                     setSelectedVideo(msg.payload);
                     break;
                 case 'CMD_SET_MUTED':
                     setIsMuted(msg.payload);
                     break;
                 case 'CMD_UPLOAD_FILE':
                     // msg.payload: { name, type, mimeType, data: ArrayBuffer }
                     const blob = new Blob([msg.payload.data], { type: msg.payload.mimeType });
                     const url = URL.createObjectURL(blob);
                     if (msg.payload.type === 'image') {
                         if (rendererRef.current) {
                            await rendererRef.current.loadImage(url);
                             if (depthEstimator) runDepthAnalysis(url);
                         }
                         setInputSource('image');
                     } else {
                         setVideoSourceUrl(url);
                         setInputSource('video');
                     }
                     break;
             }
        };
        
        // Heartbeat
        const hbInterval = setInterval(() => {
            channel.postMessage({ type: 'HEARTBEAT' });
        }, 1000);

        return () => {
            channel.close();
            clearInterval(hbInterval);
        };
    }, [depthEstimator, runDepthAnalysis, broadcastState, handleNewImage]); 

    // Broadcast on state change
    useEffect(() => {
        const channel = new BroadcastChannel(SYNC_CHANNEL_NAME);
        broadcastState(channel);
        return () => channel.close();
    }, [broadcastState]);

    const openRemote = () => {
        const url = new URL(window.location.href);
        url.searchParams.set('mode', 'remote');
        window.open(url.toString(), '_blank', 'width=400,height=800');
    };

    return (
        <div className="App">
            <header className="header">
                <div className="logo-section">
                    <div className="logo-text">Pixelocity</div>
                    <div className="subtitle-text">WebGPU Shader Playground</div>
                </div>
                <div className="header-controls">
                    <button className="toggle-sidebar-btn" onClick={openRemote}>
                         Open Remote
                    </button>
                    <button className="toggle-sidebar-btn" onClick={() => setShowSidebar(!showSidebar)}>
                        {showSidebar ? 'Hide Controls' : 'Show Controls'}
                    </button>
                </div>
            </header>

            <div className="main-container">
                <aside className={`sidebar ${!showSidebar ? 'hidden' : ''}`}>
                    <Controls
                        modes={modes}
                        setMode={setMode}
                        activeSlot={activeSlot}
                        setActiveSlot={setActiveSlot}
                        slotParams={slotParams}
                        updateSlotParam={updateSlotParam}
                        shaderCategory={shaderCategory}
                        setShaderCategory={setShaderCategory}
                        zoom={zoom} setZoom={setZoom}
                        panX={panX} setPanX={setPanX}
                        panY={panY} setPanY={setPanY}
                        onNewImage={handleNewImage}
                        autoChangeEnabled={autoChangeEnabled}
                        setAutoChangeEnabled={setAutoChangeEnabled}
                        autoChangeDelay={autoChangeDelay}
                        setAutoChangeDelay={setAutoChangeDelay}
                        onLoadModel={loadModel}
                        isModelLoaded={!!depthEstimator}
                        availableModes={availableModes}
                        inputSource={inputSource}
                        setInputSource={setInputSource}
                        videoList={videoList}
                        selectedVideo={selectedVideo}
                        setSelectedVideo={setSelectedVideo}
                        isMuted={isMuted}
                        setIsMuted={setIsMuted}
                        onUploadImageTrigger={() => fileInputImageRef.current?.click()}
                        onUploadVideoTrigger={() => fileInputVideoRef.current?.click()}
                    />
                </aside>

                <main className="canvas-container">
                    <WebGPUCanvas
                        modes={modes}
                        slotParams={slotParams}
                        zoom={zoom}
                        panX={panX}
                        panY={panY}
                        rendererRef={rendererRef}
                        farthestPoint={farthestPoint}
                        mousePosition={mousePosition}
                        setMousePosition={setMousePosition}
                        isMouseDown={isMouseDown}
                        setIsMouseDown={setIsMouseDown}
                        onInit={() => {
                        if(rendererRef.current) {
                            setAvailableModes(rendererRef.current.getAvailableModes());
                        }
                        }}
                        inputSource={inputSource}
                        selectedVideo={selectedVideo}
                        videoSourceUrl={videoSourceUrl}
                        isMuted={isMuted}
                        setInputSource={setInputSource}
                    />
                    <div className="status-bar">{status}</div>
                </main>
            </div>

            {/* Hidden Input Elements */}
            <input type="file" ref={fileInputImageRef} accept="image/*" style={{display:'none'}} onChange={handleUploadImage} />
            <input type="file" ref={fileInputVideoRef} accept="video/*" style={{display:'none'}} onChange={handleUploadVideo} />
            <canvas ref={debugCanvasRef} style={{ display: 'none' }} />
        </div>
    );
}

export default MainApp;
