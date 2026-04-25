import React, { useRef, useEffect, useLayoutEffect, useState } from 'react';
import { type Renderer } from '../renderer/Renderer';
import { RendererManager } from '../renderer/RendererManager';
import { RenderMode, InputSource, SlotParams } from '../renderer/types';
import { INTERNAL_RENDER_RESOLUTION } from '../config/appConfig';
import { LiveStreamBridge } from './LiveStreamBridge';

interface WebGPUCanvasProps {
    modes: RenderMode[];
    slotParams: SlotParams[];
    rendererRef: React.MutableRefObject<Renderer | null>;
    farthestPoint: { x: number; y: number };
    mousePosition: { x: number; y: number };
    setMousePosition: React.Dispatch<React.SetStateAction<{ x: number, y: number }>>;
    isMouseDown: boolean;
    setIsMouseDown: (down: boolean) => void;
    onInit?: () => void;
    inputSource: InputSource;
    selectedVideo: string; // Used for "Stock" videos
    videoSourceUrl?: string; // NEW: Used for "Uploaded" videos (Blob URL)
    isMuted: boolean;
    setInputSource?: (source: InputSource) => void; // Added for error handling
    activeSlot: number;
    activeGenerativeShader?: string;
    apiBaseUrl: string;
    // Webcam Props
    isWebcamActive?: boolean;
    webcamVideoElement?: HTMLVideoElement | null;
    // Live Stream Props
    liveStreamUrl?: string; // NEW: HLS live stream URL
    // Expose the canvas element to the parent (e.g. for recording)
    onCanvasRef?: (canvas: HTMLCanvasElement | null) => void;
}

