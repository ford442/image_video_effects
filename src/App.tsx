import React, { useState, useEffect, useCallback, useRef } from 'react';
import WebGPUCanvas from './components/WebGPUCanvas';
import Controls from './components/Controls';
import RemoteApp from './RemoteApp';
import { Renderer } from './renderer/Renderer';
import { RenderMode, ShaderEntry, ShaderCategory, InputSource, SlotParams } from './renderer/types';
import { SyncMessage, FullState, SYNC_CHANNEL_NAME } from './syncTypes';
import { pipeline, env } from '@xenova/transformers';
import './style.css';

env.allowLocalModels = false;
env.backends.onnx.logLevel = 'warning';
const model_loc = 'Xenova/dpt-hybrid-midas';

function MainApp() {
    // eslint-disable-next-line react-hooks/rules-of-hooks
    const [shaderCategory, setShaderCategory] = useState<ShaderCategory>('image');
    
    // Default Parameters
    const DEFAULT_SLOT_PARAMS: SlotParams = {
        zoomParam1: 0.5, zoomParam2: 0.5, zoomParam3: 0.5, zoomParam4: 0.5,
        lightStrength: 1.0, ambient: 0.2, normalStrength: 0.1, fogFalloff: 4.0, depthThreshold: 0.5,
    };

    // Stacking State
    const [modes, setModes] = useState<RenderMode[]>(['liquid', 'none', 'none']);
    const [activeSlot, setActiveSlot] = useState<number>(0);
    const [slotParams, setSlotParams] = useState<SlotParams[]>([
        { ...DEFAULT_SLOT_PARAMS },
        { ...DEFAULT_SLOT_PARAMS },
        { ...DEFAULT_SLOT_PARAMS }
    ]);

    const [zoom, setZoom] = useState(1.0);
    const [panX, setPanX] = useState(0.5);
    const [panY, setPanY] = useState(0.5);
    const [autoChangeEnabled, setAutoChangeEnabled] = useState(false);
    const [autoChangeDelay, setAutoChangeDelay] = useState(10);
    const [status, setStatus] = useState('Ready. Click "Load AI Model" for depth effects.');
    const [depthEstimator, setDepthEstimator] = useState<any>(null);
    const [depthMapResult, setDepthMapResult] = useState<any>(null);
    const [farthestPoint, setFarthestPoint] = useState({ x: 0.5, y: 0.5 });
    const [mousePosition, setMousePosition] = useState({ x: -1, y: -1 });
    const [isMouseDown, setIsMouseDown] = useState(false);
    const [availableModes, setAvailableModes] = useState<ShaderEntry[]>([]);

    // Video/Input State
    const [inputSource, setInputSource] = useState<InputSource>('image');
    const [videoList, setVideoList] = useState<string[]>([]);
    const [selectedVideo, setSelectedVideo] = useState<string>(''); // For stock videos
    const [videoSourceUrl, setVideoSourceUrl] = useState<string | undefined>(undefined); // For uploaded videos
    const [isMuted, setIsMuted] = useState(true);

    const rendererRef = useRef<Renderer | null>(null);
    const debugCanvasRef = useRef<HTMLCanvasElement>(null);
    const fileInputImageRef = useRef<HTMLInputElement>(null);
    const fileInputVideoRef = useRef<HTMLInputElement>(null);

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
        } catch (e: any) {
            console.error(e);
            setStatus(`Failed to load model: ${e.message}`);
        }
    };

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

    useEffect(() => {
        let intervalId: NodeJS.Timeout | null = null;
        if (autoChangeEnabled && inputSource === 'image') {
            intervalId = setInterval(handleNewImage, autoChangeDelay * 1000);
        }
        return () => { if (intervalId) clearInterval(intervalId); };
    }, [autoChangeEnabled, autoChangeDelay, handleNewImage, inputSource]);

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
                const value = Math.round(((data[i] - min) / range) * 255);
                imageData.data[i * 4 + 0] = value;
                imageData.data[i * 4 + 1] = value;
                imageData.data[i * 4 + 2] = value;
                imageData.data[i * 4 + 3] = 255;
            }
            context.putImageData(imageData, 0, 0);
        }
    }, [depthMapResult]);

    const handleInit = useCallback(() => {
        if (rendererRef.current) {
            setAvailableModes(rendererRef.current.getAvailableModes());
            rendererRef.current.setInputSource(inputSource);
        }
    }, [inputSource]);

    useEffect(() => {
        if (rendererRef.current) {
            rendererRef.current.setInputSource(inputSource);
        }
        // If switching to standard video input, ensure we clear custom source unless we meant to keep it.
        // But here we rely on selectedVideo vs videoSourceUrl.
        if (inputSource === 'video' && !videoSourceUrl && selectedVideo) {
            // Logic handled in Canvas
        }
    }, [inputSource, videoSourceUrl, selectedVideo]);

    const updateSlotParam = (slotIndex: number, updates: Partial<SlotParams>) => {
        setSlotParams(prev => {
            const next = [...prev];
            next[slotIndex] = { ...next[slotIndex], ...updates };
            return next;
        });
    };

    const applyModeDefaults = (mode: string, slotIndex: number) => {
         const defaults: any = {};
        if (mode === 'rain') defaults.zoomParam1 = 0.08;
        else if (mode === 'chromatic-manifold') { defaults.zoomParam3 = 0.9; defaults.zoomParam4 = 0.9; }
        else if (mode === 'spectral-vortex') { defaults.zoomParam1 = 2.0; defaults.zoomParam2 = 0.02; defaults.zoomParam3 = 0.1; defaults.zoomParam4 = 0.0; }
        else if (mode === 'quantum-fractal') { defaults.zoomParam1 = 3.0; defaults.zoomParam2 = 100.0; defaults.zoomParam3 = 1.0; defaults.zoomParam4 = 0.0; }

        if (Object.keys(defaults).length > 0) {
            updateSlotParam(slotIndex, defaults);
        }
    };

    const handleModeChange = (index: number, newMode: RenderMode) => {
        setModes(prev => {
            const next = [...prev];
            next[index] = newMode;
            return next;
        });
        applyModeDefaults(newMode, index);
    };

    // --- Remote Sync Logic ---
    const channelRef = useRef<BroadcastChannel | null>(null);
    const latestHandlers = useRef({ handleModeChange, updateSlotParam, handleNewImage, loadModel });
    latestHandlers.current = { handleModeChange, updateSlotParam, handleNewImage, loadModel };

    const broadcastState = useCallback(() => {
        if (!channelRef.current) return;
        const state: FullState = {
            modes, activeSlot, slotParams, shaderCategory, zoom, panX, panY,
            inputSource, autoChangeEnabled, autoChangeDelay,
            isModelLoaded: !!depthEstimator, availableModes,
            videoList, selectedVideo, isMuted
        };
        channelRef.current.postMessage({ type: 'STATE_FULL', payload: state });
    }, [modes, activeSlot, slotParams, shaderCategory, zoom, panX, panY, inputSource, autoChangeEnabled, autoChangeDelay, depthEstimator, availableModes, videoList, selectedVideo, isMuted]);

    const broadcastStateRef = useRef(broadcastState);
    broadcastStateRef.current = broadcastState;

    useEffect(() => {
        broadcastState();
    }, [broadcastState]);

    useEffect(() => {
        const channel = new BroadcastChannel(SYNC_CHANNEL_NAME);
        channelRef.current = channel;

        // Broadcast initial state
        broadcastStateRef.current();

        channel.onmessage = async (event) => {
            const msg = event.data as SyncMessage;
            switch (msg.type) {
                case 'HELLO':
                    broadcastStateRef.current();
                    break;
                case 'CMD_SET_MODE':
                    latestHandlers.current.handleModeChange(msg.payload.index, msg.payload.mode);
                    break;
                case 'CMD_SET_ACTIVE_SLOT':
                    setActiveSlot(msg.payload);
                    break;
                case 'CMD_UPDATE_SLOT_PARAM':
                    latestHandlers.current.updateSlotParam(msg.payload.index, msg.payload.updates);
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
                    latestHandlers.current.handleNewImage();
                    break;
                case 'CMD_LOAD_MODEL':
                    latestHandlers.current.loadModel();
                    break;
                case 'CMD_SELECT_VIDEO':
                    setSelectedVideo(msg.payload);
                    setVideoSourceUrl(undefined);
                    break;
                case 'CMD_SET_MUTED':
                    setIsMuted(msg.payload);
                    break;
                case 'CMD_UPLOAD_FILE':
                    const { type, mimeType, data } = msg.payload;
                    const blob = new Blob([data], { type: mimeType });
                    const url = URL.createObjectURL(blob);
                    if (type === 'image') {
                        if (rendererRef.current) {
                           rendererRef.current.loadImage(url);
                           setInputSource('image');
                        }
                    } else if (type === 'video') {
                        setVideoSourceUrl(url);
                        setInputSource('video');
                    }
                    break;
            }
        };

        const heartbeatInterval = setInterval(() => {
             channel.postMessage({ type: 'HEARTBEAT' });
        }, 1000);

        return () => {
            channel.close();
            channelRef.current = null;
            clearInterval(heartbeatInterval);
        };
    }, []);

    useEffect(() => {
        const fetchVideos = async () => {
            try {
                const response = await fetch('videos/');
                if (response.ok) {
                    const text = await response.text();
                    const parser = new DOMParser();
                    const doc = parser.parseFromString(text, 'text/html');
                    const links = Array.from(doc.querySelectorAll('a'));
                    const videos = links
                        .map(link => link.getAttribute('href'))
                        .filter(href => href && /\.(mp4|webm|mov)$/i.test(href))
                        .map(href => {
                            const parts = href!.split('/');
                            return parts[parts.length - 1];
                        });

                    const uniqueVideos = Array.from(new Set(videos));
                    if (uniqueVideos.length > 0) {
                        setVideoList(uniqueVideos as string[]);
                        if (!selectedVideo) setSelectedVideo(uniqueVideos[0]);
                    }
                }
            } catch (e) {
                console.error("Failed to fetch video list", e);
            }
        };

        fetchVideos();
    }, []);

    const openRemote = () => {
        const url = new URL(window.location.href);
        url.searchParams.set('mode', 'remote');
        window.open(url.toString(), 'remote_control', 'width=450,height=900,menubar=no,toolbar=no');
    };

    return (
        <div id="app-container">
            {/* Hidden Inputs */}
            <input
                type="file"
                accept="image/*"
                ref={fileInputImageRef}
                style={{display: 'none'}}
                onChange={handleUploadImage}
            />
            <input
                type="file"
                accept="video/*"
                ref={fileInputVideoRef}
                style={{display: 'none'}}
                onChange={handleUploadVideo}
            />

            <h1>
                WebGPU Liquid + Depth Effect
                <button
                    onClick={openRemote}
                    style={{marginLeft: '20px', fontSize: '16px', padding: '5px 10px', cursor: 'pointer', verticalAlign: 'middle', background: '#444', color: 'white', border: '1px solid #666', borderRadius: '4px'}}
                >
                    📱 Open Remote
                </button>
            </h1>
            <p><strong>Status:</strong> {status}</p>
            <Controls
                modes={modes}
                setMode={handleModeChange}
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
                setSelectedVideo={(v) => { setSelectedVideo(v); setVideoSourceUrl(undefined); }} // Clear custom upload if selecting stock
                isMuted={isMuted}
                setIsMuted={setIsMuted}
                // New Props Handlers
                onUploadImageTrigger={() => fileInputImageRef.current?.click()}
                onUploadVideoTrigger={() => fileInputVideoRef.current?.click()}
            />
            
            <WebGPUCanvas
                rendererRef={rendererRef}
                modes={modes}
                slotParams={slotParams}
                zoom={zoom}
                panX={panX}
                panY={panY}
                farthestPoint={farthestPoint}
                mousePosition={mousePosition}
                setMousePosition={setMousePosition}
                isMouseDown={isMouseDown}
                setIsMouseDown={setIsMouseDown}
                onInit={handleInit}
                inputSource={inputSource}
                selectedVideo={selectedVideo}
                videoSourceUrl={videoSourceUrl}
                isMuted={isMuted}
                setInputSource={setInputSource}
            />
            {depthMapResult && (
                <div className="debug-container">
                    <h2>AI Model Output (Debug Depth Map)</h2>
                    <canvas ref={debugCanvasRef} style={{ maxWidth: '100%', height: 'auto', border: '1px solid grey' }} />
                </div>
            )}
        </div>
    );
}

function App() {
    const isRemote = new URLSearchParams(window.location.search).get('mode') === 'remote';
    return isRemote ? <RemoteApp /> : <MainApp />;
}

export default App;
