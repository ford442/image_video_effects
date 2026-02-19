import React, { useState, useEffect, useCallback, useRef } from 'react';
import WebGPUCanvas from './components/WebGPUCanvas';
import Controls from './components/Controls';
import { Renderer } from './renderer/Renderer';
import { RenderMode, ShaderEntry, ShaderCategory, InputSource, SlotParams } from './renderer/types';
import { Alucinate, AIStatus, ImageRecord, ShaderRecord } from './AutoDJ';
import { pipeline, env } from '@xenova/transformers';
import { SyncMessage, FullState, SYNC_CHANNEL_NAME } from './syncTypes';
import './style.css';

// --- Webcam Fun Shaders ---
const WEBCAM_FUN_SHADERS = [
    'liquid', 'liquid-chrome-ripple', 'liquid-rainbow', 'liquid-swirl',
    'neon-pulse', 'neon-edge-pulse', 'neon-fluid-warp', 'neon-warp',
    'vortex', 'vortex-distortion', 'vortex-warp', 'chroma-vortex',
    'distortion', 'chromatic-folds', 'holographic-projection', 'cyber-glitch-hologram',
    'kaleidoscope', 'kaleido-scope', 'fractal-kaleidoscope', 'astral-kaleidoscope',
    'rgb-fluid', 'rgb-ripple-distortion', 'rgb-shift-brush',
    'pixel-sorter', 'pixel-sort-glitch', 'ascii-shockwave',
    'magnetic-field', 'magnetic-pixels', 'magnetic-rgb'
];

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

