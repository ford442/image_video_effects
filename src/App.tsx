import React, { useState, useEffect, useCallback, useRef } from 'react';
import WebGPUCanvas from './components/WebGPUCanvas';
import Controls from './components/Controls';
import RemoteApp from './RemoteApp';
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

    // Refs
    const rendererRef = useRef<Renderer | null>(null);
    const debugCanvasRef = useRef<HTMLCanvasElement>(null);
    const fileInputImageRef = useRef<HTMLInputElement>(null);
    const fileInputVideoRef = useRef<HTMLInputElement>(null);

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