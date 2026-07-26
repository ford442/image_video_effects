import { useState, useCallback, useRef, useEffect } from 'react';
import { RenderMode, ShaderEntry, InputSource } from '../renderer/types';
import { getShaderDefaults } from '../app/constants/shaderDefaults';
import { getAttractPool } from '../app/constants/attractShowcasePool';
import { pickWeightedShader } from '../utils/thumbnailWeightedPick';

export interface RatedShaderRef {
  id: string;
  stars: number;
  ratingCount: number;
}

export interface UseGenerativeShowcaseOptions {
    availableModes: ShaderEntry[];
    ratedShaders?: RatedShaderRef[];
    setMode: (index: number, mode: RenderMode) => void;
    updateSlotParam: (slotIndex: number, updates: Partial<{ zoomParam1: number; zoomParam2: number; zoomParam3: number; zoomParam4: number }>) => void;
    syncInputSourceToRenderer: (source: InputSource) => void;
    setActiveGenerativeShader: (id: string) => void;
    setStatus: (status: string) => void;
    /** First pointer engagement while attract is active (unlocked). */
    onEngagePointer?: () => void;
    /** First MIDI control event while attract is active (unlocked). */
    onEngageMidi?: () => void;
    /** Prefer shaders with preview thumbnails in rotation. */
    hasThumbnail?: (id: string) => boolean;
    isMouseDown?: boolean;
    mousePosition?: { x: number; y: number };
    midiEngageSignal?: number;
}

export interface UseGenerativeShowcaseReturn {
    generativeShowcaseActive: boolean;
    generativeShowcaseLocked: boolean;
    generativeShowcaseDelay: number;
    setGenerativeShowcaseDelay: (seconds: number) => void;
    startGenerativeShowcase: () => void;
    stopGenerativeShowcase: () => void;
    lockGenerativeShowcase: () => void;
    unlockGenerativeShowcase: () => void;
}

const MOUSE_MOVE_THRESHOLD = 0.02;

