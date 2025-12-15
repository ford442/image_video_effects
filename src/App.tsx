import React, { useState, useEffect, useCallback, useRef } from 'react';
import WebGPUCanvas from './components/WebGPUCanvas';
import Controls from './components/Controls';
import { Renderer } from './renderer/Renderer';
import { RenderMode, ShaderEntry, ShaderCategory, InputSource, SlotParams } from './renderer/types';
import { pipeline, env } from '@xenova/transformers';
import './style.css';

env.allowLocalModels = false;
env.backends.onnx.logLevel = 'warning';
const model_loc = 'Xenova/dpt-hybrid-midas';

const CHANNEL_NAME = 'webgpu_remote_control';

function App() {
    // ------------------------------------------------------------------------
    // STATE DECLARATIONS
    // ------------------------------------------------------------------------
    const [isRemote] = useState(() => new URLSearchParams(window.location.search).get('remote') === 'true');
    const [shaderCategory, setShaderCategory] = useState<ShaderCategory>('image');
    
    // Default Parameters
    const DEFAULT_SLOT_PARAMS: SlotParams = {
        zoomParam1: 0.5, zoomParam2: 0.5, zoomParam3: 0.5, zoomParam4: 0.5,
        lightStrength: 1.0, ambient: 0.2, normalStrength: 0.1, fogFalloff: 4.0, depthThreshold: 0.5,
    };

    const [modes, setModes] = useState<RenderMode[]>(['liquid', 'none', 'none']);
    const [activeSlot, setActiveSlot] = useState<number>(0);
    const [slotParams, setSlotParams] = useState<SlotParams[]>([
        { ...DEFAULT_SLOT_PARAMS }, { ...DEFAULT_SLOT_PARAMS }, { ...DEFAULT_SLOT_PARAMS }
    ]);

    const [zoom, setZoom] = useState(1.0);
    const [panX, setPanX] = useState(0.5);
    const [panY, setPanY] = useState(0.5);
    const [autoChangeEnabled, setAutoChangeEnabled] = useState(false);
    const [autoChangeDelay, setAutoChangeDelay] = useState(10);
    const [status, setStatus] = useState('Ready. Click "Load AI Model" for depth effects.');
    
    // AI & Canvas State
    const [depthEstimator, setDepthEstimator] = useState<any>(null);
    const [depthMapResult, setDepthMapResult] = useState<any>(null);
    const [farthestPoint, setFarthestPoint] = useState({ x: 0.5, y: 0.5 });
    const [mousePosition, setMousePosition] = useState({ x: -1, y: -1 });
    const [isMouseDown, setIsMouseDown] = useState(false);
    const [availableModes, setAvailableModes] = useState<ShaderEntry[]>([]);

    // Video Input State
    const [inputSource, setInputSource] = useState<InputSource>('image');
    const [videoList, setVideoList] = useState<string[]>([]);
    const [selectedVideo, setSelectedVideo] = useState<string>('');
    const [isMuted, setIsMuted] = useState(true);

    const rendererRef = useRef<Renderer | null>(null);
    const debugCanvasRef = useRef<HTMLCanvasElement>(null);
    const channelRef = useRef<BroadcastChannel | null>(null);

    // ------------------------------------------------------------------------
    // HELPER FUNCTIONS (Shared Logic)
    // ------------------------------------------------------------------------

    // Helper to update params for a specific slot
    const updateSlotParam = useCallback((slotIndex: number, updates: Partial<SlotParams>) => {
        setSlotParams(prev => {
            const next = [...prev];
            next[slotIndex] = { ...next[slotIndex], ...updates };
            return next;
        });
    }, []);

    // Helper for mode specific defaults
    const applyModeDefaults = useCallback((mode: string, slotIndex: number) => {
        const defaults: any = {};
        if (mode === 'rain') defaults.zoomParam1 = 0.08;
        else if (mode === 'chromatic-manifold') { defaults.zoomParam3 = 0.9; defaults.zoomParam4 = 0.9; }
        else if (mode === 'spectral-vortex') { defaults.zoomParam1 = 2.0; defaults.zoomParam2 = 0.02; defaults.zoomParam3 = 0.1; defaults.zoomParam4 = 0.0; }
        else if (mode === 'quantum-fractal') { defaults.zoomParam1 = 3.0; defaults.zoomParam2 = 100.0; defaults.zoomParam3 = 1.0; defaults.zoomParam4 = 0.0; }
        
        if (Object.keys(defaults).length > 0) {
            updateSlotParam(slotIndex, defaults);
        }
    }, [updateSlotParam]);

    // ------------------------------------------------------------------------
    // MAIN APP LOGIC (Only runs if !isRemote)
    // ------------------------------------------------------------------------

    const loadModel = async () => {
        if (depthEstimator) { setStatus('Model already loaded.'); return; }
        try {
            setStatus('Loading model...');
            // In remote, we just trigger; actual loading happens in main.
            if (isRemote) return; 

            const estimator = await pipeline('depth-estimation', model_loc, {
                progress_callback: (progress: any) => {
                    if (progress.status === 'progress') {
                        const msg = `Loading model... ${progress.progress.toFixed(2)}%`;
                        setStatus(msg);
                        channelRef.current?.postMessage({ type: 'SYNC_STATUS', payload: msg });
                    } else {
                        setStatus(progress.status);
                    }
                },
                quantized: false
            });
            setDepthEstimator(() => estimator);
            setStatus('Model Loaded. Processing initial image...');
            channelRef.current?.postMessage({ type: 'SYNC_STATUS', payload: 'Model Loaded. Processing initial image...' });
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
                if (v < min) { min = v; minIndex = i; }
                if (v > max) max = v;
            });

            const farthestY = Math.floor(minIndex / width);
            const farthestX = minIndex % width;
            setFarthestPoint({ x: farthestX / width, y: farthestY / height });

            const range = max - min;
            const normalizedData = new Float32Array(data.length);
            for (let i = 0; i < data.length; ++i) normalizedData[i] = 1.0 - ((data[i] - min) / range);

            setStatus('Updating depth map on GPU...');
            rendererRef.current.updateDepthMap(normalizedData, width, height);

            setDepthMapResult(result);
            setStatus('Ready.');
        } catch (e: any) {
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

    // ------------------------------------------------------------------------
    // COMMUNICATION & REMOTE CONTROL LOGIC
    // ------------------------------------------------------------------------

    const broadcastState = useCallback(() => {
        if (!channelRef.current) return;
        channelRef.current.postMessage({
            type: 'STATE_SYNC',
            payload: {
                zoom, panX, panY, modes, activeSlot, slotParams,
                shaderCategory, inputSource, selectedVideo, isMuted,
                autoChangeEnabled, autoChangeDelay, status,
                isModelLoaded: !!depthEstimator,
                availableModes: availableModes, // Crucial for remote to populate lists
                videoList: videoList
            }
        });
    }, [zoom, panX, panY, modes, activeSlot, slotParams, shaderCategory, inputSource, selectedVideo, isMuted, autoChangeEnabled, autoChangeDelay, status, depthEstimator, availableModes, videoList]);

    useEffect(() => {
        const ch = new BroadcastChannel(CHANNEL_NAME);
        channelRef.current = ch;

        ch.onmessage = (event) => {
            const { type, payload } = event.data;
            
            // LOGIC FOR REMOTE TAB
            if (isRemote) {
                if (type === 'STATE_SYNC') {
                    setZoom(payload.zoom);
                    setPanX(payload.panX);
                    setPanY(payload.panY);
                    setModes(payload.modes);
                    setActiveSlot(payload.activeSlot);
                    setSlotParams(payload.slotParams);
                    setShaderCategory(payload.shaderCategory);
                    setInputSource(payload.inputSource);
                    setSelectedVideo(payload.selectedVideo);
                    setIsMuted(payload.isMuted);
                    setAutoChangeEnabled(payload.autoChangeEnabled);
                    setAutoChangeDelay(payload.autoChangeDelay);
                    setStatus(payload.status);
                    setAvailableModes(payload.availableModes || []);
                    setVideoList(payload.videoList || []);
                    // We mock depthEstimator presence with a flag if needed, 
                    // but Controls uses isModelLoaded prop which we derived in payload
                    if (payload.isModelLoaded) setDepthEstimator(true); // Mock for UI state
                }
                if (type === 'SYNC_STATUS') {
                    setStatus(payload);
                }
            } 
            
            // LOGIC FOR MAIN APP
            else {
                if (type === 'REQUEST_SYNC') broadcastState();
                
                // Setters
                if (type === 'SET_ZOOM') setZoom(payload);
                if (type === 'SET_PAN_X') setPanX(payload);
                if (type === 'SET_PAN_Y') setPanY(payload);
                if (type === 'SET_SHADER_CATEGORY') setShaderCategory(payload);
                if (type === 'SET_INPUT_SOURCE') setInputSource(payload);
                if (type === 'SET_SELECTED_VIDEO') setSelectedVideo(payload);
                if (type === 'SET_IS_MUTED') setIsMuted(payload);
                if (type === 'SET_AUTO_CHANGE_ENABLED') setAutoChangeEnabled(payload);
                if (type === 'SET_AUTO_CHANGE_DELAY') setAutoChangeDelay(payload);
                if (type === 'SET_ACTIVE_SLOT') setActiveSlot(payload);
                
                if (type === 'SET_MODE') {
                    const { index, mode } = payload;
                    setModes(prev => {
                        const next = [...prev];
                        next[index] = mode;
                        return next;
                    });
                    applyModeDefaults(mode, index);
                }

                if (type === 'UPDATE_SLOT_PARAM') {
                    const { index, updates } = payload;
                    updateSlotParam(index, updates);
                }

                if (type === 'TRIGGER_NEW_IMAGE') handleNewImage();
                if (type === 'TRIGGER_LOAD_MODEL') loadModel();
            }
        };

        if (isRemote) {
            // Ask Main for initial state
            ch.postMessage({ type: 'REQUEST_SYNC' });
        }

        return () => ch.close();
    }, [isRemote, broadcastState, handleNewImage, applyModeDefaults, updateSlotParam]);

    // Send Sync when critical Main state changes (optional but good for keeping remote updated)
    useEffect(() => {
        if (!isRemote) {
            // Debounce or just sync on major changes? 
            // For now, let's just sync when Available Modes changes (init)
            if (availableModes.length > 0) broadcastState();
        }
    }, [availableModes, isRemote, broadcastState]);


    // ------------------------------------------------------------------------
    // REMOTE CONTROL WRAPPERS
    // ------------------------------------------------------------------------
    // These functions update local state (optimistic UI) AND send message to channel
    
    // CHANGED: localSetter type includes 'null' to fix TS error
    const wrapSender = (type: string, localSetter: Function | null, payload?: any) => {
        if (localSetter) localSetter(payload);
        channelRef.current?.postMessage({ type, payload });
    };

    const handleRemoteModeChange = (index: number, mode: RenderMode) => {
        setModes(prev => { const n = [...prev]; n[index] = mode; return n; });
        applyModeDefaults(mode, index); // Apply locally for immediate UI feedback
        channelRef.current?.postMessage({ type: 'SET_MODE', payload: { index, mode } });
    };

    const handleRemoteParamChange = (index: number, updates: Partial<SlotParams>) => {
        updateSlotParam(index, updates);
        channelRef.current?.postMessage({ type: 'UPDATE_SLOT_PARAM', payload: { index, updates } });
    };

    // ------------------------------------------------------------------------
    // EFFECT RUNNERS (Main Only)
    // ------------------------------------------------------------------------

    useEffect(() => {
        let intervalId: NodeJS.Timeout | null = null;
        if (!isRemote && autoChangeEnabled && inputSource === 'image') {
            intervalId = setInterval(handleNewImage, autoChangeDelay * 1000);
        }
        return () => { if (intervalId) clearInterval(intervalId); };
    }, [isRemote, autoChangeEnabled, autoChangeDelay, handleNewImage, inputSource]);

    const handleInit = useCallback(() => {
        if (rendererRef.current) {
            const modes = rendererRef.current.getAvailableModes();
            setAvailableModes(modes);
            rendererRef.current.setInputSource(inputSource);
            // Sync to remote once initialized
            setTimeout(broadcastState, 500); 
        }
    }, [inputSource, broadcastState]);

    useEffect(() => {
        if (!isRemote && rendererRef.current) rendererRef.current.setInputSource(inputSource);
    }, [inputSource, isRemote]);

    // Fetch video list (Main Only, then synced)
    useEffect(() => {
        if (isRemote) return; // Remote gets list via Sync
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
                    const unique = Array.from(new Set(videos)) as string[];
                    if (unique.length > 0) {
                        setVideoList(unique);
                        if (!selectedVideo) setSelectedVideo(unique[0]);
                    }
                }
            } catch (e) { console.error("Failed to fetch videos", e); }
        };
        fetchVideos();
    }, [isRemote, selectedVideo]);

    // Debug Canvas Update (Main Only)
    useEffect(() => {
        if (!isRemote && depthMapResult?.predicted_depth && debugCanvasRef.current) {
             const { data, dims } = depthMapResult.predicted_depth;
             const [height, width] = [dims[dims.length - 2], dims[dims.length - 1]];
             const canvas = debugCanvasRef.current;
             const ctx = canvas.getContext('2d');
             if(ctx) {
                 canvas.width = width; canvas.height = height;
                 const imgData = ctx.createImageData(width, height);
                 let min = Infinity, max = -Infinity;
                 data.forEach((v:number) => { if(v<min) min=v; if(v>max) max=v; });
                 const range = max - min;
                 for(let i=0; i<data.length; i++) {
                     const val = Math.round(((data[i]-min)/range)*255);
                     imgData.data[i*4]=val; imgData.data[i*4+1]=val; imgData.data[i*4+2]=val; imgData.data[i*4+3]=255;
                 }
                 ctx.putImageData(imgData, 0, 0);
             }
        }
    }, [depthMapResult, isRemote]);


    // ------------------------------------------------------------------------
    // RENDER
    // ------------------------------------------------------------------------

    if (isRemote) {
        return (
            <div id="remote-container" style={{ padding: '20px', background: '#111', color: '#eee', minHeight: '100vh', fontFamily: 'sans-serif' }}>
                <h2 style={{borderBottom: '1px solid #444', paddingBottom: '10px'}}>Remote Control</h2>
                <div style={{marginBottom: '10px', fontSize: '0.9em', color: '#aaa'}}>Status: {status}</div>
                
                <Controls
                    modes={modes}
                    setMode={handleRemoteModeChange}
                    activeSlot={activeSlot}
                    setActiveSlot={(idx) => wrapSender('SET_ACTIVE_SLOT', setActiveSlot, idx)}
                    slotParams={slotParams}
                    updateSlotParam={handleRemoteParamChange}
                    shaderCategory={shaderCategory}
                    setShaderCategory={(cat) => wrapSender('SET_SHADER_CATEGORY', setShaderCategory, cat)}
                    zoom={zoom}
                    setZoom={(z) => wrapSender('SET_ZOOM', setZoom, z)}
                    panX={panX}
                    setPanX={(x) => wrapSender('SET_PAN_X', setPanX, x)}
                    panY={panY}
                    setPanY={(y) => wrapSender('SET_PAN_Y', setPanY, y)}
                    onNewImage={() => wrapSender('TRIGGER_NEW_IMAGE', null)}
                    autoChangeEnabled={autoChangeEnabled}
                    setAutoChangeEnabled={(v) => wrapSender('SET_AUTO_CHANGE_ENABLED', setAutoChangeEnabled, v)}
                    autoChangeDelay={autoChangeDelay}
                    setAutoChangeDelay={(v) => wrapSender('SET_AUTO_CHANGE_DELAY', setAutoChangeDelay, v)}
                    onLoadModel={() => wrapSender('TRIGGER_LOAD_MODEL', null)}
                    isModelLoaded={!!depthEstimator}
                    availableModes={availableModes}
                    inputSource={inputSource}
                    setInputSource={(v) => wrapSender('SET_INPUT_SOURCE', setInputSource, v)}
                    videoList={videoList}
                    selectedVideo={selectedVideo}
                    setSelectedVideo={(v) => wrapSender('SET_SELECTED_VIDEO', setSelectedVideo, v)}
                    isMuted={isMuted}
                    setIsMuted={(v) => wrapSender('SET_IS_MUTED', setIsMuted, v)}
                />
            </div>
        );
    }

    return (
        <div id="app-container">
            <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'center'}}>
                <h1>WebGPU Liquid + Depth Effect</h1>
                <button 
                    onClick={() => window.open(window.location.href.split('?')[0] + '?remote=true', 'RemoteControl', 'width=450,height=900')}
                    style={{padding: '5px 10px', cursor: 'pointer', background: '#445', color: 'white', border: '1px solid #667'}}
                >
                    Open Remote Control
                </button>
            </div>
            
            <p><strong>Status:</strong> {status}</p>
            
            <Controls
                modes={modes}
                setMode={(idx, mode) => { 
                    setModes(p => {const n=[...p]; n[idx]=mode; return n;}); 
                    applyModeDefaults(mode, idx); 
                }}
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
                isMuted={isMuted}
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

export default App;
