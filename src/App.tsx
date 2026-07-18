import React, { useState, useEffect, useCallback, useRef } from 'react';
import WebGPUCanvas from './components/WebGPUCanvas';
import Controls from './components/Controls';
import { AppShell } from './components/app/AppShell';
import ShaderScanner from './components/ShaderScanner';
import LiveStudioTab from './components/LiveStudioTab';
import { StorageBrowser } from './components/StorageBrowser';
import { RendererToggle } from './components/RendererToggle';
import { PerformanceStatusHUD } from './components/PerformanceStatusHUD';
import { RenderQualityMode } from './config/performancePolicy';
import { loadRenderQualityMode, saveRenderQualityMode } from './services/renderQuality';
import { RendererType, RendererManager } from './renderer/RendererManager';
import { Alucinate, AIStatus, AutoTransitionConfig, ImageRecord, ShaderRecord } from './AutoDJ';
import { SyncMessage, FullState, SYNC_CHANNEL_NAME, VideoRecord } from './syncTypes';
import { ShaderApi, ShaderEntry as ApiShaderEntry } from './services/shaderApi';
import { resolveShaderUrl } from './utils/resolveShaderUrl';
import { RenderMode, ShaderEntry, ShaderCategory, InputSource, SlotParams } from './renderer/types';
import { pipeline, env } from '@xenova/transformers';
import {
    STORAGE_API_URL,
    DEFAULT_B3HD_SEGMENT_LENGTH,
    DEFAULT_B3HD_INTERVAL_SECONDS,
} from './config/appConfig';
import { VideoSegment, pickRandomSegment, hydrateDurations } from './services/videoSegmentManager';
import { savePreset } from './services/vjPresets';
import { saveMyVjSet } from './services/myVjSets';
import { SharedChain } from './services/layerChainShare';
import {
    useAudioAnalyzer,
    useDepthEstimation,
    useRendererBackend,
    useShaderMode,
    useAudioReactiveParams,
    useContentManifest,
    useShaderCatalogLoad,
    useImageLoading,
    useShaderBoot,
    useAiVjHandlers,
    useWebcam,
    useShareChain,
} from './hooks';
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
    // Showcase-optimized generative shaders
    'gen-showcase-nebula-core': [0.50, 0.30, 0.40, 0.20],
    'gen-showcase-kinetic-bloom': [0.50, 0.30, 0.40, 0.30],
    'gen-showcase-crystalline-pulse': [0.50, 0.30, 0.50, 0.20],
    'molten-gold': [0.50, 0.50, 0.50, 0.50],
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
        shaderId.replace('.wgsl', ''),              // strip .wgsl extension if present
        `${shaderId}.wgsl`,                         // with .wgsl
        shaderId.replace(/-/g, '_'),                // snake_case
        shaderId.replace(/_/g, '-'),                // kebab-case
        shaderId.replace(/^gen[-_]/, 'gen-'),       // normalize gen prefix
    ];
    
    for (const key of variations) {
        const defaults = SHADER_DEFAULTS[key];
        if (defaults) {
            return [...defaults, ...Array(4 - defaults.length).fill(0.5)].slice(0, numParams);
        }
    }
    
    return Array(numParams).fill(0.5);
}

