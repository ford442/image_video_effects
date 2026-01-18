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
    const containerRef = useRef<HTMLDivElement>(null);
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const videoRef = useRef<HTMLVideoElement>(null);
    const animationFrameId = useRef<number>(0);
    const lastMouseAddTime = useRef(0);
    const dragStartPos = useRef<{x: number, y: number} | null>(null);
    const dragStartTime = useRef<number>(0);
    const streamRef = useRef<MediaStream | null>(null);

    // Track the physical display size of the canvas element
    const [displaySize, setDisplaySize] = useState({ width: 1, height: 1 });

    // Constants for the internal high-res buffer
    const INTERNAL_RES = 2048;

    // Initialize Renderer
    useEffect(() => {
        if (!canvasRef.current) return;
        const canvas = canvasRef.current;

        // Enforce the high-res buffer size
        canvas.width = INTERNAL_RES;
        canvas.height = INTERNAL_RES;

        const renderer = new Renderer(canvas, apiBaseUrl);

        // Hook up dimensions listener - kept for potential future use or informational purposes,
        // but we are locking buffer size now.
        renderer.onImageDimensions = (w, h) => {
             // We no longer resize the canvas based on image dimensions
             // But we might want to log it or use it for aspect ratio logic if needed in future
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

    // Handle Canvas Resizing (Track Display Size Only)
    useLayoutEffect(() => {
        const container = containerRef.current;
        if (!container) return;

        const observer = new ResizeObserver((entries) => {
            for (const entry of entries) {
                // Get the displayed size (CSS pixels)
                const width = entry.contentRect.width;
                const height = entry.contentRect.height;

                if (width > 0 && height > 0) {
                    setDisplaySize({ width, height });
                }
            }
        });

        observer.observe(container);
        return () => observer.disconnect();
    }, []); // Empty dependency array as we only want to set up the observer once

    // Sync inputSource to renderer
    useEffect(() => {
        if (rendererRef.current) {
            rendererRef.current.setInputSource(inputSource);
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
                // Force square viewport to match the aspect ratio of the 2048x2048 internal buffer
                const canvasSize = Math.min(displaySize.width, displaySize.height);

                // Resolution: Use the stacking render signature from 'main'
                // AND pass display dimensions
                (rendererRef.current as any).render(
                    modes,
                    slotParams,
                    videoRef.current,
                    zoom, panX, panY, farthestPoint, mousePosition, isMouseDown,
                    activeGenerativeShader,
                    canvasSize, // viewWidth (square)
                    canvasSize  // viewHeight (square)
                );
            }
            animationFrameId.current = requestAnimationFrame(animate);
        };
        animate();
        return () => { active = false; cancelAnimationFrame(animationFrameId.current); };
    }, [modes, slotParams, zoom, panX, panY, farthestPoint, mousePosition, isMouseDown, rendererRef, activeGenerativeShader, inputSource, displaySize]);

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

    // Calculate canvas style to be a square that fits within the container (CSS Contain)
    const canvasSize = Math.min(displaySize.width, displaySize.height);
    const canvasStyle: React.CSSProperties = {
        position: 'absolute',
        width: `${canvasSize}px`,
        height: `${canvasSize}px`,
        left: '50%',
        top: '50%',
        transform: 'translate(-50%, -50%)',
        display: 'block',
        touchAction: 'none',
        // Optional: Ensure it doesn't overflow if something goes wrong with calculation
        maxWidth: '100%',
        maxHeight: '100%'
    };

    return (
        <div
            ref={containerRef}
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
            <canvas
                ref={canvasRef}
                onMouseMove={handleCanvasMouseMove}
                onMouseDown={handleMouseDown}
                onMouseUp={handleMouseUp}
                onMouseLeave={handleMouseLeave}
                style={canvasStyle}
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
        </div>
    );
};

export default WebGPUCanvas;