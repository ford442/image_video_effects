import { describe, it, expect, vi, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useAudioAnalyzer } from './useAudioAnalyzer';

function installFakes() {
    const contexts: { close: ReturnType<typeof vi.fn> }[] = [];
    const tracks: { stop: ReturnType<typeof vi.fn> }[] = [];
    class FakeCtx {
        close = vi.fn(() => Promise.resolve());
        constructor() { contexts.push(this); }
        createAnalyser() { return { fftSize: 0, frequencyBinCount: 128 }; }
        createMediaStreamSource() { return { connect: vi.fn(), disconnect: vi.fn() }; }
    }
    vi.stubGlobal('AudioContext', FakeCtx);
    Object.defineProperty(navigator, 'mediaDevices', {
        configurable: true,
        value: {
            getUserMedia: vi.fn(async () => {
                const t = { stop: vi.fn() };
                tracks.push(t);
                return { getTracks: () => [t] };
            }),
        },
    });
    return { contexts, tracks };
}

describe('useAudioAnalyzer', () => {
    afterEach(() => vi.unstubAllGlobals());

    it('stopAudio stops mic tracks and closes the context', async () => {
        const { contexts, tracks } = installFakes();
        const { result } = renderHook(() => useAudioAnalyzer());
        await act(() => result.current.startAudio());
        act(() => result.current.stopAudio());
        expect(tracks[0]?.stop).toHaveBeenCalled();
        expect(contexts[0]?.close).toHaveBeenCalled();
        expect(result.current.isActive).toBe(false);
    });

    it('a second startAudio releases the first context and stream', async () => {
        const { contexts, tracks } = installFakes();
        const { result } = renderHook(() => useAudioAnalyzer());
        await act(() => result.current.startAudio());
        await act(() => result.current.startAudio());
        expect(tracks[0]?.stop).toHaveBeenCalled();
        expect(contexts[0]?.close).toHaveBeenCalled();
        expect(contexts[1]?.close).not.toHaveBeenCalled();
    });
});
