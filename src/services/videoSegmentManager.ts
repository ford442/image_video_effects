import { VideoRecord } from '../syncTypes';

export interface VideoSegment {
    video: VideoRecord;
    start: number;
    end: number;
}

const DURATION_CACHE = new Map<string, number>();
/** Probes still waiting on metadata; concurrent callers share one request (#1404). */
const IN_FLIGHT = new Map<string, Promise<number | undefined>>();
const PROBE_TIMEOUT_MS = 15000;

let loggedBlocked = false;

/**
 * True when the WebGPU boot probe has not succeeded (failed, or not published yet).
 * Media probes are wasted work behind the "WebGPU required" overlay.
 */
function isRendererBlocked(): boolean {
    return typeof window !== 'undefined' && window.webgpuProbe?.ok !== true;
}

/**
 * Probe a video's duration by loading it into a hidden <video> element.
 * Cached per-URL for the session. Resolves undefined without touching the
 * network while the renderer is blocked; that result is not cached.
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
    if (isRendererBlocked()) {
        if (!loggedBlocked) {
            loggedBlocked = true;
            console.info('[videoSegmentManager] Duration probes skipped: renderer blocked');
        }
        return Promise.resolve(undefined);
    }

    const probe = new Promise<number | undefined>((resolve) => {
        const video = document.createElement('video');
        video.preload = 'metadata';
        video.muted = true;
        video.crossOrigin = 'anonymous';

        let settled = false;
        let timer: ReturnType<typeof setTimeout> | undefined;

        const finish = (duration: number | undefined) => {
            if (settled) return;
            settled = true;
            if (timer !== undefined) clearTimeout(timer);
            video.removeEventListener('loadedmetadata', onLoaded);
            video.removeEventListener('error', onError);
            // Release the media resource; no load() when nothing was ever requested.
            if (video.getAttribute('src')) {
                video.removeAttribute('src');
                video.load();
            }
            resolve(duration);
        };

        const onLoaded = () => {
            const duration = video.duration;
            if (duration && !isNaN(duration) && isFinite(duration)) {
                DURATION_CACHE.set(url, duration);
                finish(duration);
            } else {
                finish(undefined);
            }
        };

        const onError = () => finish(undefined);

        timer = setTimeout(() => finish(undefined), PROBE_TIMEOUT_MS);
        video.addEventListener('loadedmetadata', onLoaded);
        video.addEventListener('error', onError);
        video.src = url;
    });

    IN_FLIGHT.set(url, probe);
    void probe.finally(() => IN_FLIGHT.delete(url));
    return probe;
}

/** Test hook: forget cached durations, in-flight probes and the blocked log latch. */
export function resetDurationProbesForTests(): void {
    DURATION_CACHE.clear();
    IN_FLIGHT.clear();
    loggedBlocked = false;
}

/**
 * Ensure all videos in the list have a known duration.
 * Missing durations are probed and cached.
 */
export async function hydrateDurations(videos: VideoRecord[]): Promise<VideoRecord[]> {
    const results = await Promise.all(
        videos.map(async (v) => {
            if (typeof v.duration === 'number' && v.duration > 0) {
                return v;
            }
            const probed = await probeVideoDuration(v.url);
            if (probed !== undefined) {
                return { ...v, duration: probed };
            }
            return v;
        })
    );
    return results;
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
    for (const [i, video] of eligible.entries()) {
        random -= weights[i] ?? 0;
        if (random <= 0) {
            chosen = video;
            break;
        }
    }
    if (!chosen) {
        return null;
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
