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
import { AutoTransitionConfig } from '../../../AutoDJ';

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
}

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
    const [armed, setArmed] = useState<null | 'midi' | 'key'>(null);
    const [learnedTrigger, setLearnedTrigger] = useState<ControlTrigger | null>(null);
    const [pendingAction, setPendingAction] = useState<ControlAction>({ type: 'triggerTransition' });
    const [pendingSlot, setPendingSlot] = useState(0);
    const [pendingParam, setPendingParam] = useState('zoomParam1');
    const [bindings, setBindings] = useState<ControlBinding[]>(() => loadBindings());

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
        onStartAutoTransition?.({
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

    useEffect(() => {
        liveHandleRef.current = {
            setSlotParam: (slot, param, value) => onSetSlotParam?.(slot, param, value),
            randomizeSlot: (slot) => onRandomizeSlot?.(slot),
            randomizeAll: () => onRandomizeAllSlots?.(),
            triggerTransition: () => { onTriggerNextTransition?.(); },
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

    useEffect(() => {
        if (!liveControlOpen || !midiEnabled) {
            midiAdapterRef.current?.disable();
            midiAdapterRef.current = null;
            setMidiDevices([]);
            return;
        }

        const adapter = new MidiControlAdapter();
        midiAdapterRef.current = adapter;
        adapter.requestAccess().then((ok) => {
            if (!ok) return;
            setMidiDevices(adapter.getDevices());
            adapter.subscribe((event: ControlEvent) => handleControlEventRef.current(event));
        });

        return () => {
            adapter.disable();
            midiAdapterRef.current = null;
        };
    }, [liveControlOpen, midiEnabled]);

    useEffect(() => {
        if (!liveControlOpen) return;
        keyUnsubscribeRef.current = subscribeKeyEvents((event: ControlEvent) =>
            handleControlEventRef.current(event)
        );
        return () => {
            keyUnsubscribeRef.current?.();
            keyUnsubscribeRef.current = null;
        };
    }, [liveControlOpen]);

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

    return {
        liveControlOpen,
        setLiveControlOpen,
        midiEnabled,
        setMidiEnabled,
        midiDevices,
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
    };
}
