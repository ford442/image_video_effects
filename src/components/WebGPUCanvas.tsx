import React, { useRef, useEffect } from 'react';
import { Renderer } from '../renderer/Renderer';
import { RenderMode, InputSource, SlotParams } from '../renderer/types';

interface WebGPUCanvasProps {
    modes: RenderMode[]; // Changed from mode to modes
    slotParams: SlotParams[]; // Changed from individual params to array
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
    // New Props
    inputSource: InputSource;
    selectedVideo: string;
    isMuted: boolean;
    // Legacy props for backward compatibility if needed, but we'll try to use slotParams
    lightStrength?: number;
    ambient?: number;
    normalStrength?: number;
    fogFalloff?: number;
    depthThreshold?: number;
    zoomParam1?: number;
    zoomParam2?: number;
    zoomParam3?: number;
    zoomParam4?: number;
}

const WebGPUCanvas: React.FC<WebGPUCanvasProps> = ({
    modes, slotParams, zoom, panX, panY, rendererRef,
    farthestPoint, mousePosition, setMousePosition,
    isMouseDown, setIsMouseDown, onInit,
    inputSource, selectedVideo, isMuted,
    // Keep these destructured but unused if we rely on slotParams, or map them for single mode legacy support
}) => {
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const videoRef = useRef<HTMLVideoElement | null>(null);
    const animationFrameId = useRef<number>(0);
    const lastMouseAddTime = useRef(0);

    // Plasma Interaction Refs
    const dragStartPos = useRef<{x: number, y: number} | null>(null);
    const dragStartTime = useRef<number>(0);

    // Initialize Renderer and Video Element
    useEffect(() => {
        if (!canvasRef.current) return;
        const canvas = canvasRef.current;
        const renderer = new Renderer(canvas);

        (async () => {
            const success = await renderer.init();
            if (success) {
                 if (rendererRef && 'current' in rendererRef) {
                    (rendererRef as React.MutableRefObject<Renderer | null>).current = renderer;
                }

                // Initialize Video Element
                videoRef.current = document.createElement('video');
                videoRef.current.crossOrigin = 'anonymous';
                videoRef.current.muted = isMuted; // Use prop
                videoRef.current.loop = true;
                videoRef.current.autoplay = true;
                videoRef.current.playsInline = true;

                if (selectedVideo) {
                    videoRef.current.src = `videos/${selectedVideo}`;
                    if (inputSource === 'video') {
                        videoRef.current.play().catch(console.error);
                    }
                }

                if (onInit) onInit();
            }
        })();
        return () => {
            cancelAnimationFrame(animationFrameId.current);
            renderer.destroy();
        };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [rendererRef, onInit]);

    // Handle Selected Video Change
    useEffect(() => {
        if (videoRef.current && selectedVideo) {
            videoRef.current.src = `videos/${selectedVideo}`;
            if (inputSource === 'video') {
                videoRef.current.play().catch(e => console.log("Video play failed:", e));
            }
        }
    }, [selectedVideo]);

    // Handle Mute Change
    useEffect(() => {
        if (videoRef.current) {
            videoRef.current.muted = isMuted;
        }
    }, [isMuted]);

    // Handle Input Source Change (Play/Pause)
    useEffect(() => {
        if (videoRef.current) {
            if (inputSource === 'video') {
                if (videoRef.current.src) {
                    videoRef.current.play().catch(() => {});
                }
            } else {
                videoRef.current.pause();
            }
        }
    }, [inputSource]);

 useEffect(() => {
        let active = true;
        const animate = () => {
            if (!active) return;
            if (rendererRef.current && videoRef.current) {
                // Pass video element to render
                // We need to update the Renderer.render method to accept modes and params
                // But Renderer.ts hasn't been updated yet.
                // Assuming Renderer.render signature will change to:
                // render(modes: RenderMode[], slotParams: SlotParams[], videoElement: HTMLVideoElement, ...)

                // For now, if the Renderer is not updated, this will fail or we need a compat layer.
                // I will update Renderer.ts in the next step to match this signature.
                // To avoid TS errors before that, I'll cast renderer to any.

                (rendererRef.current as any).render(
                    modes,
                    slotParams,
                    videoRef.current,
                    zoom, panX, panY, farthestPoint, mousePosition, isMouseDown
                );
            }
            animationFrameId.current = requestAnimationFrame(animate);
        };
        animate();
        return () => { active = false; cancelAnimationFrame(animationFrameId.current); };
    }, [modes, slotParams, zoom, panX, panY, farthestPoint, mousePosition, isMouseDown, rendererRef]);

    const updateMousePosition = (event: React.MouseEvent<HTMLCanvasElement>) => {
        if (!canvasRef.current) return;
        const canvas = canvasRef.current;
        const rect = canvas.getBoundingClientRect();
        const x = (event.clientX - rect.left) / canvas.width;
        const y = (event.clientY - rect.top) / canvas.height;
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
        const x = (event.clientX - rect.left) / canvas.width;
        const y = (event.clientY - rect.top) / canvas.height;
        rendererRef.current.addRipplePoint(x, y);
    };

    const handleMouseDown = (event: React.MouseEvent<HTMLCanvasElement>) => {
        setIsMouseDown(true);
        updateMousePosition(event);

        // Simple heuristic for now: trigger ripple on any active mode that supports it
        const hasInteractiveMode = modes.some(m => m === 'ripple' || m === 'vortex' || m.startsWith('liquid'));
        if (hasInteractiveMode) {
            addRippleAtMouseEvent(event);
        }

        const plasmaMode = modes.includes('plasma');
        if (plasmaMode) {
            if (!canvasRef.current) return;
            const canvas = canvasRef.current;
            const rect = canvas.getBoundingClientRect();
            const x = (event.clientX - rect.left) / canvas.width;
            const y = (event.clientY - rect.top) / canvas.height;
            dragStartPos.current = { x, y };
            dragStartTime.current = performance.now();
        }
    };

    const handleMouseUp = (event: React.MouseEvent<HTMLCanvasElement>) => {
        setIsMouseDown(false);

        const plasmaMode = modes.includes('plasma');
        if (plasmaMode && dragStartPos.current && rendererRef.current) {
            const canvas = canvasRef.current!;
            const rect = canvas.getBoundingClientRect();
            const currentX = (event.clientX - rect.left) / canvas.width;
            const currentY = (event.clientY - rect.top) / canvas.height;

            const dt = (performance.now() - dragStartTime.current) / 1000.0;
            const dx = currentX - dragStartPos.current.x;
            const dy = currentY - dragStartPos.current.y;

            if (dt > 0.01) {
                const vx = dx / dt;
                const vy = dy / dt;
                const speed = Math.sqrt(vx*vx + vy*vy);
                if (speed > 0.1) {
                    rendererRef.current.firePlasma(currentX, currentY, vx * 0.5, vy * 0.5);
                }
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
        <canvas ref={canvasRef} width="2048" height="2048" onMouseMove={handleCanvasMouseMove} onMouseDown={handleMouseDown} onMouseUp={handleMouseUp} onMouseLeave={handleMouseLeave} />
    );
};

export default WebGPUCanvas;
