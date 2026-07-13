import React, { useState, useEffect, useCallback, useRef } from 'react';
import WebGPUCanvas from './components/WebGPUCanvas';
import Controls from './components/Controls';
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
import { RendererManager } from './renderer/RendererManager';
import { ImageRecord } from './AutoDJ';
import { VideoRecord } from './syncTypes';
import { VideoSegment } from './services/videoSegmentManager';
import { saveMyVjSet } from './services/myVjSets';
import {
    DEFAULT_B3HD_SEGMENT_LENGTH,
    DEFAULT_B3HD_INTERVAL_SECONDS,
} from './config/appConfig';
import {
    useDepthEstimation,
    useAudioReactiveParams,
    useShareChain,
    useContentManifest,
    useShaderCatalogLoad,
    useShaderBoot,
    useAiVjHandlers,
    useWebcam,
    useB3hdMode,
    useRoulette,
    useGenerativeShowcase,
    useRecording,
    useRemoteSync,
    useRendererBackend,
    useShaderMode,
    useTestHarness,
    useImageLoading,
} from './hooks';
import { WEBCAM_FUN_SHADERS, getShaderDefaults } from './app/constants/shaderDefaults';
import { defaultSlotParams } from './app/constants/defaultSlotParams';
import { AppShell } from './components/app/AppShell';
import { AppOverlays } from './components/app/AppOverlays';
import './style.css';

