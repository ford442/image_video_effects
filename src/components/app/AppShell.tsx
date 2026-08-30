import React, { RefObject, Suspense, lazy } from 'react';
import WebGPUCanvas from '../WebGPUCanvas';
import Controls from '../Controls';
import { RenderMode, ShaderEntry, ShaderCategory, InputSource, SlotParams } from '../../renderer/types';
import { RendererManager, RendererType } from '../../renderer/RendererManager';
import type { AIStatus, AutoTransitionConfig } from '../../types/aiVj';
import { VideoRecord } from '../../syncTypes';
import { VideoSegment } from '../../services/videoSegmentManager';
import { SharedChain } from '../../services/layerChainShare';
import { STORAGE_API_URL } from '../../config/appConfig';
import { RenderQualityMode } from '../../config/performancePolicy';

const LiveStudioTab = lazy(() => import(/* webpackChunkName: "live-studio" */ '../LiveStudioTab'));

export interface AppShellProps {
    activeTab: 'main' | 'live-studio';
    setActiveTab: (tab: 'main' | 'live-studio') => void;
    showSidebar: boolean;
    setShowSidebar: (show: boolean) => void;
    // Controls props
    modes: RenderMode[];
    setMode: (index: number, mode: RenderMode) => void;
    activeSlot: number;
    setActiveSlot: (index: number) => void;
    slotParams: SlotParams[];
    updateSlotParam: (slotIndex: number, updates: Partial<SlotParams>) => void;
    slotShaderStatus: Array<'idle' | 'loading' | 'error'>;
    shaderCategory: ShaderCategory;
    setShaderCategory: (category: ShaderCategory) => void;
    handleNewRandomImage: () => void;
    autoChangeEnabled: boolean;
    setAutoChangeEnabled: (enabled: boolean) => void;
    autoChangeDelay: number;
    setAutoChangeDelay: (delay: number) => void;
    loadDepthModel: () => void;
    isModelLoaded: boolean;
    availableModes: ShaderEntry[];
    inputSource: InputSource;
    syncInputSourceToRenderer: (source: InputSource) => void;
    videoList: VideoRecord[];
    selectedVideo: string;
    setSelectedVideo: (video: string) => void;
    videoB3hdMode: boolean;
    setVideoB3hdMode: (enabled: boolean) => void;
    b3hdSegmentLength: number;
    setB3hdSegmentLength: (len: number) => void;
    b3hdIntervalSeconds: number;
    setB3hdIntervalSeconds: (sec: number) => void;
    currentSegment: VideoSegment | null;
    isMuted: boolean;
    setIsMuted: (muted: boolean) => void;
    activeGenerativeShader: string;
    setActiveGenerativeShader: (id: string) => void;
    fileInputImageRef: RefObject<HTMLInputElement | null>;
    fileInputVideoRef: RefObject<HTMLInputElement | null>;
    isAiVjMode: boolean;
    toggleAiVj: () => void;
    aiVjStatus: AIStatus;
    aiVjMessage: string;
    handleGenerateFromVibe: (vibe: string) => void;
    handleUpdateStack: (ids: string[]) => void;
    handleUpdateParams: (paramsList: Record<string, number>[]) => void;
    handleRandomizeParams: () => void;
    handleSavePreset: (name: string) => void;
    handleTriggerNextTransition: () => void;
    handleRandomizeSlot: (slot: number) => void;
    handleSetSlotParam: (slot: number, param: string, value: number) => void;
    handleShareVjSet: () => void;
    handleSaveVjSet: (name: string) => void;
    startAutoTransition: (config: AutoTransitionConfig) => Promise<boolean>;
    stopAutoTransition: () => void;
    isWebcamActive: boolean;
    startWebcam: () => void;
    stopWebcam: () => void;
    webcamError: string | null;
    showWebcamShaderSuggestions: boolean;
    webcamFunShaders: string[];
    applyWebcamFunShader: (shaderId: string) => void;
    triggerRoulette: () => void;
    triggerRandomizeAllSlots: () => void;
    isRouletteActive: boolean;
    chaosModeEnabled: boolean;
    setChaosModeEnabled: (enabled: boolean) => void;
    audioReactiveParams: boolean;
    setAudioReactiveParams: (enabled: boolean) => void;
    audioReactiveAmount: number;
    setAudioReactiveAmount: (amount: number) => void;
    isRecording: boolean;
    recordingCountdown: number;
    startRecording: () => void;
    stopRecording: () => void;
    handleTakeScreenshot: () => void;
    setShowShaderScanner: (show: boolean) => void;
    activeRendererType: RendererType;
    handleSwitchRenderer: (type: RendererType) => Promise<void>;
    setShowStorageBrowser: (show: boolean) => void;
    copyChainShareLink: () => void;
    applySharedChain: (chain: SharedChain) => void;
    getCurrentChain: () => SharedChain | null;
    // Canvas props
    rendererRef: RefObject<RendererManager | null>;
    mousePosition: { x: number; y: number };
    setMousePosition: React.Dispatch<React.SetStateAction<{ x: number; y: number }>>;
    isMouseDown: boolean;
    setIsMouseDown: (down: boolean) => void;
    onInitCanvas: () => void;
    videoSourceUrl: string | undefined;
    webgpuCanvasRef: RefObject<HTMLCanvasElement | null>;
    videoElementRef: RefObject<HTMLVideoElement | null>;
    // Status bar
    status: string;
    generativeShowcaseActive: boolean;
    generativeShowcaseLocked: boolean;
    generativeShowcaseDelay: number;
    onStartGenerativeShowcase: () => void;
    onStopGenerativeShowcase: () => void;
    onSetGenerativeShowcaseDelay: (seconds: number) => void;
    onPreviewImportShader: (id: string, wgsl: string, name: string) => void;
    onImportStatus: (message: string) => void;
    isRendererSwitching: boolean;
    jsFps: number;
    wasmFps: number;
    renderQualityMode: RenderQualityMode;
    onRenderQualityChange: (mode: RenderQualityMode) => void;
    sourceAutoExposure: boolean;
    onSourceAutoExposureChange: (enabled: boolean) => void;
    performanceHud: {
        internalWidth: number;
        internalHeight: number;
        scale: number;
        targetFps: number;
        adaptive: boolean;
        maxActiveSlots: number;
        colorFormat?: import('../../config/formatPolicy').InternalColorFormat;
        estimatedTextureMiB?: number;
        requestedColorFormat?: import('../../config/formatPolicy').InternalColorFormat;
        fp32Pinned?: boolean;
        fp32PinnedBy?: string[];
        maxPassesPerFrame?: number;
    };
    rendererDiagnostics?: import('../controls/panels/AdvancedDebugPanel').RendererDiagnosticsSummary | null;
}

