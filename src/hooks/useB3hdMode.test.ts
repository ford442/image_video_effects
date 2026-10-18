import type { Mock } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { useB3hdMode, UseB3hdModeOptions } from './useB3hdMode';
import * as segments from '../services/videoSegmentManager';
import type { VideoRecord } from '../syncTypes';

const VIDEOS: VideoRecord[] = [{ url: 'https://x/a.mp4' }, { url: 'https://x/b.mp4' }];

function options(overrides: Partial<UseB3hdModeOptions> = {}): UseB3hdModeOptions {
    return {
        videoB3hdMode: false,
        inputSource: 'video',
        videoList: VIDEOS,
        b3hdSegmentLength: 5,
        b3hdIntervalSeconds: 1,
        setCurrentSegment: vi.fn(),
        setSelectedVideo: vi.fn(),
        setVideoList: vi.fn(),
        ...overrides,
    };
}

describe('useB3hdMode duration probing (#1404)', () => {
    afterEach(() => vi.restoreAllMocks());

    it('does not probe durations while B3HD is off', () => {
        const hydrate = vi.spyOn(segments, 'hydrateDurations');
        renderHook(() => useB3hdMode(options()));
        expect(hydrate).not.toHaveBeenCalled();
    });

    it('probes once B3HD turns on, then plays a segment and publishes durations', async () => {
        const hydrated = VIDEOS.map((v) => ({ ...v, duration: 30 }));
        const hydrate = vi.spyOn(segments, 'hydrateDurations').mockResolvedValue(hydrated);
        const opts = options({ videoB3hdMode: true });

        const { unmount } = renderHook(() => useB3hdMode(opts));

        await waitFor(() => expect(opts.setSelectedVideo).toHaveBeenCalled());
        expect(hydrate).toHaveBeenCalledTimes(1);
        const update = (opts.setVideoList as Mock).mock.calls[0]![0] as (p: VideoRecord[]) => VideoRecord[];
        expect(update(VIDEOS)).toEqual(hydrated);
        unmount();
    });

    it('skips probing when every video already has a duration', async () => {
        const hydrate = vi.spyOn(segments, 'hydrateDurations');
        const opts = options({
            videoB3hdMode: true,
            videoList: VIDEOS.map((v) => ({ ...v, duration: 30 })),
        });

        const { unmount } = renderHook(() => useB3hdMode(opts));

        await waitFor(() => expect(opts.setSelectedVideo).toHaveBeenCalled());
        expect(hydrate).not.toHaveBeenCalled();
        unmount();
    });
});
