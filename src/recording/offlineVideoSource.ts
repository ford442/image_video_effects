/**
 * offlineVideoSource.ts — frame-accurate video input for offline renders (#1401).
 *
 * The live source is a playing <video> whose current frame is whatever decoded last. An
 * offline frame at time t needs *the* source frame at t, so the job opens its own hidden,
 * muted element (the live one keeps playing untouched), seeks it for every output frame
 * and wraps the decoded picture in a VideoFrame for renderFrameAt's snapshot. Times past
 * the end wrap around (live videos loop).
 */

export interface OfflineVideoSource {
  readonly url: string;
  readonly durationSec: number;
  /** The decoded frame at `timeSec` (caller owns it), or null when the video cannot give one. */
  frameAt(timeSec: number, timestampUs: number): Promise<VideoFrame | null>;
  close(): void;
}

const SEEK_TIMEOUT_MS = 15_000;

function once(target: HTMLMediaElement, events: string[], timeoutMs: number): Promise<string> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      cleanup();
      reject(new Error(`video did not fire ${events.join('/')} within ${timeoutMs} ms`));
    }, timeoutMs);
    const handlers = events.map((name) => {
      const h = () => {
        cleanup();
        resolve(name);
      };
      target.addEventListener(name, h);
      return [name, h] as const;
    });
    const onError = () => {
      cleanup();
      reject(new Error(target.error?.message || 'video failed to load'));
    };
    target.addEventListener('error', onError);
    function cleanup() {
      clearTimeout(timer);
      for (const [name, h] of handlers) target.removeEventListener(name, h);
      target.removeEventListener('error', onError);
    }
  });
}

/** Wrap a media time into [0, duration). */
export function wrapMediaTime(timeSec: number, durationSec: number): number {
  if (!Number.isFinite(durationSec) || durationSec <= 0) return Math.max(0, timeSec);
  const t = timeSec % durationSec;
  return t < 0 ? t + durationSec : t;
}

export async function openOfflineVideoSource(url: string): Promise<OfflineVideoSource> {
  const video = document.createElement('video');
  video.crossOrigin = 'anonymous';
  video.muted = true;
  video.playsInline = true;
  video.preload = 'auto';
  video.src = url;
  if (video.readyState < 1) await once(video, ['loadedmetadata'], SEEK_TIMEOUT_MS);
  const durationSec = Number.isFinite(video.duration) ? video.duration : 0;
  let lastTime = -1;

  const seek = async (t: number) => {
    if (Math.abs(video.currentTime - t) < 1e-4 && video.readyState >= 2 && lastTime >= 0) return;
    const seeked = once(video, ['seeked'], SEEK_TIMEOUT_MS);
    video.currentTime = t;
    await seeked;
    // `seeked` can fire before the new frame is ready to paint; wait for it where we can.
    const rvfc = (video as HTMLVideoElement & {
      requestVideoFrameCallback?: (cb: () => void) => number;
    }).requestVideoFrameCallback;
    if (video.readyState < 2) await once(video, ['loadeddata', 'canplay'], SEEK_TIMEOUT_MS);
    else if (typeof rvfc === 'function' && !video.paused) {
      await new Promise<void>((resolve) => rvfc.call(video, () => resolve()));
    }
    lastTime = t;
  };

  return {
    url,
    durationSec,
    async frameAt(timeSec, timestampUs) {
      // Keep a little margin before the end: seeking to `duration` exactly shows no frame.
      const target = Math.min(wrapMediaTime(timeSec, durationSec), Math.max(0, durationSec - 1e-3));
      await seek(target);
      try {
        return new VideoFrame(video, { timestamp: timestampUs });
      } catch (e) {
        console.warn('[Offline render] video frame unavailable:', e);
        return null;
      }
    },
    close() {
      video.removeAttribute('src');
      video.load();
    },
  };
}
