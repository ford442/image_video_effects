import { describe, it, expect, vi, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useRoulette } from './useRoulette';
import type { RenderMode, ShaderEntry } from '../renderer/types';

const shaders = [
    { id: 'a', name: 'A' },
    { id: 'b', name: 'B' },
] as unknown as ShaderEntry[];

describe('useRoulette chaos mode', () => {
    afterEach(() => vi.useRealTimers());

    it('rolls once on enable, not again when triggerRoulette identity changes', () => {
        vi.useFakeTimers();
        const setMode = vi.fn();
        const { result } = renderHook(() =>
            useRoulette({
                availableModes: shaders,
                modes: ['a' as RenderMode],
                activeSlot: 0,
                setMode,
                updateSlotParam: vi.fn(),
                setStatus: vi.fn(),
            }),
        );
        act(() => result.current.setChaosModeEnabled(true));
        act(() => { vi.advanceTimersByTime(1000); });
        expect(setMode).toHaveBeenCalledTimes(1);
        act(() => { vi.advanceTimersByTime(10_000); });
        expect(setMode).toHaveBeenCalledTimes(2);
        act(() => result.current.setChaosModeEnabled(false));
        act(() => { vi.advanceTimersByTime(30_000); });
        expect(setMode).toHaveBeenCalledTimes(2);
    });
});
