import { useState, useEffect, useRef, Dispatch, SetStateAction } from 'react';
import {
    ControlBinding,
    ControlBindingRegistry,
    ControlEvent,
    ControlAction,
    ControlTrigger,
    LiveActionsHandle,
    loadBindings,
    saveBindings,
} from '../../../services/controlBindings';
import {
    MidiControlAdapter,
    MIDIDevice,
    subscribeKeyEvents,
    captureKeyOnce,
} from '../../../services/midiControl';
import type { AutoTransitionConfig } from '../../../types/aiVj';
import { shouldShowMidiControls } from '../../../utils/deviceCapabilities';
import { hold as holdAudioParam, release as releaseAudioParam } from '../../../services/audioParamHold';

export interface UseLiveControlOptions {
    isAiVjMode: boolean;
    autoTransitionEnabled: boolean;
    setAutoTransitionEnabled: Dispatch<SetStateAction<boolean>>;
    onSetSlotParam?: (slot: number, param: string, value: number) => void;
    onRandomizeSlot?: (slot: number) => void;
    onRandomizeAllSlots?: () => void;
    onTriggerNextTransition?: () => Promise<void> | void;
    onStartAutoTransition?: (config: AutoTransitionConfig) => Promise<boolean> | boolean;
    onStopAutoTransition?: () => void;
    autoTransitionSource: 'timer' | 'beat';
    autoTransitionIntervalMs: number;
    autoTransitionDurationMs: number;
    autoTransitionMode: 'randomize' | 'cyclePresets';
}

export interface UseLiveControlReturn {
    liveControlOpen: boolean;
    setLiveControlOpen: Dispatch<SetStateAction<boolean>>;
    midiEnabled: boolean;
    setMidiEnabled: Dispatch<SetStateAction<boolean>>;
    midiDevices: MIDIDevice[];
    /** Pair CC 0–31 / 32–63 into 14-bit values (persisted, default off). */
    midiPair14Bit: boolean;
    setMidiPair14Bit: Dispatch<SetStateAction<boolean>>;
    armed: null | 'midi' | 'key';
    setArmed: Dispatch<SetStateAction<null | 'midi' | 'key'>>;
    learnedTrigger: ControlTrigger | null;
    setLearnedTrigger: Dispatch<SetStateAction<ControlTrigger | null>>;
    pendingAction: ControlAction;
    setPendingAction: Dispatch<SetStateAction<ControlAction>>;
    pendingSlot: number;
    setPendingSlot: Dispatch<SetStateAction<number>>;
    pendingParam: string;
    setPendingParam: Dispatch<SetStateAction<string>>;
    bindings: ControlBinding[];
    setBindings: Dispatch<SetStateAction<ControlBinding[]>>;
    /** When set, learn flow is pre-targeted to a param (click-to-learn UX). */
    learnTarget: 'param' | 'free' | null;
    startLearnForParam: (slot: number, param: string) => void;
    cancelLearn: () => void;
    confirmLearnBinding: () => void;
}

const MIDI_14BIT_STORAGE_KEY = 'vj_midi_14bit';

