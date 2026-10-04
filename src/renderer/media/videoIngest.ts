/**
 * videoIngest.ts
 *
 * Per-frame video ingest policy for the TS renderer (#1314 WP-2). The frame
 * loop asks for at most one external-texture copy per frame:
 *
 *  - VideoFrame path (default when WebCodecs + rVFC + importExternalTexture
 *    exist): copy only when the pump decoded a new frame; keep the frame open
 *    until after queue.submit, then close it, exactly once.
 *  - Element path (fallback, `?video_ingest=element`, or after a pump
 *    failure): import the <video> every frame as before.
 */

import { reportError } from '../ErrorHandling';
import {
  encodeExternalCopy,
  encodeVideoFrame as encodeElementFrame,
  releaseStill,
  WebGPUMediaInputContext,
  WebGPUMediaInputState,
} from '../webgpu/WebGPUMediaInput';
import { safeClose, supportsVideoFrameIngest, VideoFramePump, VideoIngestStats } from './videoFramePump';

export interface VideoIngestDeps {
  device: GPUDevice | null;
  media: WebGPUMediaInputState;
  context: () => WebGPUMediaInputContext;
  timestamps?: () => GPURenderPassTimestampWrites | undefined;
}

export class VideoIngest {
  private pump: VideoFramePump | null = null;
  private submitted: VideoFrame | null = null;
  private elementFrames = 0;

  constructor(private readonly videoFrameDisabled = false) {}

  /** Forget the current element's pump (new element, teardown, device loss). */
  detach(): void {
    this.pump?.detach();
    this.pump = null;
    this.afterSubmit();
  }

  /** Encode this frame's copy, if any. True when commands were added to `encoder`. */
  encode(encoder: GPUCommandEncoder, deps: VideoIngestDeps): boolean {
    const video = deps.media.video;
    const pump = video && !video.error ? this.ensurePump(deps.device, video) : null;
    if (!pump) {
      const encoded = encodeElementFrame(deps.context(), deps.media, encoder, deps.timestamps);
      if (encoded) this.elementFrames++;
      return encoded;
    }

    const frame = pump.takeLatest();
    if (!frame) return false; // nothing new decoded: sourceTex still holds the last frame
    releaseStill(deps.media);
    try {
      if (!encodeExternalCopy(deps.context(), frame, encoder, deps.timestamps)) {
        safeClose(frame);
        return false;
      }
    } catch (e) {
      safeClose(frame);
      const reason = `importExternalTexture(VideoFrame) failed: ${e instanceof Error ? e.message : String(e)}`;
      pump.fail(reason);
      reportError({ type: 'media-load', message: `Video ingest fell back to the element path (${reason})`, recoverable: true });
      return encodeElementFrame(deps.context(), deps.media, encoder, deps.timestamps);
    }
    safeClose(this.submitted);
    this.submitted = frame;
    pump.noteIngested();
    return true;
  }

  /** After queue.submit: the GPU work holds its own reference; close the frame. */
  afterSubmit(): void {
    safeClose(this.submitted);
    this.submitted = null;
  }

  stats(hasVideo: boolean): VideoIngestStats {
    if (this.pump) return this.pump.getStats();
    return {
      ingestPath: hasVideo ? 'element' : 'none',
      framesIngested: this.elementFrames,
      droppedFrames: 0,
      missedFrames: 0,
      queueDepth: 0,
      ...(this.videoFrameDisabled ? { fallbackReason: '?video_ingest=element' } : {}),
    };
  }

  private ensurePump(device: GPUDevice | null, video: HTMLVideoElement): VideoFramePump | null {
    if (this.videoFrameDisabled) return null;
    if (this.pump?.element === video) return this.pump.healthy ? this.pump : null;
    if (!supportsVideoFrameIngest(device, video)) return null;
    this.pump?.detach();
    this.pump = new VideoFramePump(video);
    return this.pump;
  }
}
