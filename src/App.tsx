import React, { useState, useEffect, useCallback, useRef } from 'react';
import WebGPUCanvas from './components/WebGPUCanvas';
import Controls from './components/Controls';
import ShaderScanner from './components/ShaderScanner';
import LiveStudioTab from './components/LiveStudioTab';
import { StorageBrowser } from './components/StorageBrowser';
import { Renderer } from './renderer/Renderer';
import { RenderMode, ShaderEntry, ShaderCategory, InputSource, SlotParams } from './renderer/types';
import { Alucinate, AIStatus, ImageRecord, ShaderRecord } from './AutoDJ';
import { pipeline, env } from '@xenova/transformers';
import { SyncMessage, FullState, SYNC_CHANNEL_NAME } from './syncTypes';
import { ShaderApi, ShaderEntry as ApiShaderEntry } from './services/shaderApi';
import { 
    STORAGE_API_URL,
    IMAGE_MANIFEST_URL as VPS_IMAGE_MANIFEST_URL 
} from './config/appConfig';
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

// --- Shader Parameter Defaults ---
// Hardcoded defaults for shaders where API returns generic 0.5 values
// Format: shader_id -> [param1, param2, param3, param4, param5, param6]
const SHADER_DEFAULTS: Record<string, number[]> = {
    // Liquid shaders - tuned for fluid dynamics
    'liquid': [0.35, 0.50, 0.30, 0.50],           // surfaceTension, gravityScale, damping, turbidity
    'liquid-chrome-ripple': [0.40, 0.60, 0.25, 0.45],
    'liquid-rainbow': [0.50, 0.40, 0.35, 0.60],
    'liquid-swirl': [0.45, 0.55, 0.30, 0.40],
    'liquid-viscous': [0.60, 0.30, 0.50, 0.35],
    
    // Distortion shaders
    'distortion': [0.40, 0.50, 0.30, 0.45],
    'vortex': [0.50, 0.40, 0.60, 0.35],
    'vortex-distortion': [0.45, 0.45, 0.55, 0.40],
    'vortex-warp': [0.40, 0.50, 0.50, 0.45],
    'chroma-vortex': [0.35, 0.55, 0.45, 0.50],
    
    // Chromatic/Color shaders
    'chromatic-folds': [0.45, 0.40, 0.50, 0.35],
    'chromatic-aberration': [0.30, 0.50, 0.40, 0.45],
    'rgb-fluid': [0.40, 0.35, 0.55, 0.45],
    'rgb-ripple-distortion': [0.35, 0.45, 0.50, 0.40],
    'rgb-shift-brush': [0.50, 0.30, 0.45, 0.55],
    
    // Neon/Glow shaders
    'neon-pulse': [0.60, 0.40, 0.50, 0.35],
    'neon-edge-pulse': [0.55, 0.45, 0.40, 0.50],
    'neon-fluid-warp': [0.45, 0.55, 0.35, 0.45],
    'neon-warp': [0.50, 0.50, 0.40, 0.40],
    
    // Kaleidoscope/Geometric
    'kaleidoscope': [0.40, 0.50, 0.45, 0.35],
    'kaleido-scope': [0.45, 0.40, 0.50, 0.40],
    'fractal-kaleidoscope': [0.35, 0.55, 0.40, 0.45],
    'astral-kaleidoscope': [0.50, 0.35, 0.45, 0.50],
    
    // Glitch/Effects
    'pixel-sorter': [0.40, 0.45, 0.55, 0.35],
    'pixel-sort-glitch': [0.35, 0.50, 0.45, 0.40],
    'ascii-shockwave': [0.45, 0.40, 0.50, 0.45],
    'cyber-glitch-hologram': [0.50, 0.35, 0.40, 0.55],
    
    // Magnetic/Field shaders
    'magnetic-field': [0.40, 0.50, 0.35, 0.50],
    'magnetic-pixels': [0.45, 0.40, 0.50, 0.40],
    'magnetic-rgb': [0.35, 0.55, 0.45, 0.35],
    
    // Projection/3D effects
    'holographic-projection': [0.45, 0.45, 0.40, 0.50],
    
    // Generative shaders (common defaults)
    'gen-orb': [0.50, 0.40, 0.60, 0.35],
    'gen-grid': [0.40, 0.50, 0.45, 0.40],
    'gen-neuro-kinetic-bloom': [0.50, 0.35, 0.55, 0.40],
    'gen-quantum-foam': [0.45, 0.45, 0.40, 0.50],
    'gen-crystal-caverns': [0.35, 0.55, 0.45, 0.35],
    'gen-fractal-clockwork': [0.50, 0.40, 0.50, 0.40],
    'galaxy': [0.50, 0.40, 0.60, 0.35],
    'plasma': [0.45, 0.55, 0.40, 0.45],
    
    // Interactive/Mouse shaders
    'cmyk-halftone-interactive': [0.40, 0.50, 0.35, 0.45],
    'interactive-rgb-split': [0.35, 0.45, 0.50, 0.40],
    'interactive-zoom-blur': [0.50, 0.40, 0.45, 0.35],
    'mouse-pixel-sort': [0.40, 0.35, 0.55, 0.45],
    'magnetic-interference': [0.45, 0.50, 0.40, 0.35],
    
    // Artistic/Painterly
    'artistic_painterly_oil': [0.50, 0.40, 0.45, 0.50],
    'double-exposure-zoom': [0.40, 0.50, 0.35, 0.45],
    'halftone-reveal': [0.45, 0.40, 0.50, 0.35],
    'rorschach-inkblot': [0.50, 0.45, 0.40, 0.50],
    
    // Simulation/Physics
    'reaction-diffusion': [0.40, 0.50, 0.45, 0.35],
    'physarum': [0.50, 0.40, 0.60, 0.45],
    'lenia': [0.45, 0.45, 0.50, 0.40],
    'navier-stokes-dye': [0.40, 0.50, 0.35, 0.50],
    
    // Lighting/Glow
    'bloom': [0.50, 0.40, 0.55, 0.35],
    'dynamic-lens-flares': [0.45, 0.50, 0.40, 0.45],
    'chromatic-crawler': [0.40, 0.45, 0.50, 0.35],
    
    // Image processing effects
    'digital-haze': [0.50, 0.40, 0.45, 0.35],
    
    // Generative: Crystalline Chrono-Dyson (Panel Density, Quasar Glow, Flux Speed, Swarm Count)
    'gen-crystalline-chrono-dyson': [0.40, 0.55, 0.50, 0.45],
};

