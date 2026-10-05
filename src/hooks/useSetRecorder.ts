import { useCallback, useEffect, useRef, useState } from 'react';
import type { RenderMode, SlotParams } from '../renderer/types';
import { isGrabbed } from '../services/audioParamHold';
import { MAX_TIMELINE_EVENTS, VjTimeline, VjTimelineEvent } from '../services/vjSetExport';
import { applyEvents, diffSnapshot, firstEventAfter, RECORDER_HZ, RecorderSnapshot, takeSnapshot } from '../services/vjSetRecorder';

export type SetRecorderState = 'idle' | 'recording' | 'playing';

export interface UseSetRecorderOptions {
    modes: RenderMode[];
    slotParams: SlotParams[];
    setMode: (index: number, mode: RenderMode) => void;
    /** Same path as MIDI/OSC (touches the audio hold so audio won't fight playback). */
    onSetSlotParam?: (slot: number, param: string, value: number) => void;
}

export interface UseSetRecorderReturn {
    recorderState: SetRecorderState;
    timeline: VjTimeline | null;
    setTimeline: (timeline: VjTimeline | null) => void;
    /** ms into the current recording / playback. */
    elapsedMs: number;
    startRecording: () => void;
    stopRecording: () => void;
    startPlayback: () => void;
    stopPlayback: () => void;
    /** Recording stopped itself at the event cap. */
    hitCap: boolean;
}

const now = () => (typeof performance !== 'undefined' ? performance.now() : Date.now());

/**
 * Set recorder: samples slot shaders + sliders at 20 Hz into a diffed timeline
 * (stored in the VJ set JSON `timeline` field) and plays it back through the
 * same param path as MIDI/OSC. A slider the performer is holding is skipped
 * during playback, so you can ride a fader over a recorded set.
 */
export function useSetRecorder({ modes, slotParams, setMode, onSetSlotParam }: UseSetRecorderOptions): UseSetRecorderReturn {
    const [recorderState, setRecorderState] = useState<SetRecorderState>('idle');
    const [timeline, setTimelineState] = useState<VjTimeline | null>(null);
    const [elapsedMs, setElapsedMs] = useState(0);
    const [hitCap, setHitCap] = useState(false);

    const modesRef = useRef(modes);
    const paramsRef = useRef(slotParams);
    modesRef.current = modes;
    paramsRef.current = slotParams;
    const setModeRef = useRef(setMode);
    const setParamRef = useRef(onSetSlotParam);
    setModeRef.current = setMode;
    setParamRef.current = onSetSlotParam;

    const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
    const rafRef = useRef<number | null>(null);

    const clearLoops = () => {
        if (timerRef.current) clearInterval(timerRef.current);
        timerRef.current = null;
        if (rafRef.current !== null) cancelAnimationFrame(rafRef.current);
        rafRef.current = null;
    };

    useEffect(() => clearLoops, []);

    const setTimeline = useCallback((t: VjTimeline | null) => {
        clearLoops();
        setRecorderState('idle');
        setElapsedMs(0);
        setTimelineState(t);
    }, []);

    const stopRecording = useCallback(() => {
        clearLoops();
        setRecorderState(s => (s === 'recording' ? 'idle' : s));
    }, []);

    const startRecording = useCallback(() => {
        clearLoops();
        setHitCap(false);
        const events: VjTimelineEvent[] = [];
        const t0 = now();
        let last: RecorderSnapshot | null = null;
        const sample = () => {
            const t = Math.round(now() - t0);
            const snap = takeSnapshot(modesRef.current, paramsRef.current);
            const diff = diffSnapshot(last, snap, t);
            last = last ? applyEvents(last, diff) : snap;
            if (events.length + diff.length > MAX_TIMELINE_EVENTS) {
                setHitCap(true);
                stopRecording();
                return;
            }
            events.push(...diff);
            // Publish a fresh object so React sees the update (cheap: same array).
            setTimelineState({ hz: RECORDER_HZ, durationMs: t, events });
            setElapsedMs(t);
        };
        sample();
        timerRef.current = setInterval(sample, 1000 / RECORDER_HZ);
        setRecorderState('recording');
    }, [stopRecording]);

    const stopPlayback = useCallback(() => {
        clearLoops();
        setRecorderState(s => (s === 'playing' ? 'idle' : s));
    }, []);

    const startPlayback = useCallback(() => {
        const tl = timeline;
        if (!tl || tl.events.length === 0) return;
        clearLoops();
        const t0 = now();
        let cursor = 0;
        let lastUi = 0;
        const step = () => {
            const t = now() - t0;
            const end = firstEventAfter(tl.events, t);
            for (; cursor < end; cursor++) {
                const e = tl.events[cursor];
                if (e.kind === 'shader') {
                    if (modesRef.current[e.slot] !== e.value) setModeRef.current(e.slot, e.value);
                } else if (!isGrabbed(e.slot, e.key) && e.slot < modesRef.current.length) {
                    setParamRef.current?.(e.slot, e.key, e.value);
                }
            }
            if (t - lastUi > 100) {
                lastUi = t;
                setElapsedMs(Math.round(t));
            }
            if (cursor >= tl.events.length && t >= tl.durationMs) {
                rafRef.current = null;
                setElapsedMs(tl.durationMs);
                setRecorderState('idle');
                return;
            }
            rafRef.current = requestAnimationFrame(step);
        };
        setRecorderState('playing');
        rafRef.current = requestAnimationFrame(step);
    }, [timeline]);

    return {
        recorderState,
        timeline,
        setTimeline,
        elapsedMs,
        startRecording,
        stopRecording,
        startPlayback,
        stopPlayback,
        hitCap,
    };
}
