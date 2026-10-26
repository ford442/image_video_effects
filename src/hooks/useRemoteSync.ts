import { useCallback, useRef, useEffect } from 'react';
import { RenderMode, ShaderEntry, ShaderCategory, InputSource, SlotParams } from '../renderer/types';
import { SyncMessage, FullState, SYNC_CHANNEL_NAME, VideoRecord } from '../syncTypes';

export interface UseRemoteSyncOptions {
    modes: RenderMode[];
    activeSlot: number;
    slotParams: SlotParams[];
    shaderCategory: ShaderCategory;
    inputSource: InputSource;
    autoChangeEnabled: boolean;
    autoChangeDelay: number;
    isModelLoaded: boolean;
    availableModes: ShaderEntry[];
    videoList: VideoRecord[];
    selectedVideo: string;
    isMuted: boolean;
    setMode: (index: number, mode: RenderMode) => void;
    setActiveSlot: (index: number) => void;
    updateSlotParam: (slotIndex: number, updates: Partial<SlotParams>) => void;
    setShaderCategory: (category: ShaderCategory) => void;
    syncInputSourceToRenderer: (source: InputSource) => void;
    setAutoChangeEnabled: React.Dispatch<React.SetStateAction<boolean>>;
    setAutoChangeDelay: React.Dispatch<React.SetStateAction<number>>;
    handleNewRandomImage: () => Promise<void>;
    loadDepthModel: () => Promise<void>;
    setSelectedVideo: React.Dispatch<React.SetStateAction<string>>;
    setIsMuted: React.Dispatch<React.SetStateAction<boolean>>;
    /** Roulette / randomize handlers (main app owns availableModes + setMode). */
    handleRandomizeSlot?: (slot: number) => void;
    triggerRandomizeAllSlots?: () => void;
    triggerRoulette?: () => void;
}

