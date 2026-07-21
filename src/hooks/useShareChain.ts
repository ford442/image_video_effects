import { useState, useEffect, useCallback, RefObject } from 'react';
import { RenderMode, ShaderEntry, InputSource, SlotParams } from '../renderer/types';
import { Alucinate } from '../AutoDJ';
import { buildCatalog } from '../services/shaderCatalog';
import { mapVJStackToSharedChain } from '../services/vjToSharedChain';
import {
    SharedChain,
    encodeChain,
    decodeChain,
    buildSharedChain,
    expandSharedChain,
    MAX_SHARED_SLOTS,
} from '../services/layerChainShare';

const SHARE_CHAIN_PARAM = 'chain';

export interface UseShareChainOptions {
    modes: RenderMode[];
    activeSlot: number;
    slotParams: SlotParams[];
    inputSource: InputSource;
    currentImageUrl: string | undefined;
    activeGenerativeShader: string;
    availableModesRef: RefObject<ShaderEntry[]>;
    aiVj: Alucinate | null;
    setMode: (index: number, mode: RenderMode) => void;
    setActiveSlot: (index: number) => void;
    updateSlotParam: (slotIndex: number, updates: Partial<SlotParams>) => void;
    syncInputSourceToRenderer: (source: InputSource) => void;
    setActiveGenerativeShader: (id: string) => void;
    handleLoadImage: (url: string) => Promise<void>;
    startWebcam: () => void;
    setStatus: (status: string) => void;
}

export interface UseShareChainReturn {
    showShareModal: boolean;
    setShowShareModal: React.Dispatch<React.SetStateAction<boolean>>;
    shareableLink: string;
    setShareableLink: React.Dispatch<React.SetStateAction<string>>;
    shareVibeText: string;
    setShareVibeText: React.Dispatch<React.SetStateAction<string>>;
    generateShareableLink: () => string;
    buildVjChainString: () => Promise<string>;
    handleShareVjSet: () => Promise<void>;
    applySharedChain: (chain: SharedChain) => void;
    copyChainShareLink: () => Promise<void>;
    getCurrentChain: () => SharedChain | null;
    openRecordingShareModal: () => void;
}

