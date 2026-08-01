import React, { useState } from 'react';
import { useShaderRatings } from '../../services/ShaderRatingIntegration';
import { LiveStreamPanel } from '../LiveStreamPanel';
import { RendererBackendPanel } from './panels/RendererBackendPanel';
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
import { useCoordinateNavigation } from './hooks/useCoordinateNavigation';
import { useShaderMenuOptions } from './hooks/useShaderMenuOptions';
import { useAiVjAutoTransition } from './hooks/useAiVjAutoTransition';
import type { ControlsProps } from './types';
import '../../styles/gold-glass-theme.css';

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
    maxActiveSlots = 3,
    performanceHud,
    generativeShowcaseActive = false,
    generativeShowcaseLocked = false,
    generativeShowcaseDelay = 12,
    onStartGenerativeShowcase,
    onStopGenerativeShowcase,
    onSetGenerativeShowcaseDelay,
    onPreviewImportShader,
    onImportStatus,
}) => {
    const autoTransition = useAiVjAutoTransition();
    const [studioOpen, setStudioOpen] = useState(true);

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

    const { shaders: ratedShaders, rateShader } = useShaderRatings();
    const { ratingMap, slotMenuOptions, generativeMenuOptions } = useShaderMenuOptions({
        availableModes,
        shaderCategory,
        coordMap,
        ratedShaders,
    });

    const currentMode = modes[activeSlot];
    const currentParams = slotParams[activeSlot];
    const currentShaderEntry = availableModes.find(m => m.id === currentMode);
    const currentCoordinate = getShaderCoordinate(currentMode);

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

            <InputSourcePanel
                inputSource={inputSource}
                setInputSource={setInputSource}
                setShaderCategory={setShaderCategory}
            />

            <VjStudioPanel
                studioOpen={studioOpen}
                setStudioOpen={setStudioOpen}
                modes={modes}
                slotParams={slotParams}
                activeSlot={activeSlot}
                setActiveSlot={setActiveSlot}
                liveControl={liveControl}
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
            />

            {onRenderQualityChange && performanceHud && (
                <RenderQualityPanel
                    qualityMode={renderQualityMode}
                    onQualityChange={onRenderQualityChange}
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
                />
            )}

            {onSwitchRenderer && activeRendererType && (
                <RendererBackendPanel
                    activeRendererType={activeRendererType}
                    onSwitchRenderer={onSwitchRenderer}
                />
            )}

            {inputSource === 'image' && (
                <ImageAutoSwitchPanel
                    onNewImage={onNewImage}
                    autoChangeEnabled={autoChangeEnabled}
                    setAutoChangeEnabled={setAutoChangeEnabled}
                    autoChangeDelay={autoChangeDelay}
                    setAutoChangeDelay={setAutoChangeDelay}
                    isAiVjMode={isAiVjMode}
                />
            )}

            <EffectCategoryPanel
                shaderCategory={shaderCategory}
                setShaderCategory={setShaderCategory}
            />

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

            <SlotStackPanel
                modes={modes}
                setMode={setMode}
                activeSlot={activeSlot}
                setActiveSlot={setActiveSlot}
                slotShaderStatus={slotShaderStatus}
                slotMenuOptions={slotMenuOptions}
                maxActiveSlots={maxActiveSlots}
            />

            <ParamSlidersPanel
                activeSlot={activeSlot}
                currentShaderEntry={currentShaderEntry}
                currentParams={currentParams}
                updateSlotParam={updateSlotParam}
            />

            {currentCoordinate !== null && (
                <CoordinateDisplayPanel
                    currentCoordinate={currentCoordinate}
                    currentShaderEntry={currentShaderEntry}
                    currentMode={currentMode}
                    getZoneColor={getZoneColor}
                    ratingStars={ratingMap.get(currentMode)?.stars || 0}
                    ratingCount={ratingMap.get(currentMode)?.ratingCount || 0}
                    onRate={async (id, stars) => { await rateShader(id, stars); }}
                />
            )}

            <RecordingSharePanel
                isRecording={isRecording}
                recordingCountdown={recordingCountdown}
                onStartRecording={onStartRecording}
                onStopRecording={onStopRecording}
                onTakeScreenshot={onTakeScreenshot}
            />

            {inputSource === 'image' && (
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
            )}

            {inputSource === 'video' && (
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
            )}

            {showWebcamShaderSuggestions && isWebcamActive && (
                <WebcamSuggestionsPanel
                    availableModes={availableModes}
                    webcamFunShaders={webcamFunShaders}
                    modes={modes}
                    onApplyWebcamShader={onApplyWebcamShader}
                />
            )}

            {inputSource === 'generative' && activeGenerativeShader && setActiveGenerativeShader && (
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
            )}

            {inputSource === 'live' && (
                <LiveStreamPanel
                    liveStreamUrl={liveStreamUrl}
                    onLiveStreamLoaded={onLiveStreamLoaded}
                    onExitLiveStream={onExitLiveStream}
                />
            )}

            <AdvancedDebugPanel
                onOpenShaderScanner={onOpenShaderScanner}
                activeRendererType={activeRendererType}
                onSwitchRenderer={onSwitchRenderer}
                onOpenCoordinateBrowser={() => setShowCoordinateBrowser(true)}
                onOpenStorageBrowser={onOpenStorageBrowser}
                onPreviewImportShader={onPreviewImportShader}
                onImportStatus={onImportStatus}
            />
        </div>
    );
};

export default ControlsContainer;
