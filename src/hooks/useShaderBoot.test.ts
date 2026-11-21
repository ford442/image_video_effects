import { describe, expect, it, vi } from 'vitest';
import { renderHook } from '@testing-library/react';
import { useShaderBoot, type UseShaderBootOptions } from './useShaderBoot';
import type { ShaderEntry } from '../renderer/types';

const entry = (id: string): ShaderEntry => ({ id, name: id, url: `shaders/${id}.wgsl`, category: 'image' }) as ShaderEntry;

function boot(ids: string[]) {
  const setMode = vi.fn();
  const setStatus = vi.fn();
  const options: UseShaderBootOptions = {
    rendererReady: true,
    shadersReady: true,
    modes: ['none', 'none', 'none'],
    setMode,
    setStatus,
    imageManifest: [],
    currentImageUrl: undefined,
    inputSource: 'generative',
    handleNewRandomImage: async () => undefined,
    availableModes: ids.map(entry),
    autoChangeEnabled: false,
    autoChangeDelay: 10,
    shaderCategory: 'image',
    syncInputSourceToRenderer: vi.fn(),
  };
  renderHook(() => useShaderBoot(options));
  return { setMode, setStatus };
}

describe('useShaderBoot default Slot 1', () => {
  it('boots the frozen liquid-original when the catalog has it', () => {
    const { setMode, setStatus } = boot(['liquid', 'liquid-original']);
    expect(setMode).toHaveBeenCalledWith(0, 'liquid-original');
    expect(setStatus).toHaveBeenCalledWith(expect.stringContaining('Original'));
  });

  it('falls back to liquid while the remote catalog lacks liquid-original (never an empty Slot 1)', () => {
    const { setMode } = boot(['liquid', 'datamosh']);
    expect(setMode).toHaveBeenCalledWith(0, 'liquid');
  });

  it('only prompts the user when neither default exists', () => {
    const { setMode, setStatus } = boot(['datamosh']);
    expect(setMode).not.toHaveBeenCalled();
    expect(setStatus).toHaveBeenCalledWith(expect.stringContaining('Select a shader'));
  });
});
