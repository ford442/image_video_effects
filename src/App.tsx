import React, { useState, useEffect, useCallback, useRef } from 'react';
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
        </div>
    );
}

export default MainApp;
