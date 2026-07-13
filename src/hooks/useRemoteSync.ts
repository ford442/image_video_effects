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
}: UseRemoteSyncOptions): void {
    const channelRef = useRef<BroadcastChannel | null>(null);
    const heartbeatIntervalRef = useRef<NodeJS.Timeout | null>(null);

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
    }, []);

    useEffect(() => {
        if (channelRef.current) {
            sendMessage('STATE_FULL', buildFullState());
        }
    }, [modes, activeSlot, shaderCategory, inputSource, 
        autoChangeEnabled, autoChangeDelay, isMuted, selectedVideo, buildFullState, sendMessage]);
}
