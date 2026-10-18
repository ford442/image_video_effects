/**
 * latestFrameQueue.ts
 *
 * Drop-oldest frame queue for video ingest (#1314 WP-2). The producer
 * (requestVideoFrameCallback) pushes decoded frames; the render loop takes
 * the newest one. Anything older is closed immediately: an unclosed
 * VideoFrame pins a decoder buffer, and a few leaks stall playback.
 */

export interface Closable {
  close(): void;
}

export interface FrameQueueStats {
  enqueued: number;
  consumed: number;
  /** Frames closed without ever being rendered (queue overflow or superseded). */
  dropped: number;
}

export class LatestFrameQueue<T extends Closable> {
  private frames: T[] = [];
  private readonly stats: FrameQueueStats = { enqueued: 0, consumed: 0, dropped: 0 };

  constructor(private readonly depth = 2) {}

  get size(): number {
    return this.frames.length;
  }

  getStats(): FrameQueueStats {
    return { ...this.stats };
  }

  push(frame: T): void {
    this.frames.push(frame);
    this.stats.enqueued++;
    while (this.frames.length > this.depth) {
      this.dropOldest();
    }
  }

  /** The newest frame (caller must close it); older queued frames are dropped. */
  takeLatest(): T | null {
    while (this.frames.length > 1) this.dropOldest();
    const frame = this.frames.pop() ?? null;
    if (frame) this.stats.consumed++;
    return frame;
  }

  /** Close everything still queued (detach / teardown). Not counted as drops. */
  clear(): void {
    for (const frame of this.frames.splice(0)) safeClose(frame);
  }

  private dropOldest(): void {
    const frame = this.frames.shift();
    if (!frame) return;
    safeClose(frame);
    this.stats.dropped++;
  }
}

export function safeClose(frame: Closable | null | undefined): void {
  try {
    frame?.close();
  } catch {
    /* already closed / detached */
  }
}
