import { useState, useCallback, useRef, useEffect, RefObject } from 'react';
import { RendererManager } from '../renderer/RendererManager';
import {
    isGpuEncodeAvailable,
    loadGpuEncoder,
    readGpuEncodePreference,
    writeGpuEncodePreference,
} from '../recording/gpuEncodeSupport';
import type { GpuEncodeRecorder } from '../recording/gpuEncoder';

const CLIP_SECONDS = 8;
const CLIP_FPS = 60;
const CLIP_BITRATE = 8_000_000;

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
    /** Controls → Recording → GPU encode (WebCodecs). Off = MediaRecorder. */
    gpuEncode: boolean;
    gpuEncodeAvailable: boolean;
    setGpuEncode: (enabled: boolean) => void;
}

/**
 * Try Recording 2.0 (WebCodecs). Resolves null when no frame source or codec is
 * available so the caller keeps the MediaRecorder path.
 */
async function startGpuEncode(
    manager: RendererManager,
    canvas: HTMLCanvasElement,
): Promise<GpuEncodeRecorder | null> {
    const { GpuEncodeRecorder, canvasFrameSource, readbackFrameSource } = await loadGpuEncoder();
    const readback = manager.getFrameReadback();
    let usesCanvas = false;
    let source;
    if (readback) {
        source = readbackFrameSource(readback);
    } else if (manager.supportsCanvasFrameCapture() && manager.setCanvasCopySrc(true)) {
        source = canvasFrameSource(canvas);
        usesCanvas = true;
    } else {
        return null;
    }
    try {
        const recorder = await GpuEncodeRecorder.start(source, {
            width: canvas.width,
            height: canvas.height,
            fps: CLIP_FPS,
            bitrate: CLIP_BITRATE,
        });
        if (!recorder && usesCanvas) manager.setCanvasCopySrc(false);
        return recorder;
    } catch (e) {
        if (usesCanvas) manager.setCanvasCopySrc(false);
        throw e;
    }
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
    const gpuRecorderRef = useRef<GpuEncodeRecorder | null>(null);
    const gpuEncodeAvailable = isGpuEncodeAvailable();
    const [gpuEncode, setGpuEncodeState] = useState(() => gpuEncodeAvailable && readGpuEncodePreference());

    const setGpuEncode = useCallback((enabled: boolean) => {
        setGpuEncodeState(enabled);
        writeGpuEncodePreference(enabled);
    }, []);

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
        const gpuRecorder = gpuRecorderRef.current;
        if (gpuRecorder) {
            gpuRecorderRef.current = null;
            gpuRecorder.stop()
                .then(finishRecordingBlob)
                .catch((e) => {
                    console.error('GPU encode recording failed:', e);
                    setStatus('❌ GPU encode failed. Turn off GPU encode to use MediaRecorder.');
                })
                .finally(() => {
                    manager?.setCanvasCopySrc(false);
                    manager?.setRecording(false);
                });
            setIsRecording(false);
            setRecordingCountdown(CLIP_SECONDS);
            return;
        }
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
    }, [clearRecordingTimer, finishRecordingBlob, rendererRef, setStatus]);

    const startCountdown = useCallback((label: string) => {
        let count = CLIP_SECONDS;
        recordingTimerRef.current = setInterval(() => {
            count -= 1;
            setRecordingCountdown(count);
            setStatus(`🔴 Recording${label}… ${count}s`);
            if (count <= 0) {
                stopRecording();
            }
        }, 1000);
    }, [setStatus, stopRecording]);

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

        if (gpuEncode && gpuEncodeAvailable) {
            try {
                const recorder = await startGpuEncode(manager, canvas);
                if (recorder) {
                    gpuRecorderRef.current = recorder;
                    manager.setRecording(true);
                    setIsRecording(true);
                    setRecordingCountdown(CLIP_SECONDS);
                    setStatus(`🔴 Recording (GPU encode)… ${CLIP_SECONDS}s`);
                    startCountdown(' (GPU encode)');
                    return;
                }
                console.warn('[Recording] GPU encode unavailable for this backend/browser; using MediaRecorder');
            } catch (e) {
                console.warn('[Recording] GPU encode failed to start; using MediaRecorder:', e);
            }
        }

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

                startCountdown(' (WASM)');

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

            startCountdown('');
        } catch (e) {
            console.error('Recording failed:', e);
            setStatus('❌ Recording failed. Browser may not support this feature.');
        }
    }, [finishRecordingBlob, gpuEncode, gpuEncodeAvailable, startCountdown, rendererRef, webgpuCanvasRef, setStatus]);

    useEffect(() => {
        const currentRenderer = rendererRef.current;
        return () => {
            clearRecordingTimer();
            const gpuRecorder = gpuRecorderRef.current;
            if (gpuRecorder) {
                gpuRecorderRef.current = null;
                gpuRecorder.stop().catch(() => {}).finally(() => currentRenderer?.setCanvasCopySrc(false));
            } else if (currentRenderer?.usesInternalRecording()) {
                currentRenderer.stopRendererRecording();
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
        gpuEncode,
        gpuEncodeAvailable,
        setGpuEncode,
    };
}