// Helper to get shader defaults - tries multiple ID variations for matching
function getShaderDefaults(shaderId: string, numParams: number = 4): number[] {
    // Try multiple variations of the shader ID
    const variations = [
        shaderId,                                    // exact match
        shaderId.replace('.wgsl', ''),              // without .wgsl
        `${shaderId}.wgsl`,                         // with .wgsl
        shaderId.replace(/-/g, '_'),                // snake_case
        shaderId.replace(/_/g, '-'),                // kebab-case
        shaderId.replace(/^gen[-_]/, 'gen-'),       // normalize gen prefix
    ];
    
    for (const key of variations) {
        const defaults = SHADER_DEFAULTS[key];
        if (defaults) {
            console.log(`[getShaderDefaults] Found defaults for "${shaderId}" (matched as "${key}")`);
            return [...defaults, ...Array(6 - defaults.length).fill(0.5)].slice(0, numParams);
        }
    }
    
    console.log(`[getShaderDefaults] No defaults found for "${shaderId}" (tried: ${variations.join(', ')})`);
    return Array(numParams).fill(0.5);
}

// Debug: Log available shader default keys
console.log('[SHADER_DEFAULTS] Available keys:', Object.keys(SHADER_DEFAULTS));

// --- Configuration ---
env.allowLocalModels = false;
env.backends.onnx.logLevel = 'warning';
const DEPTH_MODEL_ID = 'Xenova/dpt-hybrid-midas';
// Use VPS Storage API instead of HuggingFace
const SHADER_WGSL_URL = `${STORAGE_API_URL}/api/shaders`;
const IMAGE_MANIFEST_URL = VPS_IMAGE_MANIFEST_URL;
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
    zoomParam5: 0.5,
    zoomParam6: 0.5,
    lightStrength: 1.0,
    ambient: 0.2,
    normalStrength: 0.1,
    fogFalloff: 4.0,
    depthThreshold: 0.5,
};