export function useShareChain({
    modes,
    activeSlot,
    slotParams,
    inputSource,
    currentImageUrl,
    activeGenerativeShader,
    availableModesRef,
    aiVj,
    setMode,
    setActiveSlot,
    updateSlotParam,
    syncInputSourceToRenderer,
    setActiveGenerativeShader,
    handleLoadImage,
    startWebcam,
    setStatus,
}: UseShareChainOptions): UseShareChainReturn {
    const [showShareModal, setShowShareModal] = useState(false);
    const [shareableLink, setShareableLink] = useState('');
    const [shareVibeText, setShareVibeText] = useState('');

    const generateShareableLink = useCallback(() => {
        const params = new URLSearchParams();

        params.set('shader', modes[0]);
        params.set('slot', activeSlot.toString());

        const params1 = slotParams[activeSlot];
        if (params1) {
            params.set('p1', params1.zoomParam1.toFixed(2));
            params.set('p2', params1.zoomParam2.toFixed(2));
            params.set('p3', params1.zoomParam3.toFixed(2));
            params.set('p4', params1.zoomParam4.toFixed(2));
            params.set('light', params1.lightStrength.toFixed(2));
            params.set('ambient', params1.ambient.toFixed(2));
        }

        params.set('source', inputSource);
        if (inputSource === 'webcam') {
            params.set('webcam', 'true');
        }
        if (currentImageUrl) {
            params.set('img', encodeURIComponent(currentImageUrl));
        }

        if (inputSource === 'generative' && activeGenerativeShader) {
            params.set('gen', activeGenerativeShader);
        }

        const hash = params.toString();
        const baseUrl = window.location.origin + window.location.pathname;
        return `${baseUrl}#${hash}`;
    }, [modes, activeSlot, slotParams, inputSource, currentImageUrl, activeGenerativeShader]);

    const restoreStateFromHash = useCallback(() => {
        const hash = window.location.hash.slice(1);
        if (!hash) return;

        try {
            const params = new URLSearchParams(hash);

            const shader = params.get('shader');
            if (shader) {
                setMode(0, shader as RenderMode);
            }

            const slot = params.get('slot');
            if (slot) {
                setActiveSlot(parseInt(slot, 10));
            }

            const updates: Partial<SlotParams> = {};
            const p1 = params.get('p1');
            const p2 = params.get('p2');
            const p3 = params.get('p3');
            const p4 = params.get('p4');
            const light = params.get('light');
            const ambient = params.get('ambient');

            if (p1) updates.zoomParam1 = parseFloat(p1);
            if (p2) updates.zoomParam2 = parseFloat(p2);
            if (p3) updates.zoomParam3 = parseFloat(p3);
            if (p4) updates.zoomParam4 = parseFloat(p4);
            if (light) updates.lightStrength = parseFloat(light);
            if (ambient) updates.ambient = parseFloat(ambient);

            if (Object.keys(updates).length > 0) {
                updateSlotParam(slot ? parseInt(slot, 10) : 0, updates);
            }

            const source = params.get('source');
            if (source) {
                syncInputSourceToRenderer(source as InputSource);
                if (source === 'webcam') {
                    setTimeout(() => startWebcam(), 1000);
                }
            }

            const img = params.get('img');
            if (img && source !== 'webcam') {
                handleLoadImage(decodeURIComponent(img));
            }

            const gen = params.get('gen');
            if (gen) {
                setActiveGenerativeShader(gen);
                syncInputSourceToRenderer('generative');
            }

            setStatus('🎉 Shared state restored!');
        } catch (e) {
            console.error('Failed to restore state from hash:', e);
        }
    }, [
        setMode,
        setActiveSlot,
        updateSlotParam,
        syncInputSourceToRenderer,
        setActiveGenerativeShader,
        handleLoadImage,
        startWebcam,
        setStatus,
    ]);

    useEffect(() => {
        restoreStateFromHash();
    }, [restoreStateFromHash]);

    const applySharedChain = useCallback((chain: SharedChain) => {
        const { modes: sharedModes, slotParams: sharedParams } = expandSharedChain(chain);
        const known = availableModesRef.current;

        sharedModes.forEach((shaderId, index) => {
            if (index >= MAX_SHARED_SLOTS) return;

            if (!shaderId || shaderId === 'none') {
                setMode(index, 'none');
                return;
            }

            const exists = known.length === 0 || known.some(m => m.id === shaderId);
            if (!exists) {
                console.warn(`[layerChainShare] skipping unknown shader id "${shaderId}" for slot ${index}`);
                return;
            }

            setMode(index, shaderId as RenderMode);
            updateSlotParam(index, sharedParams[index]);
        });

        setStatus('🔗 Shared chain loaded!');
    }, [setMode, updateSlotParam, availableModesRef, setStatus]);

    const generateChainShareLink = useCallback(() => {
        const chain = buildSharedChain(modes, slotParams);
        const encoded = encodeChain(chain);
        const url = new URL(window.location.href);
        url.search = '';
        url.hash = '';
        url.searchParams.set(SHARE_CHAIN_PARAM, encoded);
        return url.toString();
    }, [modes, slotParams]);

    const copyChainShareLink = useCallback(async () => {
        try {
            const link = generateChainShareLink();
            await navigator.clipboard.writeText(link);
            setStatus('🔗 Chain share link copied to clipboard!');
        } catch (e) {
            console.error('Failed to copy chain share link:', e);
            setStatus('❌ Failed to copy share link');
        }
    }, [generateChainShareLink, setStatus]);

    useEffect(() => {
        if (typeof window === 'undefined') return;
        const params = new URLSearchParams(window.location.search);
        const encoded = params.get(SHARE_CHAIN_PARAM);
        if (!encoded) return;

        const chain = decodeChain(encoded);
        if (!chain) {
            console.warn('[layerChainShare] ignoring invalid chain share link');
        } else {
            applySharedChain(chain);
        }

        params.delete(SHARE_CHAIN_PARAM);
        const newSearch = params.toString();
        const newUrl = `${window.location.pathname}${newSearch ? `?${newSearch}` : ''}${window.location.hash}`;
        window.history.replaceState(null, '', newUrl);
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    const buildVjChainString = useCallback(async (): Promise<string> => {
        if (!aiVj) return '';
        const shaderIds = aiVj.getActiveShaderIds();
        const params = aiVj.getCurrentParams();
        if (shaderIds.length === 0) return '';
        const catalog = await buildCatalog();
        const knownIds = new Set(catalog.map(s => s.id));
        const chain = mapVJStackToSharedChain(shaderIds, params, catalog, knownIds);
        return encodeChain(chain);
    }, [aiVj]);

    const handleShareVjSet = useCallback(async () => {
        const encoded = await buildVjChainString();
        if (!encoded) {
            setStatus('❌ No active VJ stack to share');
            return;
        }
        const url = new URL(window.location.href);
        url.search = '';
        url.hash = '';
        url.searchParams.set('chain', encoded);
        setShareableLink(url.toString());
        setShareVibeText(aiVj?.getLastVibeText() ?? '');
        setShowShareModal(true);
    }, [buildVjChainString, aiVj, setStatus]);

    const openRecordingShareModal = useCallback(() => {
        const link = generateShareableLink();
        setShareableLink(link);
        setShareVibeText('');
        setShowShareModal(true);
    }, [generateShareableLink]);

    const getCurrentChain = useCallback((): SharedChain | null => {
        const chain = buildSharedChain(modes, slotParams);
        return chain.slots.some(s => s.shaderId) ? chain : null;
    }, [modes, slotParams]);

    return {
        showShareModal,
        setShowShareModal,
        shareableLink,
        setShareableLink,
        shareVibeText,
        setShareVibeText,
        generateShareableLink,
        buildVjChainString,
        handleShareVjSet,
        applySharedChain,
        copyChainShareLink,
        getCurrentChain,
        openRecordingShareModal,
    };
}