export function useLiveControl({
    isAiVjMode,
    autoTransitionEnabled,
    setAutoTransitionEnabled,
    onSetSlotParam,
    onRandomizeSlot,
    onRandomizeAllSlots,
    onTriggerNextTransition,
    onStartAutoTransition,
    onStopAutoTransition,
    autoTransitionSource,
    autoTransitionIntervalMs,
    autoTransitionDurationMs,
    autoTransitionMode,
}: UseLiveControlOptions): UseLiveControlReturn {
    const [liveControlOpen, setLiveControlOpen] = useState(false);
    const [midiEnabled, setMidiEnabled] = useState(false);
    const [midiDevices, setMidiDevices] = useState<MIDIDevice[]>([]);
    const [midiPair14Bit, setMidiPair14Bit] = useState<boolean>(() => {
        try { return localStorage.getItem(MIDI_14BIT_STORAGE_KEY) === '1'; } catch { return false; }
    });
    const [armed, setArmed] = useState<null | 'midi' | 'key'>(null);
    const [learnedTrigger, setLearnedTrigger] = useState<ControlTrigger | null>(null);
    const [pendingAction, setPendingAction] = useState<ControlAction>({ type: 'triggerTransition' });
    const [pendingSlot, setPendingSlot] = useState(0);
    const [pendingParam, setPendingParam] = useState('zoomParam1');
    const [bindings, setBindings] = useState<ControlBinding[]>(() => loadBindings());
    const [learnTarget, setLearnTarget] = useState<'param' | 'free' | null>(null);

    const midiAdapterRef = useRef<MidiControlAdapter | null>(null);
    const keyUnsubscribeRef = useRef<(() => void) | null>(null);
    const keyCaptureUnsubscribeRef = useRef<(() => void) | null>(null);
    const registryRef = useRef(new ControlBindingRegistry(bindings));
    const liveHandleRef = useRef<LiveActionsHandle>({
        setSlotParam: () => {},
        randomizeSlot: () => {},
        randomizeAll: () => {},
        triggerTransition: () => {},
        toggleAutoTransition: () => {},
    });
    const stopAutoTransitionRef = useRef(onStopAutoTransition);

    useEffect(() => {
        stopAutoTransitionRef.current = onStopAutoTransition;
    }, [onStopAutoTransition]);

    useEffect(() => {
        if (!autoTransitionEnabled || !isAiVjMode) {
            onStopAutoTransition?.();
            return;
        }
        void onStartAutoTransition?.({
            source: autoTransitionSource,
            intervalMs: autoTransitionIntervalMs,
            durationMs: autoTransitionDurationMs,
            mode: autoTransitionMode,
        });
    }, [
        autoTransitionEnabled,
        autoTransitionSource,
        autoTransitionIntervalMs,
        autoTransitionDurationMs,
        autoTransitionMode,
        isAiVjMode,
        onStartAutoTransition,
        onStopAutoTransition,
    ]);

    useEffect(() => () => {
        stopAutoTransitionRef.current?.();
    }, []);

    useEffect(() => {
        registryRef.current = new ControlBindingRegistry(bindings);
    }, [bindings]);

    useEffect(() => {
        saveBindings(bindings);
    }, [bindings]);

    // Click-to-learn on a param: freeze host audio on it until learn ends so the
    // slider does not move under the performer while they twist a knob.
    const learnHoldSlot = learnTarget === 'param' && pendingAction.type === 'setSlotParam' ? pendingAction.slot : null;
    const learnHoldParam = learnTarget === 'param' && pendingAction.type === 'setSlotParam' ? pendingAction.param : null;
    useEffect(() => {
        if (learnHoldSlot === null || learnHoldParam === null) return;
        holdAudioParam(learnHoldSlot, learnHoldParam);
        return () => releaseAudioParam(learnHoldSlot, learnHoldParam);
    }, [learnHoldSlot, learnHoldParam]);

    useEffect(() => {
        liveHandleRef.current = {
            setSlotParam: (slot, param, value) => onSetSlotParam?.(slot, param, value),
            randomizeSlot: (slot) => onRandomizeSlot?.(slot),
            randomizeAll: () => onRandomizeAllSlots?.(),
            triggerTransition: () => { void onTriggerNextTransition?.(); },
            toggleAutoTransition: () => {
                if (autoTransitionEnabled) {
                    setAutoTransitionEnabled(false);
                    onStopAutoTransition?.();
                } else if (isAiVjMode) {
                    setAutoTransitionEnabled(true);
                }
            },
        };
    }, [
        onSetSlotParam,
        onRandomizeSlot,
        onRandomizeAllSlots,
        onTriggerNextTransition,
        onStopAutoTransition,
        autoTransitionEnabled,
        isAiVjMode,
        setAutoTransitionEnabled,
    ]);

    const midiPair14BitRef = useRef(midiPair14Bit);
    useEffect(() => {
        midiPair14BitRef.current = midiPair14Bit;
        midiAdapterRef.current?.setPair14Bit(midiPair14Bit);
        try { localStorage.setItem(MIDI_14BIT_STORAGE_KEY, midiPair14Bit ? '1' : '0'); } catch { /* private mode */ }
    }, [midiPair14Bit]);

    // MIDI must stay live after learn closes the panel — bindings only fire while
    // the adapter is subscribed. Gate on midiEnabled alone (not liveControlOpen).
    useEffect(() => {
        if (!midiEnabled) {
            midiAdapterRef.current?.disable();
            midiAdapterRef.current = null;
            setMidiDevices([]);
            return;
        }

        const adapter = new MidiControlAdapter(undefined, { pair14Bit: midiPair14BitRef.current });
        midiAdapterRef.current = adapter;
        adapter.requestAccess().then((ok) => {
            if (!ok) return;
            setMidiDevices(adapter.getDevices());
            adapter.subscribe((event: ControlEvent) => handleControlEventRef.current(event));
        }).catch((err) => console.warn('[LiveControl] MIDI access failed:', err));

        return () => {
            adapter.disable();
            midiAdapterRef.current = null;
        };
    }, [midiEnabled]);

    // Keyboard bindings stay active when the panel is open OR any binding exists.
    const hasKeyBindings = bindings.some((b) => b.trigger.source === 'key');
    useEffect(() => {
        if (!liveControlOpen && !hasKeyBindings) return;
        keyUnsubscribeRef.current = subscribeKeyEvents((event: ControlEvent) =>
            handleControlEventRef.current(event)
        );
        return () => {
            keyUnsubscribeRef.current?.();
            keyUnsubscribeRef.current = null;
        };
    }, [liveControlOpen, hasKeyBindings]);

    useEffect(() => {
        if (armed !== 'key') return;
        keyCaptureUnsubscribeRef.current = captureKeyOnce((event: ControlEvent) => {
            setLearnedTrigger({ source: event.source, id: event.id });
            setArmed(null);
        });
        return () => {
            keyCaptureUnsubscribeRef.current?.();
            keyCaptureUnsubscribeRef.current = null;
        };
    }, [armed]);

    const handleControlEventRef = useRef((event: ControlEvent) => {
        void event;
    });

    handleControlEventRef.current = (event: ControlEvent) => {
        if (armed === 'midi' && (event.source === 'midi-cc' || event.source === 'midi-note')) {
            setLearnedTrigger({ source: event.source, id: event.id });
            setArmed(null);
            return;
        }
        if (armed === 'key' && event.source === 'key') {
            setLearnedTrigger({ source: event.source, id: event.id });
            setArmed(null);
            return;
        }
        registryRef.current.dispatch(event, liveHandleRef.current);
    };

    const startLearnForParam = (slot: number, param: string) => {
        setPendingSlot(slot);
        setPendingParam(param);
        setPendingAction({ type: 'setSlotParam', slot, param });
        setLearnedTrigger(null);
        setLearnTarget('param');
        setLiveControlOpen(true);
        if (shouldShowMidiControls()) {
            setMidiEnabled(true);
            setArmed('midi');
        } else {
            setArmed('key');
        }
    };

    const cancelLearn = () => {
        setArmed(null);
        setLearnedTrigger(null);
        setLearnTarget(null);
    };

    const confirmLearnBinding = () => {
        if (!learnedTrigger) return;
        setBindings(prev => {
            const registry = new ControlBindingRegistry(prev);
            registry.addBinding(learnedTrigger, pendingAction);
            return registry.getBindings();
        });
        setLearnedTrigger(null);
        setLearnTarget(null);
        setArmed(null);
    };

    return {
        liveControlOpen,
        setLiveControlOpen,
        midiEnabled,
        setMidiEnabled,
        midiDevices,
        midiPair14Bit,
        setMidiPair14Bit,
        armed,
        setArmed,
        learnedTrigger,
        setLearnedTrigger,
        pendingAction,
        setPendingAction,
        pendingSlot,
        setPendingSlot,
        pendingParam,
        setPendingParam,
        bindings,
        setBindings,
        learnTarget,
        startLearnForParam,
        cancelLearn,
        confirmLearnBinding,
    };
}
