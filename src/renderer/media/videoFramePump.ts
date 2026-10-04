/**
 * videoFramePump.ts
 *
 * WebCodecs ingest for the hidden <video> (#1314 WP-2): every frame the
 * browser presents (requestVideoFrameCallback) becomes a VideoFrame in a
 * drop-oldest queue of depth 2. The renderer imports the newest one as a
 * GPUExternalTexture when it encodes its frame. No CPU copy and no readback,
 * and only frames that actually changed are copied (a 30 fps video on a
 * 120 Hz display is ingested 30×/s, not 120×/s). File, webcam, HLS and
 * Bilibili all play through the same element, so one pump covers them.
 *
 * A worker cannot touch HTMLVideoElement, so the render worker (#1314 WP-1)
 * receives these VideoFrames as transfers.
 */

import { LatestFrameQueue, safeClose } from './latestFrameQueue';

export type VideoIngestPath = 'videoframe' | 'element' | 'none';

export interface VideoIngestStats {
  ingestPath: VideoIngestPath;
  /** Frames handed to the GPU. */
  framesIngested: number;
  /** Frames decoded but never rendered (queue overflow / superseded). */
  droppedFrames: number;
  /** Frames the browser presented that the callback never saw (presentedFrames gaps). */
  missedFrames: number;
  queueDepth: number;
  /** Why the pump fell back to the element path, if it did. */
  fallbackReason?: string;
}

type FrameCallbackVideo = HTMLVideoElement & {
  requestVideoFrameCallback?: (cb: (now: number, metadata: VideoFrameCallbackMetadata) => void) => number;
  cancelVideoFrameCallback?: (handle: number) => void;
};

/** True when this runtime can run the VideoFrame ingest path at all. */
export function supportsVideoFrameIngest(device: GPUDevice | null, video: HTMLVideoElement | null): boolean {
  return (
    !!device &&
    !!video &&
    typeof VideoFrame !== 'undefined' &&
    typeof (video as FrameCallbackVideo).requestVideoFrameCallback === 'function' &&
    typeof device.importExternalTexture === 'function'
  );
}

export class VideoFramePump {
  private readonly queue = new LatestFrameQueue<VideoFrame>(2);
  private handle: number | null = null;
  private lastPresented = -1;
  private missed = 0;
  private ingested = 0;
  private stopped = false;
  private failed: string | null = null;

  constructor(private readonly video: HTMLVideoElement) {
    this.schedule();
  }

  get element(): HTMLVideoElement {
    return this.video;
  }

  /** False once the pump gave up (e.g. a tainted cross-origin source). */
  get healthy(): boolean {
    return !this.stopped && this.failed === null;
  }

  /** Newest decoded frame, or null when nothing new arrived since the last take. */
  takeLatest(): VideoFrame | null {
    return this.queue.takeLatest();
  }

  /** The renderer encoded `frame` into a submitted command buffer. */
  noteIngested(): void {
    this.ingested++;
  }

  /** Give up on the VideoFrame path (caller falls back to the element). */
  fail(reason: string): void {
    this.failed = reason;
    this.detach();
  }

  getStats(): VideoIngestStats {
    const q = this.queue.getStats();
    return {
      ingestPath: this.failed ? 'element' : 'videoframe',
      framesIngested: this.ingested,
      droppedFrames: q.dropped,
      missedFrames: this.missed,
      queueDepth: this.queue.size,
      ...(this.failed ? { fallbackReason: this.failed } : {}),
    };
  }

  detach(): void {
    this.stopped = true;
    const v = this.video as FrameCallbackVideo;
    if (this.handle !== null) v.cancelVideoFrameCallback?.(this.handle);
    this.handle = null;
    this.queue.clear();
  }

  private schedule(): void {
    if (this.stopped) return;
    const v = this.video as FrameCallbackVideo;
    this.handle = v.requestVideoFrameCallback?.((_now, metadata) => this.onFrame(metadata)) ?? null;
  }

  private onFrame(metadata: VideoFrameCallbackMetadata): void {
    this.handle = null;
    if (this.stopped) return;
    if (this.lastPresented >= 0 && metadata.presentedFrames > this.lastPresented + 1) {
      this.missed += metadata.presentedFrames - this.lastPresented - 1;
    }
    this.lastPresented = metadata.presentedFrames;
    try {
      const frame = new VideoFrame(this.video, { timestamp: Math.round(metadata.mediaTime * 1e6) });
      this.queue.push(frame);
    } catch (e) {
      // SecurityError (tainted cross-origin source) or an element without data.
      if (e instanceof DOMException && e.name === 'SecurityError') {
        this.fail('cross-origin video without CORS');
        return;
      }
    }
    this.schedule();
  }
}

export { safeClose };
