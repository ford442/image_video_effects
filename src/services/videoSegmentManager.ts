import { VideoRecord } from '../syncTypes';

export interface VideoSegment {
    video: VideoRecord;
    start: number;
    end: number;
}

const DURATION_CACHE = new Map<string, number>();

/**
 * Probe a video's duration by loading it into a hidden <video> element.
 * Cached per-URL for the session.
 */
export async function probeVideoDuration(url: string): Promise<number | undefined> {
    const cached = DURATION_CACHE.get(url);
    if (cached !== undefined) {
        return cached;
    }

    return new Promise((resolve) => {
        const video = document.createElement('video');
        video.preload = 'metadata';
        video.muted = true;
        video.crossOrigin = 'anonymous';

        const cleanup = () => {
            video.removeEventListener('loadedmetadata', onLoaded);
            video.removeEventListener('error', onError);
            video.src = '';
            video.load();
        };

        const onLoaded = () => {
            const duration = video.duration;
            if (duration && !isNaN(duration) && isFinite(duration)) {
                DURATION_CACHE.set(url, duration);
                cleanup();
                resolve(duration);
            } else {
                cleanup();
                resolve(undefined);
            }
        };

        const onError = () => {
            cleanup();
            resolve(undefined);
        };

        // Time out after 15 seconds
        setTimeout(() => {
            cleanup();
            resolve(undefined);
        }, 15000);

        video.addEventListener('loadedmetadata', onLoaded);
        video.addEventListener('error', onError);
        video.src = url;
    });
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
