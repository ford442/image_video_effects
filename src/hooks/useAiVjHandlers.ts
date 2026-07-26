import { useState, useCallback } from 'react';
import { RenderMode } from '../renderer/types';
import type { Alucinate } from '../AutoDJ';
import type { AIStatus, AutoTransitionConfig, ImageRecord, ShaderRecord } from '../types/aiVj';
import { ShaderEntry } from '../renderer/types';
import { savePreset } from '../services/vjPresets';
import { IMAGE_SUGGESTIONS_URL } from '../app/constants/fallbackContent';

export interface UseAiVjHandlersOptions {
    imageManifest: ImageRecord[];
    availableModes: ShaderEntry[];
    modes: RenderMode[];
    currentImageUrl: string | undefined;
    handleLoadImage: (url: string) => Promise<void>;
    handleUpdateStack: (ids: string[]) => void;
    handleUpdateParams: (paramsList: Record<string, number>[]) => void;
    handleApplyParamsDirect: (paramsList: Record<string, number>[]) => void;
    setStatus: (status: string) => void;
}

export interface UseAiVjHandlersReturn {
    aiVj: Alucinate | null;
    aiVjStatus: AIStatus;
    aiVjMessage: string;
    isAiVjMode: boolean;
    toggleAiVj: () => Promise<void>;
    handleGenerateFromVibe: (vibe: string) => Promise<void>;
    handleRandomizeParams: () => Promise<void>;
    handleTriggerNextTransition: () => Promise<void>;
    handleSavePreset: (name: string) => void;
    startAutoTransition: (config: AutoTransitionConfig) => Promise<boolean>;
    stopAutoTransition: () => void;
}

export function useAiVjHandlers({
    imageManifest,
    availableModes,
    modes,
    currentImageUrl,
    handleLoadImage,
    handleUpdateStack,
    handleUpdateParams,
    handleApplyParamsDirect,
    setStatus,
}: UseAiVjHandlersOptions): UseAiVjHandlersReturn {
    const [aiVj, setAiVj] = useState<Alucinate | null>(null);
    const [aiVjStatus, setAiVjStatus] = useState<AIStatus>('idle');
    const [aiVjMessage, setAiVjMessage] = useState('AI VJ is offline.');
    const [isAiVjMode, setIsAiVjMode] = useState(false);

    const toggleAiVj = useCallback(async () => {
        if (!aiVj) {
            if (imageManifest.length === 0 || availableModes.length === 0) {
                setStatus("Content not loaded yet, cannot start AI VJ.");
                return;
            }
            const { Alucinate: AlucinateClass } = await import(
                /* webpackChunkName: "auto-dj" */ '../AutoDJ'
            );
            const vj = new AlucinateClass(
                (url) => handleLoadImage(url),
                handleUpdateStack,
                () => {
                    const imgRecord = imageManifest.find(img => img.url === currentImageUrl) || null;
                    const shaderEntry = availableModes.find(m => m.id === modes[0]) || null;
                    const shaderRecord: ShaderRecord | null = shaderEntry ? {
                        id: shaderEntry.id,
                        name: shaderEntry.name,
                        category: shaderEntry.category || 'image',
                        description: shaderEntry.description,
                        tags: shaderEntry.tags || [],
                    } : null;
                    return { currentImage: imgRecord, currentShader: shaderRecord };
                },
                {
                    applyParamsDirect: handleApplyParamsDirect,
                }
            );
            vj.onStatusChange = (s, m) => { setAiVjStatus(s); setAiVjMessage(m); };
            vj.onUpdateParams = handleUpdateParams;
            setAiVj(vj);
            setIsAiVjMode(true);
            await vj.initialize(imageManifest, IMAGE_SUGGESTIONS_URL);
            if (vj.status === 'ready') {
                vj.start();
            }
        } else {
            if (isAiVjMode) {
                aiVj.stop();
                setIsAiVjMode(false);
            } else {
                if (aiVj.status === 'ready') {
                    if (aiVj.start()) {
                        setIsAiVjMode(true);
                    }
                } else {
                    await aiVj.initialize(imageManifest, IMAGE_SUGGESTIONS_URL);
                    if (aiVj.start()) {
                        setIsAiVjMode(true);
                    }
                }
            }
        }
    }, [aiVj, isAiVjMode, availableModes, modes, handleLoadImage, imageManifest, currentImageUrl, handleUpdateStack, handleUpdateParams, handleApplyParamsDirect, setStatus]);

    const handleGenerateFromVibe = useCallback(async (vibe: string) => {
        if (!aiVj) {
            setStatus('AI VJ not initialized. Please start AI VJ first.');
            return;
        }
        await aiVj.generateFromVibe(vibe);
    }, [aiVj, setStatus]);

    const handleRandomizeParams = useCallback(async () => {
        if (!aiVj) return;
        await aiVj.randomizeActiveParams();
    }, [aiVj]);

    const handleTriggerNextTransition = useCallback(async () => {
        if (!aiVj) return;
        await aiVj.triggerNextTransition();
    }, [aiVj]);

    const handleSavePreset = useCallback((name: string) => {
        if (!aiVj) return;
        const shaderIds = aiVj.getActiveShaderIds();
        const params = aiVj.getCurrentParams();
        if (shaderIds.length === 0 || params.length === 0) return;
        savePreset(name, shaderIds, params);
    }, [aiVj]);

    const startAutoTransition = useCallback(async (config: AutoTransitionConfig) => {
        if (!aiVj) return false;
        return aiVj.startAutoTransition(config);
    }, [aiVj]);

    const stopAutoTransition = useCallback(() => {
        aiVj?.stopAutoTransition();
    }, [aiVj]);

    return {
        aiVj,
        aiVjStatus,
        aiVjMessage,
        isAiVjMode,
        toggleAiVj,
        handleGenerateFromVibe,
        handleRandomizeParams,
        handleTriggerNextTransition,
        handleSavePreset,
        startAutoTransition,
        stopAutoTransition,
    };
}
