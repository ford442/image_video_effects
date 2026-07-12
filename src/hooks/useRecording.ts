import { useState, useCallback, useRef, useEffect, RefObject } from 'react';
import { RendererManager } from '../renderer/RendererManager';

export interface UseRecordingOptions {
    rendererRef: RefObject<RendererManager | null>;
    webgpuCanvasRef: RefObject<HTMLCanvasElement | null>;
    openRecordingShareModal: () => void;
    setStatus: (status: string) => void;
}

export interface UseRecordingReturn {
    isRecording: boolean;
    recordingCountdown: number;
    startRecording: () => Promise<void>;
    stopRecording: () => void;
}

export function useRecording({
    rendererRef,
    webgpuCanvasRef,
    openRecordingShareModal,
    setStatus,
}: UseRecordingOptions): UseRecordingReturn {
    const [isRecording, setIsRecording] = useState(false);
    const [recordingCountdown, setRecordingCountdown] = useState(8);
    const mediaRecorderRef = useRef<MediaRecorder | null>(null);
    const recordedChunksRef = useRef<Blob[]>([]);
    const recordingTimerRef = useRef<NodeJS.Timeout | null>(null);
    const wasmRecordingPromiseRef = useRef<Promise<Blob> | null>(null);
    const recordingFinishedRef = useRef(false);

    const finishRecordingBlob = useCallback((blob: Blob) => {
        if (recordingFinishedRef.current) return;
        recordingFinishedRef.current = true;

        const url = URL.createObjectURL(blob);

        const a = document.createElement('a');
        a.href = url;
        a.download = `pixelocity-clip-${Date.now()}.webm`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);

        openRecordingShareModal();
        setStatus('✅ Recording saved! Download started.');
        setTimeout(() => URL.revokeObjectURL(url), 1000);
    }, [openRecordingShareModal, setStatus]);

    const clearRecordingTimer = useCallback(() => {
        if (recordingTimerRef.current) {
            clearInterval(recordingTimerRef.current);
            recordingTimerRef.current = null;
        }
    }, []);

    const stopRecording = useCallback(() => {
        clearRecordingTimer();

        const manager = rendererRef.current;
        if (manager?.usesInternalRecording()) {
            manager.stopRendererRecording();
            manager.setRecording(false);
            wasmRecordingPromiseRef.current = null;
            setIsRecording(false);
            setRecordingCountdown(8);
            return;
        }

        if (mediaRecorderRef.current && mediaRecorderRef.current.state !== 'inactive') {
            mediaRecorderRef.current.stop();
        }

        setIsRecording(false);
        setRecordingCountdown(8);
        rendererRef.current?.setRecording?.(false);
    }, [clearRecordingTimer, rendererRef]);

    const startRecording = useCallback(async () => {
        const canvas = webgpuCanvasRef.current;
        const manager = rendererRef.current;
        if (!canvas) {
            setStatus('❌ Canvas not found for recording');
            return;
        }
        if (!manager) {
            setStatus('❌ Renderer not ready for recording');
            return;
        }

        recordingFinishedRef.current = false;

        try {
            if (manager.usesInternalRecording()) {
                setIsRecording(true);
                setRecordingCountdown(8);
                setStatus('🔴 Recording (WASM)… 8s');
                manager.setRecording(true);

                const recordingPromise = manager.startRecording(canvas, {
                    durationMs: 8000,
                    frameRate: 60,
                    videoBitsPerSecond: 8_000_000,
                });
                wasmRecordingPromiseRef.current = recordingPromise;

                recordingPromise
                    .then((blob) => {
                        finishRecordingBlob(blob);
                    })
                    .catch((e) => {
                        console.error('WASM recording failed:', e);
                        setStatus('❌ Recording failed. WASM readback may be unavailable.');
                    })
                    .finally(() => {
                        wasmRecordingPromiseRef.current = null;
                        setIsRecording(false);
                        setRecordingCountdown(8);
                        manager.setRecording(false);
                    });

                let count = 8;
                recordingTimerRef.current = setInterval(() => {
                    count -= 1;
                    setRecordingCountdown(count);
                    setStatus(`🔴 Recording (WASM)… ${count}s`);

                    if (count <= 0) {
                        stopRecording();
                    }
                }, 1000);

                return;
            }

            const stream = canvas.captureStream(60);

            let mimeType = 'video/webm;codecs=vp9';
            if (!MediaRecorder.isTypeSupported(mimeType)) {
                mimeType = 'video/webm;codecs=vp8';
                if (!MediaRecorder.isTypeSupported(mimeType)) {
                    mimeType = 'video/webm';
                }
            }

            const mediaRecorder = new MediaRecorder(stream, {
                mimeType,
                videoBitsPerSecond: 8000000,
            });

            mediaRecorderRef.current = mediaRecorder;
            recordedChunksRef.current = [];

            mediaRecorder.ondataavailable = (e) => {
                if (e.data.size > 0) {
                    recordedChunksRef.current.push(e.data);
                }
            };

            mediaRecorder.onstop = () => {
                const blob = new Blob(recordedChunksRef.current, { type: 'video/webm' });
                finishRecordingBlob(blob);
            };

            mediaRecorder.start(100);
            rendererRef.current?.setRecording?.(true);
            setIsRecording(true);
            setRecordingCountdown(8);
            setStatus('🔴 Recording… 8s');

            let count = 8;
            recordingTimerRef.current = setInterval(() => {
                count -= 1;
                setRecordingCountdown(count);
                setStatus(`🔴 Recording… ${count}s`);

                if (count <= 0) {
                    stopRecording();
                }
            }, 1000);
        } catch (e) {
            console.error('Recording failed:', e);
            setStatus('❌ Recording failed. Browser may not support this feature.');
        }
    }, [finishRecordingBlob, stopRecording, rendererRef, webgpuCanvasRef, setStatus]);

    useEffect(() => {
        return () => {
            clearRecordingTimer();
            const manager = rendererRef.current;
            if (manager?.usesInternalRecording()) {
                manager.stopRendererRecording();
            } else if (mediaRecorderRef.current && mediaRecorderRef.current.state !== 'inactive') {
                mediaRecorderRef.current.stop();
            }
        };
    }, [clearRecordingTimer, rendererRef]);

    return {
        isRecording,
        recordingCountdown,
        startRecording,
        stopRecording,
    };
}
