import { useState, useCallback, useRef, useEffect } from 'react';
import { RenderMode, InputSource, ShaderCategory } from '../renderer/types';

export interface UseWebcamOptions {
    syncInputSourceToRenderer: (source: InputSource) => void;
    setShaderCategory: (category: ShaderCategory) => void;
    setStatus: (status: string) => void;
    setMode: (index: number, mode: RenderMode) => void;
    setActiveSlot: (index: number) => void;
}

export interface UseWebcamReturn {
    isWebcamActive: boolean;
    webcamError: string | null;
    showWebcamShaderSuggestions: boolean;
    videoElementRef: React.RefObject<HTMLVideoElement | null>;
    startWebcam: () => Promise<void>;
    stopWebcam: () => void;
    applyWebcamFunShader: (shaderId: string) => void;
}

export function useWebcam({
    syncInputSourceToRenderer,
    setShaderCategory,
    setStatus,
    setMode,
    setActiveSlot,
}: UseWebcamOptions): UseWebcamReturn {
    const [isWebcamActive, setIsWebcamActive] = useState(false);
    const [webcamError, setWebcamError] = useState<string | null>(null);
    const [showWebcamShaderSuggestions, setShowWebcamShaderSuggestions] = useState(false);
    const videoElementRef = useRef<HTMLVideoElement | null>(null);
    const streamRef = useRef<MediaStream | null>(null);

    const startWebcam = useCallback(async () => {
        try {
            setWebcamError(null);
            const stream = await navigator.mediaDevices.getUserMedia({
                video: {
                    facingMode: "user",
                    width: { ideal: 1280 },
                    height: { ideal: 720 }
                }
            });
            streamRef.current = stream;
            
            if (!videoElementRef.current) {
                const video = document.createElement('video');
                video.autoplay = true;
                video.playsInline = true;
                video.muted = true;
                video.style.position = 'absolute';
                video.style.width = '1px';
                video.style.height = '1px';
                video.style.opacity = '0';
                video.style.pointerEvents = 'none';
                video.style.zIndex = '-1';
                document.body.appendChild(video);
                videoElementRef.current = video;
            }
            
            videoElementRef.current.srcObject = stream;
            await videoElementRef.current.play();
            
            setIsWebcamActive(true);
            syncInputSourceToRenderer('webcam');
            setShaderCategory('image');
            setShowWebcamShaderSuggestions(true);
            setStatus('📹 Webcam active! Try fun shaders below.');
        } catch (err: unknown) {
            console.error('Webcam error:', err);
            const error = err as { name?: string };
            setWebcamError(error.name === 'NotAllowedError' 
                ? 'Camera permission denied. Please allow camera access and try again.' 
                : 'Failed to access webcam. Please check your camera.');
            setStatus('❌ Camera permission denied');
        }
    }, [syncInputSourceToRenderer, setShaderCategory, setStatus]);

    const stopWebcam = useCallback(() => {
        if (streamRef.current) {
            streamRef.current.getTracks().forEach(track => track.stop());
            streamRef.current = null;
        }
        if (videoElementRef.current) {
            videoElementRef.current.pause();
            videoElementRef.current.srcObject = null;
        }
        setIsWebcamActive(false);
        syncInputSourceToRenderer('image');
        setShowWebcamShaderSuggestions(false);
        setStatus('Webcam stopped');
    }, [syncInputSourceToRenderer, setStatus]);

    const applyWebcamFunShader = useCallback((shaderId: string) => {
        setMode(0, shaderId as RenderMode);
        setActiveSlot(0);
    }, [setMode, setActiveSlot]);

    useEffect(() => {
        return () => {
            if (streamRef.current) {
                streamRef.current.getTracks().forEach(track => track.stop());
            }
            if (videoElementRef.current) {
                videoElementRef.current.remove();
            }
        };
    }, []);

    return {
        isWebcamActive,
        webcamError,
        showWebcamShaderSuggestions,
        videoElementRef,
        startWebcam,
        stopWebcam,
        applyWebcamFunShader,
    };
}
