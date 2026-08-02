import { useState, useCallback, useRef, useEffect } from 'react';
import { RenderMode, ShaderEntry, InputSource } from '../renderer/types';
import { getShaderDefaults } from '../app/constants/shaderDefaults';
import {
  getAttractPool,
  getAttractDwellSeconds,
  ATTRACT_DEFAULT_DWELL_SEC,
} from '../app/constants/attractShowcasePool';
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
    const [generativeShowcaseDelay, setGenerativeShowcaseDelayState] = useState(ATTRACT_DEFAULT_DWELL_SEC);
    const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
    const lastMouseRef = useRef<{ x: number; y: number } | null>(null);
    const lastMidiSignalRef = useRef(0);
    const lockedRef = useRef(false);
    const activeRef = useRef(false);
    const baseDelayRef = useRef(ATTRACT_DEFAULT_DWELL_SEC);
    const advanceRef = useRef<() => void>(() => {});

    lockedRef.current = generativeShowcaseLocked;
    activeRef.current = generativeShowcaseActive;
    baseDelayRef.current = generativeShowcaseDelay;

    const clearAttractTimer = useCallback(() => {
        if (timerRef.current) {
            clearTimeout(timerRef.current);
            timerRef.current = null;
        }
    }, []);

    const setGenerativeShowcaseDelay = useCallback((seconds: number) => {
        baseDelayRef.current = seconds;
        setGenerativeShowcaseDelayState(seconds);
    }, []);

    const getShowcaseShaders = useCallback((): ShaderEntry[] => {
        return getAttractPool(availableModes, ratedShaders);
    }, [availableModes, ratedShaders]);

    const scheduleNextAttract = useCallback((shaderId: string) => {
        clearAttractTimer();
        if (!activeRef.current || lockedRef.current) return;
        const dwell = getAttractDwellSeconds(shaderId, baseDelayRef.current);
        timerRef.current = setTimeout(() => {
            advanceRef.current();
        }, dwell * 1000);
    }, [clearAttractTimer]);

    const advanceGenerativeShowcase = useCallback(() => {
        const pool = getShowcaseShaders();
        if (pool.length === 0) return;

        const nextShader = pickWeightedShader(pool, hasThumbnail);
        if (!nextShader) return;

        const inputSource: InputSource =
            nextShader.category === 'simulation' ? 'image' : 'generative';
        syncInputSourceToRenderer(inputSource);
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
        scheduleNextAttract(nextShader.id);
    }, [
        getShowcaseShaders,
        hasThumbnail,
        setMode,
        updateSlotParam,
        syncInputSourceToRenderer,
        setActiveGenerativeShader,
        setStatus,
        scheduleNextAttract,
    ]);

    advanceRef.current = advanceGenerativeShowcase;

    const startGenerativeShowcase = useCallback(() => {
        lockedRef.current = false;
        setGenerativeShowcaseLocked(false);
        setGenerativeShowcaseActive(true);
        activeRef.current = true;
        lastMouseRef.current = mousePosition ?? null;
        advanceGenerativeShowcase();
        setStatus('🎨 Attract mode on — move mouse or press MIDI to take control (Space to lock)');
    }, [advanceGenerativeShowcase, setStatus, mousePosition]);

    const stopGenerativeShowcase = useCallback(() => {
        activeRef.current = false;
        lockedRef.current = false;
        setGenerativeShowcaseActive(false);
        setGenerativeShowcaseLocked(false);
        clearAttractTimer();
        setStatus('Attract mode stopped.');
    }, [setStatus, clearAttractTimer]);

    const lockGenerativeShowcase = useCallback(() => {
        if (!activeRef.current) return;
        lockedRef.current = true;
        setGenerativeShowcaseLocked(true);
        clearAttractTimer();
        setStatus('🔒 Shader locked — mouse control active.');
    }, [setStatus, clearAttractTimer]);

    const unlockGenerativeShowcase = useCallback(() => {
        if (!activeRef.current) return;
        lockedRef.current = false;
        setGenerativeShowcaseLocked(false);
        advanceGenerativeShowcase();
        setStatus('🔓 Attract resumed — auto-switching shaders.');
    }, [advanceGenerativeShowcase, setStatus]);

    // Reschedule when base delay slider changes while attract is running unlocked
    useEffect(() => {
        if (!generativeShowcaseActive || generativeShowcaseLocked) {
            if (generativeShowcaseLocked) clearAttractTimer();
            return;
        }
        // Keep current shader on screen; only refresh the timeout with new base delay
        // by advancing once so schedule uses the updated baseDelayRef.
        // Do not auto-advance on mount of this effect if timer already pending —
        // scheduleNextAttract from last advance already holds the id.
    }, [generativeShowcaseDelay, generativeShowcaseActive, generativeShowcaseLocked, clearAttractTimer]);

    useEffect(() => () => clearAttractTimer(), [clearAttractTimer]);

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
    }, [
        generativeShowcaseActive,
        generativeShowcaseLocked,
        startGenerativeShowcase,
        stopGenerativeShowcase,
        lockGenerativeShowcase,
        unlockGenerativeShowcase,
    ]);

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
