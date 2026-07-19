import React, { RefObject } from 'react';
import ShaderScanner from '../ShaderScanner';
import { StorageBrowser } from '../storage';
import { RenderMode, ShaderEntry, SlotParams, InputSource } from '../../renderer/types';
import { SharedChain } from '../../services/layerChainShare';

export interface AppOverlaysProps {
    rouletteFlashRef: RefObject<HTMLDivElement | null>;
    showConfetti: boolean;
    chaosModeEnabled: boolean;
    isRecording: boolean;
    recordingCountdown: number;
    showShareModal: boolean;
    setShowShareModal: (show: boolean) => void;
    shareableLink: string;
    shareVibeText: string;
    setStatus: (status: string) => void;
    showShaderScanner: boolean;
    setShowShaderScanner: (show: boolean) => void;
    availableModes: ShaderEntry[];
    setMode: (index: number, mode: RenderMode) => void;
    updateSlotParam: (slotIndex: number, updates: Partial<SlotParams>) => void;
    showStorageBrowser: boolean;
    setShowStorageBrowser: (show: boolean) => void;
    storageBrowserTab: 'shaders' | 'images' | 'videos';
    activeSlot: number;
    handleLoadImage: (url: string) => Promise<void>;
    setSelectedVideo: React.Dispatch<React.SetStateAction<string>>;
    syncInputSourceToRenderer: (source: InputSource) => void;
    setSlotParams: React.Dispatch<React.SetStateAction<SlotParams[]>>;
}

export function AppOverlays({
    rouletteFlashRef,
    showConfetti,
    chaosModeEnabled,
    isRecording,
    recordingCountdown,
    showShareModal,
    setShowShareModal,
    shareableLink,
    shareVibeText,
    setStatus,
    showShaderScanner,
    setShowShaderScanner,
    availableModes,
    setMode,
    updateSlotParam,
    showStorageBrowser,
    setShowStorageBrowser,
    storageBrowserTab,
    activeSlot,
    handleLoadImage,
    setSelectedVideo,
    syncInputSourceToRenderer,
    setSlotParams,
}: AppOverlaysProps) {
    return (
        <>
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
                    transition: 'opacity 0.15s ease-out',
                }}
            />

            {showConfetti && (
                <div className="confetti-container">
                    {Array.from({ length: 50 }).map((_, i) => (
                        <div
                            key={i}
                            className="confetti-piece"
                            style={{
                                left: `${Math.random() * 100}%`,
                                animationDelay: `${Math.random() * 2}s`,
                                backgroundColor: ['#ff6b6b', '#4ecdc4', '#45b7d1', '#96ceb4', '#ffeaa7', '#dfe6e9', '#fd79a8'][Math.floor(Math.random() * 7)]
                            }}
                        />
                    ))}
                </div>
            )}

            {chaosModeEnabled && (
                <div className="chaos-active-indicator">
                    🔥 CHAOS MODE ON
                </div>
            )}

            {isRecording && (
                <div className="recording-indicator-overlay">
                    <div className="recording-dot-large"></div>
                    <span>REC {recordingCountdown}s</span>
                </div>
            )}

            {showShareModal && (
                <div className="share-modal-overlay" onClick={() => setShowShareModal(false)}>
                    <div className="share-modal" onClick={(e) => e.stopPropagation()}>
                        <button className="share-modal-close" onClick={() => setShowShareModal(false)}>×</button>

                        <div className="share-modal-header">
                            <h2>{shareVibeText ? '🎛️ Share Your VJ Set!' : '🎉 Clip Recorded!'}</h2>
                            <p>{shareVibeText
                                ? 'Anyone who opens this link gets your exact shader stack.'
                                : 'Your video has been downloaded. Share your creation!'}</p>
                        </div>

                        {shareVibeText && (
                            <div className="share-link-section">
                                <label>Vibe Prompt:</label>
                                <div style={{
                                    fontStyle: 'italic',
                                    color: '#d0d0e0',
                                    background: 'rgba(20, 20, 30, 0.6)',
                                    border: '1px solid rgba(255, 215, 0, 0.15)',
                                    borderRadius: '6px',
                                    padding: '8px 10px',
                                }}>
                                    “{shareVibeText}”
                                </div>
                            </div>
                        )}

                        <div className="share-link-section">
                            <label>Shareable Link:</label>
                            <div className="share-link-input-group">
                                <input
                                    type="text"
                                    value={shareableLink}
                                    readOnly
                                    className="share-link-input"
                                />
                                <button
                                    className="share-copy-btn"
                                    onClick={() => {
                                        navigator.clipboard.writeText(shareableLink);
                                        setStatus('🔗 Link copied to clipboard!');
                                    }}
                                >
                                    📋 Copy
                                </button>
                            </div>
                        </div>

                        <div className="share-buttons">
                            <a
                                href={`https://twitter.com/intent/tweet?text=Check+out+my+Pixelocity+creation!&url=${encodeURIComponent(shareableLink)}`}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="share-btn twitter"
                            >
                                🐦 Share on Twitter
                            </a>
                            <a
                                href={`https://www.tiktok.com/upload?referer=${encodeURIComponent(shareableLink)}`}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="share-btn tiktok"
                            >
                                🎵 Post on TikTok
                            </a>
                        </div>

                        <div className="share-modal-footer">
                            <button className="share-done-btn" onClick={() => setShowShareModal(false)}>
                                Done
                            </button>
                        </div>
                    </div>
                </div>
            )}

            <ShaderScanner
                shaders={availableModes}
                isOpen={showShaderScanner}
                onClose={() => setShowShaderScanner(false)}
                onTestShader={async (shaderId, testValues) => {
                    try {
                        setMode(0, shaderId as RenderMode);
                        await new Promise(resolve => setTimeout(resolve, 500));
                        const testParams: Partial<SlotParams> = {
                            zoomParam1: testValues[0] ?? 0.5,
                            zoomParam2: testValues[1] ?? 0.5,
                            zoomParam3: testValues[2] ?? 0.5,
                            zoomParam4: testValues[3] ?? 0.5,
                        };
                        updateSlotParam(0, testParams as SlotParams);
                        await new Promise(resolve => setTimeout(resolve, 200));
                        return { success: true };
                    } catch (error) {
                        return {
                            success: false,
                            error: error instanceof Error ? error.message : String(error)
                        };
                    }
                }}
            />

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
                                try {
                                    if (shader.url) {
                                        const response = await fetch(shader.url);
                                        if (response.ok) {
                                            const data = await response.json();
                                            if (data.wgsl_code || data.data?.wgsl_code) {
                                                setStatus(`Loaded shader: ${shader.name} (WGSL code available)`);
                                            } else {
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
                                } catch {
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
                                if (config.modes) {
                                    config.modes.forEach((mode: string, idx: number) => {
                                        if (idx < 3) setMode(idx, mode as RenderMode);
                                    });
                                }
                                if (config.slotParams) {
                                    setSlotParams(config.slotParams);
                                }
                                if (config.inputSource) syncInputSourceToRenderer(config.inputSource as InputSource);
                                if (config.currentImageUrl) handleLoadImage(config.currentImageUrl);
                                setStatus('Loaded effect configuration from VPS');
                                setShowStorageBrowser(false);
                            }}
                            initialTab={storageBrowserTab}
                        />
                    </div>
                </div>
            )}
        </>
    );
}
