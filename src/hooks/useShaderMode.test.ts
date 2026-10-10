import { renderHook, act } from '@testing-library/react';
import { useShaderMode } from './useShaderMode';
import type { InputSource, RenderMode, ShaderEntry, SlotParams } from '../renderer/types';
import type { RendererManager } from '../renderer/RendererManager';

function deferred<T>() {
  let resolve: (v: T) => void = () => {};
  const promise = new Promise<T>((r) => { resolve = r; });
  return { promise, resolve };
}

function setup() {
  const loads = new Map<string, ReturnType<typeof deferred<boolean>>>();
  const renderer = {
    loadShader: jest.fn((id: string) => {
      const d = deferred<boolean>();
      loads.set(id, d);
      return d.promise;
    }),
    setSlotShader: jest.fn(),
  };
  const status: Array<'idle' | 'loading' | 'error'> = ['idle', 'idle', 'idle'];
  const modes: RenderMode[] = ['none', 'none', 'none'];
  const entries = ['a', 'b', 'c'].map((id) => ({ id, name: id, url: `shaders/${id}.wgsl` })) as ShaderEntry[];
  const { result } = renderHook(() =>
    useShaderMode({
      rendererRef: { current: renderer as unknown as RendererManager },
      availableModes: entries,
      availableModesRef: { current: entries },
      modesRef: { current: modes },
      slotParamsRef: { current: [] as SlotParams[] },
      inputSourceRef: { current: 'image' as InputSource },
      slotShaderStatusRef: { current: status },
      setModes: jest.fn(),
      setSlotParams: jest.fn(),
      setSlotShaderStatus: jest.fn(),
      setInputSource: jest.fn(),
    }),
  );
  return { result, renderer, loads };
}

describe('useShaderMode.setMode (#1395)', () => {
  it('applies the newest pick made while the slot was loading', async () => {
    const { result, renderer, loads } = setup();

    let first: Promise<void> = Promise.resolve();
    act(() => { first = result.current.setMode(0, 'a'); });
    await act(async () => {
      await result.current.setMode(0, 'b'); // dropped before #1395
      await result.current.setMode(0, 'c'); // newest wins over 'b'
    });
    expect(renderer.loadShader).toHaveBeenCalledTimes(1);

    await act(async () => {
      loads.get('a')!.resolve(true);
      for (let i = 0; i < 20 && !loads.has('c'); i++) await Promise.resolve();
      loads.get('c')!.resolve(true);
      await first;
    });

    expect(renderer.loadShader.mock.calls.map(([id]) => id)).toEqual(['a', 'c']);
    expect(renderer.setSlotShader).toHaveBeenLastCalledWith(0, 'c');
  });
});
