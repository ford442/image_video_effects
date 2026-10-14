import {
    hydrateDurations,
    mergeDurations,
    pickRandomSegment,
    probeVideoDuration,
    probeVideoDurations,
} from './videoSegmentManager';

type FakeVideo = HTMLVideoElement & { fireLoaded: (duration: number) => void };

let created: FakeVideo[];
let loadSpy: jest.SpyInstance;
let createSpy: jest.SpyInstance;
let live: number;
let maxLive: number;
let seq = 0;
const url = () => `https://example.test/v${seq++}.mp4`;

function setProbe(ok: boolean | undefined) {
    (window as any).webgpuProbe = ok === undefined ? undefined : { ok };
}

beforeEach(() => {
    created = [];
    live = 0;
    maxLive = 0;
    const realCreate = document.createElement.bind(document);
    loadSpy = jest.spyOn(HTMLMediaElement.prototype, 'load').mockImplementation(() => {
        // Releasing the source is what frees a probe slot.
        live = Math.max(0, live - 1);
    });
    createSpy = jest.spyOn(document, 'createElement').mockImplementation(((tag: string) => {
        const el = realCreate(tag) as FakeVideo;
        if (tag === 'video') {
            let duration = NaN;
            Object.defineProperty(el, 'duration', { get: () => duration });
            el.fireLoaded = (d: number) => {
                duration = d;
                el.dispatchEvent(new Event('loadedmetadata'));
            };
            const origSet = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src')?.set as (v: string) => void;
            Object.defineProperty(el, 'src', {
                set(v: string) {
                    origSet.call(el, v);
                    live++;
                    maxLive = Math.max(maxLive, live);
                },
                get: () => el.getAttribute('src') ?? '',
            });
            created.push(el);
        }
        return el;
    }) as typeof document.createElement);
    setProbe(true);
});

afterEach(() => {
    jest.restoreAllMocks();
    jest.useRealTimers();
    setProbe(undefined);
});

const flush = () => new Promise<void>((r) => setTimeout(r, 0));

describe('probeVideoDuration', () => {
    it('resolves undefined without creating an element when the renderer probe is not ok', async () => {
        for (const state of [false, undefined]) {
            setProbe(state);
            await expect(probeVideoDuration(url())).resolves.toBeUndefined();
        }
        expect(createSpy).not.toHaveBeenCalledWith('video');
    });

    it('shares one element between concurrent callers for the same URL', async () => {
        const u = url();
        const a = probeVideoDuration(u);
        const b = probeVideoDuration(u);
        expect(a).toBe(b);
        expect(created).toHaveLength(1);
        created[0].fireLoaded(42);
        await expect(a).resolves.toBe(42);
    });

    it('serves repeat calls from cache without creating an element', async () => {
        const u = url();
        const first = probeVideoDuration(u);
        created[0].fireLoaded(7);
        await first;
        created.length = 0;
        await expect(probeVideoDuration(u)).resolves.toBe(7);
        expect(created).toHaveLength(0);
    });

    it('releases the element once even if the timeout would fire after loadedmetadata', async () => {
        jest.useFakeTimers();
        const p = probeVideoDuration(url());
        created[0].fireLoaded(10);
        await p;
        jest.advanceTimersByTime(20000);
        expect(loadSpy).toHaveBeenCalledTimes(1);
    });

    it('resolves undefined on timeout and releases the element once', async () => {
        jest.useFakeTimers();
        const p = probeVideoDuration(url());
        jest.advanceTimersByTime(15001);
        await expect(p).resolves.toBeUndefined();
        expect(loadSpy).toHaveBeenCalledTimes(1);
    });
});

describe('hydrateDurations', () => {
    it('never has more than `concurrency` elements live at once', async () => {
        const videos = Array.from({ length: 5 }, () => ({ url: url() }));
        const done = hydrateDurations(videos, { concurrency: 2 });
        for (let i = 0; i < 5; i++) {
            await flush();
            created[i].fireLoaded(30 + i);
        }
        const result = await done;
        expect(maxLive).toBe(2);
        expect(result.map((v) => v.duration)).toEqual([30, 31, 32, 33, 34]);
    });

    it('skips records that already carry a duration', async () => {
        const out = await hydrateDurations([{ url: url(), duration: 12 }]);
        expect(out[0].duration).toBe(12);
        expect(created).toHaveLength(0);
    });

    it('probes nothing when the renderer is unavailable', async () => {
        setProbe(false);
        const videos = [{ url: url() }, { url: url() }];
        const out = await hydrateDurations(videos);
        expect(out).toEqual(videos);
        expect(created).toHaveLength(0);
    });

    it('stops starting new probes once aborted', async () => {
        const controller = new AbortController();
        const done = probeVideoDurations([url(), url(), url()], { concurrency: 1, signal: controller.signal });
        await flush();
        controller.abort();
        created[0].fireLoaded(1);
        await done;
        expect(created).toHaveLength(1);
    });
});

describe('B3HD segment picking after hydration', () => {
    it('pickRandomSegment only sees videos once durations are filled in', async () => {
        const videos = [{ url: url() }, { url: url() }];
        expect(pickRandomSegment(videos, 5)).toBeNull();
        const done = hydrateDurations(videos);
        await flush();
        created.forEach((c) => c.fireLoaded(60));
        const hydrated = await done;
        const seg = pickRandomSegment(hydrated, 5);
        if (!seg) throw new Error('expected a segment');
        expect(seg.end - seg.start).toBeCloseTo(5);
    });
});

describe('mergeDurations', () => {
    it('adds durations by URL, keeps existing, and returns the same array when unchanged', () => {
        const current = [{ url: 'a' }, { url: 'b', duration: 9 }];
        const merged = mergeDurations(current, [
            { url: 'a', duration: 3 },
            { url: 'b', duration: 99 },
        ]);
        expect(merged).toEqual([{ url: 'a', duration: 3 }, { url: 'b', duration: 9 }]);
        expect(mergeDurations(merged, [{ url: 'a', duration: 3 }])).toBe(merged);
    });
});
