import type { MockInstance } from 'vitest';
import {
    hydrateDurations,
    probeVideoDuration,
    resetDurationProbesForTests,
} from './videoSegmentManager';


function setProbe(ok: boolean | undefined): void {
    if (ok === undefined) delete window.webgpuProbe;
    else window.webgpuProbe = { ok } as Window['webgpuProbe'];
}

/** jsdom never loads media: fire loadedmetadata by hand with a fake duration. */
function fireMetadata(video: HTMLVideoElement, duration: number): void {
    Object.defineProperty(video, 'duration', { configurable: true, value: duration });
    video.dispatchEvent(new Event('loadedmetadata'));
}

describe('probeVideoDuration (#1404)', () => {
    let created: HTMLVideoElement[];
    const video = (i: number): HTMLVideoElement => {
        const el = created[i];
        if (!el) throw new Error(`no <video> #${i}`);
        return el;
    };
    let createSpy: MockInstance;
    let loadSpy: MockInstance;

    beforeEach(() => {
        resetDurationProbesForTests();
        setProbe(true);
        created = [];
        const realCreate = document.createElement.bind(document);
        createSpy = vi.spyOn(document, 'createElement').mockImplementation(
            (tag: string, options?: ElementCreationOptions) => {
                const el = realCreate(tag, options);
                if (tag === 'video') created.push(el as HTMLVideoElement);
                return el;
            },
        );
        loadSpy = vi.spyOn(HTMLMediaElement.prototype, 'load').mockImplementation(() => {});
    });

    afterEach(() => {
        vi.restoreAllMocks();
        vi.useRealTimers();
        setProbe(undefined);
    });

    it('shares one promise and one element between concurrent callers', async () => {
        const a = probeVideoDuration('https://x/a.mp4');
        const b = probeVideoDuration('https://x/a.mp4');
        expect(b).toBe(a);
        expect(created).toHaveLength(1);

        fireMetadata(video(0), 42);
        await expect(a).resolves.toBe(42);
        await expect(b).resolves.toBe(42);
    });

    it('serves cache hits without creating an element', async () => {
        const first = probeVideoDuration('https://x/b.mp4');
        fireMetadata(video(0), 7);
        await first;

        createSpy.mockClear();
        await expect(probeVideoDuration('https://x/b.mp4')).resolves.toBe(7);
        expect(createSpy).not.toHaveBeenCalled();
    });

    it.each([
        ['failed', false],
        ['not yet published', undefined],
    ])('resolves undefined without document.createElement when the probe is %s', async (_label, ok) => {
        setProbe(ok);
        const info = vi.spyOn(console, 'info').mockImplementation(() => {});

        await expect(probeVideoDuration('https://x/c.mp4')).resolves.toBeUndefined();
        await expect(probeVideoDuration('https://x/d.mp4')).resolves.toBeUndefined();
        expect(createSpy).not.toHaveBeenCalled();
        expect(info).toHaveBeenCalledTimes(1);
    });

    it('does not cache a blocked result, so a later probe still runs', async () => {
        setProbe(false);
        vi.spyOn(console, 'info').mockImplementation(() => {});
        await probeVideoDuration('https://x/e.mp4');

        setProbe(true);
        const p = probeVideoDuration('https://x/e.mp4');
        expect(created).toHaveLength(1);
        fireMetadata(video(0), 3);
        await expect(p).resolves.toBe(3);
    });

    it('releases the element once, even when the timeout fires after metadata', async () => {
        vi.useFakeTimers();
        const p = probeVideoDuration('https://x/f.mp4');
        fireMetadata(video(0), 5);
        await p;

        vi.advanceTimersByTime(20000);
        expect(loadSpy).toHaveBeenCalledTimes(1);
        expect(video(0).hasAttribute('src')).toBe(false);
    });

    it('drops the in-flight entry after an error so the URL can be retried', async () => {
        const p = probeVideoDuration('https://x/g.mp4');
        video(0).dispatchEvent(new Event('error'));
        await expect(p).resolves.toBeUndefined();

        const retry = probeVideoDuration('https://x/g.mp4');
        expect(retry).not.toBe(p);
        expect(created).toHaveLength(2);
    });

    it('hydrateDurations probes each missing URL once and keeps known durations', async () => {
        const pending = hydrateDurations([
            { url: 'https://x/h.mp4' },
            { url: 'https://x/h.mp4' },
            { url: 'https://x/i.mp4', duration: 9 },
        ]);
        expect(created).toHaveLength(1);
        fireMetadata(video(0), 11);
        await expect(pending).resolves.toEqual([
            { url: 'https://x/h.mp4', duration: 11 },
            { url: 'https://x/h.mp4', duration: 11 },
            { url: 'https://x/i.mp4', duration: 9 },
        ]);
    });
});
