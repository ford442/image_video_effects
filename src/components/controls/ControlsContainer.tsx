import React, { useState } from 'react';
import { useShaderRatings } from '../../services/ShaderRatingIntegration';
import { LiveStreamPanel } from '../LiveStreamPanel';
import { ParamSlidersPanel } from './panels/ParamSlidersPanel';
import { SlotStackPanel } from './panels/SlotStackPanel';
import { InputSourcePanel } from './panels/InputSourcePanel';
import { RecordingSharePanel } from './panels/RecordingSharePanel';
import { VjStudioPanel } from './panels/VjStudioPanel';
import { RoulettePanel } from './panels/RoulettePanel';
import { CoordinateBrowserOverlay } from './panels/CoordinateBrowserOverlay';
import { AdvancedDebugPanel } from './panels/AdvancedDebugPanel';
import { RenderQualityPanel } from './panels/RenderQualityPanel';
import { EffectCategoryPanel } from './panels/EffectCategoryPanel';
import { ImageAutoSwitchPanel } from './panels/ImageAutoSwitchPanel';
import { CoordinateDisplayPanel } from './panels/CoordinateDisplayPanel';
import { AiVjStudioPanel } from './panels/AiVjStudioPanel';
import { VideoSourcePanel } from './panels/VideoSourcePanel';
import { WebcamSuggestionsPanel } from './panels/WebcamSuggestionsPanel';
import { GenerativeSourcePanel } from './panels/GenerativeSourcePanel';
import { useLiveControl } from './hooks/useLiveControl';
import { useOscControl } from './hooks/useOscControl';
import { useSetRecorder } from '../../hooks/useSetRecorder';
import { useProjectFile } from '../../hooks/useProjectFile';
import { useCoordinateNavigation } from './hooks/useCoordinateNavigation';
import { useShaderMenuOptions } from './hooks/useShaderMenuOptions';
import { useAiVjAutoTransition } from './hooks/useAiVjAutoTransition';
import { SidebarGroup } from './SidebarGroup';
import { SidebarSearch } from './SidebarSearch';
import { findEffects, matchesQuery } from './sidebarFilter';
import { usePersistedToggle } from '../../hooks/usePersistedToggle';
import type { RenderMode } from '../../renderer/types';
import type { ControlsProps } from './types';
import { defaultSlotParams } from '../../app/constants/defaultSlotParams';
import '../../styles/gold-glass-theme.css';

const SIDEBAR_GROUPS = [
    { id: 'source', title: 'Source & Media', icon: '📷' },
    { id: 'effects', title: 'Effects & Slots', icon: '✨' },
    { id: 'output', title: 'Output', icon: '🎞️' },
    { id: 'studio', title: 'Studio, MIDI & Tools', icon: '🎛️' },
] as const;

interface SidebarSection {
    id: string;
    group: typeof SIDEBAR_GROUPS[number]['id'];
    title: string;
    keywords: string;
    node: React.ReactNode;
}

