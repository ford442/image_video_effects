/**
 * offlineEncoder.ts — offline export encode + mux (#1401). Part of the lazy "gpu-encode"
 * chunk (re-exported by gpuEncoder.ts; never import statically from the page bundle).
 *
 * Unlike the realtime GpuEncodeRecorder, nothing here is paced by rAF: the caller hands
 * over frame n when the renderer has produced it, and `encode` waits (backpressure) while
 * the encoder is behind instead of dropping frames. Every frame given is in the file.
 *
 *   .mp4  — mp4-muxer: H.264 / HEVC / AV1 / VP9 (what Resolume, Premiere, Instagram take)
 *   .webm — webm-muxer: VP9 / AV1 / VP8
 *
 * Output goes to a FileSystemWritableFileStream when the page got one (streamed to disk,
 * no 2 GiB Blob ceiling) or to memory → Blob.
 */

import {
  ArrayBufferTarget as Mp4ArrayBufferTarget,
  FileSystemWritableFileStreamTarget as Mp4FileTarget,
  Muxer as Mp4Muxer,
} from 'mp4-muxer';
import {
  ArrayBufferTarget as WebmArrayBufferTarget,
  FileSystemWritableFileStreamTarget as WebmFileTarget,
  Muxer as WebmMuxer,
} from 'webm-muxer';
import {
  offlineBitrate,
  offlineCodecCandidates,
  type OfflineCodecCandidate,
  type OfflineCodecChoice,
  type OfflineContainer,
  type OfflineQuality,
} from './offlineExportPlan';

export interface OfflineEncodeOptions {
  width: number;
  height: number;
  fps: number;
  container: OfflineContainer;
  codec: OfflineCodecChoice;
  quality: OfflineQuality;
  /** Overrides the ladder (bits per second). */
  bitrate?: number;
  /** Stream to this file (File System Access API); omitted → in memory, finish() returns a Blob. */
  stream?: FileSystemWritableFileStream | null;
  /** Seconds between keyframes (default 2). */
  keyframeIntervalSec?: number;
}

export interface PickedOfflineEncoder {
  candidate: OfflineCodecCandidate;
  config: VideoEncoderConfig;
}

/** Most frames the encoder may hold before `encode` waits for it. */
export const OFFLINE_MAX_ENCODE_QUEUE = 8;

type IsConfigSupported = (config: VideoEncoderConfig) => Promise<VideoEncoderSupport>;

/** The first candidate (best first) this browser can encode at this size, rate and bitrate. */
export async function pickOfflineEncoderConfig(
  opts: Pick<OfflineEncodeOptions, 'width' | 'height' | 'fps' | 'container' | 'codec' | 'quality' | 'bitrate'>,
  isConfigSupported: IsConfigSupported = (c) => VideoEncoder.isConfigSupported(c),
): Promise<PickedOfflineEncoder | null> {
  for (const candidate of offlineCodecCandidates(opts.container, opts.codec, opts.width, opts.height, opts.fps)) {
    const config: VideoEncoderConfig & { hevc?: { format: 'hevc' } } = {
      codec: candidate.codec,
      width: opts.width,
      height: opts.height,
      framerate: opts.fps,
      bitrate: opts.bitrate ?? offlineBitrate(opts.width, opts.height, opts.fps, candidate.id, opts.quality),
      bitrateMode: 'variable',
      latencyMode: 'quality',
      ...(candidate.id === 'h264' ? { avc: { format: 'avc' as const } } : {}),
      ...(candidate.id === 'hevc' ? { hevc: { format: 'hevc' as const } } : {}),
    };
    try {
      const support = await isConfigSupported(config);
      if (support.supported) return { candidate, config: support.config ?? config };
    } catch {
      // Unknown codec string on this browser: try the next one.
    }
  }
  return null;
}

interface AnyMuxer {
  addVideoChunk(chunk: EncodedVideoChunk, meta?: EncodedVideoChunkMetadata): void;
  finalize(): void;
}

export interface OfflineEncoderDeps {
  isConfigSupported?: IsConfigSupported;
  createEncoder?: (init: VideoEncoderInit) => VideoEncoder;
}

export class OfflineEncodeSession {
  framesEncoded = 0;
  private encodeError: Error | null = null;
  private closed = false;

  private constructor(
    readonly candidate: OfflineCodecCandidate,
    readonly config: VideoEncoderConfig,
    private readonly encoder: VideoEncoder,
    private readonly muxer: AnyMuxer,
    private readonly bufferTarget: { buffer: ArrayBuffer } | null,
    private readonly keyframeEvery: number,
  ) {}

