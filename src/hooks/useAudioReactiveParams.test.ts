import { act, renderHook } from '@testing-library/react';
import type { RefObject } from 'react';
import type { RendererManager } from '../renderer/RendererManager';
import { DEFAULT_SLOT_OUTPUT } from '../renderer/slotOutput';
import { useAudioReactiveParams } from './useAudioReactiveParams';

vi.mock('./useAudioAnalyzer', () => ({
  useAudioAnalyzer: () => ({
    startAudio: vi.fn(async () => undefined),
    stopAudio: vi.fn(),
    getAudioData: () => ({ bass: 0, mid: 0, treble: 0 }),
    getAudioBins: () => new Float32Array(128),
  }),
}));

describe('useAudioReactiveParams: layer opacity (#1512)', () => {
  it('puts the fader opacity back on banded slots when audio reactivity turns off', () => {
    const setSlotOutput = vi.fn();
    const rendererRef = {
      current: { setSlotOutput, updateAudioData: vi.fn(), updateAudioFrequencyBins: vi.fn(), getMaxActiveSlots: () => 1 },
    } as unknown as RefObject<RendererManager | null>;
    const { result } = renderHook(() =>
      useAudioReactiveParams({
        rendererRef,
        modes: [],
        availableModes: [],
        updateSlotParam: vi.fn(),
        getShaderDefaults: () => [],
        setStatus: vi.fn(),
        slotOutputs: [{ ...DEFAULT_SLOT_OUTPUT }, { ...DEFAULT_SLOT_OUTPUT, mode: 'blend', opacity: 0.8 }],
        opacityAudio: [null, 'bass'],
      }),
    );
    expect(setSlotOutput).not.toHaveBeenCalled(); // not on mount

    act(() => result.current.setAudioReactiveParams(true));
    setSlotOutput.mockClear(); // the gated writes of the running loop are not under test

    act(() => result.current.setAudioReactiveParams(false));
    expect(setSlotOutput).toHaveBeenCalledTimes(1);
    expect(setSlotOutput).toHaveBeenCalledWith(1, { opacity: 0.8 });
  });
});
