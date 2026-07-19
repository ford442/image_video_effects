import React, { useState, useEffect, useCallback, useRef } from 'react';
import { AppShell } from './components/app/AppShell';
import { AppOverlays } from './components/app/AppOverlays';
import { DEFAULT_B3HD_SEGMENT_LENGTH, DEFAULT_B3HD_INTERVAL_SECONDS } from './config/appConfig';
import { RenderQualityMode } from './config/performancePolicy';
import { isRenderQualityMode, loadRenderQualityMode, saveRenderQualityMode } from './services/renderQuality';
import { RendererManager } from './renderer/RendererManager';
import { ImageRecord } from './AutoDJ';
import { VideoRecord } from './syncTypes';
import { VideoSegment } from './services/videoSegmentManager';
import { saveMyVjSet } from './services/myVjSets';
import {
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
    useB3hdMode,
    useRoulette,
    useGenerativeShowcase,
    useRecording,
    useRemoteSync,
    useTestHarness,
} from './hooks';
import { WEBCAM_FUN_SHADERS, getShaderDefaults } from './app/constants/shaderDefaults';
import { defaultSlotParams } from './app/constants/defaultSlotParams';
import { RenderMode, ShaderEntry, ShaderCategory, InputSource, SlotParams } from './renderer/types';
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
    const [videoSourceUrl, setVideoSourceUrl] = useState<string | undefined>(undefined);
    const [isMuted, setIsMuted] = useState(true);
    const [selectedVideo, setSelectedVideo] = useState<string>('');
    const [videoB3hdMode, setVideoB3hdMode] = useState(false);
    const [b3hdSegmentLength, setB3hdSegmentLength] = useState(DEFAULT_B3HD_SEGMENT_LENGTH);
    const [b3hdIntervalSeconds, setB3hdIntervalSeconds] = useState(DEFAULT_B3HD_INTERVAL_SECONDS);
    const [currentSegment, setCurrentSegment] = useState<VideoSegment | null>(null);
    const [showSidebar, setShowSidebar] = useState(true);
    const [showShaderScanner, setShowShaderScanner] = useState(false);
    const [showStorageBrowser, setShowStorageBrowser] = useState(false);
    const [storageBrowserTab, setStorageBrowserTab] = useState<'shaders' | 'images' | 'videos'>('shaders');
    const [mousePosition, setMousePosition] = useState({ x: 0.5, y: 0.5 });
    const [isMouseDown, setIsMouseDown] = useState(false);
    const [shadersReady, setShadersReady] = useState(false);
    const [renderQualityMode, setRenderQualityMode] = useState<RenderQualityMode>(() => {
        if (typeof window !== 'undefined') {
            const fromUrl = new URLSearchParams(window.location.search).get('renderQuality');
            if (isRenderQualityMode(fromUrl)) return fromUrl;
        }
        return loadRenderQualityMode();
    });
    const [performanceHud, setPerformanceHud] = useState({
        internalWidth: 2048,
        internalHeight: 2048,
        scale: 1,
        targetFps: 60,
        adaptive: true,
        maxActiveSlots: 3,
    });

    const rendererRef = useRef<RendererManager | null>(null);
    const modesRef = useRef<RenderMode[]>(modes);
    const availableModesRef = useRef<ShaderEntry[]>(availableModes);
    const slotParamsRef = useRef<SlotParams[]>(slotParams);
    const inputSourceRef = useRef<InputSource>(inputSource);
    const fileInputImageRef = useRef<HTMLInputElement>(null);
    const fileInputVideoRef = useRef<HTMLInputElement>(null);
    const slotShaderStatusRef = useRef<Array<'idle' | 'loading' | 'error'>>(['idle', 'idle', 'idle', 'idle', 'idle', 'idle']);
    const webgpuCanvasRef = useRef<HTMLCanvasElement | null>(null);

    useEffect(() => { modesRef.current = modes; }, [modes]);
    useEffect(() => { availableModesRef.current = availableModes; }, [availableModes]);
    useEffect(() => { slotParamsRef.current = slotParams; }, [slotParams]);
    useEffect(() => { inputSourceRef.current = inputSource; }, [inputSource]);

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
        isModelLoaded,
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
    } = useGenerativeShowcase({
        availableModes,
        setMode,
        updateSlotParam,
        syncInputSourceToRenderer,
        setActiveGenerativeShader,
        setStatus,
    });

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

    useEffect(() => {
        if (!rendererReady) return;
        const manager = rendererRef.current;
        if (!manager) return;
        manager.setRenderQuality(renderQualityMode, {
            supportsDeepWorkgroup: manager.getSupportsDeepWorkgroup(),
        });
    }, [rendererReady, renderQualityMode]);

    const handleSaveVjSet = useCallback(async (name: string) => {
        const encoded = await buildVjChainString();
        if (!encoded) {
            setStatus('❌ No active VJ stack to save');
            return;
        }
        saveMyVjSet(name, aiVj?.getLastVibeText() ?? '', encoded);
        setStatus(`💾 Saved VJ set "${name}"`);
    }, [buildVjChainString, aiVj, setStatus]);

    const handleRenderQualityChange = useCallback((mode: RenderQualityMode) => {
        setRenderQualityMode(mode);
        saveRenderQualityMode(mode);
        const manager = rendererRef.current;
        if (manager) {
            manager.setRenderQuality(mode, { supportsDeepWorkgroup: manager.getSupportsDeepWorkgroup() });
        }
    }, []);

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
    }, [setStatus]);

    useEffect(() => {
        if (!rendererReady) return;
        const tick = () => {
            const manager = rendererRef.current;
            if (!manager) return;
            const perf = manager.getPerformanceStatus();
            setPerformanceHud({
                internalWidth: perf.internalWidth,
                internalHeight: perf.internalHeight,
                scale: perf.scale,
                targetFps: perf.targetFps,
                adaptive: perf.adaptive,
                maxActiveSlots: perf.maxActiveSlots,
            });
        };
        tick();
        const interval = setInterval(tick, 1000);
        return () => clearInterval(interval);
    }, [rendererReady, activeRendererType, renderQualityMode]);

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
                renderQualityMode={renderQualityMode}
                onRenderQualityChange={handleRenderQualityChange}
                performanceHud={performanceHud}
            />

            <AppOverlays
                rouletteFlashRef={rouletteFlashRef}
                showConfetti={showConfetti}
                chaosModeEnabled={chaosModeEnabled}
                isRecording={isRecording}
                recordingCountdown={recordingCountdown}
                showShareModal={showShareModal}
                setShowShareModal={setShowShareModal}
                shareableLink={shareableLink}
                shareVibeText={shareVibeText}
                setStatus={setStatus}
                showShaderScanner={showShaderScanner}
                setShowShaderScanner={setShowShaderScanner}
                availableModes={availableModes}
                setMode={setMode}
                updateSlotParam={updateSlotParam}
                showStorageBrowser={showStorageBrowser}
                setShowStorageBrowser={setShowStorageBrowser}
                storageBrowserTab={storageBrowserTab}
                activeSlot={activeSlot}
                handleLoadImage={handleLoadImage}
                setSelectedVideo={setSelectedVideo}
                syncInputSourceToRenderer={syncInputSourceToRenderer}
                setSlotParams={setSlotParams}
            />
        </div>
    );
}

export default MainApp;