export function AppShell(props: AppShellProps) {
    const {
        activeTab,
        setActiveTab,
        showSidebar,
        setShowSidebar,
        modes,
        setMode,
        activeSlot,
        setActiveSlot,
        slotParams,
        updateSlotParam,
        slotShaderStatus,
        shaderCategory,
        setShaderCategory,
        handleNewRandomImage,
        autoChangeEnabled,
        setAutoChangeEnabled,
        autoChangeDelay,
        setAutoChangeDelay,
        loadDepthModel,
        isModelLoaded,
        availableModes,
        inputSource,
        syncInputSourceToRenderer,
        videoList,
        selectedVideo,
        setSelectedVideo,
        videoB3hdMode,
        setVideoB3hdMode,
        b3hdSegmentLength,
        setB3hdSegmentLength,
        b3hdIntervalSeconds,
        setB3hdIntervalSeconds,
        currentSegment,
        isMuted,
        setIsMuted,
        activeGenerativeShader,
        setActiveGenerativeShader,
        fileInputImageRef,
        fileInputVideoRef,
        isAiVjMode,
        toggleAiVj,
        aiVjStatus,
        aiVjMessage,
        handleGenerateFromVibe,
        handleUpdateStack,
        handleUpdateParams,
        handleRandomizeParams,
        handleSavePreset,
        handleTriggerNextTransition,
        handleRandomizeSlot,
        handleSetSlotParam,
        handleShareVjSet,
        handleSaveVjSet,
        startAutoTransition,
        stopAutoTransition,
        isWebcamActive,
        startWebcam,
        stopWebcam,
        webcamError,
        showWebcamShaderSuggestions,
        webcamFunShaders,
        applyWebcamFunShader,
        triggerRoulette,
        triggerRandomizeAllSlots,
        isRouletteActive,
        chaosModeEnabled,
        setChaosModeEnabled,
        audioReactiveParams,
        setAudioReactiveParams,
        audioReactiveAmount,
        setAudioReactiveAmount,
        isRecording,
        recordingCountdown,
        startRecording,
        stopRecording,
        handleTakeScreenshot,
        setShowShaderScanner,
        activeRendererType,
        handleSwitchRenderer,
        setShowStorageBrowser,
        copyChainShareLink,
        applySharedChain,
        getCurrentChain,
        rendererRef,
        mousePosition,
        setMousePosition,
        isMouseDown,
        setIsMouseDown,
        onInitCanvas,
        videoSourceUrl,
        webgpuCanvasRef,
        videoElementRef,
        status,
        generativeShowcaseActive,
        generativeShowcaseLocked,
        generativeShowcaseDelay,
        onStartGenerativeShowcase,
        onStopGenerativeShowcase,
        onSetGenerativeShowcaseDelay,
        onPreviewImportShader,
        onImportStatus,
        isRendererSwitching,
        jsFps,
        wasmFps,
        renderQualityMode,
        onRenderQualityChange,
        sourceAutoExposure,
        onSourceAutoExposureChange,
        performanceHud,
        rendererDiagnostics,
    } = props;

    return (
        <>
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
                    {activeTab === 'main' && (
                        <>
                            <button
                                className="toggle-sidebar-btn header-action-btn"
                                onClick={() => handleNewRandomImage()}
                                title="Load a random image from the manifest"
                                disabled={inputSource !== 'image'}
                            >
                                🎲 Random Image
                            </button>
                            <button
                                className={`toggle-sidebar-btn header-action-btn ${isRouletteActive ? 'spinning' : ''}`}
                                onClick={() => triggerRoulette()}
                                title={`Randomize slot ${activeSlot + 1} shader + sliders (R)`}
                            >
                                🎰 Randomize Slot {activeSlot + 1}
                            </button>
                            <div style={{ width: '1px', height: '24px', background: 'rgba(255,255,255,0.2)', margin: '0 4px' }} />
                        </>
                    )}
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
                <Suspense fallback={<div className="main-container" style={{ padding: '2rem', color: '#aaa' }}>Loading Live Studio…</div>}>
                    <LiveStudioTab />
                </Suspense>
            ) : (
            <div className="main-container">
                <aside className={`sidebar ${!showSidebar ? 'hidden' : ''}`}>
                    <Controls
                        modes={modes} setMode={setMode} activeSlot={activeSlot} setActiveSlot={setActiveSlot}
                        slotParams={slotParams} updateSlotParam={updateSlotParam} slotShaderStatus={slotShaderStatus} shaderCategory={shaderCategory as import('../../renderer/types').ShaderCategory}
                        setShaderCategory={setShaderCategory as (category: import('../../renderer/types').ShaderCategory) => void} onNewImage={handleNewRandomImage}
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
                        webcamFunShaders={webcamFunShaders}
                        onApplyWebcamShader={applyWebcamFunShader}
                        onRoulette={triggerRoulette}
                        onRandomizeAllSlots={triggerRandomizeAllSlots}
                        isRouletteActive={isRouletteActive}
                        chaosModeEnabled={chaosModeEnabled}
                        setChaosModeEnabled={setChaosModeEnabled}
                        audioReactiveParams={audioReactiveParams}
                        setAudioReactiveParams={setAudioReactiveParams}
                        audioReactiveAmount={audioReactiveAmount}
                        setAudioReactiveAmount={setAudioReactiveAmount}
                        isRecording={isRecording}
                        recordingCountdown={recordingCountdown}
                        onStartRecording={startRecording}
                        onStopRecording={stopRecording}
                        onTakeScreenshot={handleTakeScreenshot}
                        onOpenShaderScanner={() => setShowShaderScanner(true)}
                        activeRendererType={activeRendererType}
                        onSwitchRenderer={handleSwitchRenderer}
                        onOpenStorageBrowser={() => setShowStorageBrowser(true)}
                        onCopyChainShareLink={copyChainShareLink}
                        onApplySharedChain={applySharedChain}
                        getCurrentChain={getCurrentChain}
                        renderQualityMode={renderQualityMode}
                        onRenderQualityChange={onRenderQualityChange}
                        sourceAutoExposure={sourceAutoExposure}
                        onSourceAutoExposureChange={onSourceAutoExposureChange}
                        performanceHud={performanceHud}
                        rendererDiagnostics={rendererDiagnostics}
                        maxActiveSlots={performanceHud.maxActiveSlots}
                        generativeShowcaseActive={generativeShowcaseActive}
                        generativeShowcaseLocked={generativeShowcaseLocked}
                        generativeShowcaseDelay={generativeShowcaseDelay}
                        onStartGenerativeShowcase={onStartGenerativeShowcase}
                        onStopGenerativeShowcase={onStopGenerativeShowcase}
                        onSetGenerativeShowcaseDelay={onSetGenerativeShowcaseDelay}
                        onPreviewImportShader={onPreviewImportShader}
                        onImportStatus={onImportStatus}
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
                                🎨 Attract {generativeShowcaseLocked ? '🔒 LOCKED' : '● AUTO'}
                            </span>
                        )}
                        {audioReactiveParams && (
                            <span style={{ color: '#FFD700', marginLeft: '12px' }}>
                                🔊 Audio-Reactive {Math.round(audioReactiveAmount * 100)}%
                            </span>
                        )}

                        <span
                            className={`renderer-badge renderer-badge--${activeRendererType}`}
                            title={[
                                activeRendererType === 'wasm'
                                    ? 'Experimental C++ WASM — click to cycle renderer'
                                    : 'Click to cycle renderer (WebGPU ↔ WASM ↔ Canvas2D)',
                                jsFps > 0 ? `JS ${jsFps} FPS` : null,
                                wasmFps > 0 ? `WASM ${wasmFps} FPS` : null,
                                isRendererSwitching ? 'Switching…' : null,
                            ].filter(Boolean).join(' · ')}
                            onClick={() => {
                                if (isRendererSwitching) return;
                                const cycle: Record<RendererType, RendererType> = {
                                    webgpu: 'wasm',
                                    wasm: 'js',
                                    js: 'webgpu',
                                };
                                handleSwitchRenderer(cycle[activeRendererType]);
                            }}
                            style={isRendererSwitching ? { opacity: 0.6, cursor: 'wait' } : undefined}
                        >
                            {activeRendererType === 'wasm'
                                ? '⚡ WASM (exp.)'
                                : activeRendererType === 'js'
                                  ? '🎨 Canvas2D'
                                  : '🔷 WebGPU'}
                        </span>
                    </div>
                </main>
            </div>
            )}
            <input type="file" ref={fileInputImageRef} accept="image/*" style={{display:'none'}} onChange={() => {}} />
            <input type="file" ref={fileInputVideoRef} accept="video/*" style={{display:'none'}} onChange={() => {}} />
        </>
    );
}
