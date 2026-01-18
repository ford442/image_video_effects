import React, { useRef, useEffect, useLayoutEffect, useState } from 'react';
import { Renderer } from '../renderer/Renderer';
import { RenderMode, InputSource, SlotParams } from '../renderer/types';

interface WebGPUCanvasProps {
    modes: RenderMode[];
    slotParams: SlotParams[];
    zoom: number;
    panX: number;
    panY: number;
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
    activeGenerativeShader?: string;
    apiBaseUrl: string;
}

const WebGPUCanvas: React.FC<WebGPUCanvasProps> = ({
    modes, slotParams, zoom, panX, panY, rendererRef,
    farthestPoint, mousePosition, setMousePosition,
    isMouseDown, setIsMouseDown, onInit,
    inputSource, selectedVideo, videoSourceUrl, isMuted,
    setInputSource, activeGenerativeShader, apiBaseUrl
}) => {
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const videoRef = useRef<HTMLVideoElement>(null);
    const animationFrameId = useRef<number>(0);
    const lastMouseAddTime = useRef(0);
    const dragStartPos = useRef<{x: number, y: number} | null>(null);
    const dragStartTime = useRef<number>(0);
    const streamRef = useRef<MediaStream | null>(null);
    const [nativeDimensions, setNativeDimensions] = useState<{width: number, height: number} | null>(null);

    // Initialize Renderer
    useEffect(() => {
        if (!canvasRef.current) return;
        const canvas = canvasRef.current;
        const renderer = new Renderer(canvas, apiBaseUrl);

        // Hook up dimensions listener
        renderer.onImageDimensions = (w, h) => {
            // Only update for image source to avoid conflicts
            setNativeDimensions({width: w, height: h});
        };

        (async () => {
            const success = await renderer.init();
            if (success) {
                 if (rendererRef && 'current' in rendererRef) {
                    (rendererRef as React.MutableRefObject<Renderer | null>).current = renderer;
                }

                if (onInit) onInit();
            }
        })();
        return () => {
            cancelAnimationFrame(animationFrameId.current);
            renderer.destroy();
            // Stop webcam stream if active
            if (streamRef.current) {
                streamRef.current.getTracks().forEach(track => track.stop());
            }
        };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [rendererRef, onInit, apiBaseUrl]);

    // Handle Canvas Resizing
    useLayoutEffect(() => {
        const canvas = canvasRef.current;
        if (!canvas) return;

        const observer = new ResizeObserver((entries) => {
            for (const entry of entries) {
                // If we are in a native/fixed mode, strictly enforce the native dimensions
                // ignoring the container's layout constraints
                if (nativeDimensions && (inputSource === 'generative' || inputSource === 'image' || inputSource === 'video')) {
                     if (canvas.width !== nativeDimensions.width || canvas.height !== nativeDimensions.height) {
                         canvas.width = nativeDimensions.width;
                         canvas.height = nativeDimensions.height;
                         rendererRef.current?.handleResize(nativeDimensions.width, nativeDimensions.height);
                     }
                     return;
                }

                let width;
                let height;

                // 1. Get physical pixel dimensions
                if (entry.devicePixelContentBoxSize && entry.devicePixelContentBoxSize.length > 0) {
                    width = entry.devicePixelContentBoxSize[0].inlineSize;
                    height = entry.devicePixelContentBoxSize[0].blockSize;
                } else {
                    const dpr = window.devicePixelRatio || 1;
                    width = Math.max(1, Math.round(entry.contentRect.width * dpr));
                    height = Math.max(1, Math.round(entry.contentRect.height * dpr));
                }

                // 2. Update canvas buffer size
                if (canvas.width !== width || canvas.height !== height) {
                    canvas.width = width;
                    canvas.height = height;
                    // Use optional chaining so we update canvas size even if renderer isn't ready
                    rendererRef.current?.handleResize(width, height);
                }
            }
        });

        observer.observe(canvas);
        return () => observer.disconnect();
    }, [rendererRef, nativeDimensions, inputSource]);


    // Sync inputSource to renderer & Handle Native Modes
    useEffect(() => {
        if (rendererRef.current) {
            rendererRef.current.setInputSource(inputSource);
        }

        if (inputSource === 'generative') {
            setNativeDimensions({ width: 2048, height: 2048 });
        } else if (inputSource === 'webcam') {
            setNativeDimensions(null);
        } else if (inputSource === 'image') {
            // Wait for onImageDimensions callback
        } else if (inputSource === 'video') {
            // Wait for video metadata
        }
    }, [inputSource, rendererRef]);

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
                 try {
                     const stream = await navigator.mediaDevices.getUserMedia({ video: true });
                     streamRef.current = stream;
                     videoRef.current!.srcObject = stream;
                     videoRef.current!.play().catch(console.error);
                 } catch (e) {
                     console.error("Error accessing webcam:", e);
                     alert("Could not access webcam.");
                     // Revert to image if webcam fails
                     if (setInputSource) {
                         setInputSource('image');
                     }
                 }
             } else if (inputSource === 'video') {
                 // Clean up srcObject if coming from webcam
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

    }, [inputSource, selectedVideo, videoSourceUrl, setInputSource]);

    // Handle Mute
    useEffect(() => {
        if (videoRef.current) {
            videoRef.current.muted = isMuted;
        }
    }, [isMuted]);

    // Animation Loop
    useEffect(() => {
        let active = true;
        const animate = () => {
            if (!active) return;
            if (rendererRef.current && videoRef.current) {
                // Resolution: Use the stacking render signature from 'main'
                (rendererRef.current as any).render(
                    modes,
                    slotParams,
                    videoRef.current,
                    zoom, panX, panY, farthestPoint, mousePosition, isMouseDown,
                    activeGenerativeShader
                );
            }
            animationFrameId.current = requestAnimationFrame(animate);
        };
        animate();
        return () => { active = false; cancelAnimationFrame(animationFrameId.current); };
    }, [modes, slotParams, zoom, panX, panY, farthestPoint, mousePosition, isMouseDown, rendererRef, activeGenerativeShader, inputSource]);

    // Mouse Handlers
    const updateMousePosition = (event: React.MouseEvent<HTMLCanvasElement>) => {
        if (!canvasRef.current) return;
        const canvas = canvasRef.current;
        const rect = canvas.getBoundingClientRect();
        const x = (event.clientX - rect.left) / rect.width;
        const y = (event.clientY - rect.top) / rect.height;
        setMousePosition({ x, y });
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
        rendererRef.current.addRipplePoint(x, y);
    };

    const handleMouseDown = (event: React.MouseEvent<HTMLCanvasElement>) => {
        setIsMouseDown(true);
        updateMousePosition(event);
        
        // Check if any active mode supports interaction
        const hasInteractiveMode = modes.some(m => m === 'ripple' || m === 'vortex' || m.startsWith('liquid'));
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
                if (Math.sqrt(vx*vx + vy*vy) > 0.1) rendererRef.current.firePlasma(currentX, currentY, vx * 0.5, vy * 0.5);
            }
            dragStartPos.current = null;
        }
    };

    const handleCanvasMouseMove = (event: React.MouseEvent<HTMLCanvasElement>) => {
        updateMousePosition(event);
        const hasInteractiveMode = modes.some(m => m === 'ripple' || m === 'vortex' || m.startsWith('liquid'));
        if (isMouseDown && hasInteractiveMode) {
            const now = performance.now();
            if (now - lastMouseAddTime.current < 10) return;
            lastMouseAddTime.current = now;
            addRippleAtMouseEvent(event);
        }
    };

    return (
        <>
            <canvas
                ref={canvasRef}
                width={nativeDimensions?.width}
                height={nativeDimensions?.height}
                onMouseMove={handleCanvasMouseMove}
                onMouseDown={handleMouseDown}
                onMouseUp={handleMouseUp}
                onMouseLeave={handleMouseLeave}
                style={{
                    width: nativeDimensions ? `${nativeDimensions.width}px` : '100%',
                    height: nativeDimensions ? `${nativeDimensions.height}px` : '100%',
                    display: 'block',
                    touchAction: 'none'
                }}
            />
            <video
                ref={videoRef}
                crossOrigin="anonymous"
                muted={isMuted}
                loop
                autoPlay
                playsInline
                preload="auto"
                onLoadedMetadata={(e) => {
                     if (inputSource === 'video') {
                         setNativeDimensions({
                             width: e.currentTarget.videoWidth,
                             height: e.currentTarget.videoHeight
                         });
                     }
                }}
                onCanPlay={() => {
                     // Ensure video plays when loaded
                     videoRef.current?.play().catch(() => {});
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
        </>
    );
};

export default WebGPUCanvas;