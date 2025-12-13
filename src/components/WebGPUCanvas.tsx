import React, { useRef, useEffect } from 'react';
import { Renderer } from '../renderer/Renderer';
import { RenderMode, InputSource } from '../renderer/types';

interface WebGPUCanvasProps {
    mode: RenderMode;
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
    // Infinite Zoom
    lightStrength?: number;
    ambient?: number;
    normalStrength?: number;
    fogFalloff?: number;
    depthThreshold?: number;
    // Generic Params
    zoomParam1?: number;
    zoomParam2?: number;
    zoomParam3?: number;
    zoomParam4?: number;
}

const WebGPUCanvas: React.FC<WebGPUCanvasProps> = ({
    mode, zoom, panX, panY, rendererRef,
    farthestPoint, mousePosition, setMousePosition,
    isMouseDown, setIsMouseDown, onInit,
    inputSource, selectedVideo, isMuted,
    lightStrength, ambient, normalStrength, fogFalloff, depthThreshold,
    zoomParam1, zoomParam2, zoomParam3, zoomParam4
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
                // Special handling for Galaxy mode to pass zoom/pan via uniforms
                if (mode === 'galaxy') {
                    rendererRef.current.updateZoomParams({
                        fgSpeed: zoom,
                        bgSpeed: panX,
                        parallaxStrength: panY
                    });
                } else if (mode === 'rain') {
                    rendererRef.current.updateZoomParams({
                        fgSpeed: zoomParam1 ?? 0.08,
                        bgSpeed: zoomParam2 ?? 0.5,
                        parallaxStrength: zoomParam3 ?? 2.0,
                        fogDensity: zoomParam4 ?? 0.7
                    });
                } else {
                    // Reset to defaults when not in galaxy mode
                    rendererRef.current.updateZoomParams({
                        fgSpeed: 0.08,
                        bgSpeed: 0.0,
                        parallaxStrength: 2.0
                    });
                }
                if (mode === 'chromatic-manifold') {
                    rendererRef.current.updateZoomParams({
                        fgSpeed: zoomParam1 ?? 0.5, // hueWeight
                        bgSpeed: zoomParam2 ?? 0.5, // warpStrength
                        parallaxStrength: zoomParam3 ?? 0.8, // tearThreshold
                        fogDensity: zoomParam4 ?? 0.5 // curvatureStrength
                    });
                }
                if (mode === 'digital-decay') {
                    rendererRef.current.updateZoomParams({
                        fgSpeed: zoomParam1 ?? 0.5, // decayIntensity
                        bgSpeed: zoomParam2 ?? 0.5, // blockSize
                        parallaxStrength: zoomParam3 ?? 0.5, // corruptionSpeed
                        fogDensity: zoomParam4 ?? 0.5 // depthFocus
                    });
                }
                if (mode === 'spectral-vortex') {
                    rendererRef.current.updateZoomParams({
                        fgSpeed: zoomParam1 ?? 2.0, // Twist Strength
                        bgSpeed: zoomParam2 ?? 0.02, // Distortion Step
                        parallaxStrength: zoomParam3 ?? 0.1, // Color Shift
                        fogDensity: zoomParam4 ?? 0.0 // Unused
                    });
                }
                if (mode === 'magnetic-field') {
                    rendererRef.current.updateZoomParams({
                        fgSpeed: zoomParam1 ?? 0.5,
                        bgSpeed: zoomParam2 ?? 0.5,
                        parallaxStrength: zoomParam3 ?? 0.2,
                        fogDensity: zoomParam4 ?? 0.0
                    });
                }
                if (mode === 'pixel-sorter') {
                    rendererRef.current.updateZoomParams({
                        fgSpeed: zoomParam1 ?? 0.0,
                        bgSpeed: zoomParam2 ?? 0.0,
                        parallaxStrength: zoomParam3 ?? 0.0,
                        fogDensity: zoomParam4 ?? 0.0
                    });
                }
                if (mode === 'cyber-lens') {
                    rendererRef.current.updateZoomParams({
                        fgSpeed: zoomParam1 ?? 0.4, // Lens Radius
                        bgSpeed: zoomParam2 ?? 0.5, // Magnification
                        parallaxStrength: zoomParam3 ?? 0.5, // Grid Intensity
                        fogDensity: zoomParam4 ?? 0.2 // Aberration
                    });
                }
                if (mode === 'interactive-ripple') {
                    rendererRef.current.updateZoomParams({
                        fgSpeed: zoomParam1 ?? 0.5, // Wave Speed
                        bgSpeed: zoomParam2 ?? 0.5, // Frequency
                        parallaxStrength: zoomParam3 ?? 0.5, // Decay
                        fogDensity: zoomParam4 ?? 0.5 // Specular
                    });
                }
                if (mode === 'quantum-fractal') {
                    rendererRef.current.updateZoomParams({
                        fgSpeed: zoomParam1 ?? 3.0, // Scale
                        bgSpeed: zoomParam2 ?? 100.0, // Iterations
                        parallaxStrength: zoomParam3 ?? 1.0, // Entanglement
                        fogDensity: zoomParam4 ?? 0.0 // Unused
                    });
                }
                if (mode === 'cyber-ripples') {
                    rendererRef.current.updateZoomParams({
                        fgSpeed: zoomParam1 ?? 0.5,
                        bgSpeed: zoomParam2 ?? 0.1,
                        parallaxStrength: zoomParam3 ?? 0.2,
                        fogDensity: zoomParam4 ?? 0.5
                    });
                }
                if (mode === 'cursor-aura') {
                    rendererRef.current.updateZoomParams({
                        fgSpeed: zoomParam1 ?? 0.3,
                        bgSpeed: zoomParam2 ?? 0.8,
                        parallaxStrength: zoomParam3 ?? 0.7,
                        fogDensity: zoomParam4 ?? 0.5
                    });
                }

                // Update Lighting Params
                rendererRef.current.updateLightingParams({
                    lightStrength,
                    ambient,
                    normalStrength,
                    fogFalloff,
                    depthThreshold
                });

                // Pass video element to render
                rendererRef.current.render(mode, videoRef.current, zoom, panX, panY, farthestPoint, mousePosition, isMouseDown);
            }
            animationFrameId.current = requestAnimationFrame(animate);
        };
        animate();
        return () => { active = false; cancelAnimationFrame(animationFrameId.current); };
    }, [mode, zoom, panX, panY, farthestPoint, mousePosition, isMouseDown, rendererRef, lightStrength, ambient, normalStrength, fogFalloff, depthThreshold, zoomParam1, zoomParam2, zoomParam3, zoomParam4]);

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
        if (mode === 'ripple' || mode === 'vortex' || mode.startsWith('liquid')) {
            addRippleAtMouseEvent(event);
        }

        if (mode === 'plasma') {
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

        if (mode === 'plasma' && dragStartPos.current && rendererRef.current) {
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
        if (isMouseDown && (mode === 'ripple' || mode === 'vortex' || mode.startsWith('liquid'))) {
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
