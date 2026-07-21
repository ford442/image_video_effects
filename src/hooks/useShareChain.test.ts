import { renderHook } from '@testing-library/react';
import { useShareChain } from './useShareChain';
import type { RenderMode, SlotParams } from '../renderer/types';

const defaultSlotParams: SlotParams = {
  zoomParam1: 0.5,
  zoomParam2: 0.5,
  zoomParam3: 0.5,
  zoomParam4: 0.5,
  lightStrength: 1.0,
  ambient: 0.2,
  normalStrength: 0.1,
  fogFalloff: 4.0,
  depthThreshold: 0.5,
};

function makeOptions(overrides: Partial<Parameters<typeof useShareChain>[0]> = {}) {
  return {
    modes: ['liquid-metal', 'none', 'none'] as RenderMode[],
    activeSlot: 0,
    slotParams: [defaultSlotParams, defaultSlotParams, defaultSlotParams],
    inputSource: 'image' as const,
    currentImageUrl: undefined,
    activeGenerativeShader: 'gen-orb',
    availableModesRef: { current: [] },
    aiVj: null,
    setMode: jest.fn(),
    setActiveSlot: jest.fn(),
    updateSlotParam: jest.fn(),
    syncInputSourceToRenderer: jest.fn(),
    setActiveGenerativeShader: jest.fn(),
    handleLoadImage: jest.fn(),
    startWebcam: jest.fn(),
    setStatus: jest.fn(),
    ...overrides,
  };
}

describe('useShareChain', () => {
  it('getCurrentChain returns the active chain when slots have shaders', () => {
    const { result } = renderHook(() => useShareChain(makeOptions()));
    const chain = result.current.getCurrentChain();
    expect(chain).not.toBeNull();
    expect(chain?.slots[0]?.shaderId).toBe('liquid-metal');
  });

  it('getCurrentChain returns null when no shaders are loaded', () => {
    const { result } = renderHook(() =>
      useShareChain(
        makeOptions({
          modes: ['none', 'none', 'none'],
        })
      )
    );
    expect(result.current.getCurrentChain()).toBeNull();
  });
});