export const ControlsContainer: React.FC<ControlsProps> = ({
    modes, setMode,
    activeSlot, setActiveSlot,
    slotParams, updateSlotParam,
    slotShaderStatus = ['idle', 'idle', 'idle', 'idle', 'idle', 'idle'],
    shaderCategory, setShaderCategory,
    onNewImage,
    autoChangeEnabled, setAutoChangeEnabled,
    autoChangeDelay, setAutoChangeDelay,
    onLoadModel, isModelLoaded,
    availableModes = [],
    imageManifest = [],
    currentImageUrl,
    onLoadProjectImage = async () => {},
    inputSource, setInputSource,
    videoList, selectedVideo, setSelectedVideo,
    videoB3hdMode, setVideoB3hdMode,
    b3hdSegmentLength, setB3hdSegmentLength,
    b3hdIntervalSeconds, setB3hdIntervalSeconds,
    currentSegment,
    isMuted, setIsMuted,
    onUploadImageTrigger,
    onUploadVideoTrigger,
    activeGenerativeShader, setActiveGenerativeShader,
    isAiVjMode,
    onToggleAiVj,
    aiVjStatus,
    aiVjMessage,
    onGenerateFromVibe,
    onUpdateStack,
    onUpdateParams,
    onRandomizeParams,
    onSavePreset,
    onShareVjSet,
    onSaveVjSet,
    onStartAutoTransition,
    onStopAutoTransition,
    isWebcamActive = false,
    onStartWebcam,
    onStopWebcam,
    webcamError,
    showWebcamShaderSuggestions = false,
    webcamFunShaders = [],
    onApplyWebcamShader,
    onRoulette,
    onRandomizeAllSlots,
    isRouletteActive = false,
    chaosModeEnabled = false,
    setChaosModeEnabled,
    audioReactiveParams = false,
    setAudioReactiveParams,
    audioReactiveAmount = 0.8,
    setAudioReactiveAmount,
    isRecording = false,
    recordingCountdown = 8,
    onStartRecording,
    onStopRecording,
    gpuEncode,
    gpuEncodeAvailable,
    onGpuEncodeChange,
    onTakeScreenshot,
    liveStreamUrl,
    onLiveStreamLoaded,
    onExitLiveStream,
    onOpenShaderScanner,
    activeRendererType = 'webgpu',
    onSwitchRenderer,
    onOpenStorageBrowser,
    onCopyChainShareLink,
    onApplySharedChain,
    getCurrentChain,
    onTriggerNextTransition,
    onRandomizeSlot,
    onSetSlotParam,
    renderQualityMode = 'auto',
    onRenderQualityChange,
    sourceAutoExposure = false,
    onSourceAutoExposureChange,
    maxActiveSlots = 3,
    performanceHud,
    rendererDiagnostics,
    generativeShowcaseActive = false,
    generativeShowcaseLocked = false,
    generativeShowcaseDelay = 12,
    onStartGenerativeShowcase,
    onStopGenerativeShowcase,
    onSetGenerativeShowcaseDelay,
    onPreviewImportShader,
    onImportStatus,
    compositing,
    hdrToneMap,
    canvasColor,
}) => {
    const autoTransition = useAiVjAutoTransition();
    const [studioOpen, setStudioOpen] = usePersistedToggle('vj.studio', true);
    const [filterQuery, setFilterQuery] = useState('');

    const {
        coordMap,
        getShaderCoordinate,
        findShaderByCoordinate,
        getZoneColor,
        shadersByZone,
        showCoordinateBrowser,
        setShowCoordinateBrowser,
        showNumberOverlay,
        typedNumber,
    } = useCoordinateNavigation({ availableModes, activeSlot, setMode });

    const liveControl = useLiveControl({
        isAiVjMode,
        autoTransitionEnabled: autoTransition.autoTransitionEnabled,
        setAutoTransitionEnabled: autoTransition.setAutoTransitionEnabled,
        onSetSlotParam,
        onRandomizeSlot,
        onRandomizeAllSlots,
        onTriggerNextTransition,
        onStartAutoTransition,
        onStopAutoTransition,
        autoTransitionSource: autoTransition.autoTransitionSource,
        autoTransitionIntervalMs: autoTransition.autoTransitionIntervalMs,
        autoTransitionDurationMs: autoTransition.autoTransitionDurationMs,
        autoTransitionMode: autoTransition.autoTransitionMode,
    });

    const osc = useOscControl({
        modes,
        availableModes,
        setMode,
        onSetSlotParam,
        onTriggerNextTransition,
        setAudioReactiveAmount,
    });

    const recorder = useSetRecorder({ modes, slotParams, setMode, onSetSlotParam });
    const projectFile = useProjectFile({
        modes,
        slotParams,
        slotModes: compositing?.slotModes,
        slotLayers: compositing?.slotLayers,
        hdrToneMap: hdrToneMap?.settings,
        setHdrToneMap: hdrToneMap?.setSettings,
        activeSlot,
        inputSource,
        currentImageUrl,
        imageManifest,
        selectedVideo,
        videoList,
        liveStreamUrl,
        activeGenerativeShader,
        renderQualityMode,
        bindings: liveControl.bindings,
        timeline: recorder.timeline,
        recorderState: recorder.recorderState,
        availableModes,
        applySharedChain: onApplySharedChain ?? (() => {}),
        setActiveSlot,
        setInputSource,
        setSelectedVideo,
        setActiveGenerativeShader,
        startWebcam: onStartWebcam,
        loadImage: onLoadProjectImage,
        loadStream: onLiveStreamLoaded,
        setRenderQuality: onRenderQualityChange,
        setBindings: liveControl.setBindings,
        setTimeline: recorder.setTimeline,
    });

    const { shaders: ratedShaders, rateShader } = useShaderRatings();
    const { ratingMap, slotMenuOptions, generativeMenuOptions } = useShaderMenuOptions({
        availableModes,
        shaderCategory,
        coordMap,
        ratedShaders,
    });

    const currentMode = modes[activeSlot] ?? 'none';
    const currentParams = slotParams[activeSlot] ?? defaultSlotParams;
    const currentShaderEntry = availableModes.find(m => m.id === currentMode);
    const currentCoordinate = getShaderCoordinate(currentMode);

    const paramNames = currentShaderEntry?.params?.map(p => p.name).join(' ') ?? '';
    const slotNames = modes.join(' ');

    // Every sidebar panel, tagged with its top-level group and the words the filter box matches.
    const allSections: SidebarSection[] = [
        {
            id: 'input-source', group: 'source', title: 'Input Source',
            keywords: 'input source image video webcam camera generative live stream',
            node: (
                <InputSourcePanel
                    inputSource={inputSource}
                    setInputSource={setInputSource}
                    setShaderCategory={setShaderCategory}
                />
            ),
        },
        {
            id: 'image-auto', group: 'source', title: 'Image Auto-Switch',
            keywords: 'image auto switch random new image delay',
            node: (inputSource === 'image') ? (
                <ImageAutoSwitchPanel
                    onNewImage={onNewImage}
                    autoChangeEnabled={autoChangeEnabled}
                    setAutoChangeEnabled={setAutoChangeEnabled}
                    autoChangeDelay={autoChangeDelay}
                    setAutoChangeDelay={setAutoChangeDelay}
                    isAiVjMode={isAiVjMode}
                />
            ) : null,
        },
        {
            id: 'video-source', group: 'source', title: 'Video',
            keywords: 'video select b3hd segment mute upload',
            node: (inputSource === 'video') ? (
                <VideoSourcePanel
                    selectedVideo={selectedVideo}
                    setSelectedVideo={setSelectedVideo}
                    setInputSource={setInputSource}
                    videoList={videoList}
                    videoB3hdMode={videoB3hdMode}
                    setVideoB3hdMode={setVideoB3hdMode}
                    b3hdSegmentLength={b3hdSegmentLength}
                    setB3hdSegmentLength={setB3hdSegmentLength}
                    b3hdIntervalSeconds={b3hdIntervalSeconds}
                    setB3hdIntervalSeconds={setB3hdIntervalSeconds}
                    currentSegment={currentSegment}
                    onUploadVideoTrigger={onUploadVideoTrigger}
                    isMuted={isMuted}
                    setIsMuted={setIsMuted}
                />
            ) : null,
        },
        {
            id: 'webcam-suggestions', group: 'source', title: 'Webcam Suggestions',
            keywords: 'webcam camera suggestions fun shaders',
            node: (showWebcamShaderSuggestions && isWebcamActive) ? (
                <WebcamSuggestionsPanel
                    availableModes={availableModes}
                    webcamFunShaders={webcamFunShaders}
                    modes={modes}
                    onApplyWebcamShader={onApplyWebcamShader}
                />
            ) : null,
        },
        {
            id: 'generative-source', group: 'source', title: 'Generative Shader',
            keywords: 'generative procedural shader showcase',
            node: (inputSource === 'generative' && activeGenerativeShader && setActiveGenerativeShader) ? (
                <GenerativeSourcePanel
                    activeGenerativeShader={activeGenerativeShader}
                    setActiveGenerativeShader={setActiveGenerativeShader}
                    generativeMenuOptions={generativeMenuOptions}
                    generativeShowcaseActive={generativeShowcaseActive}
                    generativeShowcaseLocked={generativeShowcaseLocked}
                    generativeShowcaseDelay={generativeShowcaseDelay}
                    onStartGenerativeShowcase={onStartGenerativeShowcase}
                    onStopGenerativeShowcase={onStopGenerativeShowcase}
                    onSetGenerativeShowcaseDelay={onSetGenerativeShowcaseDelay}
                />
            ) : null,
        },
        {
            id: 'live-stream', group: 'source', title: 'Live Stream',
            keywords: 'live stream hls url',
            node: (inputSource === 'live') ? (
                <LiveStreamPanel
                    liveStreamUrl={liveStreamUrl}
                    onLiveStreamLoaded={onLiveStreamLoaded}
                    onExitLiveStream={onExitLiveStream}
                />
            ) : null,
        },
        {
            id: 'effect-filter', group: 'effects', title: 'Effect Filter',
            keywords: 'effect filter category type',
            node: (
                <EffectCategoryPanel
                    shaderCategory={shaderCategory}
                    setShaderCategory={setShaderCategory}
                />
            ),
        },
        {
            id: 'roulette', group: 'effects', title: 'Roulette',
            keywords: 'roulette randomize random chaos audio reactive',
            node: (
                <RoulettePanel
                    activeSlot={activeSlot}
                    onRoulette={onRoulette}
                    onRandomizeAllSlots={onRandomizeAllSlots}
                    isRouletteActive={isRouletteActive}
                    chaosModeEnabled={chaosModeEnabled}
                    setChaosModeEnabled={setChaosModeEnabled}
                    audioReactiveParams={audioReactiveParams}
                    setAudioReactiveParams={setAudioReactiveParams}
                    audioReactiveAmount={audioReactiveAmount}
                    setAudioReactiveAmount={setAudioReactiveAmount}
                />
            ),
        },
        {
            id: 'slots', group: 'effects', title: 'Shader Slots',
            keywords: `shader slots stack chain effects ${slotNames}`,
            node: (
                <SlotStackPanel
                    modes={modes}
                    setMode={setMode}
                    activeSlot={activeSlot}
                    setActiveSlot={setActiveSlot}
                    slotShaderStatus={slotShaderStatus}
                    slotMenuOptions={slotMenuOptions}
                    maxActiveSlots={maxActiveSlots}
                    slotModes={compositing?.slotModes}
                    slotLayers={compositing?.slotLayers}
                    setSlotMode={compositing?.setSlotMode}
                    setSlotLayer={compositing?.setSlotLayer}
                    compositorAvailable={activeRendererType === 'webgpu'}
                />
            ),
        },
        {
            id: 'params', group: 'effects', title: 'Shader Parameters',
            keywords: `shader parameters sliders ${currentShaderEntry?.name ?? ''} ${paramNames}`,
            node: (
                <ParamSlidersPanel
                    activeSlot={activeSlot}
                    currentShaderEntry={currentShaderEntry}
                    currentParams={currentParams}
                    updateSlotParam={updateSlotParam}
                    onStartMidiLearn={(slot, param) => liveControl.startLearnForParam(slot, param)}
                    learnActiveParam={
                        liveControl.learnTarget === 'param' ? liveControl.pendingParam : null
                    }
                />
            ),
        },
        {
            id: 'coordinate', group: 'effects', title: 'Shader Info',
            keywords: 'coordinate rating stars info',
            node: (currentCoordinate !== null) ? (
                <CoordinateDisplayPanel
                    currentCoordinate={currentCoordinate}
                    currentShaderEntry={currentShaderEntry}
                    currentMode={currentMode}
                    getZoneColor={getZoneColor}
                    ratingStars={ratingMap.get(currentMode)?.stars || 0}
                    ratingCount={ratingMap.get(currentMode)?.ratingCount || 0}
                    onRate={async (id, stars) => { await rateShader(id, stars); }}
                />
            ) : null,
        },
        {
            id: 'render-quality', group: 'output', title: 'Render Quality',
            keywords: 'render quality resolution fps performance hdr exposure adaptive',
            node: (onRenderQualityChange && performanceHud) ? (
                <RenderQualityPanel
                    qualityMode={renderQualityMode}
                    onQualityChange={onRenderQualityChange}
                    sourceAutoExposure={sourceAutoExposure}
                    onSourceAutoExposureChange={onSourceAutoExposureChange}
                    sourceAutoExposureDisabled={
                        activeRendererType !== 'webgpu' || rendererDiagnostics?.gpuComputeAvailable === false
                    }
                    displayP3={canvasColor?.displayP3}
                    onDisplayP3Change={canvasColor?.setDisplayP3}
                    displayP3Disabled={activeRendererType !== 'webgpu'}
                    displayP3Status={canvasColor?.status}
                    hdrActive={canvasColor?.hdrActive}
                    hdrToneMap={hdrToneMap?.settings}
                    onHdrToneMapChange={hdrToneMap?.setSettings}
                    maxActiveSlots={maxActiveSlots}
                    internalResolution={performanceHud.internalWidth}
                    scale={performanceHud.scale}
                    adaptive={performanceHud.adaptive}
                    targetFps={performanceHud.targetFps}
                    colorFormat={performanceHud.colorFormat}
                    estimatedTextureMiB={performanceHud.estimatedTextureMiB}
                    requestedColorFormat={performanceHud.requestedColorFormat}
                    fp32Pinned={performanceHud.fp32Pinned}
                    fp32PinnedBy={performanceHud.fp32PinnedBy}
                    maxPassesPerFrame={performanceHud.maxPassesPerFrame}
                    historyLayers={performanceHud.historyLayers}
                    workingSizeCap={performanceHud.workingSizeCap}
                />
            ) : null,
        },
        {
            id: 'recording', group: 'output', title: 'Recording & Share',
            keywords: 'recording record screenshot share webm gpu encode capture',
            node: (
                <RecordingSharePanel
                    isRecording={isRecording}
                    recordingCountdown={recordingCountdown}
                    onStartRecording={onStartRecording}
                    onStopRecording={onStopRecording}
                    gpuEncode={gpuEncode}
                    gpuEncodeAvailable={gpuEncodeAvailable}
                    onGpuEncodeChange={onGpuEncodeChange}
                    onTakeScreenshot={onTakeScreenshot}
                />
            ),
        },
        {
            id: 'vj-studio', group: 'studio', title: 'VJ Studio',
            keywords: 'vj studio midi osc auto transition share sets history project save load timeline',
            node: (
                <VjStudioPanel
                    studioOpen={studioOpen}
                    setStudioOpen={setStudioOpen}
                    modes={modes}
                    slotParams={slotParams}
                    activeSlot={activeSlot}
                    setActiveSlot={setActiveSlot}
                    liveControl={liveControl}
                    osc={osc}
                    recorder={recorder}
                    isAiVjMode={isAiVjMode}
                    autoTransitionOpen={autoTransition.autoTransitionOpen}
                    setAutoTransitionOpen={autoTransition.setAutoTransitionOpen}
                    autoTransitionEnabled={autoTransition.autoTransitionEnabled}
                    setAutoTransitionEnabled={autoTransition.setAutoTransitionEnabled}
                    autoTransitionSource={autoTransition.autoTransitionSource}
                    setAutoTransitionSource={autoTransition.setAutoTransitionSource}
                    autoTransitionIntervalMs={autoTransition.autoTransitionIntervalMs}
                    setAutoTransitionIntervalMs={autoTransition.setAutoTransitionIntervalMs}
                    autoTransitionDurationMs={autoTransition.autoTransitionDurationMs}
                    setAutoTransitionDurationMs={autoTransition.setAutoTransitionDurationMs}
                    autoTransitionMode={autoTransition.autoTransitionMode}
                    setAutoTransitionMode={autoTransition.setAutoTransitionMode}
                    audioReactiveParams={audioReactiveParams}
                    setAudioReactiveParams={setAudioReactiveParams}
                    audioReactiveAmount={audioReactiveAmount}
                    setAudioReactiveAmount={setAudioReactiveAmount}
                    onCopyChainShareLink={onCopyChainShareLink}
                    onShareVjSet={onShareVjSet}
                    onSaveVjSet={onSaveVjSet}
                    onApplySharedChain={onApplySharedChain}
                    getCurrentChain={getCurrentChain}
                    onUpdateStack={onUpdateStack}
                    onUpdateParams={onUpdateParams}
                    onGenerateFromVibe={onGenerateFromVibe}
                    projectFile={projectFile}
                />
            ),
        },
        {
            id: 'ai-vj', group: 'studio', title: 'AI VJ',
            keywords: 'ai vj studio vibe webcam model depth preset',
            node: (inputSource === 'image') ? (
                <AiVjStudioPanel
                    modes={modes}
                    slotParams={slotParams}
                    isWebcamActive={isWebcamActive}
                    onStartWebcam={onStartWebcam}
                    onStopWebcam={onStopWebcam}
                    webcamError={webcamError}
                    onUploadImageTrigger={onUploadImageTrigger}
                    onLoadModel={onLoadModel}
                    isModelLoaded={isModelLoaded}
                    isAiVjMode={isAiVjMode}
                    onToggleAiVj={onToggleAiVj}
                    aiVjStatus={aiVjStatus}
                    aiVjMessage={aiVjMessage}
                    onGenerateFromVibe={onGenerateFromVibe}
                    onUpdateStack={onUpdateStack}
                    onUpdateParams={onUpdateParams}
                    onRandomizeParams={onRandomizeParams}
                    onSavePreset={onSavePreset}
                    onShareVjSet={onShareVjSet}
                    onSaveVjSet={onSaveVjSet}
                    onApplySharedChain={onApplySharedChain}
                    getCurrentChain={getCurrentChain}
                    onCopyChainShareLink={onCopyChainShareLink}
                    {...autoTransition}
                />
            ) : null,
        },
        {
            id: 'advanced', group: 'studio', title: 'Advanced & Dev Tools',
            keywords: 'advanced dev tools debug renderer shader scanner storage browser import shadertoy diagnostics',
            node: (
                <AdvancedDebugPanel
                    onOpenShaderScanner={onOpenShaderScanner}
                    activeRendererType={activeRendererType}
                    onSwitchRenderer={onSwitchRenderer}
                    onOpenCoordinateBrowser={() => setShowCoordinateBrowser(true)}
                    onOpenStorageBrowser={onOpenStorageBrowser}
                    onPreviewImportShader={onPreviewImportShader}
                    onImportStatus={onImportStatus}
                    diagnostics={rendererDiagnostics}
                />
            ),
        },
    ];
    const sections = allSections.filter(sec => sec.node);

    const filtering = filterQuery.trim().length > 0;
    const visibleSections = filtering
        ? sections.filter(sec => matchesQuery(filterQuery, `${sec.title} ${sec.keywords} ${SIDEBAR_GROUPS.find(g => g.id === sec.group)?.title ?? ''}`))
        : sections;
    const effectResults = filtering ? findEffects(availableModes, filterQuery) : [];

    return (
        <div className="controls gold-scroll">
            <CoordinateBrowserOverlay
                showNumberOverlay={showNumberOverlay}
                typedNumber={typedNumber}
                findShaderByCoordinate={findShaderByCoordinate}
                coordMap={coordMap}
                showCoordinateBrowser={showCoordinateBrowser}
                setShowCoordinateBrowser={setShowCoordinateBrowser}
                shadersByZone={shadersByZone}
                availableModes={availableModes}
                currentMode={currentMode}
                activeSlot={activeSlot}
                setMode={setMode}
            />

            <SidebarSearch
                query={filterQuery}
                setQuery={setFilterQuery}
                effectResults={effectResults}
                activeSlot={activeSlot}
                onPickEffect={(id) => setMode(activeSlot, id as RenderMode)}
            />

            {SIDEBAR_GROUPS.map(group => {
                const groupSections = visibleSections.filter(sec => sec.group === group.id);
                if (groupSections.length === 0) return null;
                return (
                    <SidebarGroup key={group.id} id={group.id} title={group.title} icon={group.icon} forceOpen={filtering}>
                        {groupSections.map(sec => <React.Fragment key={sec.id}>{sec.node}</React.Fragment>)}
                    </SidebarGroup>
                );
            })}

            {filtering && visibleSections.length === 0 && effectResults.length === 0 && (
                <div className="sidebar-search-empty">No controls or effects match “{filterQuery.trim()}”.</div>
            )}
        </div>
    );
};

export default ControlsContainer;
