import { useEffect, useRef, useState, Dispatch, SetStateAction } from 'react';
import type { RenderMode, ShaderEntry } from '../../../renderer/types';
import {
    DEFAULT_OSC_WS_URL,
    OSC_ENABLED_STORAGE_KEY,
    OSC_URL_STORAGE_KEY,
    loadOscBridge,
    oscFlagFromSearch,
    oscWsUrlFromSearch,
} from '../../../services/osc/oscFlags';
import type { OscActionsHandle, OscBridgeStatus } from '../../../services/osc/oscBridge';

export interface UseOscControlOptions {
    modes: RenderMode[];
    availableModes: ShaderEntry[];
    setMode: (index: number, mode: RenderMode) => void;
    onSetSlotParam?: (slot: number, param: string, value: number) => void;
    onTriggerNextTransition?: () => Promise<void> | void;
    setAudioReactiveAmount?: (amount: number) => void;
}

export interface UseOscControlReturn {
    oscEnabled: boolean;
    setOscEnabled: Dispatch<SetStateAction<boolean>>;
    oscUrl: string;
    setOscUrl: Dispatch<SetStateAction<string>>;
    oscStatus: OscBridgeStatus | 'off';
    oscStatusDetail: string | null;
    oscLastAddress: string | null;
}

function readStorage(key: string): string | null {
    try { return localStorage.getItem(key); } catch { return null; }
}

function writeStorage(key: string, value: string): void {
    try { localStorage.setItem(key, value); } catch { /* private mode */ }
}

/**
 * Opt-in OSC → WebSocket bridge (`?osc=1` or the Studio toggle; default off).
 * The decoder/socket live in the lazy "osc" chunk and load only when enabled.
 */
export function useOscControl({
    modes,
    availableModes,
    setMode,
    onSetSlotParam,
    onTriggerNextTransition,
    setAudioReactiveAmount,
}: UseOscControlOptions): UseOscControlReturn {
    const [oscEnabled, setOscEnabled] = useState<boolean>(
        () => oscFlagFromSearch() ?? readStorage(OSC_ENABLED_STORAGE_KEY) === '1',
    );
    const [oscUrl, setOscUrl] = useState<string>(
        () => oscWsUrlFromSearch() ?? readStorage(OSC_URL_STORAGE_KEY) ?? DEFAULT_OSC_WS_URL,
    );
    const [oscStatus, setOscStatus] = useState<OscBridgeStatus | 'off'>('off');
    const [oscStatusDetail, setOscStatusDetail] = useState<string | null>(null);
    const [oscLastAddress, setOscLastAddress] = useState<string | null>(null);

    // Handle is rebuilt every render and read per packet, so the socket never
    // reconnects just because a callback identity changed.
    const handle: OscActionsHandle = {
        setSlotParam: (slot, param, value) => {
            if (slot < modes.length) onSetSlotParam?.(slot, param, value);
        },
        setSlotShader: (slot, shaderId) => {
            if (slot >= modes.length) return;
            if (shaderId === 'none' || availableModes.some(m => m.id === shaderId)) setMode(slot, shaderId);
        },
        triggerTransition: () => { void onTriggerNextTransition?.(); },
        setAudioAmount: (value) => setAudioReactiveAmount?.(value),
    };
    const handleRef = useRef<OscActionsHandle>(handle);
    handleRef.current = handle;

    useEffect(() => {
        writeStorage(OSC_ENABLED_STORAGE_KEY, oscEnabled ? '1' : '0');
    }, [oscEnabled]);

    useEffect(() => {
        writeStorage(OSC_URL_STORAGE_KEY, oscUrl);
    }, [oscUrl]);

    useEffect(() => {
        if (!oscEnabled) {
            setOscStatus('off');
            setOscStatusDetail(null);
            return;
        }
        let cancelled = false;
        let stop: (() => void) | null = null;
        let lastAddressAt = 0;
        loadOscBridge().then(({ OscBridge }) => {
            if (cancelled) return;
            const bridge = new OscBridge({
                url: oscUrl,
                getHandle: () => handleRef.current,
                onStatus: (status, detail) => {
                    if (cancelled) return;
                    setOscStatus(status);
                    setOscStatusDetail(detail ?? null);
                },
                onMessage: (msg) => {
                    // Throttle UI updates — a fader can send hundreds of msgs/s.
                    const now = performance.now();
                    if (now - lastAddressAt < 150) return;
                    lastAddressAt = now;
                    setOscLastAddress(msg.address);
                },
            });
            bridge.start();
            stop = () => bridge.stop();
        }).catch((err) => {
            if (cancelled) return;
            setOscStatus('error');
            setOscStatusDetail(`failed to load OSC module: ${String(err)}`);
        });
        return () => {
            cancelled = true;
            stop?.();
        };
    }, [oscEnabled, oscUrl]);

    return { oscEnabled, setOscEnabled, oscUrl, setOscUrl, oscStatus, oscStatusDetail, oscLastAddress };
}
