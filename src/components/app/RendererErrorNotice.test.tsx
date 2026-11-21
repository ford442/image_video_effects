import { afterEach, describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen } from '@testing-library/react';
import { RendererErrorNotice } from './RendererErrorNotice';
import type { ErrorNotice } from '../../renderer/errorNotices';

const shader: ErrorNotice = { key: 's', kind: 'shader', message: 'The effect “x” couldn’t run.' };
const image: ErrorNotice = { key: 'i', kind: 'image', message: 'Couldn’t load that image.' };

function setup(notice: ErrorNotice | null, imageHandler = true) {
  const h = { onDismiss: vi.fn(), onTryAnotherEffect: vi.fn(), onTryAnotherImage: vi.fn(), onUseGenerative: vi.fn() };
  render(<RendererErrorNotice notice={notice} {...h} onTryAnotherImage={imageHandler ? h.onTryAnotherImage : undefined} />);
  return h;
}

afterEach(() => {
  vi.useRealTimers();
});

describe('RendererErrorNotice', () => {
  it('renders nothing without a notice', () => {
    setup(null);
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('announces a shader failure and offers another effect', () => {
    const h = setup(shader);
    expect(screen.getByRole('alert').textContent).toContain('couldn’t run');
    fireEvent.click(screen.getByRole('button', { name: 'Try another effect' }));
    expect(h.onTryAnotherEffect).toHaveBeenCalledTimes(1);
    expect(h.onDismiss).toHaveBeenCalledTimes(1);
  });

  it('offers image + generative recovery for an unreachable image', () => {
    const h = setup(image);
    fireEvent.click(screen.getByRole('button', { name: 'Try another image' }));
    fireEvent.click(screen.getByRole('button', { name: 'Use generative source' }));
    expect(h.onTryAnotherImage).toHaveBeenCalledTimes(1);
    expect(h.onUseGenerative).toHaveBeenCalledTimes(1);
  });

  it('hides "Try another image" when the Image source is not active', () => {
    setup(image, false);
    expect(screen.queryByRole('button', { name: 'Try another image' })).toBeNull();
    expect(screen.getByRole('button', { name: 'Use generative source' })).toBeTruthy();
  });

  it('can be dismissed and auto-dismisses after a while', () => {
    vi.useFakeTimers();
    const h = setup(shader);
    fireEvent.click(screen.getByRole('button', { name: 'Dismiss' }));
    expect(h.onDismiss).toHaveBeenCalledTimes(1);
    act(() => { vi.advanceTimersByTime(20_001); });
    expect(h.onDismiss).toHaveBeenCalledTimes(2);
  });
});