function MainApp() {
    const [activeTab, setActiveTab] = useState<'main' | 'live-studio'>('main');
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
    const [autoChangeEnabled, setAutoChangeEnabled] = useState(false);
    const [autoChangeDelay, setAutoChangeDelay] = useState(10);
    const [status, setStatus] = useState('Ready.');
    const [slotShaderStatus, setSlotShaderStatus] = useState<Array<'idle' | 'loading' | 'error'>>(['idle', 'idle', 'idle', 'idle', 'idle', 'idle']);
    const [imageManifest, setImageManifest] = useState<ImageRecord[]>([]);
    const [videoList, setVideoList] = useState<VideoRecord[]>([]);
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
    const [showSidebar, setShowSidebar] = useState(true);
    const [showShaderScanner, setShowShaderScanner] = useState(false);
    const [showStorageBrowser, setShowStorageBrowser] = useState(false);
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const [storageBrowserTab, setStorageBrowserTab] = useState<'shaders' | 'images' | 'videos'>('shaders');
    const [mousePosition, setMousePosition] = useState({ x: 0.5, y: 0.5 });
    const [isMouseDown, setIsMouseDown] = useState(false);
    const [shadersReady, setShadersReady] = useState(false);
    const initialBootAppliedRef = useRef(false);

    // --- State: GPU Capabilities ---
    const [supportsDeepWorkgroup, setSupportsDeepWorkgroup] = useState(false);

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
    const slotShaderStatusRef = useRef<Array<'idle' | 'loading' | 'error'>>(['idle', 'idle', 'idle', 'idle', 'idle', 'idle']);
    const webgpuCanvasRef = useRef<HTMLCanvasElement | null>(null);
    const fileInputImageRef = useRef<HTMLInputElement>(null);
    const fileInputVideoRef = useRef<HTMLInputElement>(null);

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

    // --- Renderer backend state ---
    const [activeRendererType, setActiveRendererType] = useState<RendererType>('webgpu');
    const [jsFps, setJsFps] = useState(0);
    const [wasmFps, setWasmFps] = useState(0);
    const [isRendererSwitching, setIsRendererSwitching] = useState(false);

    const handleSwitchRenderer = useCallback(async (type: RendererType) => {
        const manager = rendererRef.current;
        if (!manager) return;

        setIsRendererSwitching(true);
        setStatus(`Switching to ${type} renderer…`);

        // Snapshot current FPS into the correct bucket before switching
        const currentFps = manager.getCurrentFPS?.() ?? 0;
        if (activeRendererType === 'webgpu' || activeRendererType === 'js') {
            setJsFps(currentFps);
        } else if (activeRendererType === 'wasm') {
            setWasmFps(currentFps);
        }

        const ok = await manager.switchRenderer(type);

        if (ok) {
            setActiveRendererType(type);
            setStatus(`✅ Now using ${type === 'wasm' ? 'C++ WASM (experimental)' : type === 'webgpu' ? 'TypeScript WebGPU' : 'Canvas2D'} renderer.`);

            // Re-bind shaders + params so the new backend matches the UI state
            if (type === 'wasm' || type === 'webgpu') {
                await manager.resyncShaderStack({
                    modes: modesRef.current,
                    slotParams: slotParamsRef.current,
                    resolveShader: (shaderId) => availableModesRef.current.find(s => s.id === shaderId),
                    inputSource: inputSourceRef.current,
                });
            }
        } else {
            setStatus(`⚠️ Failed to switch to ${type} renderer — staying on ${activeRendererType}.`);
        }
        setIsRendererSwitching(false);
    }, [activeRendererType]);

    // Poll real FPS from the active renderer and keep separate buckets for comparison
    useEffect(() => {
        const interval = setInterval(() => {
            const manager = rendererRef.current;
            if (!manager) return;
            const fps = manager.getCurrentFPS?.() ?? 0;
            if (activeRendererType === 'wasm') {
                setWasmFps(fps);
            } else {
                setJsFps(fps);
            }
        }, 800);
        return () => clearInterval(interval);
    }, [activeRendererType]);
    const fileInputImageRef = useRef<HTMLInputElement>(null);
    const fileInputVideoRef = useRef<HTMLInputElement>(null);
    const channelRef = useRef<BroadcastChannel | null>(null);
    const heartbeatIntervalRef = useRef<NodeJS.Timeout | null>(null);
    const rouletteFlashRef = useRef<HTMLDivElement | null>(null);
    // Mirrors slotShaderStatus state so setMode can read it without being in its dep array
    const slotShaderStatusRef = useRef<Array<'idle' | 'loading' | 'error'>>(['idle', 'idle', 'idle', 'idle', 'idle', 'idle']);
    // Direct ref to the WebGPU canvas — set via onCanvasRef callback (avoids fragile querySelector)
    const webgpuCanvasRef = useRef<HTMLCanvasElement | null>(null);

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

    /** Push input-source changes to the active renderer (WebGPU, WASM, or JS). */
    const syncInputSourceToRenderer = useCallback((source: InputSource) => {
        inputSourceRef.current = source;
        setInputSource(source);
        rendererRef.current?.setInputSource(source);
    }, []);

    const mapShaderParamUpdates = useCallback((slotParamsUpdates: Record<string, number>, slotIndex: number): Partial<SlotParams> => {
        const shaderId = modesRef.current[slotIndex];
        const shaderEntry = availableModesRef.current.find(m => m.id === shaderId);
        if (!shaderEntry || !shaderEntry.params) return {};

        return mapOrderedParamsToSlotParams(slotParamsUpdates, shaderEntry.params.map(p => p.id));
    }, []);

    const handleApplyParamsDirect = useCallback((paramsList: Record<string, number>[]) => {
        paramsList.forEach((slotParamsUpdates, slotIndex) => {
            const updates = mapShaderParamUpdates(slotParamsUpdates, slotIndex);
            if (Object.keys(updates).length > 0) {
                rendererRef.current?.updateSlotParams({
                    zoomParam1: updates.zoomParam1,
                    zoomParam2: updates.zoomParam2,
                    zoomParam3: updates.zoomParam3,
                    zoomParam4: updates.zoomParam4,
                }, slotIndex);
            }
        });
    }, [mapShaderParamUpdates]);

    const setMode = useCallback(async (index: number, mode: RenderMode) => {
        const maxSlots = rendererRef.current?.getMaxActiveSlots?.() ?? 3;
        if (mode !== 'none' && index >= maxSlots) {
            setStatus(`Quality cap: only ${maxSlots} slot(s) active — raise quality in Render Quality panel.`);
            return;
        }

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
            if (rendererRef.current) {
                rendererRef.current.setSlotShader(index, '');
            }
            return;
        }

        // Attempt to load & compile the shader, tracking status
        const shaderEntry = availableModes.find(s => s.id === mode);
        if (shaderEntry && rendererRef.current) {
            slotShaderStatusRef.current[index] = 'loading';
            setSlotShaderStatus(prev => { const n = [...prev]; n[index] = 'loading'; return n; });

            try {
                // Determine shader URL — API shaders now point directly to the .wgsl static file
                // served by nginx with CORS headers, so pass the URL straight to loadShader.
                let shaderUrl = shaderEntry.url;
                
                // Load the shader
                const ok = await rendererRef.current.loadShader(
                    shaderEntry.id,
                    shaderUrl,
                    { requiresDeepWorkgroup: shaderEntry.requiresDeepWorkgroup },
                );
                
                // Activate the shader on the specified slot
                if (ok && rendererRef.current) {
                    rendererRef.current.setSlotShader(index, shaderEntry.id);
                }
                
                slotShaderStatusRef.current[index] = ok ? 'idle' : 'error';
                setSlotShaderStatus(prev => { const n = [...prev]; n[index] = ok ? 'idle' : 'error'; return n; });
                
                // Initialize slider values to shader's declared param defaults
                // Use hardcoded defaults first (API returns generic 0.5 values)
                const hardcodedDefaults = getShaderDefaults(shaderEntry.id, shaderEntry.params?.length || 4);
                const hasHardcoded = hardcodedDefaults.some(v => v !== 0.5);
                
                if (ok && (shaderEntry.params?.length || hasHardcoded)) {
                    const paramDefaults: Partial<SlotParams> = {};
                    const numParams = shaderEntry.params?.length || hardcodedDefaults.length;
                    
                    for (let i = 0; i < numParams; i++) {
                        // Use hardcoded default if available, otherwise fall back to API default
                        const defaultValue = hasHardcoded ? hardcodedDefaults[i] : (shaderEntry.params?.[i]?.default ?? 0.5);
                        if (i === 0) paramDefaults.zoomParam1 = defaultValue;
                        else if (i === 1) paramDefaults.zoomParam2 = defaultValue;
                        else if (i === 2) paramDefaults.zoomParam3 = defaultValue;
                        else if (i === 3) paramDefaults.zoomParam4 = defaultValue;
                    }
                    
                    setSlotParams(prev => {
                        const next = [...prev];
                        next[index] = { ...next[index], ...paramDefaults };
                        return next;
                    });
                }
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

    useEffect(() => { modesRef.current = modes; }, [modes]);
    useEffect(() => { availableModesRef.current = availableModes; }, [availableModes]);
    useEffect(() => { slotParamsRef.current = slotParams; }, [slotParams]);
    useEffect(() => { inputSourceRef.current = inputSource; }, [inputSource]);

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
                    requiresDeepWorkgroup: shader.requiresDeepWorkgroup === true,
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
    
    const onInitCanvas = useCallback(() => {
        const manager = rendererRef.current;
        if (!manager) return;
        setActiveRendererType(manager.getActiveRendererType());
        const deep = manager.getSupportsDeepWorkgroup();
        setSupportsDeepWorkgroup(deep);
        manager.setRenderQuality(renderQualityMode, { supportsDeepWorkgroup: deep });
        manager.setInputSource(inputSourceRef.current);
        setRendererReady(true);
    }, [renderQualityMode]);

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
    }, [buildVjChainString, aiVj, setStatus]);

    useB3hdMode({
        videoB3hdMode,
        inputSource,
        videoList,
        b3hdSegmentLength,
        b3hdIntervalSeconds,
        setCurrentSegment,
        setSelectedVideo,
    });

    const {
        isRouletteActive,
        chaosModeEnabled,
        setChaosModeEnabled,
        showConfetti,
        rouletteFlashRef,
        handleRandomizeSlot,
        triggerRoulette,
        triggerRandomizeAllSlots,
    } = useRoulette({
        availableModes,
        modes,
        activeSlot,
        setMode,
        updateSlotParam,
        setStatus,
    });

    const {
        generativeShowcaseActive,
        generativeShowcaseLocked,
        startGenerativeShowcase,
        stopGenerativeShowcase,
        lockGenerativeShowcase,
        unlockGenerativeShowcase,
    } = useGenerativeShowcase({
        availableModes,
        setMode,
        updateSlotParam,
        syncInputSourceToRenderer,
        setActiveGenerativeShader,
        setStatus,
    });

    const handleSetSlotParam = useCallback((slot: number, param: string, value: number) => {
        const updates: Partial<SlotParams> = { [param]: value };
        updateSlotParam(slot, updates);
        rendererRef.current?.updateSlotParams(updates, slot);
    }, [updateSlotParam]);

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

    // --- Keyboard shortcuts: Generative Showcase ---
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

    const {
        isRecording,
        recordingCountdown,
        startRecording,
        stopRecording,
    } = useRecording({
        rendererRef,
        webgpuCanvasRef,
        openRecordingShareModal,
        setStatus,
    });

    useRemoteSync({
        modes,
        activeSlot,
        slotParams,
        shaderCategory,
        inputSource,
        autoChangeEnabled,
        autoChangeDelay,
        isModelLoaded,
        availableModes,
        videoList,
        selectedVideo,
        isMuted,
        setMode,
        setActiveSlot,
        updateSlotParam,
        setShaderCategory,
        syncInputSourceToRenderer,
        setAutoChangeEnabled,
        setAutoChangeDelay,
        handleNewRandomImage,
        loadDepthModel,
        setSelectedVideo,
        setIsMuted,
    });

    useTestHarness({ rendererRef, rendererReady });

    return (
        <div className="App">
            <header className="header">
                <div className="logo-section">
                    <div style={{ height: '80px', overflow: 'hidden', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                        <img
                            src="https://test.1ink.us/image_video_effects/static/media/pixelocity_title_logo_glitch.gif"
                            alt="Pixelocity"
                            className="logo-img"
                            style={{ height: '100px', width: 'auto', objectFit: 'contain' }}
                        />
                    </div>
                    <div className="subtitle-text">Image Playpen</div>
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
                        setShaderCategory={setShaderCategory} onNewImage={handleNewRandomImage}
                        autoChangeEnabled={autoChangeEnabled} setAutoChangeEnabled={setAutoChangeEnabled}
                        autoChangeDelay={autoChangeDelay} setAutoChangeDelay={setAutoChangeDelay}
                        onLoadModel={loadDepthModel} isModelLoaded={isModelLoaded} availableModes={availableModes}
                        inputSource={inputSource} setInputSource={syncInputSourceToRenderer} videoList={videoList}
                        selectedVideo={selectedVideo} setSelectedVideo={setSelectedVideo}
                        videoB3hdMode={videoB3hdMode} setVideoB3hdMode={setVideoB3hdMode}
                        b3hdSegmentLength={b3hdSegmentLength} setB3hdSegmentLength={setB3hdSegmentLength}
                        b3hdIntervalSeconds={b3hdIntervalSeconds} setB3hdIntervalSeconds={setB3hdIntervalSeconds}
                        currentSegment={currentSegment}
                        isMuted={isMuted} setIsMuted={setIsMuted}
                        activeGenerativeShader={activeGenerativeShader} setActiveGenerativeShader={setActiveGenerativeShader}
                        onUploadImageTrigger={() => fileInputImageRef.current?.click()}
                        onUploadVideoTrigger={() => fileInputVideoRef.current?.click()}
                        isAiVjMode={isAiVjMode} onToggleAiVj={toggleAiVj} aiVjStatus={aiVjStatus}
                        aiVjMessage={aiVjMessage} onGenerateFromVibe={handleGenerateFromVibe}
                        onUpdateStack={handleUpdateStack} onUpdateParams={handleUpdateParams}
                        onRandomizeParams={handleRandomizeParams}
                        onSavePreset={handleSavePreset}
                        onTriggerNextTransition={handleTriggerNextTransition}
                        onRandomizeSlot={handleRandomizeSlot}
                        onSetSlotParam={handleSetSlotParam}
                        onShareVjSet={handleShareVjSet}
                        onSaveVjSet={handleSaveVjSet}
                        onStartAutoTransition={startAutoTransition}
                        onStopAutoTransition={stopAutoTransition}
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
                        // Audio-Reactive Props
                        audioReactiveParams={audioReactiveParams}
                        setAudioReactiveParams={setAudioReactiveParams}
                        audioReactiveAmount={audioReactiveAmount}
                        setAudioReactiveAmount={setAudioReactiveAmount}
                        // Recording props
                        isRecording={isRecording}
                        recordingCountdown={recordingCountdown}
                        onStartRecording={startRecording}
                        onStopRecording={stopRecording}
                        onTakeScreenshot={handleTakeScreenshot}
                        // Dev Tools props
                        onOpenShaderScanner={() => setShowShaderScanner(true)}
                        // Renderer switch props
                        activeRendererType={activeRendererType}
                        onSwitchRenderer={handleSwitchRenderer}
                        // Storage Browser props
                        onOpenStorageBrowser={() => setShowStorageBrowser(true)}
                        // Multi-Slot Chain Sharing props
                        onCopyChainShareLink={copyChainShareLink}
                        onApplySharedChain={applySharedChain}
                        renderQualityMode={renderQualityMode}
                        onRenderQualityChange={handleRenderQualityChange}
                        maxActiveSlots={performanceHud.maxActiveSlots}
                        performanceHud={performanceHud}
                    />
                </aside>
                <main className="canvas-container">
                    <WebGPUCanvas
                        modes={modes} slotParams={slotParams}
                        rendererRef={rendererRef} farthestPoint={{x:0.5, y:0.5}}
                        mousePosition={mousePosition} setMousePosition={setMousePosition}
                        isMouseDown={isMouseDown} setIsMouseDown={setIsMouseDown} onInit={onInitCanvas}
                        inputSource={inputSource} videoSourceUrl={videoSourceUrl}
                        isMuted={isMuted} setInputSource={syncInputSourceToRenderer}
                        activeSlot={activeSlot}
                        activeGenerativeShader={activeGenerativeShader}
                        selectedVideo={selectedVideo}
                        segment={currentSegment ? { start: currentSegment.start, end: currentSegment.end } : null}
                        apiBaseUrl={STORAGE_API_URL}
                        isWebcamActive={isWebcamActive}
                        webcamVideoElement={videoElementRef.current}
                        onCanvasRef={(el) => { webgpuCanvasRef.current = el; }}
                        shaderCatalog={availableModes}
                    />
                    <div className="status-bar">
                        <span>{isAiVjMode ? `[AI VJ]: ${aiVjMessage}` : status}</span>
                        {generativeShowcaseActive && (
                            <span style={{ color: '#00d4ff', marginLeft: '12px', fontWeight: 600 }}>
                                🎨 Showcase {generativeShowcaseLocked ? '🔒 LOCKED' : '● AUTO'}
                            </span>
                        )}
                        {audioReactiveParams && (
                            <span style={{ color: '#FFD700', marginLeft: '12px' }}>
                                🔊 Audio-Reactive {Math.round(audioReactiveAmount * 100)}%
                            </span>
                        )}

                        {/* Current Renderer Badge (clickable for cycling) */}
                        <span
                            className={`renderer-badge renderer-badge--${activeRendererType}`}
                            title={
                                activeRendererType === 'wasm'
                                    ? 'Experimental C++ WASM — click to cycle renderer'
                                    : 'Click to cycle renderer (WebGPU ↔ WASM ↔ Canvas2D)'
                            }
                            onClick={() => {
                                const cycle: Record<RendererType, RendererType> = {
                                    webgpu: 'wasm',
                                    wasm: 'js',
                                    js: 'webgpu',
                                };
                                handleSwitchRenderer(cycle[activeRendererType]);
                            }}
                        >
                            {activeRendererType === 'wasm'
                                ? '⚡ WASM (exp.)'
                                : activeRendererType === 'js'
                                  ? '🎨 Canvas2D'
                                  : '🔷 WebGPU'}
                        </span>

                        <PerformanceStatusHUD
                            backend={activeRendererType}
                            internalWidth={performanceHud.internalWidth}
                            internalHeight={performanceHud.internalHeight}
                            scale={performanceHud.scale}
                            fps={activeRendererType === 'wasm' ? wasmFps : jsFps}
                            qualityLabel={renderQualityMode}
                        />

                        {/* FPS Comparison + Switch Toggle (JS WebGPU vs C++ WASM) */}
                        <RendererToggle
                            isWASM={activeRendererType === 'wasm'}
                            onToggle={async (useWasm) => {
                                const target: RendererType = useWasm ? 'wasm' : 'webgpu';
                                await handleSwitchRenderer(target);
                            }}
                            isLoading={isRendererSwitching}
                            jsFps={jsFps}
                            wasmFps={wasmFps}
                        />
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
            <AppOverlays
                rouletteFlashRef={rouletteFlashRef}
                showConfetti={showConfetti}
                chaosModeEnabled={chaosModeEnabled}
                isRecording={isRecording}
                recordingCountdown={recordingCountdown}
                showShareModal={showShareModal}
                setShowShareModal={setShowShareModal}
                shareVibeText={shareVibeText}
                shareableLink={shareableLink}
                setStatus={setStatus}
                availableModes={availableModes}
                showShaderScanner={showShaderScanner}
                setShowShaderScanner={setShowShaderScanner}
                setMode={setMode}
                updateSlotParam={updateSlotParam}
                showStorageBrowser={showStorageBrowser}
                setShowStorageBrowser={setShowStorageBrowser}
                activeSlot={activeSlot}
                handleLoadImage={handleLoadImage}
                syncInputSourceToRenderer={syncInputSourceToRenderer}
                setSelectedVideo={setSelectedVideo}
                setSlotParams={setSlotParams}
                storageBrowserTab={storageBrowserTab}
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
                                if (config.inputSource) {
                                    syncInputSourceToRenderer(config.inputSource as InputSource);
                                }
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
