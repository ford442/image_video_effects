import { VideoRecord } from '../syncTypes';

export interface VideoSegment {
    video: VideoRecord;
    start: number;
    end: number;
}

const DURATION_CACHE = new Map<string, number>();
const IN_FLIGHT = new Map<string, Promise<number | undefined>>();
const PROBE_TIMEOUT_MS = 15000;
const DEFAULT_PROBE_CONCURRENCY = 3;

let gateLogged = false;

/**
 * Media probing is only allowed once the WebGPU boot probe has succeeded.
 * With no adapter the "WebGPU required" overlay is up and nothing can use the
 * video, so we must not spend ~2 range requests per file finding out how long
 * it is. A missing `window.webgpuProbe` (jsdom, SSR) counts as blocked.
 */
function isProbeAllowed(): boolean {
    if (typeof window === 'undefined' || typeof document === 'undefined') return false;
    if (window.webgpuProbe?.ok === true) return true;
    if (!gateLogged) {
        gateLogged = true;
        console.info('Video duration probing skipped: WebGPU renderer is not available.');
    }
    return false;
}

function loadDuration(url: string): Promise<number | undefined> {
    return new Promise((resolve) => {
        const video = document.createElement('video');
        video.preload = 'metadata';
        video.muted = true;
        video.crossOrigin = 'anonymous';

        let done = false;
        let timer: ReturnType<typeof setTimeout> | undefined;

        const settle = (duration: number | undefined) => {
            if (done) return;
            done = true;
            if (timer !== undefined) clearTimeout(timer);
            video.removeEventListener('loadedmetadata', onLoaded);
            video.removeEventListener('error', onError);
            // Drop the source so the browser abandons any remaining range
            // request; only meaningful if a src was ever assigned.
            if (video.hasAttribute('src')) {
                video.removeAttribute('src');
                video.load();
            }
            if (duration !== undefined) DURATION_CACHE.set(url, duration);
            resolve(duration);
        };

        const onLoaded = () => {
            const d = video.duration;
            settle(d && !isNaN(d) && isFinite(d) ? d : undefined);
        };
        const onError = () => settle(undefined);

        video.addEventListener('loadedmetadata', onLoaded);
        video.addEventListener('error', onError);
        timer = setTimeout(() => settle(undefined), PROBE_TIMEOUT_MS);
        video.src = url;
    });
}

/**
 * Probe a video's duration by loading it into a hidden <video> element.
 * Cached per-URL for the session; concurrent callers share one element.
 * Never rejects: every failure resolves `undefined`.
 */
export function probeVideoDuration(url: string): Promise<number | undefined> {
    const cached = DURATION_CACHE.get(url);
    if (cached !== undefined) {
        return Promise.resolve(cached);
    }
    const pending = IN_FLIGHT.get(url);
    if (pending) {
        return pending;
    }
    if (!isProbeAllowed()) {
        return Promise.resolve(undefined);
    }

    const promise = loadDuration(url).finally(() => {
        IN_FLIGHT.delete(url);
    });
    IN_FLIGHT.set(url, promise);
    return promise;
}

export interface ProbeOptions {
    /** Max elements loading at once. Default 3. */
    concurrency?: number;
    /** Stop starting new probes once aborted (in-flight ones finish). */
    signal?: AbortSignal;
}

/**
 * Probe many URLs with bounded concurrency. Results align with `urls`.
 */
export async function probeVideoDurations(
    urls: string[],
    { concurrency = DEFAULT_PROBE_CONCURRENCY, signal }: ProbeOptions = {}
): Promise<(number | undefined)[]> {
    const results: (number | undefined)[] = new Array(urls.length).fill(undefined);
    let next = 0;
    const worker = async () => {
        while (next < urls.length && !signal?.aborted) {
            const i = next++;
            results[i] = await probeVideoDuration(urls[i]);
        }
    };
    const workers = Math.min(Math.max(1, Math.floor(concurrency)), urls.length);
    await Promise.all(Array.from({ length: workers }, worker));
    return results;
}

/**
 * Ensure all videos in the list have a known duration.
 * Missing durations are probed (bounded) and cached.
 */
export async function hydrateDurations(
    videos: VideoRecord[],
    options?: ProbeOptions
): Promise<VideoRecord[]> {
    const missing = videos.filter((v) => !(typeof v.duration === 'number' && v.duration > 0));
    if (missing.length === 0) return videos;

    const probed = await probeVideoDurations(missing.map((v) => v.url), options);
    const byUrl = new Map<string, number>();
    missing.forEach((v, i) => {
        const d = probed[i];
        if (d !== undefined) byUrl.set(v.url, d);
    });
    return videos.map((v) => {
        const d = byUrl.get(v.url);
        return d === undefined ? v : { ...v, duration: d };
    });
}

/**
 * Copy durations from `hydrated` onto `current` by URL, leaving records that
 * already have a duration (and any entries added since) untouched. Returns
 * `current` itself when nothing changed so React can bail out.
 */
export function mergeDurations(current: VideoRecord[], hydrated: VideoRecord[]): VideoRecord[] {
    const byUrl = new Map<string, number>();
    for (const v of hydrated) {
        if (typeof v.duration === 'number' && v.duration > 0) byUrl.set(v.url, v.duration);
    }
    let changed = false;
    const merged = current.map((v) => {
        const d = byUrl.get(v.url);
        if (d === undefined || (typeof v.duration === 'number' && v.duration > 0)) return v;
        changed = true;
        return { ...v, duration: d };
    });
    return changed ? merged : current;
}

/**
 * Pick a random segment from the available videos.
 * Videos are weighted by their duration (longer videos = more segments possible).
 */
export function pickRandomSegment(
    videos: VideoRecord[],
    segmentLength: number,
    recentHistory: string[] = [],
    historyWeight: number = 0.3
): VideoSegment | null {
    const eligible = videos.filter(
        (v) => typeof v.duration === 'number' && v.duration > segmentLength
    );

    if (eligible.length === 0) {
        return null;
    }

    // Weight by duration, with a penalty for recently played videos
    const weights = eligible.map((v) => {
        const recencyPenalty = recentHistory.includes(v.id || v.url) ? historyWeight : 1;
        return (v.duration || 0) * recencyPenalty;
    });

    const totalWeight = weights.reduce((a, b) => a + b, 0);
    if (totalWeight <= 0) {
        return null;
    }

    let random = Math.random() * totalWeight;
    let chosen = eligible[0];
    for (let i = 0; i < eligible.length; i++) {
        random -= weights[i];
        if (random <= 0) {
            chosen = eligible[i];
            break;
        }
    }

    const duration = chosen.duration || 0;
    const maxStart = Math.max(0, duration - segmentLength);
    const start = Math.random() * maxStart;
    const end = Math.min(duration, start + segmentLength);

    return {
        video: chosen,
        start,
        end,
    };
}

/**
 * Build a pre-generated queue of segments.
 */
export function buildSegmentPlaylist(
    videos: VideoRecord[],
    segmentLength: number,
    count: number
): VideoSegment[] {
    const playlist: VideoSegment[] = [];
    const recentHistory: string[] = [];

    for (let i = 0; i < count; i++) {
        const segment = pickRandomSegment(videos, segmentLength, recentHistory);
        if (!segment) break;
        playlist.push(segment);
        recentHistory.push(segment.video.id || segment.video.url);
        if (recentHistory.length > 5) {
            recentHistory.shift();
        }
    }

    return playlist;
}
