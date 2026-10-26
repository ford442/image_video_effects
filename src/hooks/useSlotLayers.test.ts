import { act, renderHook } from '@testing-library/react';
import type { RendererManager } from '../renderer/RendererManager';
import { DEFAULT_SLOT_OUTPUT } from '../renderer/slotOutput';
import { useSlotLayers } from './useSlotLayers';

function fakeManager() {
  return { setSlotMode: vi.fn(), setSlotOutput: vi.fn() };
}

describe('useSlotLayers', () => {
  it('keeps page state and the renderer in step', () => {
    const manager = fakeManager();
    const rendererRef = { current: manager as unknown as RendererManager };
    const { result } = renderHook(() => useSlotLayers({ rendererRef, rendererReady: false }));
    act(() => result.current.setSlotMode(1, 'parallel'));
    act(() => result.current.setSlotOutput(1, { mode: 'blend', blend: 'screen' }));
    act(() => result.current.setSlotOpacity(1, 0.5));
    expect(result.current.slotModes[1]).toBe('parallel');
    expect(result.current.slotOutputs[1]).toEqual({ ...DEFAULT_SLOT_OUTPUT, mode: 'blend', blend: 'screen', opacity: 0.5 });
    expect(manager.setSlotMode).toHaveBeenCalledWith(1, 'parallel');
    expect(manager.setSlotOutput).toHaveBeenLastCalledWith(1, { opacity: 0.5 });
  });

  it('applies a whole layering (share link / project) and re-sends it to a new backend', () => {
    const manager = fakeManager();
    const rendererRef = { current: manager as unknown as RendererManager };
    const { result, rerender } = renderHook(
      ({ ready }) => useSlotLayers({ rendererRef, rendererReady: ready }),
      { initialProps: { ready: false } },
    );
    act(() => result.current.applyLayers({
      slotModes: ['chained', 'parallel'],
      slotOutputs: [{ ...DEFAULT_SLOT_OUTPUT }, { ...DEFAULT_SLOT_OUTPUT, mode: 'mask' }],
    }));
    expect(result.current.slotModes).toEqual(['chained', 'parallel', 'chained', 'chained', 'chained', 'chained']);
    expect(result.current.slotOutputs[1]!.mode).toBe('mask');
    manager.setSlotMode.mockClear();
    manager.setSlotOutput.mockClear();
    rerender({ ready: true });
    expect(manager.setSlotMode.mock.calls).toEqual([[1, 'parallel']]);
    expect(manager.setSlotOutput).toHaveBeenCalledWith(1, expect.objectContaining({ mode: 'mask' }));
  });
});