const WebGPUCanvas: React.FC<WebGPUCanvasProps> = ({
    modes, slotParams, rendererRef,
    farthestPoint, mousePosition, setMousePosition,
    isMouseDown, setIsMouseDown, onInit,
    inputSource, selectedVideo, videoSourceUrl, isMuted,
    setInputSource, activeSlot, activeGenerativeShader, apiBaseUrl,
    isWebcamActive = false,
    webcamVideoElement,
    liveStreamUrl,
    onCanvasRef
}) => {
    const containerRef = useRef<HTMLDivElement>(null);
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const videoRef = useRef<HTMLVideoElement>(null);
    const animationFrameId = useRef<number>(0);
    const lastMouseAddTime = useRef(0);
    const dragStartPos = useRef<{ x: number, y: number } | null>(null);
    const dragStartTime = useRef<number>(0);
    const streamRef = useRef<MediaStream | null>(null);
    const hlsVideoRef = useRef<HTMLVideoElement | null>(null); // NEW: Live stream video element

    // Track the CSS display size of the canvas element
    const [displaySize, setDisplaySize] = useState({ width: 1, height: 1 });

    // Track if canvas has valid dimensions before initializing WebGPU
    const [canvasReady, setCanvasReady] = useState(false);

    // Track if there are active interactive/mouse-driven effects
    const [hasInteractiveEffects, setHasInteractiveEffects] = useState(false);

    // Expose canvas element to parent (e.g. for recording) via onCanvasRef callback
    useEffect(() => {
        if (!canvasRef.current) return;
        onCanvasRef?.(canvasRef.current);
        return () => onCanvasRef?.(null);
    // canvasRef.current is stable; we only need to re-run if the callback identity changes
    // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [onCanvasRef]);

    // Ensure canvas has valid dimensions before WebGPU initialization
    const ensureCanvasSize = (canvas: HTMLCanvasElement) => {
        // Only check the on-screen CSS box here; the backing buffer is fixed separately.
        const rect = canvas.getBoundingClientRect();
        const width = Math.max(1, Math.floor(rect.width));
        const height = Math.max(1, Math.floor(rect.height));
        
        // Log for debugging - should NOT be 0x0
        if (width <= 1 || height <= 1) {
            if (process.env.NODE_ENV === 'development') {
                console.warn(`Canvas has near-zero dimensions: ${width}x${height}, delaying WebGPU init`);
            }
            return false;
        }
        
        return true;
    };

    // Initialize Renderer (with StrictMode guard)
    useEffect(() => {
        if (!canvasRef.current || !canvasReady) return;
        const canvas = canvasRef.current;

        // Guard: Ensure canvas has actual dimensions before creating textures
        if (!ensureCanvasSize(canvas)) {
            if (process.env.NODE_ENV === 'development') {
                console.warn('Canvas not ready for WebGPU initialization, skipping...');
            }
            return;
        }

        // Enforce the high-res buffer size
        canvas.width = INTERNAL_RENDER_RESOLUTION;
        canvas.height = INTERNAL_RENDER_RESOLUTION;
        if (process.env.NODE_ENV === 'development') {
            console.log(`Initializing WebGPU with canvas: ${canvas.width}x${canvas.height}`);
        }

        const renderer = new RendererManager({
            width: INTERNAL_RENDER_RESOLUTION,
            height: INTERNAL_RENDER_RESOLUTION,
            agentCount: 50000
        });
        let mounted = true;

        // Hook up dimensions listener - kept for potential future use or informational purposes,
        // but we are locking buffer size now.
        if ('onImageDimensions' in renderer) {
            (renderer as any).onImageDimensions = (w: number, h: number) => {
                // We no longer resize the canvas based on image dimensions
                // But we might want to log it or use it for aspect ratio logic if needed in future
            };
        }

        (async () => {
            const success = await renderer.init(canvasRef.current!);
            // StrictMode guard: if unmounted during async init, discard the result
            if (!mounted) {
                renderer.destroy();
                return;
            }
            if (success) {
                if (rendererRef && 'current' in rendererRef) {
                    (rendererRef as React.MutableRefObject<any>).current = renderer;
                }
                if (videoRef.current && 'setVideo' in renderer) {
                    (renderer as any).setVideo(videoRef.current);
                }

                if (onInit) onInit();
            } else {
                // Init failed - clean up the renderer
                renderer.destroy();
            }
        })();
        return () => {
            mounted = false;
            cancelAnimationFrame(animationFrameId.current);
            renderer.destroy();
            // Stop webcam stream if active
            if (streamRef.current) {
                streamRef.current.getTracks().forEach(track => track.stop());
            }
        };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [rendererRef, onInit, apiBaseUrl, canvasReady]);

    // Handle Canvas Resizing (Track Display Size Only)
    useLayoutEffect(() => {
        const container = containerRef.current;
        if (!container) return;

        // Try to get initial size from container
        const rect = container.getBoundingClientRect();
        if (rect.width > 0 && rect.height > 0 && displaySize.width === 1) {
            if (process.env.NODE_ENV === 'development') {
                console.log(`📦 Initial container size from getBoundingClientRect: ${rect.width}x${rect.height}`);
            }
            setDisplaySize({ width: rect.width, height: rect.height });
            if (!canvasReady) {
                setCanvasReady(true);
            }
        }

        const observer = new ResizeObserver((entries) => {
            for (const entry of entries) {
                // Get the displayed size (CSS pixels)
                const width = entry.contentRect.width;
                const height = entry.contentRect.height;

                if (process.env.NODE_ENV === 'development') {
                    console.log(`🔍 ResizeObserver fired: ${width}x${height}`);
                }

                if (width > 0 && height > 0) {
                    setDisplaySize({ width, height });
                    // Mark canvas as ready for WebGPU initialization
                    if (!canvasReady) {
                        if (process.env.NODE_ENV === 'development') {
                            console.log(`✅ Canvas ready: ${width}x${height}`);
                        }
                        setCanvasReady(true);
                    }
                } else {
                    if (process.env.NODE_ENV === 'development') {
                        console.warn(`⚠️ Container has zero dimensions: ${width}x${height}`);
                    }
                }
            }
        });

        observer.observe(container);
        return () => observer.disconnect();
    }, [canvasReady, displaySize.width]); // Add displaySize.width to re-run if needed



    // Sync inputSource to renderer
    useEffect(() => {
        if (rendererRef.current) {
            if ('setInputSource' in rendererRef.current) {
                (rendererRef.current as any).setInputSource(inputSource);
            }
        }
    }, [inputSource, rendererRef]);

    // Check for interactive effects
    useEffect(() => {
        const hasInteractive = (() => {
            const rendererModes = rendererRef.current?.getAvailableModes?.() || [];
            for (const mm of modes) {
                const entry = rendererModes.find(s => s.id === mm);
                if (entry?.features?.includes('mouse-driven') || entry?.features?.includes('splat') || mm === 'ripple' || mm === 'vortex' || mm.startsWith('liquid')) return true;
            }
            return false;
        })();
        setHasInteractiveEffects(hasInteractive);
    }, [modes, rendererRef]);

    // Handle webcam video element
    useEffect(() => {
        if (isWebcamActive && webcamVideoElement && videoRef.current) {
            // Use the provided webcam video element
            videoRef.current.srcObject = webcamVideoElement.srcObject;
            videoRef.current.play().catch(console.error);
        }
    }, [isWebcamActive, webcamVideoElement, videoRef]);

    // Handle Live Stream Video Ready
    const handleLiveVideoReady = (video: HTMLVideoElement) => {
        if (process.env.NODE_ENV === 'development') {
            console.log('🔴 WebGPUCanvas: Live video ready');
        }
        hlsVideoRef.current = video;
        // If we're in live mode, sync the video element
        if (inputSource === 'live' && videoRef.current) {
            videoRef.current.src = video.src;
            videoRef.current.srcObject = video.srcObject;
            videoRef.current.play().catch(console.error);
        }
    };

    // Handle Input Source & Video Source Changes
    useEffect(() => {
        if (!videoRef.current) return;

        const handleVideoSource = async () => {
            // Stop previous webcam stream if switching away or re-requesting
            if (streamRef.current && inputSource !== 'webcam') {
                streamRef.current.getTracks().forEach(track => track.stop());
                streamRef.current = null;
            }

            if (inputSource === 'webcam') {
                // Use the webcam stream already acquired by App.tsx (via startWebcam)
                // to avoid duplicate getUserMedia calls and leaked MediaStreams.
                if (webcamVideoElement && webcamVideoElement.srcObject) {
                    videoRef.current!.srcObject = webcamVideoElement.srcObject;
                    videoRef.current!.play().catch(console.error);
                }
            } else if (inputSource === 'live') {
                // Live stream mode - use the HLS video element
                if (hlsVideoRef.current) {
                    videoRef.current!.src = hlsVideoRef.current.src;
                    videoRef.current!.srcObject = hlsVideoRef.current.srcObject;
                    videoRef.current!.play().catch(console.error);
                }
            } else if (inputSource === 'video') {
                // Clean up srcObject if coming from webcam or live
                if (videoRef.current!.srcObject) {
                    videoRef.current!.srcObject = null;
                }

                // Determine URL
                let src = '';
                if (videoSourceUrl) {
                    src = videoSourceUrl; // Uploaded video (blob:)
                } else if (selectedVideo) {
                    // Handle both local files and full bucket URLs
                    src = selectedVideo.startsWith('http')
                        ? selectedVideo
                        : `videos/${selectedVideo}`;
                }

                if (src && videoRef.current!.src !== src) {
                    videoRef.current!.src = src;
                    videoRef.current!.load(); // Force browser to acknowledge the new source immediately
                    const playPromise = videoRef.current!.play();
                    if (playPromise !== undefined) {
                        playPromise.catch(e => console.log("Video play failed:", e));
                    }
                }
            } else {
                // Image or Generative mode: pause video to save resources
                videoRef.current!.pause();
            }
        };

        handleVideoSource();

        // Ensure the renderer is aware of the video element whenever source changes
        if (rendererRef.current && videoRef.current) {
            if ('setVideo' in rendererRef.current) {
                (rendererRef.current as any).setVideo(videoRef.current);
            }
        }

    }, [inputSource, selectedVideo, videoSourceUrl, setInputSource, webcamVideoElement]);

    // Handle Mute
    useEffect(() => {
        if (videoRef.current) {
            videoRef.current.muted = isMuted;
        }
    }, [isMuted]);

    // Sync mouseDown state to renderer
    useEffect(() => {
        if (rendererRef.current?.setParam) {
            rendererRef.current.setParam('mouseDown', isMouseDown ? 1 : 0);
        }
    }, [isMouseDown, rendererRef]);

    // Sync slotParams to renderer (zoomParam1-4) - use active slot's params
    useEffect(() => {
        if (rendererRef.current?.updateSlotParams && slotParams.length > 0) {
            const params = slotParams[activeSlot] ?? slotParams[0];
            rendererRef.current.updateSlotParams({
                zoomParam1: params.zoomParam1,
                zoomParam2: params.zoomParam2,
                zoomParam3: params.zoomParam3,
                zoomParam4: params.zoomParam4,
            });
        }
    }, [slotParams, activeSlot, rendererRef]);

    // Animation Loop
    useEffect(() => {
        let active = true;
        const animate = () => {
            if (!active) return;
            if (rendererRef.current && videoRef.current) {
                // Force square viewport to match the aspect ratio of the 2048x2048 internal buffer
                const canvasSize = Math.min(displaySize.width, displaySize.height);

                // Resolution: Use the stacking render signature from 'main'
                // AND pass display dimensions

                // Extra safety: repeatedly ensure the renderer has the video reference
                // (in case the renderer was instantiated after the effect ran)
                if ('setVideo' in rendererRef.current) {
                    (rendererRef.current as any).setVideo(videoRef.current);
                }

                (rendererRef.current as any).render(
                    modes,
                    slotParams,
                    videoRef.current,
                    farthestPoint, mousePosition, isMouseDown,
                    activeGenerativeShader,
                    canvasSize, // viewWidth (square)
                    canvasSize  // viewHeight (square)
                );
            }
            animationFrameId.current = requestAnimationFrame(animate);
        };
        animate();
        return () => { active = false; cancelAnimationFrame(animationFrameId.current); };
    }, [modes, slotParams, farthestPoint, mousePosition, isMouseDown, rendererRef, activeGenerativeShader, inputSource, displaySize]);

    // Mouse Handlers
    const updateMousePosition = (event: React.MouseEvent<HTMLCanvasElement>) => {
        if (!canvasRef.current) return;
        const canvas = canvasRef.current;
        const rect = canvas.getBoundingClientRect();
        const x = (event.clientX - rect.left) / rect.width;
        const y = (event.clientY - rect.top) / rect.height;
        setMousePosition({ x, y });
        
        // Sync to renderer
        if (rendererRef.current?.updateMouse) {
            rendererRef.current.updateMouse(x, y);
        }
    };

    const handleMouseLeave = () => {
        setIsMouseDown(false);
        setMousePosition({ x: -1, y: -1 });
    };

    const addRippleAtMouseEvent = (event: React.MouseEvent<HTMLCanvasElement>) => {
        if (!rendererRef.current) return;
        const canvas = canvasRef.current!;
        const rect = canvas.getBoundingClientRect();
        const x = (event.clientX - rect.left) / rect.width;
        const y = (event.clientY - rect.top) / rect.height;
        if (typeof (rendererRef.current as any).addRipplePoint === 'function') {
            (rendererRef.current as any).addRipplePoint(x, y);
        } else if ('addRipplePoint' in rendererRef.current) {
            (rendererRef.current as any).addRipplePoint(x, y);
        }
    };

    const handleMouseDown = (event: React.MouseEvent<HTMLCanvasElement>) => {
        setIsMouseDown(true);
        updateMousePosition(event);

        // Check if any active mode supports interaction (use shader metadata when available)
        const hasInteractiveMode = (() => {
            // Prefer renderer-provided metadata when available (covers many interactive shaders)
            const rendererModes = rendererRef.current?.getAvailableModes?.() || [];
            for (const mm of modes) {
                const entry = rendererModes.find(s => s.id === mm);
                if (entry?.features?.includes('mouse-driven') || entry?.features?.includes('splat') || mm === 'ripple' || mm === 'vortex' || mm.startsWith('liquid')) return true;
            }
            return false;
        })();

        if (hasInteractiveMode) addRippleAtMouseEvent(event);

        const plasmaMode = modes.includes('plasma');
        if (plasmaMode) {
            if (!canvasRef.current) return;
            const canvas = canvasRef.current;
            const rect = canvas.getBoundingClientRect();
            dragStartPos.current = { x: (event.clientX - rect.left) / rect.width, y: (event.clientY - rect.top) / rect.height };
            dragStartTime.current = performance.now();
        }
    };

    const handleMouseUp = (event: React.MouseEvent<HTMLCanvasElement>) => {
        setIsMouseDown(false);
        const plasmaMode = modes.includes('plasma');
        if (plasmaMode && dragStartPos.current && rendererRef.current) {
            const canvas = canvasRef.current!;
            const rect = canvas.getBoundingClientRect();
            const currentX = (event.clientX - rect.left) / rect.width;
            const currentY = (event.clientY - rect.top) / rect.height;
            const dt = (performance.now() - dragStartTime.current) / 1000.0;
            const dx = currentX - dragStartPos.current.x;
            const dy = currentY - dragStartPos.current.y;
            if (dt > 0.01) {
                const vx = dx / dt; const vy = dy / dt;
            if (Math.sqrt(vx * vx + vy * vy) > 0.1) {
                if ('firePlasma' in rendererRef.current) {
                    (rendererRef.current as any).firePlasma(currentX, currentY, vx * 0.5, vy * 0.5);
                }
            }
            }
            dragStartPos.current = null;
        }
    };

    const handleCanvasMouseMove = (event: React.MouseEvent<HTMLCanvasElement> | React.PointerEvent<HTMLCanvasElement>) => {
        updateMousePosition(event as any);
        const hasInteractiveMode = (() => {
            const rendererModes = rendererRef.current?.getAvailableModes?.() || [];
            for (const mm of modes) {
                const entry = rendererModes.find(s => s.id === mm);
                if (entry?.features?.includes('mouse-driven') || entry?.features?.includes('splat') || mm === 'ripple' || mm === 'vortex' || mm.startsWith('liquid')) return true;
            }
            return false;
        })();

        if (isMouseDown && hasInteractiveMode) {
            const now = performance.now();
            if (now - lastMouseAddTime.current < 10) return;
            lastMouseAddTime.current = now;
            addRippleAtMouseEvent(event as any);
        }
    };

    // Calculate canvas style to be a square that fits within the container
    const canvasSize = Math.min(displaySize.width, displaySize.height);
    const finalCanvasSize = Math.max(canvasSize, 100); // Ensure minimum visible size

    // Debug logging only in development
    if (process.env.NODE_ENV === 'development') {
        if (displaySize.width !== 1 || displaySize.height !== 1) {
            console.log(`📐 Canvas size calculated: ${finalCanvasSize}px (from ${displaySize.width}x${displaySize.height})`);
        } else {
            console.warn(`⚠️ Canvas size is still using default (1x1), using fallback display size`);
        }
    }

    const canvasStyle: React.CSSProperties = {
        position: 'absolute',
        width: `${finalCanvasSize}px`,
        height: `${finalCanvasSize}px`,
        left: '50%',
        top: '50%',
        transform: 'translate(-50%, -50%)',
        display: 'block',
        touchAction: 'none',
        // Ensure it doesn't overflow
        maxWidth: '100%',
        maxHeight: '100%'
    };

    return (
        <div
            ref={containerRef}
            className={`canvas-wrapper ${isWebcamActive ? 'webcam-active' : ''}`}
            style={{
                width: '100%',
                height: '100%',
                position: 'relative',
                overflow: 'hidden',
                // Center the canvas content
                display: 'flex',
                justifyContent: 'center',
                alignItems: 'center',
                backgroundColor: '#000' // Optional: letterboxing color
            }}
        >
            {isWebcamActive && (
                <div className="webcam-indicator">
                    <span className="recording-dot"></span>
                    LIVE
                </div>
            )}
            
            {/* Live Stream Bridge - hidden HLS video */}
            {liveStreamUrl && (
                <LiveStreamBridge
                    streamUrl={liveStreamUrl}
                    onVideoReady={handleLiveVideoReady}
                    onError={(err) => console.error('Live stream error:', err)}
                />
            )}
            <canvas
                ref={canvasRef}
                data-testid="webgpu-canvas"
                width={INTERNAL_RENDER_RESOLUTION}
                height={INTERNAL_RENDER_RESOLUTION}
                onPointerMove={handleCanvasMouseMove}
                onPointerDown={handleMouseDown} onMouseDown={handleMouseDown}
                onPointerUp={handleMouseUp}
                onPointerLeave={handleMouseLeave}
                style={canvasStyle}
                className={`webgpu-canvas ${isWebcamActive ? 'webcam-canvas' : ''} ${hasInteractiveEffects ? 'interactive-effects' : ''}`}
            />
            <video
                ref={videoRef}
                crossOrigin="anonymous"
                muted={isMuted}
                loop
                autoPlay
                playsInline
                preload="auto"
                onCanPlay={() => {
                    // Ensure video plays when loaded
                    videoRef.current?.play().catch(() => { });
                }}
                style={{
                    position: 'absolute',
                    width: '1px',
                    height: '1px',
                    opacity: 0,
                    pointerEvents: 'none',
                    zIndex: -1
                }}
            />
        </div>
    );
};

export default WebGPUCanvas;
