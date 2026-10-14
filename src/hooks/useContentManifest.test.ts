import { renderHook, waitFor } from '@testing-library/react';
import { useContentManifest } from './useContentManifest';
import * as contentLoader from '../services/contentLoader';
import * as segments from '../services/videoSegmentManager';

jest.mock('../services/contentLoader');

const loaded = {
    manifest: [{ url: 'https://example.test/a.jpg', tags: [], description: '' }],
    videos: [{ url: 'https://example.test/a.mp4' }],
};

function setup() {
    const opts = {
        rendererRef: { current: null },
        setImageManifest: jest.fn(),
        setVideoList: jest.fn(),
        setStatus: jest.fn(),
    };
    const hook = renderHook(() => useContentManifest(opts));
    return { opts, ...hook };
}

describe('useContentManifest', () => {
    afterEach(() => jest.restoreAllMocks());

    it('sets the video list as fetched and does not probe durations', async () => {
        (contentLoader.fetchContentManifest as jest.Mock).mockResolvedValue(loaded);
        const hydrate = jest.spyOn(segments, 'hydrateDurations');
        const { opts } = setup();
        await waitFor(() => expect(opts.setVideoList).toHaveBeenCalledWith(loaded.videos));
        expect(opts.setVideoList).toHaveBeenCalledTimes(1);
        expect(hydrate).not.toHaveBeenCalled();
    });

    it('passes an abort signal and sets no state after unmount', async () => {
        let resolve!: (v: typeof loaded) => void;
        let signal: AbortSignal | undefined;
        (contentLoader.fetchContentManifest as jest.Mock).mockImplementation(
            (o?: { signal?: AbortSignal }) => {
                signal = o?.signal;
                return new Promise((r) => { resolve = r; });
            }
        );
        const { opts, unmount } = setup();
        unmount();
        expect(signal?.aborted).toBe(true);
        resolve(loaded);
        await new Promise((r) => setTimeout(r, 0));
        expect(opts.setVideoList).not.toHaveBeenCalled();
        expect(opts.setImageManifest).not.toHaveBeenCalled();
    });

    it('does not fall back to demo content when the fetch is aborted', async () => {
        const abort = Object.assign(new Error('aborted'), { name: 'AbortError' });
        (contentLoader.fetchContentManifest as jest.Mock).mockRejectedValue(abort);
        const { opts } = setup();
        await new Promise((r) => setTimeout(r, 0));
        expect(opts.setVideoList).not.toHaveBeenCalled();
    });
});
