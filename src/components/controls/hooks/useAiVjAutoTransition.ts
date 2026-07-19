import { useState } from 'react';

export function useAiVjAutoTransition() {
    const [autoTransitionOpen, setAutoTransitionOpen] = useState(false);
    const [autoTransitionEnabled, setAutoTransitionEnabled] = useState(false);
    const [autoTransitionSource, setAutoTransitionSource] = useState<'timer' | 'beat'>('timer');
    const [autoTransitionIntervalMs, setAutoTransitionIntervalMs] = useState(8000);
    const [autoTransitionDurationMs, setAutoTransitionDurationMs] = useState(2000);
    const [autoTransitionMode, setAutoTransitionMode] = useState<'randomize' | 'cyclePresets'>('randomize');

    return {
        autoTransitionOpen,
        setAutoTransitionOpen,
        autoTransitionEnabled,
        setAutoTransitionEnabled,
        autoTransitionSource,
        setAutoTransitionSource,
        autoTransitionIntervalMs,
        setAutoTransitionIntervalMs,
        autoTransitionDurationMs,
        setAutoTransitionDurationMs,
        autoTransitionMode,
        setAutoTransitionMode,
    };
}