export function useRemoteSync({
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
    handleRandomizeSlot,
    triggerRandomizeAllSlots,
    triggerRoulette,
}: UseRemoteSyncOptions): void {
    const channelRef = useRef<BroadcastChannel | null>(null);
    const heartbeatIntervalRef = useRef<NodeJS.Timeout | null>(null);

    // Keep latest handlers in refs so the BroadcastChannel listener (mounted once)
    // always calls current logic without re-binding the channel. Stale closures here
    // were the remote-control "sliders do nothing" class of bug.
    const handleRandomizeSlotRef = useRef(handleRandomizeSlot);
    handleRandomizeSlotRef.current = handleRandomizeSlot;
    const triggerRandomizeAllSlotsRef = useRef(triggerRandomizeAllSlots);
    triggerRandomizeAllSlotsRef.current = triggerRandomizeAllSlots;
    const triggerRouletteRef = useRef(triggerRoulette);
    triggerRouletteRef.current = triggerRoulette;
    const setModeRef = useRef(setMode);
    setModeRef.current = setMode;
    const setActiveSlotRef = useRef(setActiveSlot);
    setActiveSlotRef.current = setActiveSlot;
    const updateSlotParamRef = useRef(updateSlotParam);
    updateSlotParamRef.current = updateSlotParam;
    const setShaderCategoryRef = useRef(setShaderCategory);
    setShaderCategoryRef.current = setShaderCategory;
    const syncInputSourceToRendererRef = useRef(syncInputSourceToRenderer);
    syncInputSourceToRendererRef.current = syncInputSourceToRenderer;
    const setAutoChangeEnabledRef = useRef(setAutoChangeEnabled);
    setAutoChangeEnabledRef.current = setAutoChangeEnabled;
    const setAutoChangeDelayRef = useRef(setAutoChangeDelay);
    setAutoChangeDelayRef.current = setAutoChangeDelay;
    const handleNewRandomImageRef = useRef(handleNewRandomImage);
    handleNewRandomImageRef.current = handleNewRandomImage;
    const loadDepthModelRef = useRef(loadDepthModel);
    loadDepthModelRef.current = loadDepthModel;
    const setSelectedVideoRef = useRef(setSelectedVideo);
    setSelectedVideoRef.current = setSelectedVideo;
    const setIsMutedRef = useRef(setIsMuted);
    setIsMutedRef.current = setIsMuted;

    const buildFullState = useCallback((): FullState => ({
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
    }), [modes, activeSlot, slotParams, shaderCategory, inputSource,
        autoChangeEnabled, autoChangeDelay, isModelLoaded, availableModes, videoList, selectedVideo, isMuted]);

    const buildFullStateRef = useRef(buildFullState);
    buildFullStateRef.current = buildFullState;

    const sendMessage = useCallback((type: SyncMessage['type'], payload?: unknown) => {
        if (channelRef.current) {
            channelRef.current.postMessage({ type, payload });
        }
    }, []);

    useEffect(() => {
        const channel = new BroadcastChannel(SYNC_CHANNEL_NAME);
        channelRef.current = channel;

        channel.onmessage = (event) => {
            const msg = event.data as SyncMessage;

            if (msg.type === 'HELLO') {
                sendMessage('STATE_FULL', buildFullStateRef.current());
                sendMessage('HEARTBEAT');
                if (!heartbeatIntervalRef.current) {
                    heartbeatIntervalRef.current = setInterval(() => {
                        sendMessage('HEARTBEAT');
                    }, 5000);
                }
            } else if (msg.type === 'CMD_SET_MODE') {
                const { index, mode } = msg.payload ?? {};
                if (typeof index === 'number' && mode != null) {
                    void setModeRef.current(index, mode);
                }
            } else if (msg.type === 'CMD_SET_ACTIVE_SLOT') {
                if (typeof msg.payload === 'number') {
                    setActiveSlotRef.current(msg.payload);
                }
            } else if (msg.type === 'CMD_UPDATE_SLOT_PARAM') {
                const { index, updates } = msg.payload ?? {};
                if (typeof index === 'number' && updates && typeof updates === 'object') {
                    updateSlotParamRef.current(index, updates as Partial<SlotParams>);
                } else {
                    console.warn('[RemoteSync] CMD_UPDATE_SLOT_PARAM missing index/updates', msg.payload);
                }
            } else if (msg.type === 'CMD_SET_SHADER_CATEGORY') {
                setShaderCategoryRef.current(msg.payload);
            } else if (msg.type === 'CMD_SET_INPUT_SOURCE') {
                syncInputSourceToRendererRef.current(msg.payload);
            } else if (msg.type === 'CMD_SET_AUTO_CHANGE') {
                setAutoChangeEnabledRef.current(msg.payload);
            } else if (msg.type === 'CMD_SET_AUTO_CHANGE_DELAY') {
                setAutoChangeDelayRef.current(msg.payload);
            } else if (msg.type === 'CMD_LOAD_RANDOM_IMAGE') {
                void handleNewRandomImageRef.current();
            } else if (msg.type === 'CMD_LOAD_MODEL') {
                void loadDepthModelRef.current();
            } else if (msg.type === 'CMD_SELECT_VIDEO') {
                setSelectedVideoRef.current(msg.payload);
            } else if (msg.type === 'CMD_SET_MUTED') {
                setIsMutedRef.current(msg.payload);
            } else if (msg.type === 'CMD_RANDOMIZE_SLOT') {
                const slot = typeof msg.payload === 'number' ? msg.payload : msg.payload?.slot;
                if (typeof slot === 'number' && slot >= 0 && slot <= 2) {
                    handleRandomizeSlotRef.current?.(slot);
                } else {
                    console.warn('[RemoteSync] CMD_RANDOMIZE_SLOT missing/invalid slot', msg.payload);
                }
            } else if (msg.type === 'CMD_RANDOMIZE_ALL_SLOTS') {
                triggerRandomizeAllSlotsRef.current?.();
            } else if (msg.type === 'CMD_ROULETTE') {
                // Prefer dedicated roulette (active slot + flash); fall back to slot 0.
                if (triggerRouletteRef.current) {
                    triggerRouletteRef.current();
                } else {
                    handleRandomizeSlotRef.current?.(0);
                }
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
    }, []);

    useEffect(() => {
        if (channelRef.current) {
            sendMessage('STATE_FULL', buildFullState());
        }
    }, [modes, activeSlot, slotParams, shaderCategory, inputSource,
        autoChangeEnabled, autoChangeDelay, isMuted, selectedVideo, buildFullState, sendMessage]);
}
