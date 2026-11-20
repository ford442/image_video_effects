import { act, renderHook } from '@testing-library/react';
import { useSetRecorder } from './useSetRecorder';

describe('useSetRecorder keyframes (#1401)', () => {
  const opts = { modes: ['liquid'], slotParams: [], setMode: vi.fn() };

  it('adds keyframes sorted by time, replaces one at the same slot / key / time, and removes them', () => {
    const { result } = renderHook(() => useSetRecorder(opts));
    act(() => result.current.addKeyframe({ t: 2000, slot: 0, key: 'zoomParam1', value: 1, ease: 'linear' }));
    act(() => result.current.addKeyframe({ t: 500, slot: 0, key: 'zoomParam1', value: 0, ease: 'linear' }));
    act(() => result.current.addKeyframe({ t: 2000, slot: 0, key: 'zoomParam1', value: 0.7, ease: 'easeOut' }));
    expect(result.current.timeline?.keyframes).toEqual([
      { t: 500, slot: 0, key: 'zoomParam1', value: 0, ease: 'linear' },
      { t: 2000, slot: 0, key: 'zoomParam1', value: 0.7, ease: 'easeOut' },
    ]);
    expect(result.current.timeline?.durationMs).toBe(2000);
    act(() => result.current.removeKeyframe(0));
    expect(result.current.timeline?.keyframes).toHaveLength(1);
    act(() => result.current.removeKeyframe(0));
    // A keyframes-only timeline with no keyframes left is no timeline.
    expect(result.current.timeline).toBeNull();
  });

  it('records the source with the slots when the app reports it', () => {
    vi.useFakeTimers();
    const getSource = vi.fn(() => ({ type: 'image' as const, url: 'https://x/a.jpg' }));
    const { result } = renderHook(() => useSetRecorder({ ...opts, getSource }));
    act(() => result.current.startRecording());
    act(() => result.current.stopRecording());
    expect(result.current.timeline?.events[0]).toEqual({ t: 0, slot: 0, kind: 'source', value: { type: 'image', url: 'https://x/a.jpg' } });
    vi.useRealTimers();
  });
});