export function useGenerativeShowcase({
    availableModes,
    ratedShaders = [],
    setMode,
    updateSlotParam,
    syncInputSourceToRenderer,
    setActiveGenerativeShader,
    setStatus,
    hasThumbnail = () => false,
    isMouseDown = false,
    mousePosition,
    midiEngageSignal = 0,
}: UseGenerativeShowcaseOptions): UseGenerativeShowcaseReturn {
    const [generativeShowcaseActive, setGenerativeShowcaseActive] = useState(false);
    const [generativeShowcaseLocked, setGenerativeShowcaseLocked] = useState(false);
    const [generativeShowcaseDelay, setGenerativeShowcaseDelay] = useState(12);
    const generativeShowcaseTimerRef = useRef<NodeJS.Timeout | null>(null);
    const lastMouseRef = useRef<{ x: number; y: number } | null>(null);
    const lastMidiSignalRef = useRef(0);

    const getShowcaseShaders = useCallback((): ShaderEntry[] => {
        return getAttractPool(availableModes, ratedShaders);
    }, [availableModes, ratedShaders]);

    const advanceGenerativeShowcase = useCallback(() => {
        const genShaders = getShowcaseShaders();
        if (genShaders.length === 0) return;

        const nextShader = pickWeightedShader(genShaders, hasThumbnail);
        if (!nextShader) return;

        syncInputSourceToRenderer('generative');
        setActiveGenerativeShader(nextShader.id);

        setMode(0, nextShader.id as RenderMode);

        const defaults = getShaderDefaults(nextShader.id, nextShader.params?.length || 4);
        updateSlotParam(0, {
            zoomParam1: defaults[0],
            zoomParam2: defaults[1],
            zoomParam3: defaults[2],
            zoomParam4: defaults[3],
        });

        setStatus(`🎨 Attract: ${nextShader.name}`);
    }, [getShowcaseShaders, hasThumbnail, setMode, updateSlotParam, syncInputSourceToRenderer, setActiveGenerativeShader, setStatus]);

    const startGenerativeShowcase = useCallback(() => {
        setGenerativeShowcaseLocked(false);
        setGenerativeShowcaseActive(true);
        lastMouseRef.current = mousePosition ?? null;
        syncInputSourceToRenderer('generative');
        advanceGenerativeShowcase();
        setStatus('🎨 Attract mode on — move mouse or press MIDI to take control (Space to lock)');
    }, [advanceGenerativeShowcase, syncInputSourceToRenderer, setStatus, mousePosition]);

    const stopGenerativeShowcase = useCallback(() => {
        setGenerativeShowcaseActive(false);
        setGenerativeShowcaseLocked(false);
        if (generativeShowcaseTimerRef.current) {
            clearInterval(generativeShowcaseTimerRef.current);
            generativeShowcaseTimerRef.current = null;
        }
        setStatus('Attract mode stopped.');
    }, [setStatus]);

    const lockGenerativeShowcase = useCallback(() => {
        if (!generativeShowcaseActive) return;
        setGenerativeShowcaseLocked(true);
        if (generativeShowcaseTimerRef.current) {
            clearInterval(generativeShowcaseTimerRef.current);
            generativeShowcaseTimerRef.current = null;
        }
        setStatus('🔒 Shader locked — mouse control active.');
    }, [generativeShowcaseActive, setStatus]);

    const unlockGenerativeShowcase = useCallback(() => {
        if (!generativeShowcaseActive) return;
        setGenerativeShowcaseLocked(false);
        if (generativeShowcaseTimerRef.current) {
            clearInterval(generativeShowcaseTimerRef.current);
        }
        generativeShowcaseTimerRef.current = setInterval(() => {
            advanceGenerativeShowcase();
        }, generativeShowcaseDelay * 1000);
        setStatus('🔓 Attract resumed — auto-switching shaders.');
    }, [generativeShowcaseActive, generativeShowcaseDelay, advanceGenerativeShowcase, setStatus]);

    useEffect(() => {
        if (generativeShowcaseActive && !generativeShowcaseLocked) {
            if (generativeShowcaseTimerRef.current) {
                clearInterval(generativeShowcaseTimerRef.current);
            }
            generativeShowcaseTimerRef.current = setInterval(() => {
                advanceGenerativeShowcase();
            }, generativeShowcaseDelay * 1000);
        } else {
            if (generativeShowcaseTimerRef.current) {
                clearInterval(generativeShowcaseTimerRef.current);
                generativeShowcaseTimerRef.current = null;
            }
        }

        return () => {
            if (generativeShowcaseTimerRef.current) {
                clearInterval(generativeShowcaseTimerRef.current);
            }
        };
    }, [generativeShowcaseActive, generativeShowcaseLocked, generativeShowcaseDelay, advanceGenerativeShowcase]);

    // Mouse / pointer engagement → lock
    useEffect(() => {
        if (!generativeShowcaseActive || generativeShowcaseLocked) return;
        if (isMouseDown) {
            lockGenerativeShowcase();
            return;
        }
        if (!mousePosition) return;
        const prev = lastMouseRef.current;
        lastMouseRef.current = mousePosition;
        if (!prev) return;
        const dx = mousePosition.x - prev.x;
        const dy = mousePosition.y - prev.y;
        if (Math.hypot(dx, dy) > MOUSE_MOVE_THRESHOLD) {
            lockGenerativeShowcase();
        }
    }, [generativeShowcaseActive, generativeShowcaseLocked, isMouseDown, mousePosition, lockGenerativeShowcase]);

    // MIDI engagement → lock
    useEffect(() => {
        if (!generativeShowcaseActive || generativeShowcaseLocked) return;
        if (midiEngageSignal > 0 && midiEngageSignal !== lastMidiSignalRef.current) {
            lastMidiSignalRef.current = midiEngageSignal;
            lockGenerativeShowcase();
        }
    }, [midiEngageSignal, generativeShowcaseActive, generativeShowcaseLocked, lockGenerativeShowcase]);

    useEffect(() => {
        const handleKeyDown = (e: KeyboardEvent) => {
            if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;

            if (e.key === 'g' || e.key === 'G') {
                if (generativeShowcaseActive) {
                    stopGenerativeShowcase();
                } else {
                    startGenerativeShowcase();
                }
            }
            if (e.key === ' ') {
                e.preventDefault();
                if (generativeShowcaseActive) {
                    if (generativeShowcaseLocked) {
                        unlockGenerativeShowcase();
                    } else {
                        lockGenerativeShowcase();
                    }
                }
            }
        };

        window.addEventListener('keydown', handleKeyDown);
        return () => window.removeEventListener('keydown', handleKeyDown);
    }, [generativeShowcaseActive, generativeShowcaseLocked, startGenerativeShowcase, stopGenerativeShowcase, lockGenerativeShowcase, unlockGenerativeShowcase]);

    return {
        generativeShowcaseActive,
        generativeShowcaseLocked,
        generativeShowcaseDelay,
        setGenerativeShowcaseDelay,
        startGenerativeShowcase,
        stopGenerativeShowcase,
        lockGenerativeShowcase,
        unlockGenerativeShowcase,
    };
}
