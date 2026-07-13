import React, { useState, useMemo } from 'react';
import type { ShaderMegaMenuOption } from '../ShaderMegaMenu';
import { useShaderRatings } from '../../services/ShaderRatingIntegration';
import { LiveStreamPanel } from '../LiveStreamPanel';
import { RendererBackendPanel } from './panels/RendererBackendPanel';
import { ParamSlidersPanel } from './panels/ParamSlidersPanel';
import { SlotStackPanel } from './panels/SlotStackPanel';
import { InputSourcePanel } from './panels/InputSourcePanel';
import { RecordingSharePanel } from './panels/RecordingSharePanel';
import { LiveControlPanel } from './panels/LiveControlPanel';
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
    onTriggerNextTransition,
    onRandomizeSlot,
    onSetSlotParam,
    renderQualityMode = 'auto',
    onRenderQualityChange,
    maxActiveSlots = 3,
    performanceHud,
}) => {
    const [devToolsOpen, setDevToolsOpen] = useState(false);
    const [autoTransitionOpen, setAutoTransitionOpen] = useState(false);
    const [autoTransitionEnabled, setAutoTransitionEnabled] = useState(false);
    const [autoTransitionSource, setAutoTransitionSource] = useState<'timer' | 'beat'>('timer');
    const [autoTransitionIntervalMs, setAutoTransitionIntervalMs] = useState(8000);
    const [autoTransitionDurationMs, setAutoTransitionDurationMs] = useState(2000);
    const [autoTransitionMode, setAutoTransitionMode] = useState<'randomize' | 'cyclePresets'>('randomize');

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
        autoTransitionEnabled,
        setAutoTransitionEnabled,
        onSetSlotParam,
        onRandomizeSlot,
        onRandomizeAllSlots,
        onTriggerNextTransition,
        onStartAutoTransition,
        onStopAutoTransition,
        autoTransitionSource,
        autoTransitionIntervalMs,
        autoTransitionDurationMs,
        autoTransitionMode,
    });

    const { shaders: ratedShaders, rateShader } = useShaderRatings();
    const ratingMap = useMemo(() => {
        const map = new Map<string, { stars: number; ratingCount: number }>();
        for (const s of ratedShaders) {
            map.set(s.id, { stars: s.stars, ratingCount: s.ratingCount });
        }
        return map;
    }, [ratedShaders]);

    const currentModes = useMemo(() => {
        if (shaderCategory === 'image') {
            return availableModes.filter(entry => entry.category !== 'generative');
        }
        return availableModes.filter(entry => entry.category === shaderCategory);
    }, [availableModes, shaderCategory]);

    const currentMode = modes[activeSlot];
    const currentParams = slotParams[activeSlot];

    const slotMenuOptions = useMemo(
        () => currentModes.map((m): ShaderMegaMenuOption => {
            const rating = ratingMap.get(m.id);
            return {
                id: m.id,
                name: m.name,
                coordinate: coordMap[m.id]?.coordinate ?? null,
                category: coordMap[m.id]?.category ?? m.category,
                stars: rating?.stars,
                ratingCount: rating?.ratingCount,
            };
        }),
        [currentModes, coordMap, ratingMap]
    );

    const generativeMenuOptions = useMemo(
        () => availableModes
            .filter(m => m.category === 'generative')
            .map((m): ShaderMegaMenuOption => {
                const rating = ratingMap.get(m.id);
                return {
                    id: m.id,
                    name: m.name,
                    coordinate: coordMap[m.id]?.coordinate ?? null,
                    category: coordMap[m.id]?.category ?? m.category,
                    stars: rating?.stars,
                    ratingCount: rating?.ratingCount,
                };
            }),
        [availableModes, coordMap, ratingMap]
    );

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

            <LiveControlPanel
                {...liveControl}
                modes={modes}
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
                />
            )}

            {/* --- Renderer Switcher --- */}
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
                    onCopyChainShareLink={onCopyChainShareLink}
                    autoTransitionOpen={autoTransitionOpen}
                    setAutoTransitionOpen={setAutoTransitionOpen}
                    autoTransitionEnabled={autoTransitionEnabled}
                    setAutoTransitionEnabled={setAutoTransitionEnabled}
                    autoTransitionSource={autoTransitionSource}
                    setAutoTransitionSource={setAutoTransitionSource}
                    autoTransitionIntervalMs={autoTransitionIntervalMs}
                    setAutoTransitionIntervalMs={setAutoTransitionIntervalMs}
                    autoTransitionDurationMs={autoTransitionDurationMs}
                    setAutoTransitionDurationMs={setAutoTransitionDurationMs}
                    autoTransitionMode={autoTransitionMode}
                    setAutoTransitionMode={setAutoTransitionMode}
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
                devToolsOpen={devToolsOpen}
                setDevToolsOpen={setDevToolsOpen}
                onOpenShaderScanner={onOpenShaderScanner}
                activeRendererType={activeRendererType}
                onSwitchRenderer={onSwitchRenderer}
                onOpenCoordinateBrowser={() => setShowCoordinateBrowser(true)}
                onOpenStorageBrowser={onOpenStorageBrowser}
            />
        </div>
    );
};

export default ControlsContainer;