  /** Null when no candidate codec is supported for this container, size and rate. */
  static async start(opts: OfflineEncodeOptions, deps: OfflineEncoderDeps = {}): Promise<OfflineEncodeSession | null> {
    const picked = await pickOfflineEncoderConfig(opts, deps.isConfigSupported);
    if (!picked) return null;
    const { candidate, config } = picked;
    const stream = opts.stream ?? null;
    const toFile = stream !== null;

    let muxer: AnyMuxer;
    let bufferTarget: { buffer: ArrayBuffer } | null = null;
    if (opts.container === 'mp4') {
      const target = stream ? new Mp4FileTarget(stream) : new Mp4ArrayBufferTarget();
      if (!toFile) bufferTarget = target as Mp4ArrayBufferTarget;
      muxer = new Mp4Muxer({
        target,
        video: { codec: candidate.muxCodec as 'avc' | 'hevc' | 'vp9' | 'av1', width: opts.width, height: opts.height, frameRate: opts.fps },
        // In memory the index goes up front (Fast Start); streaming writes it at the end.
        fastStart: toFile ? false : 'in-memory',
        firstTimestampBehavior: 'offset',
      });
    } else {
      const target = stream ? new WebmFileTarget(stream) : new WebmArrayBufferTarget();
      if (!toFile) bufferTarget = target as WebmArrayBufferTarget;
      muxer = new WebmMuxer({
        target,
        video: { codec: candidate.muxCodec, width: opts.width, height: opts.height, frameRate: opts.fps },
        firstTimestampBehavior: 'offset',
      });
    }

    let session: OfflineEncodeSession | null = null;
    const init: VideoEncoderInit = {
      output: (chunk, meta) => muxer.addVideoChunk(chunk, meta),
      error: (e) => {
        if (session) session.encodeError = e instanceof Error ? e : new Error(String(e));
      },
    };
    const encoder = deps.createEncoder ? deps.createEncoder(init) : new VideoEncoder(init);
    encoder.configure(config);
    const keyframeEvery = Math.max(1, Math.round((opts.keyframeIntervalSec ?? 2) * opts.fps));
    session = new OfflineEncodeSession(candidate, config, encoder, muxer, bufferTarget, keyframeEvery);
    return session;
  }

  /**
   * Encode frame `index` (takes ownership: the frame is closed). Waits while the encoder
   * holds more than OFFLINE_MAX_ENCODE_QUEUE frames, so memory stays bounded at 8K.
   */
  async encode(frame: VideoFrame, index: number): Promise<void> {
    try {
      if (this.encodeError) throw this.encodeError;
      if (this.closed || this.encoder.state !== 'configured') throw new Error('offline encoder is closed');
      this.encoder.encode(frame, { keyFrame: index % this.keyframeEvery === 0 });
      this.framesEncoded++;
    } finally {
      frame.close();
    }
    while (this.encoder.encodeQueueSize > OFFLINE_MAX_ENCODE_QUEUE && !this.encodeError) {
      await waitForDequeue(this.encoder);
    }
    if (this.encodeError) throw this.encodeError;
  }

  /** Flush and finalize. Returns the file as a Blob when it was built in memory, else null. */
  async finish(): Promise<Blob | null> {
    if (this.encodeError) {
      this.abort();
      throw this.encodeError;
    }
    if (this.framesEncoded === 0) {
      this.abort();
      throw new Error('offline encoder received no frames');
    }
    await this.encoder.flush();
    if (this.encodeError) {
      this.abort();
      throw this.encodeError;
    }
    this.encoder.close();
    this.closed = true;
    this.muxer.finalize();
    if (!this.bufferTarget) return null;
    const type = this.candidate.container === 'mp4' ? 'video/mp4' : 'video/webm';
    return new Blob([this.bufferTarget.buffer], { type });
  }

  /** Stop without a file (cancel / error). Safe to call twice. */
  abort(): void {
    if (this.closed) return;
    this.closed = true;
    try {
      if (this.encoder.state !== 'closed') this.encoder.close();
    } catch {
      // already closed
    }
  }
}

/** Resolve on the encoder's next `dequeue`; a short timer covers browsers without the event. */
function waitForDequeue(encoder: VideoEncoder): Promise<void> {
  return new Promise((resolve) => {
    let done = false;
    const finish = () => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      encoder.removeEventListener?.('dequeue', finish);
      resolve();
    };
    const timer = setTimeout(finish, 20);
    encoder.addEventListener?.('dequeue', finish);
  });
}