// Sample videos for when bucket has no videos
const FALLBACK_VIDEOS = [
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/SubaruOutbackOnStreetAndDirt.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/VolkswagenGTIReview.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/WeAreGoingOnBullrun.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/WhatCarCanYouGetForAGrand.mp4"
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

    // --- State: Webcam ---
    const [isWebcamActive, setIsWebcamActive] = useState(false);
    const [webcamError, setWebcamError] = useState<string | null>(null);
    const [showWebcamShaderSuggestions, setShowWebcamShaderSuggestions] = useState(false);
    const videoElementRef = useRef<HTMLVideoElement | null>(null);
    const streamRef = useRef<MediaStream | null>(null);

    // --- State: Roulette ---
    const [isRouletteActive, setIsRouletteActive] = useState(false);
    const [chaosModeEnabled, setChaosModeEnabled] = useState(false);
    const [rouletteFirstUse, setRouletteFirstUse] = useState(true);
    const [showConfetti, setShowConfetti] = useState(false);
    const chaosIntervalRef = useRef<NodeJS.Timeout | null>(null);

    // --- State: Recording ---
    const [isRecording, setIsRecording] = useState(false);
    const [recordingCountdown, setRecordingCountdown] = useState(8);
    const [showShareModal, setShowShareModal] = useState(false);
    const [shareableLink, setShareableLink] = useState('');
    const mediaRecorderRef = useRef<MediaRecorder | null>(null);
    const recordedChunksRef = useRef<Blob[]>([]);
    const recordingTimerRef = useRef<NodeJS.Timeout | null>(null);
    const canvasRef = useRef<HTMLCanvasElement | null>(null);

    // --- State: Mouse Interaction ---
    const [mousePosition, setMousePosition] = useState<{ x: number; y: number }>({ x: -1, y: -1 });
    const [isMouseDown, setIsMouseDown] = useState(false);

    // --- Refs ---
    const rendererRef = useRef<Renderer | null>(null);
    const fileInputImageRef = useRef<HTMLInputElement>(null);
    const fileInputVideoRef = useRef<HTMLInputElement>(null);
    const channelRef = useRef<BroadcastChannel | null>(null);
    const heartbeatIntervalRef = useRef<NodeJS.Timeout | null>(null);
    const rouletteFlashRef = useRef<HTMLDivElement | null>(null);
    const canvasContainerRef = useRef<HTMLDivElement | null>(null);

    // --- Helpers ---
    const setMode = useCallback((index: number, mode: RenderMode) => {
        setModes(prev => {
            const next = [...prev];
            next[index] = mode;
            return next;
        });
    }, []);

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

            // 2. Try Local Manifest (Bucket Images & Videos) if API Empty OR Videos Missing
            if (manifest.length === 0 || videos.length === 0) {
                try {
                    const response = await fetch(LOCAL_MANIFEST_URL);
                    if (response.ok) {
                        const data = await response.json();

                        // Process Images (only if API failed to provide them)
                        if (manifest.length === 0) {
                            manifest = (data.images || []).map((item: any) => {
                                // Fix double bucket names if they exist in the manifest already
                                const cleanUrl = item.url.replace('my-sd35-space-images-2025/', '');
                                return {
                                    url: item.url.startsWith('http') ? item.url : `${BUCKET_BASE_URL}/${cleanUrl}`,
                                    tags: item.tags || [],
                                    description: item.tags ? item.tags.join(', ') : ''
                                };
                            });
                        }

                        // Process Videos (if missing)
                        if (videos.length === 0) {
                            videos = (data.videos || []).map((item: any) => {
                                const cleanUrl = item.url.replace('my-sd35-space-images-2025/', '');
                                return item.url.startsWith('http') ? item.url : `${BUCKET_BASE_URL}/${cleanUrl}`;
                            });
                        }

                        console.log("Loaded local manifest. Total:", manifest.length, "images,", videos.length, "videos");
                    }
                } catch (e) {
                    console.warn("Failed to load local manifest:", e);
                }
            }

            // 3. Last Resort: Fallbacks for images and videos
            if (manifest.length === 0) {
                console.warn("Image manifest empty. Using robust Unsplash fallback.");
                manifest = FALLBACK_IMAGES.map(url => ({
                    url,
                    tags: ['fallback', 'unsplash', 'demo'],
                    description: 'Demo Image'
                }));
            }
            
            // Video fallback
            if (videos.length === 0) {
                console.warn("No videos found. Using sample videos.");
                videos = FALLBACK_VIDEOS;
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

    // --- Webcam Handlers ---
    const startWebcam = useCallback(async () => {
        try {
            setWebcamError(null);
            const stream = await navigator.mediaDevices.getUserMedia({
                video: {
                    facingMode: "user",
                    width: { ideal: 1280 },
                    height: { ideal: 720 }
                }
            });
            streamRef.current = stream;
            
            // Create hidden video element
            if (!videoElementRef.current) {
                const video = document.createElement('video');
                video.autoplay = true;
                video.playsInline = true;
                video.muted = true;
                video.style.position = 'absolute';
                video.style.width = '1px';
                video.style.height = '1px';
                video.style.opacity = '0';
                video.style.pointerEvents = 'none';
                video.style.zIndex = '-1';
                document.body.appendChild(video);
                videoElementRef.current = video;
            }
            
            videoElementRef.current.srcObject = stream;
            await videoElementRef.current.play();
            
            setIsWebcamActive(true);
            setInputSource('webcam');
            setShaderCategory('image');
            setShowWebcamShaderSuggestions(true);
            setStatus('📹 Webcam active! Try fun shaders below.');
        } catch (err: any) {
            console.error('Webcam error:', err);
            setWebcamError(err.name === 'NotAllowedError' 
                ? 'Camera permission denied. Please allow camera access and try again.' 
                : 'Failed to access webcam. Please check your camera.');
            setStatus('❌ Camera permission denied');
        }
    }, []);

    const stopWebcam = useCallback(() => {
        if (streamRef.current) {
            streamRef.current.getTracks().forEach(track => track.stop());
            streamRef.current = null;
        }
        if (videoElementRef.current) {
            videoElementRef.current.pause();
            videoElementRef.current.srcObject = null;
        }
        setIsWebcamActive(false);
        setInputSource('image');
        setShowWebcamShaderSuggestions(false);
        setStatus('Webcam stopped');
    }, []);

    const applyWebcamFunShader = useCallback((shaderId: string) => {
        setMode(0, shaderId as RenderMode);
        setActiveSlot(0);
    }, [setMode]);

    // Cleanup webcam on unmount
    useEffect(() => {
        return () => {
            if (streamRef.current) {
                streamRef.current.getTracks().forEach(track => track.stop());
            }
            if (videoElementRef.current) {
                videoElementRef.current.remove();
            }
            if (chaosIntervalRef.current) {
                clearInterval(chaosIntervalRef.current);
            }
        };
    }, []);

    // --- Roulette / Chaos Mode Functions ---
    const getRandomShader = useCallback((): ShaderEntry | null => {
        if (availableModes.length === 0) return null;
        // Filter out 'none' and ensure valid shader entries
        const validShaders = availableModes.filter(s => s.id && s.id !== 'none');
        if (validShaders.length === 0) return null;
        const randomIndex = Math.floor(Math.random() * validShaders.length);
        return validShaders[randomIndex];
    }, [availableModes]);

    const randomizeSlotParams = useCallback((): SlotParams => {
        // Generate random values within sensible ranges for fun effects
        return {
            zoomParam1: 0.3 + Math.random() * 0.7,      // 0.3 - 1.0
            zoomParam2: 0.5 + Math.random() * 0.5,      // 0.5 - 1.0
            zoomParam3: Math.random() * 1.0,            // 0.0 - 1.0
            zoomParam4: Math.random() * 1.0,            // 0.0 - 1.0
            lightStrength: 0.5 + Math.random() * 1.5,   // 0.5 - 2.0
            ambient: 0.1 + Math.random() * 0.4,         // 0.1 - 0.5
            normalStrength: 0.05 + Math.random() * 0.25,// 0.05 - 0.3
            fogFalloff: 2.0 + Math.random() * 6.0,      // 2.0 - 8.0
            depthThreshold: 0.3 + Math.random() * 0.5,  // 0.3 - 0.8
        };
    }, []);

    const triggerRoulette = useCallback(() => {
        const randomShader = getRandomShader();
        if (!randomShader) {
            setStatus('No shaders available for Roulette!');
            return;
        }

        // Flash effect
        if (rouletteFlashRef.current) {
            rouletteFlashRef.current.classList.add('flash-active');
            setTimeout(() => {
                rouletteFlashRef.current?.classList.remove('flash-active');
            }, 300);
        }

        // Apply random shader to slot 0
        setMode(0, randomShader.id as RenderMode);
        setActiveSlot(0);

        // Randomize parameters for fresh look
        const newParams = randomizeSlotParams();
        updateSlotParam(0, newParams);

        // Show confetti on first use
        if (rouletteFirstUse) {
            setShowConfetti(true);
            setRouletteFirstUse(false);
            setTimeout(() => setShowConfetti(false), 3000);
        }

        setStatus(`🎰 Roulette: ${randomShader.name}`);
        setIsRouletteActive(true);
        setTimeout(() => setIsRouletteActive(false), 500);
    }, [getRandomShader, randomizeSlotParams, setMode, updateSlotParam, rouletteFirstUse]);

    // Chaos Mode effect
    useEffect(() => {
        if (chaosModeEnabled) {
            // Initial trigger
            triggerRoulette();
            // Set up interval (6-10 seconds random)
            chaosIntervalRef.current = setInterval(() => {
                triggerRoulette();
            }, 6000 + Math.random() * 4000);
        } else {
            if (chaosIntervalRef.current) {
                clearInterval(chaosIntervalRef.current);
                chaosIntervalRef.current = null;
            }
        }

        return () => {
            if (chaosIntervalRef.current) {
                clearInterval(chaosIntervalRef.current);
            }
        };
    }, [chaosModeEnabled, triggerRoulette]);

    // Keyboard shortcut for Roulette
    useEffect(() => {
        const handleKeyDown = (e: KeyboardEvent) => {
            if (e.key === 'r' || e.key === 'R') {
                // Don't trigger if user is typing in an input
                if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) {
                    return;
                }
                triggerRoulette();
            }
        };

        window.addEventListener('keydown', handleKeyDown);
        return () => window.removeEventListener('keydown', handleKeyDown);
    }, [triggerRoulette]);

    // --- Recording & Share Functions ---
    const generateShareableLink = useCallback(() => {
        const params = new URLSearchParams();
        
        // Current shader/mode
        params.set('shader', modes[0]);
        params.set('slot', activeSlot.toString());
        
        // Current slot parameters
        const params1 = slotParams[activeSlot];
        if (params1) {
            params.set('p1', params1.zoomParam1.toFixed(2));
            params.set('p2', params1.zoomParam2.toFixed(2));
            params.set('p3', params1.zoomParam3.toFixed(2));
            params.set('p4', params1.zoomParam4.toFixed(2));
            params.set('light', params1.lightStrength.toFixed(2));
            params.set('ambient', params1.ambient.toFixed(2));
        }
        
        // Input source and related state
        params.set('source', inputSource);
        if (inputSource === 'webcam') {
            params.set('webcam', 'true');
        }
        if (currentImageUrl) {
            params.set('img', encodeURIComponent(currentImageUrl));
        }
        
        // View settings
        params.set('zoom', zoom.toFixed(2));
        params.set('panX', panX.toFixed(2));
        params.set('panY', panY.toFixed(2));
        
        // Generative shader if active
        if (inputSource === 'generative' && activeGenerativeShader) {
            params.set('gen', activeGenerativeShader);
        }
        
        const hash = params.toString();
        const baseUrl = window.location.origin + window.location.pathname;
        return `${baseUrl}#${hash}`;
    }, [modes, activeSlot, slotParams, inputSource, currentImageUrl, zoom, panX, panY, activeGenerativeShader]);

    const restoreStateFromHash = useCallback(() => {
        const hash = window.location.hash.slice(1); // Remove #
        if (!hash) return;
        
        try {
            const params = new URLSearchParams(hash);
            
            // Restore shader/mode
            const shader = params.get('shader');
            if (shader) {
                setMode(0, shader as RenderMode);
            }
            
            // Restore active slot
            const slot = params.get('slot');
            if (slot) {
                setActiveSlot(parseInt(slot, 10));
            }
            
            // Restore slot parameters
            const updates: Partial<SlotParams> = {};
            const p1 = params.get('p1');
            const p2 = params.get('p2');
            const p3 = params.get('p3');
            const p4 = params.get('p4');
            const light = params.get('light');
            const ambient = params.get('ambient');
            
            if (p1) updates.zoomParam1 = parseFloat(p1);
            if (p2) updates.zoomParam2 = parseFloat(p2);
            if (p3) updates.zoomParam3 = parseFloat(p3);
            if (p4) updates.zoomParam4 = parseFloat(p4);
            if (light) updates.lightStrength = parseFloat(light);
            if (ambient) updates.ambient = parseFloat(ambient);
            
            if (Object.keys(updates).length > 0) {
                updateSlotParam(slot ? parseInt(slot, 10) : 0, updates);
            }
            
            // Restore input source
            const source = params.get('source');
            if (source) {
                setInputSource(source as InputSource);
                if (source === 'webcam') {
                    // Will need to trigger webcam start separately
                    setTimeout(() => startWebcam(), 1000);
                }
            }
            
            // Restore image URL if present
            const img = params.get('img');
            if (img && source !== 'webcam') {
                handleLoadImage(decodeURIComponent(img));
            }
            
            // Restore view settings
            const zoomVal = params.get('zoom');
            const panXVal = params.get('panX');
            const panYVal = params.get('panY');
            if (zoomVal) setZoom(parseFloat(zoomVal));
            if (panXVal) setPanX(parseFloat(panXVal));
            if (panYVal) setPanY(parseFloat(panYVal));
            
            // Restore generative shader
            const gen = params.get('gen');
            if (gen) {
                setActiveGenerativeShader(gen);
                setInputSource('generative');
            }
            
            setStatus('🎉 Shared state restored!');
        } catch (e) {
            console.error('Failed to restore state from hash:', e);
        }
    }, [setMode, setActiveSlot, updateSlotParam, setInputSource, setZoom, setPanX, setPanY, setActiveGenerativeShader, handleLoadImage, startWebcam]);

    // Restore state from URL hash on load
    useEffect(() => {
        restoreStateFromHash();
    }, []);

    const startRecording = useCallback(async () => {
        // Find the canvas element
        const canvas = document.querySelector('canvas[data-testid="webgpu-canvas"]') as HTMLCanvasElement;
        if (!canvas) {
            setStatus('❌ Canvas not found for recording');
            return;
        }
        
        try {
            // Capture stream at 60fps
            const stream = canvas.captureStream(60);
            
            // Try VP9 first, fall back to VP8 or default
            let mimeType = 'video/webm;codecs=vp9';
            if (!MediaRecorder.isTypeSupported(mimeType)) {
                mimeType = 'video/webm;codecs=vp8';
                if (!MediaRecorder.isTypeSupported(mimeType)) {
                    mimeType = 'video/webm';
                }
            }
            
            const mediaRecorder = new MediaRecorder(stream, {
                mimeType,
                videoBitsPerSecond: 8000000 // 8 Mbps for good quality
            });
            
            mediaRecorderRef.current = mediaRecorder;
            recordedChunksRef.current = [];
            
            mediaRecorder.ondataavailable = (e) => {
                if (e.data.size > 0) {
                    recordedChunksRef.current.push(e.data);
                }
            };
            
            mediaRecorder.onstop = () => {
                const blob = new Blob(recordedChunksRef.current, { type: 'video/webm' });
                const url = URL.createObjectURL(blob);
                
                // Auto-download
                const a = document.createElement('a');
                a.href = url;
                a.download = `pixelocity-clip-${Date.now()}.webm`;
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
                
                // Generate shareable link
                const link = generateShareableLink();
                setShareableLink(link);
                setShowShareModal(true);
                
                setStatus('✅ Recording saved! Download started.');
                
                // Cleanup
                setTimeout(() => URL.revokeObjectURL(url), 1000);
            };
            
            // Start recording
            mediaRecorder.start(100); // Collect data every 100ms
            setIsRecording(true);
            setRecordingCountdown(8);
            setStatus('🔴 Recording... 8s');
            
            // Countdown timer
            let count = 8;
            recordingTimerRef.current = setInterval(() => {
                count -= 1;
                setRecordingCountdown(count);
                setStatus(`🔴 Recording... ${count}s`);
                
                if (count <= 0) {
                    stopRecording();
                }
            }, 1000);
            
        } catch (e) {
            console.error('Recording failed:', e);
            setStatus('❌ Recording failed. Browser may not support this feature.');
        }
    }, [generateShareableLink]);

    const stopRecording = useCallback(() => {
        if (recordingTimerRef.current) {
            clearInterval(recordingTimerRef.current);
            recordingTimerRef.current = null;
        }
        
        if (mediaRecorderRef.current && mediaRecorderRef.current.state !== 'inactive') {
            mediaRecorderRef.current.stop();
        }
        
        setIsRecording(false);
        setRecordingCountdown(8);
    }, []);

    // Cleanup recording on unmount
    useEffect(() => {
        return () => {
            if (recordingTimerRef.current) {
                clearInterval(recordingTimerRef.current);
            }
            if (mediaRecorderRef.current && mediaRecorderRef.current.state !== 'inactive') {
                mediaRecorderRef.current.stop();
            }
        };
    }, []);

    // --- Remote Control Sync ---
    // Build full state object for syncing
    const buildFullState = useCallback((): FullState => ({
        modes,
        activeSlot,
        slotParams,
        shaderCategory,
        zoom,
        panX,
        panY,
        inputSource,
        autoChangeEnabled,
        autoChangeDelay,
        isModelLoaded: !!depthEstimator,
        availableModes,
        videoList,
        selectedVideo,
        isMuted,
    }), [modes, activeSlot, slotParams, shaderCategory, zoom, panX, panY, inputSource, 
        autoChangeEnabled, autoChangeDelay, depthEstimator, availableModes, videoList, selectedVideo, isMuted]);

    // Send message to remote
    const sendMessage = useCallback((type: SyncMessage['type'], payload?: any) => {
        if (channelRef.current) {
            channelRef.current.postMessage({ type, payload });
        }
    }, []);

    // Setup BroadcastChannel for remote control
    useEffect(() => {
        const channel = new BroadcastChannel(SYNC_CHANNEL_NAME);
        channelRef.current = channel;

        channel.onmessage = (event) => {
            const msg = event.data as SyncMessage;
            
            if (msg.type === 'HELLO') {
                // Remote app connected, send full state
                sendMessage('STATE_FULL', buildFullState());
            } else if (msg.type === 'CMD_SET_MODE') {
                const { index, mode } = msg.payload;
                setMode(index, mode);
            } else if (msg.type === 'CMD_SET_ACTIVE_SLOT') {
                setActiveSlot(msg.payload);
            } else if (msg.type === 'CMD_UPDATE_SLOT_PARAM') {
                const { index, updates } = msg.payload;
                updateSlotParam(index, updates);
            } else if (msg.type === 'CMD_SET_SHADER_CATEGORY') {
                setShaderCategory(msg.payload);
            } else if (msg.type === 'CMD_SET_ZOOM') {
                setZoom(msg.payload);
            } else if (msg.type === 'CMD_SET_PAN_X') {
                setPanX(msg.payload);
            } else if (msg.type === 'CMD_SET_PAN_Y') {
                setPanY(msg.payload);
            } else if (msg.type === 'CMD_SET_INPUT_SOURCE') {
                setInputSource(msg.payload);
            } else if (msg.type === 'CMD_SET_AUTO_CHANGE') {
                setAutoChangeEnabled(msg.payload);
            } else if (msg.type === 'CMD_SET_AUTO_CHANGE_DELAY') {
                setAutoChangeDelay(msg.payload);
            } else if (msg.type === 'CMD_LOAD_RANDOM_IMAGE') {
                handleNewRandomImage();
            } else if (msg.type === 'CMD_LOAD_MODEL') {
                loadDepthModel();
            } else if (msg.type === 'CMD_SELECT_VIDEO') {
                setSelectedVideo(msg.payload);
            } else if (msg.type === 'CMD_SET_MUTED') {
                setIsMuted(msg.payload);
            } else if (msg.type === 'CMD_UPLOAD_FILE') {
                // File upload from remote - handle if needed
                console.log('File upload from remote:', msg.payload);
            }
        };

        // Start heartbeat to keep remote connected
        heartbeatIntervalRef.current = setInterval(() => {
            sendMessage('HEARTBEAT');
        }, 1000); // Send heartbeat every second

        return () => {
            channel.close();
            if (heartbeatIntervalRef.current) {
                clearInterval(heartbeatIntervalRef.current);
            }
        };
    }, [buildFullState, sendMessage, handleNewRandomImage, loadDepthModel, updateSlotParam, setMode]);

    // Send state updates to remote when key state changes
    useEffect(() => {
        if (channelRef.current) {
            sendMessage('STATE_FULL', buildFullState());
        }
    }, [modes, activeSlot, shaderCategory, zoom, panX, panY, inputSource, 
        autoChangeEnabled, autoChangeDelay, isMuted, selectedVideo, buildFullState, sendMessage]);

    return (
        <div className="App">
            <header className="header">
                <div className="logo-section">
                    <div className="logo-text">Pixelocity</div>
                    <div className="subtitle-text">AI VJ Image Playground</div>
                </div>
                <div className="header-controls">
                    <button 
                        className="toggle-sidebar-btn" 
                        onClick={() => window.open('?mode=remote', '_blank', 'width=420,height=900')}
                        title="Open Remote Control in new window"
                    >
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
                        isWebcamActive={isWebcamActive}
                        onStartWebcam={startWebcam}
                        onStopWebcam={stopWebcam}
                        webcamError={webcamError}
                        showWebcamShaderSuggestions={showWebcamShaderSuggestions}
                        webcamFunShaders={WEBCAM_FUN_SHADERS}
                        onApplyWebcamShader={applyWebcamFunShader}
                        // Roulette props
                        onRoulette={triggerRoulette}
                        isRouletteActive={isRouletteActive}
                        chaosModeEnabled={chaosModeEnabled}
                        setChaosModeEnabled={setChaosModeEnabled}
                        // Recording props
                        isRecording={isRecording}
                        recordingCountdown={recordingCountdown}
                        onStartRecording={startRecording}
                        onStopRecording={stopRecording}
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
                        isWebcamActive={isWebcamActive}
                        webcamVideoElement={videoElementRef.current}
                    />
                    <div className="status-bar">
                        {isAiVjMode ? `[AI VJ]: ${aiVjMessage}` : status}
                    </div>
                </main>
            </div>
            <input type="file" ref={fileInputImageRef} accept="image/*" style={{display:'none'}} onChange={() => {}} />
            <input type="file" ref={fileInputVideoRef} accept="video/*" style={{display:'none'}} onChange={() => {}} />
            
            {/* Roulette Flash Overlay */}
            <div 
                ref={rouletteFlashRef} 
                className="roulette-flash"
                style={{
                    position: 'fixed',
                    top: 0,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    background: 'white',
                    opacity: 0,
                    pointerEvents: 'none',
                    zIndex: 9999,
                    transition: 'opacity 0.15s ease-out'
                }}
            />
            
            {/* Confetti Container */}
            {showConfetti && (
                <div className="confetti-container">
                    {Array.from({ length: 50 }).map((_, i) => (
                        <div
                            key={i}
                            className="confetti-piece"
                            style={{
                                left: `${Math.random() * 100}%`,
                                animationDelay: `${Math.random() * 2}s`,
                                backgroundColor: ['#ff6b6b', '#4ecdc4', '#45b7d1', '#96ceb4', '#ffeaa7', '#dfe6e9', '#fd79a8'][Math.floor(Math.random() * 7)]
                            }}
                        />
                    ))}
                </div>
            )}
            
            {/* Chaos Mode Indicator */}
            {chaosModeEnabled && (
                <div className="chaos-active-indicator">
                    🔥 CHAOS MODE ON
                </div>
            )}
            
            {/* Recording Indicator Overlay */}
            {isRecording && (
                <div className="recording-indicator-overlay">
                    <div className="recording-dot-large"></div>
                    <span>REC {recordingCountdown}s</span>
                </div>
            )}
            
            {/* Share Modal */}
            {showShareModal && (
                <div className="share-modal-overlay" onClick={() => setShowShareModal(false)}>
                    <div className="share-modal" onClick={(e) => e.stopPropagation()}>
                        <button className="share-modal-close" onClick={() => setShowShareModal(false)}>×</button>
                        
                        <div className="share-modal-header">
                            <h2>🎉 Clip Recorded!</h2>
                            <p>Your video has been downloaded. Share your creation!</p>
                        </div>
                        
                        <div className="share-link-section">
                            <label>Shareable Link:</label>
                            <div className="share-link-input-group">
                                <input 
                                    type="text" 
                                    value={shareableLink} 
                                    readOnly 
                                    className="share-link-input"
                                />
                                <button 
                                    className="share-copy-btn"
                                    onClick={() => {
                                        navigator.clipboard.writeText(shareableLink);
                                        setStatus('🔗 Link copied to clipboard!');
                                    }}
                                >
                                    📋 Copy
                                </button>
                            </div>
                        </div>
                        
                        <div className="share-buttons">
                            <a 
                                href={`https://twitter.com/intent/tweet?text=Check+out+my+Pixelocity+creation!&url=${encodeURIComponent(shareableLink)}`}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="share-btn twitter"
                            >
                                🐦 Share on Twitter
                            </a>
                            <a 
                                href={`https://www.tiktok.com/upload?referer=${encodeURIComponent(shareableLink)}`}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="share-btn tiktok"
                            >
                                🎵 Post on TikTok
                            </a>
                        </div>
                        
                        <div className="share-modal-footer">
                            <button className="share-done-btn" onClick={() => setShowShareModal(false)}>
                                Done
                            </button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}

export default MainApp;
