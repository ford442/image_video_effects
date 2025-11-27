import React, { useRef, useEffect, useState } from 'react';
import { Renderer } from '../renderer/Renderer';
import { RenderMode } from '../renderer/types';

interface WebGPUCanvasProps {
    mode: RenderMode;
    zoom: number;
    panX: number;
    panY: number;
    rendererRef: React.MutableRefObject<Renderer | null>;
    farthestPoint: { x: number; y: number };
    mousePosition: { x: number; y: number };
    setMousePosition: (pos: { x: number, y: number }) => void;
    isMouseDown: boolean;
    setIsMouseDown: (down: boolean) => void;
    onInit?: () => void;
}

const WebGPUCanvas: React.FC<WebGPUCanvasProps> = ({ mode, zoom, panX, panY, rendererRef, farthestPoint, mousePosition, setMousePosition, isMouseDown, setIsMouseDown, onInit }) => {
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const videoRef = useRef<HTMLVideoElement | null>(null);
    const animationFrameId = useRef<number>(0);
    const lastMouseAddTime = useRef(0);
    const [isPointerLocked, setIsPointerLocked] = useState(false);

    // Plasma Interaction Refs
    const dragStartPos = useRef<{x: number, y: number} | null>(null);
    const dragStartTime = useRef<number>(0);

    useEffect(() => {
        const handlePointerLockChange = () => {
            if (document.pointerLockElement === canvasRef.current) {
                setIsPointerLocked(true);
            } else {
                setIsPointerLocked(false);
            }
        };

        document.addEventListener('pointerlockchange', handlePointerLockChange, false);

        return () => {
            document.removeEventListener('pointerlockchange', handlePointerLockChange, false);
        };
    }, []);

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
                videoRef.current = document.createElement('video');
                videoRef.current.src = 'https://test.1ink.us/webgputs/big_buck_bunny_720p_surround.mp4';
                videoRef.current.crossOrigin = 'anonymous';
                videoRef.current.muted = true;
                videoRef.current.loop = true;
                videoRef.current.autoplay = true;
                videoRef.current.playsInline = true;
                await videoRef.current.play().catch(console.error);
                if (onInit) onInit();
            }
        })();
        return () => {
            cancelAnimationFrame(animationFrameId.current);
            renderer.destroy();
        };
    }, [rendererRef, onInit]);

 useEffect(() => {
        let active = true;
        const animate = () => {
            if (!active) return;
            if (rendererRef.current && videoRef.current) {
                // --- THIS IS THE CORRECTED LINE ---
                rendererRef.current.render(mode, videoRef.current, zoom, panX, panY, farthestPoint, mousePosition, isMouseDown);
            }
            animationFrameId.current = requestAnimationFrame(animate);
        };
        animate();
        return () => { active = false; cancelAnimationFrame(animationFrameId.current); };
    }, [mode, zoom, panX, panY, farthestPoint, mousePosition, isMouseDown, rendererRef]); // Added isMouseDown and rendererRef

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
        updateMousePosition(event); // Ensure position is updated on click
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

            // Simple velocity calculation
            // If drag was very fast, dt is small -> high velocity
            // We might want to cap it or scale it
            if (dt > 0.01) {
                const vx = dx / dt;
                const vy = dy / dt;

                // Fire if there is significant movement
                const speed = Math.sqrt(vx*vx + vy*vy);
                if (speed > 0.1) {
                    // Fire from the release point
                    rendererRef.current.firePlasma(currentX, currentY, vx * 0.5, vy * 0.5); // Scale down a bit
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

    const handleCanvasClick = () => {
        if (canvasRef.current) {
            canvasRef.current.requestPointerLock();
        }
    };

   return (
        <canvas ref={canvasRef} width="2048" height="2048" onMouseMove={handleCanvasMouseMove} onMouseDown={handleMouseDown} onMouseUp={handleMouseUp} onMouseLeave={handleMouseLeave} onClick={handleCanvasClick} className={isPointerLocked ? 'pointer-locked' : ''} />
    );
};

export default WebGPUCanvas;
