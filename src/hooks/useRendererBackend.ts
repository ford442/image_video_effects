import { useState, useCallback, useEffect, RefObject } from 'react';
import { RendererManager, RendererType } from '../renderer/RendererManager';
import { RenderMode, InputSource, SlotParams } from '../renderer/types';
import { ShaderEntry } from '../renderer/types';
import { resolveShaderId } from '../utils/resolveShaderId';

export interface UseRendererBackendOptions {
    rendererRef: RefObject<RendererManager | null>;
    modesRef: RefObject<RenderMode[]>;
    slotParamsRef: RefObject<SlotParams[]>;
    availableModesRef: RefObject<ShaderEntry[]>;
    inputSourceRef: RefObject<InputSource>;
    setStatus: (status: string) => void;
}

export interface UseRendererBackendReturn {
    activeRendererType: RendererType;
    jsFps: number;
    wasmFps: number;
    isRendererSwitching: boolean;
    rendererReady: boolean;
    supportsDeepWorkgroup: boolean;
    handleSwitchRenderer: (type: RendererType) => Promise<void>;
    onInitCanvas: () => void;
}

export function useRendererBackend({
    rendererRef,
    modesRef,
    slotParamsRef,
    availableModesRef,
    inputSourceRef,
    setStatus,
}: UseRendererBackendOptions): UseRendererBackendReturn {
    const [activeRendererType, setActiveRendererType] = useState<RendererType>('webgpu');
    const [jsFps, setJsFps] = useState(0);
    const [wasmFps, setWasmFps] = useState(0);
    const [isRendererSwitching, setIsRendererSwitching] = useState(false);
    const [rendererReady, setRendererReady] = useState(false);
    const [supportsDeepWorkgroup, setSupportsDeepWorkgroup] = useState(false);

    const handleSwitchRenderer = useCallback(async (type: RendererType) => {
        const manager = rendererRef.current;
        if (!manager) return;

        setIsRendererSwitching(true);
        setStatus(`Switching to ${type} renderer…`);

        const currentFps = manager.getCurrentFPS?.() ?? 0;
        if (activeRendererType === 'webgpu' || activeRendererType === 'js') {
            setJsFps(currentFps);
        } else if (activeRendererType === 'wasm') {
            setWasmFps(currentFps);
        }

        const ok = await manager.switchRenderer(type);

        if (ok) {
            setActiveRendererType(type);
            setStatus(`✅ Now using ${type === 'wasm' ? 'C++ WASM (experimental)' : type === 'webgpu' ? 'TypeScript WebGPU' : 'Canvas2D'} renderer.`);

            if (type === 'wasm' || type === 'webgpu') {
                await manager.resyncShaderStack({
                    modes: modesRef.current,
                    slotParams: slotParamsRef.current,
                    resolveShader: (shaderId) => availableModesRef.current.find(s => s.id === resolveShaderId(shaderId)),
                    inputSource: inputSourceRef.current,
                });
            }
        } else {
            setStatus(`⚠️ Failed to switch to ${type} renderer — staying on ${activeRendererType}.`);
        }
        setIsRendererSwitching(false);
    }, [activeRendererType, rendererRef, modesRef, slotParamsRef, availableModesRef, inputSourceRef, setStatus]);

    useEffect(() => {
        const interval = setInterval(() => {
            const manager = rendererRef.current;
            if (!manager) return;
            const fps = manager.getCurrentFPS?.() ?? 0;
            // Skip no-op React updates — 800ms setState thrash was contributing
            // to main-thread pressure alongside adaptive scale rebuilds.
            if (activeRendererType === 'wasm') {
                setWasmFps((prev) => (Math.abs(prev - fps) < 0.5 ? prev : fps));
            } else {
                setJsFps((prev) => (Math.abs(prev - fps) < 0.5 ? prev : fps));
            }
        }, 800);
        return () => clearInterval(interval);
    }, [activeRendererType, rendererRef]);

    const onInitCanvas = useCallback(() => {
        const manager = rendererRef.current;
        if (!manager) return;
        setActiveRendererType(manager.getActiveRendererType());
        setSupportsDeepWorkgroup(manager.getSupportsDeepWorkgroup());
        manager.setInputSource(inputSourceRef.current);
        setRendererReady(true);
    }, [rendererRef, inputSourceRef]);

    return {
        activeRendererType,
        jsFps,
        wasmFps,
        isRendererSwitching,
        rendererReady,
        supportsDeepWorkgroup,
        handleSwitchRenderer,
        onInitCanvas,
    };
}