function MainApp() {
    // --- State: Tabs ---
    const [activeTab, setActiveTab] = useState<'main' | 'live-studio'>('main');

    // --- State: General & Stacking ---
    const [shaderCategory, setShaderCategory] = useState<ShaderCategory>('image');
    const [modes, setModes] = useState<RenderMode[]>(['liquid-displacement', 'none', 'none']);
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
    const [slotShaderStatus, setSlotShaderStatus] = useState<Array<'idle' | 'loading' | 'error'>>(['idle', 'idle', 'idle']);
    
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
    const [showShaderScanner, setShowShaderScanner] = useState(false);
    const [showStorageBrowser, setShowStorageBrowser] = useState(false);
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const [storageBrowserTab, setStorageBrowserTab] = useState<'shaders' | 'images' | 'videos'>('shaders');

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

    // --- State: Mouse Interaction ---
    const [mousePosition, setMousePosition] = useState<{ x: number; y: number }>({ x: -1, y: -1 });
    const [isMouseDown, setIsMouseDown] = useState(false);

    // --- State: Boot Gate ---
    const [rendererReady, setRendererReady] = useState(false);
    const [shadersReady, setShadersReady] = useState(false);
    const initialBootAppliedRef = useRef(false);

    // --- Refs ---
    const rendererRef = useRef<Renderer | null>(null);
    const fileInputImageRef = useRef<HTMLInputElement>(null);
    const fileInputVideoRef = useRef<HTMLInputElement>(null);
    const channelRef = useRef<BroadcastChannel | null>(null);
    const heartbeatIntervalRef = useRef<NodeJS.Timeout | null>(null);
    const rouletteFlashRef = useRef<HTMLDivElement | null>(null);
    // Mirrors slotShaderStatus state so setMode can read it without being in its dep array
    const slotShaderStatusRef = useRef<Array<'idle' | 'loading' | 'error'>>(['idle', 'idle', 'idle']);
    // Direct ref to the WebGPU canvas — set via onCanvasRef callback (avoids fragile querySelector)
    const webgpuCanvasRef = useRef<HTMLCanvasElement | null>(null);

    // --- Helpers ---
    const setMode = useCallback(async (index: number, mode: RenderMode) => {
        // Guard: if a shader is already compiling on this slot, skip to prevent chaos-mode pile-up
        if (slotShaderStatusRef.current[index] === 'loading') return;

        setModes(prev => {
            const next = [...prev];
            next[index] = mode;
            return next;
        });

        if (mode === 'none') {
            slotShaderStatusRef.current[index] = 'idle';
            setSlotShaderStatus(prev => { const n = [...prev]; n[index] = 'idle'; return n; });
            // Tell the renderer to disable this slot so other slots keep running
            if (rendererRef.current && typeof (rendererRef.current as any).setSlotShader === 'function') {
                (rendererRef.current as any).setSlotShader(index, '');
            }
            return;
        }

        // Attempt to load & compile the shader, tracking status
        const shaderEntry = availableModes.find(s => s.id === mode);
        if (shaderEntry && rendererRef.current && 'loadShader' in rendererRef.current) {
            slotShaderStatusRef.current[index] = 'loading';
            setSlotShaderStatus(prev => { const n = [...prev]; n[index] = 'loading'; return n; });

            try {
                // Determine shader URL — API shaders now point directly to the .wgsl static file
                // served by nginx with CORS headers, so pass the URL straight to loadShader.
                let shaderUrl = shaderEntry.url;
                
                // Load the shader
                const ok = await (rendererRef.current as any).loadShader(shaderEntry.id, shaderUrl);
                
                // Activate the shader on the specified slot
                if (ok && rendererRef.current) {
                    if (typeof (rendererRef.current as any).setSlotShader === 'function') {
                        (rendererRef.current as any).setSlotShader(index, shaderEntry.id);
                    } else if (typeof (rendererRef.current as any).setActiveShader === 'function') {
                        (rendererRef.current as any).setActiveShader(shaderEntry.id);
                    }
                }
                
                slotShaderStatusRef.current[index] = ok ? 'idle' : 'error';
                setSlotShaderStatus(prev => { const n = [...prev]; n[index] = ok ? 'idle' : 'error'; return n; });
                
                // Initialize slider values to shader's declared param defaults
                // Use hardcoded defaults first (API returns generic 0.5 values)
                console.log(`[setMode] Setting defaults for shader: "${shaderEntry.id}"`);
                const hardcodedDefaults = getShaderDefaults(shaderEntry.id, shaderEntry.params?.length || 4);
                const hasHardcoded = hardcodedDefaults.some(v => v !== 0.5);
                console.log(`[setMode] Has hardcoded defaults: ${hasHardcoded}`, hardcodedDefaults);
                
                if (ok && (shaderEntry.params?.length || hasHardcoded)) {
                    const paramDefaults: Partial<SlotParams> = {};
                    const numParams = shaderEntry.params?.length || hardcodedDefaults.length;
                    
                    console.log(`[setMode] Applying defaults for ${shaderEntry.id}:`, 
                        hasHardcoded ? 'using hardcoded defaults' : 'using API defaults');
                    
                    for (let i = 0; i < numParams; i++) {
                        // Use hardcoded default if available, otherwise fall back to API default
                        const defaultValue = hasHardcoded ? hardcodedDefaults[i] : (shaderEntry.params?.[i]?.default ?? 0.5);
                        console.log(`[setMode] Param ${i}: default = ${defaultValue}`);
                        if (i === 0) paramDefaults.zoomParam1 = defaultValue;
                        else if (i === 1) paramDefaults.zoomParam2 = defaultValue;
                        else if (i === 2) paramDefaults.zoomParam3 = defaultValue;
                        else if (i === 3) paramDefaults.zoomParam4 = defaultValue;
                        else if (i === 4) paramDefaults.zoomParam5 = defaultValue;
                        else if (i === 5) paramDefaults.zoomParam6 = defaultValue;
                    }
                    
                    console.log(`[setMode] Setting slot ${index} defaults:`, paramDefaults);
                    setSlotParams(prev => {
                        const next = [...prev];
                        next[index] = { ...next[index], ...paramDefaults };
                        return next;
                    });
                } else {
                    console.log(`[setMode] No params for ${shaderEntry.id}:`, { ok, params: shaderEntry.params });
                }

                // Record play event (fire-and-forget)
                if (ok) {
                    fetch(`${SHADER_WGSL_URL}/${shaderEntry.id}/play`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                    }).catch(() => {});
                }
            } catch (error) {
                console.error(`❌ Failed to load shader ${shaderEntry.id}:`, error);
                slotShaderStatusRef.current[index] = 'error';
                setSlotShaderStatus(prev => { const n = [...prev]; n[index] = 'error'; return n; });
            }
        }
    }, [availableModes, rendererRef]);

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
        if (shaderCategory === 'generative') {
            // When user selects "Procedural Generation", force input source to generative
            setInputSource('generative');
            setStatus('Switched to Generative Input');
        }
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [shaderCategory]); // Only depend on shaderCategory, not inputSource

    // --- Effects & Initializers ---
    
    useEffect(() => {
        const controller = new AbortController();
        const signal = controller.signal;

        // Fetch the dynamic image manifest from the backend on startup
        const fetchImageManifest = async () => {
            let manifest: ImageRecord[] = [];
            let videos: string[] = [];

            // 1. Try API
            try {
                const response = await fetch(IMAGE_MANIFEST_URL, { signal });
                if (response.ok) {
                    const data = await response.json();
                    if (!Array.isArray(data)) {
                        throw new TypeError(`API response is not an array, received: ${typeof data}`);
                    }
                    manifest = data.map((item: any) => ({
                        url: item.url,
                        tags: item.description ? item.description.toLowerCase().split(/[\s,]+/) : [],
                        description: item.description || ''
                    }));
                }
            } catch (error) {
                if ((error as Error).name === 'AbortError') return;
                console.warn("Backend API failed, trying local manifest...", error);
            }

            // 2. Try Local Manifest (Bucket Images & Videos) if API Empty OR Videos Missing
            if (manifest.length === 0 || videos.length === 0) {
                try {
                    const response = await fetch(LOCAL_MANIFEST_URL, { signal });
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
                    if ((e as Error).name === 'AbortError') return;
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
                setStatus('Using fallback images - manifest unavailable');
            } else {
                setStatus(`Loaded ${manifest.length} images, ${videos.length} videos`);
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
                if (rendererRef.current.setImageList) {
                    rendererRef.current.setImageList(manifest.map(m => m.url));
                }
                // If the renderer has a setVideoList method, call it here.
                // Currently assuming Controls handles the selection via `selectedVideo` prop.
            }
        };
        fetchImageManifest();
        return () => controller.abort();
    }, []);

    // --- Load Available Shaders (API-First with Local Fallback) ---
    useEffect(() => {
        let isMounted = true;

        const loadShaders = async () => {
            try {
                // Try API first, fallback to local shader_coordinates.json
                const apiShaders = await ShaderApi.getShaderList();
                if (!isMounted) return;

                // Transform API shaders to match expected format
                const entries: ShaderEntry[] = apiShaders.map(shader => ({
                    id: shader.id,
                    name: shader.name || shader.id,
                    // Use API URL (already points to .wgsl file) or local fallback
                    url: shader.url || `./shaders/${shader.id}.wgsl`,
                    category: determineCategory(shader),
                    description: shader.description || '',
                    tags: shader.tags || [],
                    rating: shader.rating,
                    hasErrors: shader.has_errors,
                    params: (shader.params || []).map((p: any, idx: number) => ({
                        id: p.id || p.name || `param${idx + 1}`,
                        name: p.label || p.name || `Parameter ${idx + 1}`,
                        default: p.default ?? 0.5,
                        min: p.min ?? 0,
                        max: p.max ?? 1,
                        step: p.step ?? 0.01,
                        labels: p.labels,
                    })),
                }));

                setAvailableModes(entries);
                setShadersReady(true);
                // Debug: Check params
                const withParams = entries.filter(e => e.params && e.params.length > 0);
                console.log(`✅ Loaded ${entries.length} shaders (API-first with fallback)`);
                console.log(`   ${withParams.length} shaders have params`);
                if (withParams.length > 0) {
                    console.log(`   Example: ${withParams[0].id} has params:`, withParams[0].params);
                }
            } catch (error) {
                if (!isMounted) return;
                console.warn('Failed to load shaders:', error);
                setShadersReady(true); // Mark ready even on failure so boot gate doesn't block forever
            }
        };

        // Helper to determine category — use API category field first, then infer from tags/id
        function determineCategory(shader: ApiShaderEntry): ShaderCategory {
            // Prefer the category field from the API/definition if available
            const VALID_CATEGORIES: ShaderCategory[] = [
                'image', 'generative', 'simulation', 'distortion', 'artistic',
                'interactive-mouse', 'lighting-effects', 'liquid-effects',
                'retro-glitch', 'visual-effects', 'geometric', 'glitch',
            ];
            if (shader.category && VALID_CATEGORIES.includes(shader.category as ShaderCategory)) {
                return shader.category as ShaderCategory;
            }

            // Fallback: infer from tags and ID
            if (shader.tags?.includes('generative') || shader.id.startsWith('gen-') || shader.id.startsWith('gen_')) {
                return 'generative';
            }
            if (shader.tags?.includes('simulation')) return 'simulation';
            if (shader.tags?.includes('distortion') || shader.tags?.includes('warp')) return 'distortion';
            if (shader.tags?.includes('artistic') || shader.tags?.includes('painterly')) return 'artistic';
            if (shader.tags?.includes('interactive') || shader.tags?.includes('mouse-driven')) return 'interactive-mouse';
            if (shader.tags?.includes('lighting') || shader.tags?.includes('plasma') || shader.tags?.includes('glow')) return 'lighting-effects';
            if (shader.tags?.includes('liquid') || shader.tags?.includes('fluid')) return 'liquid-effects';
            if (shader.tags?.includes('retro') || shader.tags?.includes('glitch') || shader.tags?.includes('vhs')) return 'retro-glitch';
            if (shader.tags?.includes('visual-effects') || shader.tags?.includes('chromatic')) return 'visual-effects';
            if (shader.tags?.includes('geometric') || shader.tags?.includes('tessellation')) return 'geometric';
            return 'image';
        }

        loadShaders();
        return () => { isMounted = false; };
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
            if (rendererRef.current.updateDepthMap) {
                rendererRef.current.updateDepthMap(normalizedData, width, height);
            }
            setStatus('Depth map updated.');
        } catch (e: any) {
            console.error("Error during analysis:", e);
            setStatus(`Failed to analyze image: ${e.message}`);
        }
    }, [depthEstimator]);

    const handleLoadImage = useCallback(async (url: string) => {
        if (!rendererRef.current) return;
        if (rendererRef.current.loadImage) {
            const newImageUrl = await rendererRef.current.loadImage(url);
            if (newImageUrl) {
                setCurrentImageUrl(newImageUrl);
                if (depthEstimator) {
                    await runDepthAnalysis(newImageUrl);
                }
            }
        }
    }, [depthEstimator, runDepthAnalysis]);

    const handleNewRandomImage = useCallback(async () => {
        // If manifest is empty, try to use fallback images directly
        let sourceList = imageManifest;
        if (sourceList.length === 0) {
            console.warn('Manifest empty, using fallback images directly');
            sourceList = FALLBACK_IMAGES.map(url => ({
                url,
                tags: ['fallback', 'unsplash', 'demo'],
                description: 'Demo Image'
            }));
        }
        
        const randomImage = sourceList[Math.floor(Math.random() * sourceList.length)];
        if (randomImage) {
            setStatus('Loading image...');
            await handleLoadImage(randomImage.url);
            setStatus('Image loaded');
        }
    }, [imageManifest, handleLoadImage]);

    // --- Coordinated Boot Gate ---
    // Wait for both renderer and shader list to be ready before loading initial shader.
    // Image auto-load is handled by a separate effect below so it works even if the
    // manifest arrives after the renderer/shader gate fires.
    useEffect(() => {
        if (!rendererReady || !shadersReady) return;
        if (initialBootAppliedRef.current) return;
        initialBootAppliedRef.current = true;

        // Load initial shader
        const initialMode = modes[0];
        if (initialMode && initialMode !== 'none') {
            console.log(`[boot] Loading initial shader: ${initialMode}`);
            setMode(0, initialMode);
        }
    }, [rendererReady, shadersReady, modes, setMode]);

    // --- Initial Image Auto-Load ---
    // Separate from the boot gate so it fires whenever the manifest becomes available,
    // even if that happens after the renderer is already ready.
    useEffect(() => {
        if (!rendererReady || imageManifest.length === 0 || currentImageUrl) return;
        if (inputSource !== 'image') return;
        console.log('[boot] Auto-loading first image (manifest ready)...');
        handleNewRandomImage();
    }, [rendererReady, imageManifest, currentImageUrl, inputSource, handleNewRandomImage]);

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
        if (rendererRef.current) {
            if (rendererRef.current.getAvailableModes) {
                setAvailableModes(rendererRef.current.getAvailableModes());
            }
            setRendererReady(true);
        }
    }, []);

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
            zoomParam5: Math.random() * 1.0,            // 0.0 - 1.0
            zoomParam6: Math.random() * 1.0,            // 0.0 - 1.0
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

        // Apply random shader to active slot
        setMode(activeSlot, randomShader.id as RenderMode);

        // Randomize parameters for fresh look
        const newParams = randomizeSlotParams();
        updateSlotParam(activeSlot, newParams);

        // Show confetti on first use
        if (rouletteFirstUse) {
            setShowConfetti(true);
            setRouletteFirstUse(false);
            setTimeout(() => setShowConfetti(false), 3000);
        }

        setStatus(`🎰 Roulette slot ${activeSlot + 1}: ${randomShader.name}`);
        setIsRouletteActive(true);
        setTimeout(() => setIsRouletteActive(false), 500);
    }, [getRandomShader, randomizeSlotParams, setMode, updateSlotParam, rouletteFirstUse, activeSlot]);

    const triggerRandomizeAllSlots = useCallback(() => {
        // Flash effect
        if (rouletteFlashRef.current) {
            rouletteFlashRef.current.classList.add('flash-active');
            setTimeout(() => {
                rouletteFlashRef.current?.classList.remove('flash-active');
            }, 300);
        }

        const names: string[] = [];
        for (let i = 0; i < 3; i++) {
            const randomShader = getRandomShader();
            if (randomShader) {
                setMode(i, randomShader.id as RenderMode);
                updateSlotParam(i, randomizeSlotParams());
                names.push(randomShader.name);
            }
        }

        setStatus(`🎲 All slots randomized: ${names.join(', ')}`);
        setIsRouletteActive(true);
        setTimeout(() => setIsRouletteActive(false), 500);
    }, [getRandomShader, randomizeSlotParams, setMode, updateSlotParam]);

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
    }, [restoreStateFromHash]);

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

    const startRecording = useCallback(async () => {
        // Use the canvas ref exposed by WebGPUCanvas (avoids fragile DOM querySelector)
        const canvas = webgpuCanvasRef.current;
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
    }, [generateShareableLink, stopRecording]);

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
                // Remote app connected — send full state and start heartbeat if not already running
                sendMessage('STATE_FULL', buildFullState());
                if (!heartbeatIntervalRef.current) {
                    heartbeatIntervalRef.current = setInterval(() => {
                        sendMessage('HEARTBEAT');
                    }, 5000); // 5s is plenty for a keep-alive
                }
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

        return () => {
            channel.close();
            if (heartbeatIntervalRef.current) {
                clearInterval(heartbeatIntervalRef.current);
                heartbeatIntervalRef.current = null;
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
                        className={`toggle-sidebar-btn ${activeTab === 'main' ? 'active' : ''}`}
                        onClick={() => setActiveTab('main')}
                    >
                        Main
                    </button>
                    <button
                        className={`toggle-sidebar-btn ${activeTab === 'live-studio' ? 'active' : ''}`}
                        onClick={() => setActiveTab('live-studio')}
                        style={{ background: activeTab === 'live-studio' ? 'linear-gradient(135deg, #00d4ff, #7b2cbf)' : undefined }}
                    >
                        🎥 Live Studio
                    </button>
                    <div style={{ width: '1px', height: '24px', background: 'rgba(255,255,255,0.2)', margin: '0 8px' }} />
                    <button 
                        className="toggle-sidebar-btn" 
                        onClick={() => window.open('?mode=remote', '_blank', 'width=420,height=900')}
                        title="Open Remote Control in new window"
                    >
                        Open Remote
                    </button>
                    {activeTab === 'main' && (
                        <button className="toggle-sidebar-btn" onClick={() => setShowSidebar(!showSidebar)}>
                            {showSidebar ? 'Hide Controls' : 'Show Controls'}
                        </button>
                    )}
                </div>
            </header>
            {activeTab === 'live-studio' ? (
                <LiveStudioTab />
            ) : (
            <div className="main-container">
                <aside className={`sidebar ${!showSidebar ? 'hidden' : ''}`}>
                    <Controls
                        // ... pass all props to Controls component
                        modes={modes} setMode={setMode} activeSlot={activeSlot} setActiveSlot={setActiveSlot}
                        slotParams={slotParams} updateSlotParam={updateSlotParam} slotShaderStatus={slotShaderStatus} shaderCategory={shaderCategory}
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
                        onRandomizeAllSlots={triggerRandomizeAllSlots}
                        isRouletteActive={isRouletteActive}
                        chaosModeEnabled={chaosModeEnabled}
                        setChaosModeEnabled={setChaosModeEnabled}
                        // Recording props
                        isRecording={isRecording}
                        recordingCountdown={recordingCountdown}
                        onStartRecording={startRecording}
                        onStopRecording={stopRecording}
                        // Dev Tools props
                        onOpenShaderScanner={() => setShowShaderScanner(true)}
                        // Storage Browser props
                        onOpenStorageBrowser={() => setShowStorageBrowser(true)}
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
                        activeSlot={activeSlot}
                        activeGenerativeShader={activeGenerativeShader}
                        selectedVideo={selectedVideo}
                        apiBaseUrl={STORAGE_API_URL}
                        isWebcamActive={isWebcamActive}
                        webcamVideoElement={videoElementRef.current}
                        onCanvasRef={(el) => { webgpuCanvasRef.current = el; }}
                    />
                    <div className="status-bar">
                        {isAiVjMode ? `[AI VJ]: ${aiVjMessage}` : status}
                    </div>
                </main>
            </div>
            )}
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

            {/* Shader Scanner Modal */}
            <ShaderScanner
                shaders={availableModes}
                isOpen={showShaderScanner}
                onClose={() => setShowShaderScanner(false)}
                onTestShader={async (shaderId, testValues) => {
                    try {
                        // Load the shader
                        setMode(0, shaderId as RenderMode);
                        
                        // Wait for shader to load
                        await new Promise(resolve => setTimeout(resolve, 500));
                        
                        // Test setting parameters
                        const testParams: Partial<SlotParams> = {
                            zoomParam1: testValues[0] ?? 0.5,
                            zoomParam2: testValues[1] ?? 0.5,
                            zoomParam3: testValues[2] ?? 0.5,
                            zoomParam4: testValues[3] ?? 0.5,
                        };
                        updateSlotParam(0, testParams as SlotParams);
                        
                        // Wait for params to apply
                        await new Promise(resolve => setTimeout(resolve, 200));
                        
                        return { success: true };
                    } catch (error) {
                        return { 
                            success: false, 
                            error: error instanceof Error ? error.message : String(error) 
                        };
                    }
                }}
            />

            {/* Storage Browser Modal */}
            {showStorageBrowser && (
                <div 
                    className="storage-browser-modal-overlay"
                    style={{
                        position: 'fixed',
                        inset: 0,
                        background: 'rgba(0, 0, 0, 0.85)',
                        backdropFilter: 'blur(8px)',
                        zIndex: 2000,
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        padding: '20px',
                    }}
                    onClick={() => setShowStorageBrowser(false)}
                >
                    <div 
                        style={{
                            width: '100%',
                            maxWidth: '1200px',
                            height: '85vh',
                            background: '#1a1a2e',
                            borderRadius: '16px',
                            overflow: 'hidden',
                            boxShadow: '0 25px 80px rgba(0, 0, 0, 0.6)',
                        }}
                        onClick={e => e.stopPropagation()}
                    >
                        <StorageBrowser
                            onSelectShader={async (shader) => {
                                // Load shader from VPS
                                try {
                                    if (shader.url) {
                                        const response = await fetch(shader.url);
                                        if (response.ok) {
                                            const data = await response.json();
                                            // Apply shader data if it contains WGSL
                                            if (data.wgsl_code || data.data?.wgsl_code) {
                                                setStatus(`Loaded shader: ${shader.name} (WGSL code available)`);
                                            } else {
                                                // Try to set as mode if it exists
                                                const existingMode = availableModes.find(m => m.id === shader.id);
                                                if (existingMode) {
                                                    setMode(activeSlot, shader.id as RenderMode);
                                                    setStatus(`Applied shader: ${shader.name}`);
                                                } else {
                                                    setStatus(`Shader ${shader.name} not found in local modes`);
                                                }
                                            }
                                        }
                                    }
                                } catch (err) {
                                    setStatus(`Failed to load shader: ${shader.name}`);
                                }
                                setShowStorageBrowser(false);
                            }}
                            onSelectImage={async (image) => {
                                await handleLoadImage(image.url);
                                setStatus(`Loaded image from VPS: ${image.description || 'Untitled'}`);
                                setShowStorageBrowser(false);
                            }}
                            onSelectVideo={(video) => {
                                setSelectedVideo(video.url);
                                setInputSource('video');
                                setStatus(`Selected video: ${video.title}`);
                                setShowStorageBrowser(false);
                            }}
                            onLoadEffectConfig={(config) => {
                                // Apply saved configuration
                                if (config.modes) {
                                    config.modes.forEach((mode: string, idx: number) => {
                                        if (idx < 3) setMode(idx, mode as RenderMode);
                                    });
                                }
                                if (config.slotParams) {
                                    setSlotParams(config.slotParams);
                                }
                                if (config.inputSource) setInputSource(config.inputSource);
                                if (config.currentImageUrl) handleLoadImage(config.currentImageUrl);
                                setStatus('Loaded effect configuration from VPS');
                                setShowStorageBrowser(false);
                            }}
                            initialTab={storageBrowserTab}
                        />
                    </div>
                </div>
            )}
        </div>
    );
}

export default MainApp;
