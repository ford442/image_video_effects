import React, { useState, useEffect, useRef, useCallback } from 'react';
import Controls from './components/Controls';
import { RenderMode, ShaderEntry, ShaderCategory, InputSource, SlotParams } from './renderer/types';
import { SyncMessage, FullState, SYNC_CHANNEL_NAME } from './syncTypes';

// Default State (matches App.tsx defaults roughly, but will be overwritten by sync)
const DEFAULT_SLOT_PARAMS: SlotParams = {
    zoomParam1: 0.5, zoomParam2: 0.5, zoomParam3: 0.5, zoomParam4: 0.5,
    lightStrength: 1.0, ambient: 0.2, normalStrength: 0.1, fogFalloff: 4.0, depthThreshold: 0.5,
};

const RemoteApp: React.FC = () => {
    // State
    const [connected, setConnected] = useState(false);
    const [modes, setModes] = useState<RenderMode[]>(['liquid', 'none', 'none']);
    const [activeSlot, setActiveSlot] = useState<number>(0);
    const [slotParams, setSlotParams] = useState<SlotParams[]>([
        { ...DEFAULT_SLOT_PARAMS },
        { ...DEFAULT_SLOT_PARAMS },
        { ...DEFAULT_SLOT_PARAMS }
    ]);
    const [shaderCategory, setShaderCategory] = useState<ShaderCategory>('image');
    const [zoom, setZoom] = useState(1.0);
    const [panX, setPanX] = useState(0.5);
    const [panY, setPanY] = useState(0.5);
    const [inputSource, setInputSource] = useState<InputSource>('image');
    const [autoChangeEnabled, setAutoChangeEnabled] = useState(false);
    const [autoChangeDelay, setAutoChangeDelay] = useState(10);
    const [isModelLoaded, setIsModelLoaded] = useState(false);
    const [availableModes, setAvailableModes] = useState<ShaderEntry[]>([]);
    const [videoList, setVideoList] = useState<string[]>([]);
    const [selectedVideo, setSelectedVideo] = useState<string>('');
    const [isMuted, setIsMuted] = useState(true);

    const channelRef = useRef<BroadcastChannel | null>(null);
    const heartbeatTimeoutRef = useRef<NodeJS.Timeout | null>(null);
    const fileInputImageRef = useRef<HTMLInputElement>(null);
    const fileInputVideoRef = useRef<HTMLInputElement>(null);

    // Messaging Helper
    const sendMessage = useCallback((type: SyncMessage['type'], payload?: any) => {
        if (channelRef.current) {
            channelRef.current.postMessage({ type, payload });
        }
    }, []);

    // Heartbeat Logic
    const resetHeartbeat = useCallback(() => {
        setConnected(true);
        if (heartbeatTimeoutRef.current) clearTimeout(heartbeatTimeoutRef.current);
        heartbeatTimeoutRef.current = setTimeout(() => {
            setConnected(false);
        }, 3000); // 3 seconds timeout
    }, []);

    useEffect(() => {
        const channel = new BroadcastChannel(SYNC_CHANNEL_NAME);
        channelRef.current = channel;

        channel.onmessage = (event) => {
            const msg = event.data as SyncMessage;
            if (msg.type === 'HEARTBEAT') {
                resetHeartbeat();
            } else if (msg.type === 'STATE_FULL') {
                const state = msg.payload as FullState;
                setModes(state.modes);
                setActiveSlot(state.activeSlot);
                setSlotParams(state.slotParams);
                setShaderCategory(state.shaderCategory);
                setZoom(state.zoom);
                setPanX(state.panX);
                setPanY(state.panY);
                setInputSource(state.inputSource);
                setAutoChangeEnabled(state.autoChangeEnabled);
                setAutoChangeDelay(state.autoChangeDelay);
                setIsModelLoaded(state.isModelLoaded);
                setAvailableModes(state.availableModes);
                setVideoList(state.videoList);
                setSelectedVideo(state.selectedVideo);
                setIsMuted(state.isMuted);
                resetHeartbeat();
            } else if (msg.type === 'STATE_UPDATE') {
                // Handle partial updates if needed
            }
        };

        // Send Hello
        sendMessage('HELLO');

        return () => {
            channel.close();
            if (heartbeatTimeoutRef.current) clearTimeout(heartbeatTimeoutRef.current);
        };
    }, [resetHeartbeat, sendMessage]);


    // Handlers
    const handleSetMode = (index: number, mode: RenderMode) => {
        const newModes = [...modes];
        newModes[index] = mode;
        setModes(newModes);
        sendMessage('CMD_SET_MODE', { index, mode });
    };

    const handleSetActiveSlot = (index: number) => {
        setActiveSlot(index);
        sendMessage('CMD_SET_ACTIVE_SLOT', index);
    };

    const handleUpdateSlotParam = (index: number, updates: Partial<SlotParams>) => {
        const newParams = [...slotParams];
        newParams[index] = { ...newParams[index], ...updates };
        setSlotParams(newParams);
        sendMessage('CMD_UPDATE_SLOT_PARAM', { index, updates });
    };

    const handleSetShaderCategory = (cat: ShaderCategory) => {
        setShaderCategory(cat);
        sendMessage('CMD_SET_SHADER_CATEGORY', cat);
    };

    const handleSetZoom = (val: number) => {
        setZoom(val);
        sendMessage('CMD_SET_ZOOM', val);
    };

    const handleSetPanX = (val: number) => {
        setPanX(val);
        sendMessage('CMD_SET_PAN_X', val);
    };

    const handleSetPanY = (val: number) => {
        setPanY(val);
        sendMessage('CMD_SET_PAN_Y', val);
    };

    const handleSetInputSource = (source: InputSource) => {
        setInputSource(source);
        sendMessage('CMD_SET_INPUT_SOURCE', source);
    };

    const handleSetAutoChange = (enabled: boolean) => {
        setAutoChangeEnabled(enabled);
        sendMessage('CMD_SET_AUTO_CHANGE', enabled);
    };

    const handleSetAutoChangeDelay = (delay: number) => {
        setAutoChangeDelay(delay);
        sendMessage('CMD_SET_AUTO_CHANGE_DELAY', delay);
    };

    const handleLoadRandom = () => {
        sendMessage('CMD_LOAD_RANDOM_IMAGE');
    };

    const handleLoadModel = () => {
        sendMessage('CMD_LOAD_MODEL');
    };

    const handleSetSelectedVideo = (video: string) => {
        setSelectedVideo(video);
        sendMessage('CMD_SELECT_VIDEO', video);
    };

    const handleSetMuted = (muted: boolean) => {
        setIsMuted(muted);
        sendMessage('CMD_SET_MUTED', muted);
    };

    // File Uploads
    const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>, type: 'image' | 'video') => {
        const file = e.target.files?.[0];
        if (!file) return;

        // Read file
        const buffer = await file.arrayBuffer();
        sendMessage('CMD_UPLOAD_FILE', {
            name: file.name,
            type: type,
            mimeType: file.type,
            data: buffer
        });

        // Reset input
        e.target.value = '';
    };

    if (!connected) {
        return (
            <div style={{
                display: 'flex', justifyContent: 'center', alignItems: 'center',
                height: '100vh', backgroundColor: '#000', color: 'red',
                fontSize: '2rem', flexDirection: 'column'
            }}>
                <div>LOST CONNECTION</div>
                <div style={{fontSize: '1rem', color: '#666', marginTop: '20px'}}>
                    Waiting for Main App...
                </div>
            </div>
        );
    }

    return (
        <div className="remote-app" style={{
            backgroundColor: '#222',
            height: '100vh',
            color: 'white',
            display: 'flex',
            flexDirection: 'column',
            overflow: 'hidden' // Prevent body scroll
        }}>
            <h2 style={{
                textAlign: 'center',
                padding: '20px 0',
                margin: 0,
                backgroundColor: '#2a2a2a',
                borderBottom: '1px solid #444',
                flexShrink: 0
            }}>
                Remote Control
            </h2>

            {/* Hidden Inputs */}
            <input
                type="file"
                accept="image/*"
                ref={fileInputImageRef}
                style={{display: 'none'}}
                onChange={(e) => handleFileUpload(e, 'image')}
            />
            <input
                type="file"
                accept="video/*"
                ref={fileInputVideoRef}
                style={{display: 'none'}}
                onChange={(e) => handleFileUpload(e, 'video')}
            />

            {/* Scrollable Content Container */}
            <div className="remote-content" style={{
                flex: 1,
                overflowY: 'auto',
                padding: '20px',
                position: 'relative'
            }}>
                <Controls
                    modes={modes}
                    setMode={handleSetMode}
                    activeSlot={activeSlot}
                    setActiveSlot={handleSetActiveSlot}
                    slotParams={slotParams}
                    updateSlotParam={handleUpdateSlotParam}
                    shaderCategory={shaderCategory}
                    setShaderCategory={handleSetShaderCategory}
                    zoom={zoom} setZoom={handleSetZoom}
                    panX={panX} setPanX={handleSetPanX}
                    panY={panY} setPanY={handleSetPanY}
                    onNewImage={handleLoadRandom}
                    autoChangeEnabled={autoChangeEnabled}
                    setAutoChangeEnabled={handleSetAutoChange}
                    autoChangeDelay={autoChangeDelay}
                    setAutoChangeDelay={handleSetAutoChangeDelay}
                    onLoadModel={handleLoadModel}
                    isModelLoaded={isModelLoaded}
                    availableModes={availableModes}
                    inputSource={inputSource}
                    setInputSource={handleSetInputSource}
                    videoList={videoList}
                    selectedVideo={selectedVideo}
                    setSelectedVideo={handleSetSelectedVideo}
                    isMuted={isMuted}
                    setIsMuted={handleSetMuted}
                    onUploadImageTrigger={() => fileInputImageRef.current?.click()}
                    onUploadVideoTrigger={() => fileInputVideoRef.current?.click()}
                />
            </div>
        </div>
    );
};

export default RemoteApp;