// --- Configuration ---
env.allowLocalModels = false;
env.backends.onnx.logLevel = 'warning';
const DEPTH_MODEL_ID = 'Xenova/dpt-hybrid-midas';
// Use VPS Storage API instead of HuggingFace
const SHADER_WGSL_URL = `${STORAGE_API_URL}/api/shaders`;
// URL vars removed for unused variables warning
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
    // --- State: Tabs ---
    const [activeTab, setActiveTab] = useState<'main' | 'live-studio'>('main');

    // --- State: General & Stacking ---
    const [shaderCategory, setShaderCategory] = useState<ShaderCategory>('image');
    const [modes, setModes] = useState<RenderMode[]>(['none', 'none', 'none', 'none', 'none', 'none']);
    const [activeSlot, setActiveSlot] = useState<number>(0);
    const [slotParams, setSlotParams] = useState<SlotParams[]>([
        defaultSlotParams,
        defaultSlotParams,
        defaultSlotParams,
        defaultSlotParams,
        defaultSlotParams,
        defaultSlotParams,
    ]);

    // --- State: Automation & Status ---
    const [autoChangeEnabled, setAutoChangeEnabled] = useState(false);
    const [autoChangeDelay, setAutoChangeDelay] = useState(10);
    const [status, setStatus] = useState('Ready.');
    const [slotShaderStatus, setSlotShaderStatus] = useState<Array<'idle' | 'loading' | 'error'>>(['idle', 'idle', 'idle', 'idle', 'idle', 'idle']);
    
    // --- State: AI Models & VJ ---
    const [depthEstimator, setDepthEstimator] = useState<any>(null);
    const [aiVj, setAiVj] = useState<Alucinate | null>(null);
    const [aiVjStatus, setAiVjStatus] = useState<AIStatus>('idle');
    const [aiVjMessage, setAiVjMessage] = useState('AI VJ is offline.');
    const [isAiVjMode, setIsAiVjMode] = useState(false);

    // --- State: Content ---
    const [imageManifest, setImageManifest] = useState<ImageRecord[]>([]);
    const [videoList, setVideoList] = useState<VideoRecord[]>([]); // Video List with metadata
    const [currentImageUrl, setCurrentImageUrl] = useState<string | undefined>();
    const [availableModes, setAvailableModes] = useState<ShaderEntry[]>([]);
    const [inputSource, setInputSource] = useState<InputSource>('image');
    const [activeGenerativeShader, setActiveGenerativeShader] = useState<string>('gen-orb');
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const [videoSourceUrl, setVideoSourceUrl] = useState<string | undefined>(undefined);
    const [isMuted, setIsMuted] = useState(true);
    const [selectedVideo, setSelectedVideo] = useState<string>("");
    const [videoB3hdMode, setVideoB3hdMode] = useState(false);
    const [b3hdSegmentLength, setB3hdSegmentLength] = useState(DEFAULT_B3HD_SEGMENT_LENGTH);
    const [b3hdIntervalSeconds, setB3hdIntervalSeconds] = useState(DEFAULT_B3HD_INTERVAL_SECONDS);
    const [currentSegment, setCurrentSegment] = useState<VideoSegment | null>(null);

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
    const mediaRecorderRef = useRef<MediaRecorder | null>(null);
    const recordedChunksRef = useRef<Blob[]>([]);
    const recordingTimerRef = useRef<NodeJS.Timeout | null>(null);
    const wasmRecordingPromiseRef = useRef<Promise<Blob> | null>(null);
    const recordingFinishedRef = useRef(false);

    // --- State: Mouse Control ---
    const [mousePosition, setMousePosition] = useState({ x: 0.5, y: 0.5 });
    const [isMouseDown, setIsMouseDown] = useState(false);

    // --- State: Generative Showcase ---
    const [generativeShowcaseActive, setGenerativeShowcaseActive] = useState(false);
    const [generativeShowcaseLocked, setGenerativeShowcaseLocked] = useState(false);
    const [generativeShowcaseDelay] = useState(12);
    const generativeShowcaseTimerRef = useRef<NodeJS.Timeout | null>(null);

    // --- State: Audio-Reactive Params ---
    const [audioReactiveParams, setAudioReactiveParams] = useState(false);
    const [audioReactiveAmount, setAudioReactiveAmount] = useState(0.8); // master 0-1 mix

    // --- Audio Analyzer Hook ---
    const { startAudio: startAudioAnalyzer, stopAudio: stopAudioAnalyzer, getAudioData: getAudioAnalyzerData, getAudioBins } = useAudioAnalyzer();

    // --- Refs for audio-reactive param smoothing ---
    const audioParamSmoothedRef = useRef<[number, number, number, number]>([0.5, 0.5, 0.5, 0.5]);

    // --- State: Boot Gate ---
    const [shadersReady, setShadersReady] = useState(false);
    const initialBootAppliedRef = useRef(false);

    // --- State: Render quality ---
    const [renderQualityMode, setRenderQualityMode] = useState<RenderQualityMode>(() => loadRenderQualityMode());
    const [performanceHud, setPerformanceHud] = useState({
        internalWidth: 2048,
        internalHeight: 2048,
        scale: 1,
        targetFps: 60,
        adaptive: true,
        maxActiveSlots: 3,
    });

    // --- Refs ---
    const rendererRef = useRef<RendererManager | null>(null);
    const modesRef = useRef<RenderMode[]>(modes);
    const availableModesRef = useRef<ShaderEntry[]>(availableModes);
    const slotParamsRef = useRef<SlotParams[]>(slotParams);
    const inputSourceRef = useRef<InputSource>(inputSource);
    const fileInputImageRef = useRef<HTMLInputElement>(null);
    const fileInputVideoRef = useRef<HTMLInputElement>(null);
    const channelRef = useRef<BroadcastChannel | null>(null);
    const heartbeatIntervalRef = useRef<NodeJS.Timeout | null>(null);
    const rouletteFlashRef = useRef<HTMLDivElement | null>(null);
    // Mirrors slotShaderStatus state so setMode can read it without being in its dep array
    const slotShaderStatusRef = useRef<Array<'idle' | 'loading' | 'error'>>(['idle', 'idle', 'idle', 'idle', 'idle', 'idle']);
    // Direct ref to the WebGPU canvas — set via onCanvasRef callback (avoids fragile querySelector)
    const webgpuCanvasRef = useRef<HTMLCanvasElement | null>(null);

    const {
        depthEstimator,
        isModelLoaded,
        loadDepthModel,
        runDepthAnalysis,
    } = useDepthEstimation({
        rendererRef,
        currentImageUrl,
        setStatus,
    });

    // --- Helpers ---
    useEffect(() => {
        modesRef.current = modes;
    }, [modes]);

    useEffect(() => {
        availableModesRef.current = availableModes;
    }, [availableModes]);

    useEffect(() => {
        slotParamsRef.current = slotParams;
    }, [slotParams]);

    useEffect(() => {
        inputSourceRef.current = inputSource;
    }, [inputSource]);

    const {
        activeRendererType,
        jsFps,
        wasmFps,
        isRendererSwitching,
        rendererReady,
        supportsDeepWorkgroup,
        handleSwitchRenderer,
        onInitCanvas,
    } = useRendererBackend({
        rendererRef,
        modesRef,
        slotParamsRef,
        availableModesRef,
        inputSourceRef,
        setStatus,
    });

    const {
        setMode,
        updateSlotParam,
        mapShaderParamUpdates,
        handleApplyParamsDirect,
        syncInputSourceToRenderer,
    } = useShaderMode({
        rendererRef,
        availableModes,
        availableModesRef,
        modesRef,
        slotParamsRef,
        inputSourceRef,
        slotShaderStatusRef,
        setModes,
        setSlotParams,
        setSlotShaderStatus,
        setInputSource,
    });

    const {
        audioReactiveParams,
        setAudioReactiveParams,
        audioReactiveAmount,
        setAudioReactiveAmount,
    } = useAudioReactiveParams({
        rendererRef,
        modes,
        availableModes,
        updateSlotParam,
        getShaderDefaults,
        setStatus,
    });

    const handleUpdateStack = useCallback((ids: string[]) => {
        setModes(prev => {
            const next = [...prev];
            if (ids.length > 0) next[0] = ids[0];
            if (ids.length > 1) next[1] = ids[1];
            if (ids.length > 2) next[2] = ids[2];
            return next;
        });
    }, []);

    const handleUpdateParams = useCallback((paramsList: Record<string, number>[]) => {
        paramsList.forEach((slotParamsUpdates, slotIndex) => {
            const updates = mapShaderParamUpdates(slotParamsUpdates, slotIndex);
            if (Object.keys(updates).length > 0) {
                updateSlotParam(slotIndex, updates);
            }
        });
    }, [mapShaderParamUpdates, updateSlotParam]);

    // --- EFFECT: Auto-Switch Generative Mode ---
    // This fixes the issue where generative mode wouldn't replace image/video input
    useEffect(() => {
        if (shaderCategory === 'generative') {
            // When user selects "Procedural Generation", force input source to generative
            syncInputSourceToRenderer('generative');
            setStatus('Switched to Generative Input');
        }
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [shaderCategory]); // Only depend on shaderCategory, not inputSource

    // --- Effects & Initializers ---
    
    useEffect(() => {
        const controller = new AbortController();


        // Fetch the dynamic image and video manifests from the backend on startup
        const fetchManifests = async () => {
            let content: LoadedContent;
            try {
                content = await fetchContentManifest();
            } catch (error) {
                if ((error as Error).name === 'AbortError') return;
                console.warn("Failed to fetch manifests:", error);
                content = {
                    manifest: FALLBACK_IMAGES.map(url => ({
                        url,
                        tags: ['fallback', 'unsplash', 'demo'],
                        description: 'Demo Image'
                    })),
                    videos: FALLBACK_VIDEOS.map(url => ({ url })),
                };
            }

            setImageManifest(content.manifest);
            setVideoList(content.videos);
            setStatus(`Loaded ${content.manifest.length} images, ${content.videos.length} videos`);

            // Hydrate durations in the background so B3HD mode can use them
            if (content.videos.length > 0) {
                hydrateDurations(content.videos).then((hydrated) => {
                    setVideoList(hydrated);
                }).catch((e) => {
                    console.warn("Failed to hydrate video durations:", e);
                });
            }

            // Push images to Renderer
            if (rendererRef.current) {
                rendererRef.current.setImageList(content.manifest.map(m => m.url));
            }
        };
        fetchManifests();
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
                    url: shader.url || resolveShaderUrl(`shaders/${shader.id}.wgsl`),
                    category: determineCategory(shader),
                    description: shader.description || '',
                    tags: shader.tags || [],
                    rating: shader.rating,
                    hasErrors: shader.has_errors,
                    requiresDeepWorkgroup: (shader as any).requiresDeepWorkgroup === true,
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
            } catch (error) {
                if (!isMounted) return;
                console.warn('Failed to load shaders:', error);
                setShadersReady(true); // Mark ready even on failure so boot gate doesn't block forever
                setStatus('⚠️ Could not load shader list. Some effects may be unavailable.');
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


    // --- Filter shaders that require unsupported GPU capabilities ---
    // Runs when the renderer is ready (capabilities known) or when the shader list
    // grows (new shaders added after renderer init).  Using availableModes.length as
    // the dep — rather than the full array reference — prevents re-triggering on the
    // reference change caused by the setAvailableModes(filtered) call below, because
    // filtering *reduces* the length: after the first pass the length is smaller and
    // the effect only re-runs if more shaders are subsequently added.
    useEffect(() => {
        if (!rendererReady || supportsDeepWorkgroup) return;  // nothing to filter
        const skipped: string[] = [];
        const filtered = availableModes.filter(s => {
            if (s.requiresDeepWorkgroup) {
                skipped.push(s.id);
                return false;
            }
            return true;
        });
        if (skipped.length > 0) {
            console.log(
                `[Shaders] ${skipped.length} shader(s) require deep-workgroup (16×16×4) ` +
                `which is not supported on this GPU — hiding from list: ${skipped.join(', ')}`
            );
            setAvailableModes(filtered);
        }
    // availableModes.length (not the full array) is intentional: we react when the
    // list grows, but filtering reduces length, so subsequent runs are prevented until
    // more shaders are added.  supportsDeepWorkgroup is stable after renderer init.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [rendererReady, supportsDeepWorkgroup, availableModes.length]);

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
        const manager = rendererRef.current;
        if (!manager) return;
        const newImageUrl = await manager.loadImage(url);
        if (newImageUrl) {
            setCurrentImageUrl(newImageUrl);
            if (depthEstimator) {
                await runDepthAnalysis(newImageUrl);
            }
        }
    }, [depthEstimator, runDepthAnalysis]);

    const handleNewRandomImage = useCallback(async () => {
        // If manifest is empty, try to use fallback images directly
        let sourceList = imageManifest;
        if (sourceList.length === 0) {
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
            // Clear the transient status message after a short delay
            setTimeout(() => setStatus('Ready.'), 2000);
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
            setMode(0, initialMode);
        } else {
            // All slots are none — guide the user to pick a shader from the dropdown
            setStatus('Ready. Select a shader from Slot 1 to get started.');
        }
    }, [rendererReady, shadersReady, modes, setMode]);

    // --- Initial Image Auto-Load ---
    // Separate from the boot gate so it fires whenever the manifest becomes available,
    // even if that happens after the renderer is already ready.
    useEffect(() => {
        if (!rendererReady || imageManifest.length === 0 || currentImageUrl) return;
        if (inputSource !== 'image') return;
        handleNewRandomImage();
    }, [rendererReady, imageManifest, currentImageUrl, inputSource, handleNewRandomImage]);

    // --- Auto-select shader when switching to video input ---
    // If user switches to video but no shader is active, auto-select the first available image shader
    useEffect(() => {
        if (inputSource !== 'video') return;
        if (modes[0] && modes[0] !== 'none') return; // Already have a shader
        if (availableModes.length === 0) return; // No shaders loaded yet

        // Find first non-generative shader (generative shaders require specific input)
        const firstImageShader = availableModes.find(s => s.category !== 'generative');
        if (firstImageShader) {
            console.log('[App] Auto-selecting shader for video input:', firstImageShader.id);
            setMode(0, firstImageShader.id as RenderMode);
        }
    }, [inputSource, modes, availableModes, setMode]);

    // --- Auto Image Switch Timer ---
    useEffect(() => {
        if (!autoChangeEnabled || inputSource !== 'image') return;
        const interval = setInterval(() => {
            handleNewRandomImage();
        }, autoChangeDelay * 1000);
        return () => clearInterval(interval);
    }, [autoChangeEnabled, autoChangeDelay, inputSource, handleNewRandomImage]);

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
                handleUpdateStack,
                () => { // This now correctly reads from state
                    const imgRecord = imageManifest.find(img => img.url === currentImageUrl) || null;
                    const shaderEntry = availableModes.find(m => m.id === modes[0]) || null;
                    const shaderRecord: ShaderRecord | null = shaderEntry ? {
                        id: shaderEntry.id,
                        name: shaderEntry.name,
                        category: shaderEntry.category || 'image',
                        description: shaderEntry.description,
                        tags: shaderEntry.tags || [],
                    } : null;
                    return { currentImage: imgRecord, currentShader: shaderRecord };
                },
                {
                    applyParamsDirect: handleApplyParamsDirect,
                }
            );
            vj.onStatusChange = (s, m) => { setAiVjStatus(s); setAiVjMessage(m); };
            vj.onUpdateParams = handleUpdateParams;
            setAiVj(vj);
            setIsAiVjMode(true);
            await vj.initialize(imageManifest, IMAGE_SUGGESTIONS_URL);
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
                    await aiVj.initialize(imageManifest, IMAGE_SUGGESTIONS_URL);
                    if (aiVj.start()) {
                        setIsAiVjMode(true);
                    }
                }
            }
        }
    }, [aiVj, isAiVjMode, availableModes, modes, handleLoadImage, imageManifest, currentImageUrl, handleUpdateStack, handleUpdateParams, handleApplyParamsDirect]);

    const handleGenerateFromVibe = useCallback(async (vibe: string) => {
        if (!aiVj) {
            setStatus('AI VJ not initialized. Please start AI VJ first.');
            return;
        }
        await aiVj.generateFromVibe(vibe);
    }, [aiVj]);

    const handleRandomizeParams = useCallback(async () => {
        if (!aiVj) return;
        await aiVj.randomizeActiveParams();
    }, [aiVj]);

    const handleTriggerNextTransition = useCallback(async () => {
        if (!aiVj) return;
        await aiVj.triggerNextTransition();
    }, [aiVj]);

    const handleSavePreset = useCallback((name: string) => {
        if (!aiVj) return;
        const shaderIds = aiVj.getActiveShaderIds();
        const params = aiVj.getCurrentParams();
        if (shaderIds.length === 0 || params.length === 0) return;
        savePreset(name, shaderIds, params);
    }, [aiVj]);

    const startAutoTransition = useCallback(async (config: AutoTransitionConfig) => {
        if (!aiVj) return false;
        return aiVj.startAutoTransition(config);
    }, [aiVj]);

    const stopAutoTransition = useCallback(() => {
        aiVj?.stopAutoTransition();
    }, [aiVj]);

    const handleRenderQualityChange = useCallback((mode: RenderQualityMode) => {
        setRenderQualityMode(mode);
        saveRenderQualityMode(mode);
        const manager = rendererRef.current;
        if (manager) {
            manager.setRenderQuality(mode, { supportsDeepWorkgroup: manager.getSupportsDeepWorkgroup() });
        }
    }, []);

    // Poll internal resolution + backend for status HUD
    useEffect(() => {
        if (!rendererReady) return;
        const tick = () => {
            const manager = rendererRef.current;
            if (!manager) return;
            const status = manager.getPerformanceStatus();
            setPerformanceHud({
                internalWidth: status.internalWidth,
                internalHeight: status.internalHeight,
                scale: status.scale,
                targetFps: status.targetFps,
                adaptive: status.adaptive,
                maxActiveSlots: status.maxActiveSlots,
            });
        };
        tick();
        const interval = setInterval(tick, 1000);
        return () => clearInterval(interval);
    }, [rendererReady, activeRendererType, renderQualityMode]);

    // --- Test Mode Hook (exposes renderer for Playwright harness) ---
    useEffect(() => {
        if (typeof window === 'undefined') return;
        const params = new URLSearchParams(window.location.search);
        if (params.get('testMode') === '1' && rendererRef.current) {
            const manager = rendererRef.current;
            const loadShaderTracked = async (id: string, url: string) => {
                const ok = await manager.loadShader(id, url) ?? false;
                if (params.get('shaderHotReload') === '1') {
                    import('./dev/shaderHotReload').then(({ trackShaderForHotReload }) => {
                        trackShaderForHotReload(id, url);
                    });
                }
                return ok;
            };
            (window as any).__pixelocity__ = {
                renderer: manager,
                getRendererType: () => manager.getActiveRendererType(),
                setSlotShader: (index: number, id: string) => {
                    manager.setSlotShader(index, id);
                },
                loadShader: loadShaderTracked,
                reloadShader: (id: string, url: string) => manager.reloadShader(id, url),
                setInputSource: (source: Parameters<typeof manager.setInputSource>[0]) => {
                    manager.setInputSource(source);
                },
                setTestRenderState: (state: Parameters<typeof manager.applyTestRenderState>[0]) => {
                    manager.applyTestRenderState(state);
                },
                captureCanvasScreenshot: async () => {
                    const canvas = document.querySelector('canvas');
                    if (!canvas) return null;
                    return canvas.toDataURL('image/png');
                },
                runBenchmark: async (frameCount = 90) => {
                    const samples: Array<{ fps: number; gpu: ReturnType<typeof manager.getGPUTimings> }> = [];
                    for (let i = 0; i < frameCount; i++) {
                        await new Promise<void>((r) => requestAnimationFrame(() => r()));
                        samples.push({
                            fps: manager.getMetrics().fps,
                            gpu: manager.getGPUTimings(),
                        });
                    }
                    const totals = samples.map((s) => s.gpu.totalTime).filter((t) => t > 0);
                    const avgTotalMs = totals.length
                        ? totals.reduce((a, b) => a + b, 0) / totals.length
                        : 0;
                    return {
                        frames: frameCount,
                        avgFps: samples.reduce((a, s) => a + s.fps, 0) / frameCount,
                        avgTotalMs,
                        gpuTimingsAvailable: samples.some((s) => s.gpu.available),
                        rendererType: manager.getActiveRendererType(),
                        samples: samples.slice(-5),
                    };
                },
                updateAudioFrequencyBins: (bins: Float32Array) => {
                    manager.updateAudioFrequencyBins(bins);
                },
                getSlotState: (index: number) => manager.getSlotState(index),
                getGPUTimings: () => manager.getGPUTimings(),
                getSupportsDeepWorkgroup: () => manager.getSupportsDeepWorkgroup(),
                takeScreenshot: (filename?: string) => manager.takeScreenshot(filename),
                refreshFrameImage: () => manager.refreshFrameImage(),
                getFrameImage: () => manager.getFrameImage(),
            };
        }
    }, [rendererReady]);
    useContentManifest({
        rendererRef,
        setImageManifest,
        setVideoList,
        setStatus,
    });

    useShaderCatalogLoad({
        setAvailableModes,
        setShadersReady,
        setStatus,
        rendererReady,
        supportsDeepWorkgroup,
        availableModes,
    });

    const { handleLoadImage, handleNewRandomImage } = useImageLoading({
        rendererRef,
        depthEstimator,
        runDepthAnalysis,
        imageManifest,
        setCurrentImageUrl,
        setStatus,
    });

    useShaderBoot({
        rendererReady,
        shadersReady,
        modes,
        setMode,
        setStatus,
        imageManifest,
        currentImageUrl,
        inputSource,
        handleNewRandomImage,
        availableModes,
        autoChangeEnabled,
        autoChangeDelay,
        shaderCategory,
        syncInputSourceToRenderer,
    });

    const {
        aiVj,
        aiVjStatus,
        aiVjMessage,
        isAiVjMode,
        toggleAiVj,
        handleGenerateFromVibe,
        handleRandomizeParams,
        handleTriggerNextTransition,
        handleSavePreset,
        startAutoTransition,
        stopAutoTransition,
    } = useAiVjHandlers({
        imageManifest,
        availableModes,
        modes,
        currentImageUrl,
        handleLoadImage,
        handleUpdateStack,
        handleUpdateParams,
        handleApplyParamsDirect,
        setStatus,
    });

    const {
        isWebcamActive,
        webcamError,
        showWebcamShaderSuggestions,
        videoElementRef,
        startWebcam,
        stopWebcam,
        applyWebcamFunShader,
    } = useWebcam({
        syncInputSourceToRenderer,
        setShaderCategory,
        setStatus,
        setMode,
        setActiveSlot,
    });

    const {
        showShareModal,
        setShowShareModal,
        shareableLink,
        shareVibeText,
        buildVjChainString,
        handleShareVjSet,
        applySharedChain,
        copyChainShareLink,
        getCurrentChain,
        openRecordingShareModal,
    } = useShareChain({
        modes,
        activeSlot,
        slotParams,
        inputSource,
        currentImageUrl,
        activeGenerativeShader,
        availableModesRef,
        aiVj,
        setMode,
        setActiveSlot,
        updateSlotParam,
        syncInputSourceToRenderer,
        setActiveGenerativeShader,
        handleLoadImage,
        startWebcam,
        setStatus,
    });

    const handleSaveVjSet = useCallback(async (name: string) => {
        const encoded = await buildVjChainString();
        if (!encoded) {
            setStatus('❌ No active VJ stack to save');
            return;
        }
        saveMyVjSet(name, aiVj?.getLastVibeText() ?? '', encoded);
        setStatus(`💾 Saved VJ set "${name}"`);
    }, [buildVjChainString, aiVj]);

    // --- Dev shader hot-reload (?renderer=wasm&shaderHotReload=1) ---
    useEffect(() => {
        if (typeof window === 'undefined' || !rendererRef.current) return;
        const params = new URLSearchParams(window.location.search);
        if (params.get('shaderHotReload') !== '1') return;
        if (params.get('renderer') !== 'wasm') return;

        let cleanup: (() => void) | undefined;
        import('./dev/shaderHotReload').then(({ attachShaderHotReload, wrapLoadShaderForHotReload }) => {
            const manager = rendererRef.current!;
            const wrapped = wrapLoadShaderForHotReload(manager);
            (window as any).__pixelocity__ = {
                ...(window as any).__pixelocity__,
                loadShader: wrapped,
                reloadShader: (id: string, url: string) => manager.reloadShader(id, url),
            };
            cleanup = attachShaderHotReload(manager);
            console.log('[HotReload] Enabled — edit files in public/shaders/ to reload pipelines');
        });
        return () => cleanup?.();
    }, [rendererReady]);

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
            syncInputSourceToRenderer('webcam');
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
    }, [syncInputSourceToRenderer]);

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
        syncInputSourceToRenderer('image');
        setShowWebcamShaderSuggestions(false);
        setStatus('Webcam stopped');
    }, [syncInputSourceToRenderer]);

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

    // --- B3HD Video Rotation Mode ---
    const b3hdTimerRef = useRef<NodeJS.Timeout | null>(null);
    const b3hdRecentHistoryRef = useRef<string[]>([]);
    const videoListRef = useRef<VideoRecord[]>(videoList);
    videoListRef.current = videoList;

    useEffect(() => {
        // Clear any existing timer when mode changes
        if (b3hdTimerRef.current) {
            clearTimeout(b3hdTimerRef.current);
            b3hdTimerRef.current = null;
        }

        if (!videoB3hdMode || inputSource !== 'video' || videoList.length === 0) {
            setCurrentSegment(null);
            return;
        }

        const playNextSegment = () => {
            const segment = pickRandomSegment(
                videoListRef.current,
                b3hdSegmentLength,
                b3hdRecentHistoryRef.current
            );
            if (!segment) {
                console.warn("B3HD: No valid segment found");
                return;
            }

            setCurrentSegment(segment);
            setSelectedVideo(segment.video.url);

            // Update history
            b3hdRecentHistoryRef.current.push(segment.video.id || segment.video.url);
            if (b3hdRecentHistoryRef.current.length > 5) {
                b3hdRecentHistoryRef.current.shift();
            }

            // Schedule next segment
            const totalCycle = (b3hdSegmentLength + b3hdIntervalSeconds) * 1000;
            b3hdTimerRef.current = setTimeout(playNextSegment, totalCycle);
        };

        // Start immediately
        playNextSegment();

        return () => {
            if (b3hdTimerRef.current) {
                clearTimeout(b3hdTimerRef.current);
                b3hdTimerRef.current = null;
            }
        };
    }, [videoB3hdMode, inputSource, b3hdSegmentLength, b3hdIntervalSeconds, videoList.length]);

    // --- Roulette / Chaos Mode Functions ---
    const getRandomShader = useCallback((): ShaderEntry | null => {
        if (availableModes.length === 0) return null;
        // Only include effect shaders that process input textures.
        // Exclude generative/simulation shaders (they render their own content and block the canvas).
        // Also filter by tags in case a shader is miscategorized by the API (e.g., category:"none" fallback).
        const EXCLUDED_CATEGORIES = new Set(['generative', 'simulation']);
        const validShaders = availableModes.filter(s => {
            if (!s.id || s.id === 'none') return false;
            if (EXCLUDED_CATEGORIES.has(s.category)) return false;
            if (s.tags?.includes('generative') || s.tags?.includes('simulation')) return false;
            return true;
        });
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

    const handleRandomizeSlot = useCallback((slot: number) => {
        const randomShader = getRandomShader();
        if (!randomShader) {
            setStatus('No shaders available for randomize.');
            return;
        }
        setMode(slot, randomShader.id as RenderMode);
        const newParams = randomizeSlotParams();
        updateSlotParam(slot, newParams);
        setStatus(`🎲 Randomized slot ${slot + 1}: ${randomShader.name}`);
        setIsRouletteActive(true);
        setTimeout(() => setIsRouletteActive(false), 500);
    }, [getRandomShader, randomizeSlotParams, setMode, updateSlotParam]);

    const handleSetSlotParam = useCallback((slot: number, param: string, value: number) => {
        const updates: Partial<SlotParams> = { [param]: value };
        updateSlotParam(slot, updates);
        rendererRef.current?.updateSlotParams(updates, slot);
    }, [updateSlotParam]);

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
        for (let i = 0; i < modes.length; i++) {
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
    }, [getRandomShader, randomizeSlotParams, setMode, updateSlotParam, modes.length]);

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

    // --- Generative Showcase Functions ---
    // Build a randomized list of all available generative shaders
    const getGenerativeShaders = useCallback((): ShaderEntry[] => {
        return availableModes.filter(s => s.category === 'generative' && s.id !== 'none');
    }, [availableModes]);

    const advanceGenerativeShowcase = useCallback(() => {
        const genShaders = getGenerativeShaders();
        if (genShaders.length === 0) return;

        // Pick next generative shader (random to avoid predictable order)
        const nextShader = genShaders[Math.floor(Math.random() * genShaders.length)];
        if (!nextShader) return;

        // Switch to generative input source if not already
        syncInputSourceToRenderer('generative');
        setActiveGenerativeShader(nextShader.id);

        // Load the shader into slot 0
        setMode(0, nextShader.id as RenderMode);

        // Set sensible default params (or randomize for variety)
        const defaults = getShaderDefaults(nextShader.id, nextShader.params?.length || 4);
        updateSlotParam(0, {
            zoomParam1: defaults[0],
            zoomParam2: defaults[1],
            zoomParam3: defaults[2],
            zoomParam4: defaults[3],
        });

        setStatus(`🎨 Generative Showcase: ${nextShader.name}`);
    }, [getGenerativeShaders, setMode, updateSlotParam, syncInputSourceToRenderer, setActiveGenerativeShader]);

    const startGenerativeShowcase = useCallback(() => {
        setGenerativeShowcaseLocked(false);
        setGenerativeShowcaseActive(true);
        syncInputSourceToRenderer('generative');
        advanceGenerativeShowcase(); // First one immediately
        setStatus('🎨 Generative Showcase started! Click or press SPACE to lock the current shader.');
    }, [advanceGenerativeShowcase, syncInputSourceToRenderer]);

    const stopGenerativeShowcase = useCallback(() => {
        setGenerativeShowcaseActive(false);
        setGenerativeShowcaseLocked(false);
        if (generativeShowcaseTimerRef.current) {
            clearInterval(generativeShowcaseTimerRef.current);
            generativeShowcaseTimerRef.current = null;
        }
        setStatus('Generative Showcase stopped.');
    }, []);

    const lockGenerativeShowcase = useCallback(() => {
        if (!generativeShowcaseActive) return;
        setGenerativeShowcaseLocked(true);
        if (generativeShowcaseTimerRef.current) {
            clearInterval(generativeShowcaseTimerRef.current);
            generativeShowcaseTimerRef.current = null;
        }
        setStatus('🔒 Generative shader locked! Mouse control is active.');
    }, [generativeShowcaseActive]);

    const unlockGenerativeShowcase = useCallback(() => {
        if (!generativeShowcaseActive) return;
        setGenerativeShowcaseLocked(false);
        // Restart timer
        if (generativeShowcaseTimerRef.current) {
            clearInterval(generativeShowcaseTimerRef.current);
        }
        generativeShowcaseTimerRef.current = setInterval(() => {
            advanceGenerativeShowcase();
        }, generativeShowcaseDelay * 1000);
        setStatus('🔓 Showcase resumed. Auto-switching generative shaders.');
    }, [generativeShowcaseActive, generativeShowcaseDelay, advanceGenerativeShowcase]);

    // Generative Showcase timer effect
    useEffect(() => {
        if (generativeShowcaseActive && !generativeShowcaseLocked) {
            // Clear any existing timer
            if (generativeShowcaseTimerRef.current) {
                clearInterval(generativeShowcaseTimerRef.current);
            }
            generativeShowcaseTimerRef.current = setInterval(() => {
                advanceGenerativeShowcase();
            }, generativeShowcaseDelay * 1000);
        } else {
            if (generativeShowcaseTimerRef.current) {
                clearInterval(generativeShowcaseTimerRef.current);
                generativeShowcaseTimerRef.current = null;
            }
        }

        return () => {
            if (generativeShowcaseTimerRef.current) {
                clearInterval(generativeShowcaseTimerRef.current);
            }
        };
    }, [generativeShowcaseActive, generativeShowcaseLocked, generativeShowcaseDelay, advanceGenerativeShowcase]);

    // --- Audio-Reactive Param Modulation ---
    // When enabled, zoomParam1-4 are automatically modulated by audio analysis
    // data sent from the audioGraph / WebGPU renderer extraBuffer.
    const updateAudioReactiveParams = useCallback(() => {
        const manager = rendererRef.current;
        if (!manager || !audioReactiveParams) return;

        // Read audio values from the analyzer hook (started when A toggle goes on)
        const audioData = getAudioAnalyzerData();
        if (!audioData) return;

        const { bass, mid, treble } = audioData;
        manager.updateAudioData(bass, mid, treble);
        manager.updateAudioFrequencyBins(getAudioBins());

        const overall = (bass + mid + treble) / 3.0;
        const amount = audioReactiveAmount;

        // Smooth the values to avoid jitter
        const smoothed = audioParamSmoothedRef.current;
        const smoothing = 0.15;
        smoothed[0] += (bass - smoothed[0]) * smoothing;
        smoothed[1] += (mid - smoothed[1]) * smoothing;
        smoothed[2] += (treble - smoothed[2]) * smoothing;
        smoothed[3] += (overall - smoothed[3]) * smoothing;

        // Only apply to generative shaders in active slot
        const currentShader = modes[0];
        const shaderEntry = availableModes.find(m => m.id === currentShader);
        if (shaderEntry && shaderEntry.category === 'generative') {
            const baseDefaults = getShaderDefaults(currentShader, 4);

            // Modulate around defaults: default ± amount * audio
            const modulated = {
                zoomParam1: Math.max(0, Math.min(1, baseDefaults[0] + (smoothed[0] - 0.5) * amount)),
                zoomParam2: Math.max(0, Math.min(1, baseDefaults[1] + (smoothed[1] - 0.5) * amount)),
                zoomParam3: Math.max(0, Math.min(1, baseDefaults[2] + (smoothed[2] - 0.5) * amount)),
                zoomParam4: Math.max(0, Math.min(1, baseDefaults[3] + (smoothed[3] - 0.5) * amount)),
            };

            updateSlotParam(0, modulated);
            rendererRef.current?.updateSlotParams(modulated, 0);
        }
    }, [audioReactiveParams, audioReactiveAmount, modes, availableModes, updateSlotParam, getAudioAnalyzerData, getAudioBins]);

    const handleTakeScreenshot = useCallback(async () => {
        const manager = rendererRef.current;
        if (!manager) return;
        try {
            const filename = `pixelocity-${Date.now()}.png`;
            await manager.takeScreenshot(filename);
            setStatus(`📸 Screenshot saved (${filename})`);
        } catch (err) {
            console.error('Screenshot failed:', err);
            setStatus('❌ Screenshot failed');
        }
    }, []);

    // Animation-frame callback for audio-reactive params (runs every frame)
    useEffect(() => {
        if (!audioReactiveParams) return;

        let rafId: number;
        const tick = () => {
            updateAudioReactiveParams();
            rafId = requestAnimationFrame(tick);
        };
        rafId = requestAnimationFrame(tick);

        return () => cancelAnimationFrame(rafId);
    }, [audioReactiveParams, updateAudioReactiveParams]);

    // Start/stop audio analyzer when A toggle changes
    useEffect(() => {
        if (audioReactiveParams) {
            startAudioAnalyzer();
        } else {
            stopAudioAnalyzer();
        }
    }, [audioReactiveParams, startAudioAnalyzer, stopAudioAnalyzer]);

    // --- Keyboard shortcuts: Generative Showcase & Audio-Reactive ---
    useEffect(() => {
        const handleKeyDown = (e: KeyboardEvent) => {
            if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;

            // 'G' toggles Generative Showcase
            if (e.key === 'g' || e.key === 'G') {
                if (generativeShowcaseActive) {
                    stopGenerativeShowcase();
                } else {
                    startGenerativeShowcase();
                }
            }
            // SPACE locks/unlocks the current generative shader
            if (e.key === ' ') {
                e.preventDefault(); // prevent page scroll
                if (generativeShowcaseActive) {
                    if (generativeShowcaseLocked) {
                        unlockGenerativeShowcase();
                    } else {
                        lockGenerativeShowcase();
                    }
                }
            }
            // 'A' toggles audio-reactive param modulation
            if (e.key === 'a' || e.key === 'A') {
                setAudioReactiveParams(prev => {
                    const next = !prev;
                    setStatus(next ? '🔊 Audio-reactive params ON' : '🔇 Audio-reactive params OFF');
                    return next;
                });
            }
            // '[' / ']' adjust audio reactive amount
            if (e.key === '[') {
                setAudioReactiveAmount(prev => {
                    const next = Math.max(0, Math.min(1, prev - 0.1));
                    setStatus(`🔊 Audio React Amount: ${Math.round(next * 100)}%`);
                    return next;
                });
            }
            if (e.key === ']') {
                setAudioReactiveAmount(prev => {
                    const next = Math.max(0, Math.min(1, prev + 0.1));
                    setStatus(`🔊 Audio React Amount: ${Math.round(next * 100)}%`);
                    return next;
                });
            }
        };

        window.addEventListener('keydown', handleKeyDown);
        return () => window.removeEventListener('keydown', handleKeyDown);
    }, [generativeShowcaseActive, generativeShowcaseLocked, startGenerativeShowcase, stopGenerativeShowcase, lockGenerativeShowcase, unlockGenerativeShowcase]);

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

    const finishRecordingBlob = useCallback((blob: Blob) => {
        if (recordingFinishedRef.current) return;
        recordingFinishedRef.current = true;

        const url = URL.createObjectURL(blob);

        const a = document.createElement('a');
        a.href = url;
        a.download = `pixelocity-clip-${Date.now()}.webm`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);

        openRecordingShareModal();

        setStatus('✅ Recording saved! Download started.');
        setTimeout(() => URL.revokeObjectURL(url), 1000);
    }, [openRecordingShareModal]);

    const clearRecordingTimer = useCallback(() => {
        if (recordingTimerRef.current) {
            clearInterval(recordingTimerRef.current);
            recordingTimerRef.current = null;
        }
    }, []);

    const stopRecording = useCallback(() => {
        clearRecordingTimer();

        const manager = rendererRef.current;
        if (manager?.usesInternalRecording()) {
            manager.stopRendererRecording();
            manager.setRecording(false);
            wasmRecordingPromiseRef.current = null;
            setIsRecording(false);
            setRecordingCountdown(8);
            return;
        }

        if (mediaRecorderRef.current && mediaRecorderRef.current.state !== 'inactive') {
            mediaRecorderRef.current.stop();
        }

        setIsRecording(false);
        setRecordingCountdown(8);
        rendererRef.current?.setRecording?.(false);
    }, [clearRecordingTimer]);

    const startRecording = useCallback(async () => {
        const canvas = webgpuCanvasRef.current;
        const manager = rendererRef.current;
        if (!canvas) {
            setStatus('❌ Canvas not found for recording');
            return;
        }
        if (!manager) {
            setStatus('❌ Renderer not ready for recording');
            return;
        }

        recordingFinishedRef.current = false;

        try {
            if (manager.usesInternalRecording()) {
                setIsRecording(true);
                setRecordingCountdown(8);
                setStatus('🔴 Recording (WASM)… 8s');
                manager.setRecording(true);

                const recordingPromise = manager.startRecording(canvas, {
                    durationMs: 8000,
                    frameRate: 60,
                    videoBitsPerSecond: 8_000_000,
                });
                wasmRecordingPromiseRef.current = recordingPromise;

                recordingPromise
                    .then((blob) => {
                        finishRecordingBlob(blob);
                    })
                    .catch((e) => {
                        console.error('WASM recording failed:', e);
                        setStatus('❌ Recording failed. WASM readback may be unavailable.');
                    })
                    .finally(() => {
                        wasmRecordingPromiseRef.current = null;
                        setIsRecording(false);
                        setRecordingCountdown(8);
                        manager.setRecording(false);
                    });

                let count = 8;
                recordingTimerRef.current = setInterval(() => {
                    count -= 1;
                    setRecordingCountdown(count);
                    setStatus(`🔴 Recording (WASM)… ${count}s`);

                    if (count <= 0) {
                        stopRecording();
                    }
                }, 1000);

                return;
            }

            // TS WebGPU path: capture the visible WebGPU canvas directly.
            const stream = canvas.captureStream(60);

            let mimeType = 'video/webm;codecs=vp9';
            if (!MediaRecorder.isTypeSupported(mimeType)) {
                mimeType = 'video/webm;codecs=vp8';
                if (!MediaRecorder.isTypeSupported(mimeType)) {
                    mimeType = 'video/webm';
                }
            }

            const mediaRecorder = new MediaRecorder(stream, {
                mimeType,
                videoBitsPerSecond: 8000000,
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
                finishRecordingBlob(blob);
            };

            mediaRecorder.start(100);
            rendererRef.current?.setRecording?.(true);
            setIsRecording(true);
            setRecordingCountdown(8);
            setStatus('🔴 Recording… 8s');

            let count = 8;
            recordingTimerRef.current = setInterval(() => {
                count -= 1;
                setRecordingCountdown(count);
                setStatus(`🔴 Recording… ${count}s`);

                if (count <= 0) {
                    stopRecording();
                }
            }, 1000);
        } catch (e) {
            console.error('Recording failed:', e);
            setStatus('❌ Recording failed. Browser may not support this feature.');
        }
    }, [finishRecordingBlob, stopRecording]);

    // Cleanup recording on unmount
    useEffect(() => {
        return () => {
            clearRecordingTimer();
            const manager = rendererRef.current;
            if (manager?.usesInternalRecording()) {
                manager.stopRendererRecording();
            } else if (mediaRecorderRef.current && mediaRecorderRef.current.state !== 'inactive') {
                mediaRecorderRef.current.stop();
            }
        };
    }, [clearRecordingTimer]);

    // --- Remote Control Sync ---
    // Build full state object for syncing
    const buildFullState = useCallback((): FullState => ({
        modes,
        activeSlot,
        slotParams,
        shaderCategory,
        inputSource,
        autoChangeEnabled,
        autoChangeDelay,
        isModelLoaded: !!depthEstimator,
        availableModes,
        videoList,
        selectedVideo,
        isMuted,
    }), [modes, activeSlot, slotParams, shaderCategory, inputSource,
        autoChangeEnabled, autoChangeDelay, depthEstimator, availableModes, videoList, selectedVideo, isMuted]);

    // Keep latest buildFullState in a ref so the BroadcastChannel effect
    // doesn't re-run every time state changes.
    const buildFullStateRef = useRef(buildFullState);
    buildFullStateRef.current = buildFullState;

    // Send message to remote
    const sendMessage = useCallback((type: SyncMessage['type'], payload?: any) => {
        if (channelRef.current) {
            channelRef.current.postMessage({ type, payload });
        }
    }, []);

    // Setup BroadcastChannel for remote control — runs once on mount
    useEffect(() => {
        const channel = new BroadcastChannel(SYNC_CHANNEL_NAME);
        channelRef.current = channel;

        channel.onmessage = (event) => {
            const msg = event.data as SyncMessage;

            if (msg.type === 'HELLO') {
                // Remote app connected — send full state and start heartbeat if not already running
                sendMessage('STATE_FULL', buildFullStateRef.current());
                // Send an immediate heartbeat so the remote doesn't timeout
                // before the first interval tick
                sendMessage('HEARTBEAT');
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
            } else if (msg.type === 'CMD_SET_INPUT_SOURCE') {
                syncInputSourceToRenderer(msg.payload);
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
            }
        };

        return () => {
            channel.close();
            if (heartbeatIntervalRef.current) {
                clearInterval(heartbeatIntervalRef.current);
                heartbeatIntervalRef.current = null;
            }
        };
    // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []); // Intentionally empty — channel lifecycle should not depend on state

    // Send state updates to remote when key state changes
    useEffect(() => {
        if (channelRef.current) {
            sendMessage('STATE_FULL', buildFullState());
        }
    }, [modes, activeSlot, shaderCategory, inputSource, 
        autoChangeEnabled, autoChangeDelay, isMuted, selectedVideo, buildFullState, sendMessage]);

    return (
        <div className="App">
            <AppShell
                activeTab={activeTab}
                setActiveTab={setActiveTab}
                showSidebar={showSidebar}
                setShowSidebar={setShowSidebar}
                modes={modes}
                setMode={setMode}
                activeSlot={activeSlot}
                setActiveSlot={setActiveSlot}
                slotParams={slotParams}
                updateSlotParam={updateSlotParam}
                slotShaderStatus={slotShaderStatus}
                shaderCategory={shaderCategory}
                setShaderCategory={setShaderCategory}
                handleNewRandomImage={handleNewRandomImage}
                autoChangeEnabled={autoChangeEnabled}
                setAutoChangeEnabled={setAutoChangeEnabled}
                autoChangeDelay={autoChangeDelay}
                setAutoChangeDelay={setAutoChangeDelay}
                loadDepthModel={loadDepthModel}
                isModelLoaded={isModelLoaded}
                availableModes={availableModes}
                inputSource={inputSource}
                syncInputSourceToRenderer={syncInputSourceToRenderer}
                videoList={videoList}
                selectedVideo={selectedVideo}
                setSelectedVideo={setSelectedVideo}
                videoB3hdMode={videoB3hdMode}
                setVideoB3hdMode={setVideoB3hdMode}
                b3hdSegmentLength={b3hdSegmentLength}
                setB3hdSegmentLength={setB3hdSegmentLength}
                b3hdIntervalSeconds={b3hdIntervalSeconds}
                setB3hdIntervalSeconds={setB3hdIntervalSeconds}
                currentSegment={currentSegment}
                isMuted={isMuted}
                setIsMuted={setIsMuted}
                activeGenerativeShader={activeGenerativeShader}
                setActiveGenerativeShader={setActiveGenerativeShader}
                fileInputImageRef={fileInputImageRef}
                fileInputVideoRef={fileInputVideoRef}
                isAiVjMode={isAiVjMode}
                toggleAiVj={toggleAiVj}
                aiVjStatus={aiVjStatus}
                aiVjMessage={aiVjMessage}
                handleGenerateFromVibe={handleGenerateFromVibe}
                handleUpdateStack={handleUpdateStack}
                handleUpdateParams={handleUpdateParams}
                handleRandomizeParams={handleRandomizeParams}
                handleSavePreset={handleSavePreset}
                handleTriggerNextTransition={handleTriggerNextTransition}
                handleRandomizeSlot={handleRandomizeSlot}
                handleSetSlotParam={handleSetSlotParam}
                handleShareVjSet={handleShareVjSet}
                handleSaveVjSet={handleSaveVjSet}
                startAutoTransition={startAutoTransition}
                stopAutoTransition={stopAutoTransition}
                isWebcamActive={isWebcamActive}
                startWebcam={startWebcam}
                stopWebcam={stopWebcam}
                webcamError={webcamError}
                showWebcamShaderSuggestions={showWebcamShaderSuggestions}
                webcamFunShaders={WEBCAM_FUN_SHADERS}
                applyWebcamFunShader={applyWebcamFunShader}
                triggerRoulette={triggerRoulette}
                triggerRandomizeAllSlots={triggerRandomizeAllSlots}
                isRouletteActive={isRouletteActive}
                chaosModeEnabled={chaosModeEnabled}
                setChaosModeEnabled={setChaosModeEnabled}
                audioReactiveParams={audioReactiveParams}
                setAudioReactiveParams={setAudioReactiveParams}
                audioReactiveAmount={audioReactiveAmount}
                setAudioReactiveAmount={setAudioReactiveAmount}
                isRecording={isRecording}
                recordingCountdown={recordingCountdown}
                startRecording={startRecording}
                stopRecording={stopRecording}
                handleTakeScreenshot={handleTakeScreenshot}
                setShowShaderScanner={setShowShaderScanner}
                activeRendererType={activeRendererType}
                handleSwitchRenderer={handleSwitchRenderer}
                setShowStorageBrowser={setShowStorageBrowser}
                copyChainShareLink={copyChainShareLink}
                applySharedChain={applySharedChain}
                getCurrentChain={getCurrentChain}
                rendererRef={rendererRef}
                mousePosition={mousePosition}
                setMousePosition={setMousePosition}
                isMouseDown={isMouseDown}
                setIsMouseDown={setIsMouseDown}
                onInitCanvas={onInitCanvas}
                videoSourceUrl={videoSourceUrl}
                webgpuCanvasRef={webgpuCanvasRef}
                videoElementRef={videoElementRef}
                status={status}
                generativeShowcaseActive={generativeShowcaseActive}
                generativeShowcaseLocked={generativeShowcaseLocked}
                isRendererSwitching={isRendererSwitching}
                jsFps={jsFps}
                wasmFps={wasmFps}
            />

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
                    transition: 'opacity 0.15s ease-out',
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
                            <h2>{shareVibeText ? '🎛️ Share Your VJ Set!' : '🎉 Clip Recorded!'}</h2>
                            <p>{shareVibeText
                                ? 'Anyone who opens this link gets your exact shader stack.'
                                : 'Your video has been downloaded. Share your creation!'}</p>
                        </div>

                        {shareVibeText && (
                            <div className="share-link-section">
                                <label>Vibe Prompt:</label>
                                <div style={{
                                    fontStyle: 'italic',
                                    color: '#d0d0e0',
                                    background: 'rgba(20, 20, 30, 0.6)',
                                    border: '1px solid rgba(255, 215, 0, 0.15)',
                                    borderRadius: '6px',
                                    padding: '8px 10px',
                                }}>
                                    “{shareVibeText}”
                                </div>
                            </div>
                        )}

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
                                syncInputSourceToRenderer('video');
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
                                if (config.inputSource) syncInputSourceToRenderer(config.inputSource);
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
