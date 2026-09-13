/**
 * gpuEncoder.ts — lazy "gpu-encode" chunk (never import statically).
 *
 * Recording 2.0: platform WebCodecs VideoEncoder + webm-muxer. Frames come from
 * a GpuFrameSource (the WebGPU canvas when the swapchain accepts COPY_SRC, or a
 * GPU readback for WASM); no Canvas2D putImageData and no MediaRecorder.
 */

import { ArrayBufferTarget, Muxer } from 'webm-muxer';

export interface GpuFrameSource {
  readonly kind: 'canvas' | 'readback';
  /** Snapshot the current output as a VideoFrame at `timestampUs`; null skips the tick. */
  grab(timestampUs: number): VideoFrame | null | Promise<VideoFrame | null>;
}

export interface GpuEncodeOptions {
  width: number;
  height: number;
  fps: number;
  bitrate: number;
}

/** WebM-muxable codecs in preference order (avc1 needs an MP4 muxer, so it is not offered). */
export const GPU_ENCODE_CODECS = [
  { codec: 'vp09.00.10.08', muxCodec: 'V_VP9' },
  { codec: 'av01.0.04M.08', muxCodec: 'V_AV1' },
  { codec: 'vp8', muxCodec: 'V_VP8' },
] as const;

export type GpuEncodeCodec = (typeof GPU_ENCODE_CODECS)[number];

const KEYFRAME_INTERVAL_US = 2_000_000;
/** Drop ticks while the encoder is this far behind rather than queueing unbounded frames. */
const MAX_ENCODE_QUEUE = 4;

/** The WebGPU canvas itself; valid once the swapchain was reconfigured with COPY_SRC. */
export function canvasFrameSource(canvas: HTMLCanvasElement): GpuFrameSource {
  return {
    kind: 'canvas',
    grab: (timestamp) => new VideoFrame(canvas, { timestamp, alpha: 'discard' }),
  };
}

/** RGBA8 readback (WASM beginFrameCapture) wrapped directly into a VideoFrame. */
export function readbackFrameSource(capture: () => Promise<ImageData>): GpuFrameSource {
  return {
    kind: 'readback',
    grab: async (timestamp) => {
      const img = await capture();
      return new VideoFrame(img.data, {
        format: 'RGBA',
        codedWidth: img.width,
        codedHeight: img.height,
        timestamp,
      });
    },
  };
}

export async function pickEncoderConfig(
  opts: GpuEncodeOptions,
  isConfigSupported: (c: VideoEncoderConfig) => Promise<VideoEncoderSupport> =
    (c) => VideoEncoder.isConfigSupported(c),
): Promise<{ codec: GpuEncodeCodec; config: VideoEncoderConfig } | null> {
  for (const codec of GPU_ENCODE_CODECS) {
    const config: VideoEncoderConfig = {
      codec: codec.codec,
      width: opts.width,
      height: opts.height,
      bitrate: opts.bitrate,
      framerate: opts.fps,
      latencyMode: 'quality',
    };
    try {
      const support = await isConfigSupported(config);
      if (support.supported) return { codec, config: support.config ?? config };
    } catch {
      // Malformed/unknown codec string on this browser: try the next one.
    }
  }
  return null;
}

type RafLike = {
  request: (cb: (now: number) => void) => number;
  cancel: (id: number) => void;
  now: () => number;
};

const browserRaf: RafLike = {
  request: (cb) => requestAnimationFrame(cb),
  cancel: (id) => cancelAnimationFrame(id),
  now: () => performance.now(),
};

export class GpuEncodeRecorder {
  private rafId: number | null = null;
  private grabbing = false;
  private stopped = false;
  private lastKeyUs = -Infinity;
  private lastFrameMs = -Infinity;
  private startMs = 0;
  private encodeError: Error | null = null;
  framesEncoded = 0;

  private constructor(
    private readonly source: GpuFrameSource,
    private readonly opts: GpuEncodeOptions,
    private readonly encoder: VideoEncoder,
    private readonly muxer: Muxer<ArrayBufferTarget>,
    readonly codec: GpuEncodeCodec,
    private readonly raf: RafLike,
  ) {}

  /** Resolves null when no WebM codec is supported (caller falls back to MediaRecorder). */
  static async start(
    source: GpuFrameSource,
    opts: GpuEncodeOptions,
    raf: RafLike = browserRaf,
  ): Promise<GpuEncodeRecorder | null> {
    const picked = await pickEncoderConfig(opts);
    if (!picked) return null;

    const muxer = new Muxer({
      target: new ArrayBufferTarget(),
      video: { codec: picked.codec.muxCodec, width: opts.width, height: opts.height, frameRate: opts.fps },
      firstTimestampBehavior: 'offset',
    });

    let recorder: GpuEncodeRecorder | null = null;
    const encoder = new VideoEncoder({
      output: (chunk, meta) => muxer.addVideoChunk(chunk, meta),
      error: (e) => {
        if (recorder) recorder.encodeError = e instanceof Error ? e : new Error(String(e));
      },
    });
    encoder.configure(picked.config);

    recorder = new GpuEncodeRecorder(source, opts, encoder, muxer, picked.codec, raf);
    recorder.startMs = raf.now();
    recorder.rafId = raf.request(recorder.tick);
    return recorder;
  }

  private tick = (now: number): void => {
    if (this.stopped) return;
    this.rafId = this.raf.request(this.tick);

    // Pace to the requested fps; allow 1ms slack so 60fps on a 60Hz display never drops.
    if (now - this.lastFrameMs < 1000 / this.opts.fps - 1) return;
    if (this.grabbing || this.encodeError || this.encoder.encodeQueueSize > MAX_ENCODE_QUEUE) return;
    this.lastFrameMs = now;

    const timestampUs = Math.round((now - this.startMs) * 1000);
    this.grabbing = true;
    Promise.resolve()
      .then(() => this.source.grab(timestampUs))
      .then((frame) => {
        if (!frame) return;
        try {
          if (!this.stopped && this.encoder.state === 'configured') {
            const keyFrame = timestampUs - this.lastKeyUs >= KEYFRAME_INTERVAL_US;
            if (keyFrame) this.lastKeyUs = timestampUs;
            this.encoder.encode(frame, { keyFrame });
            this.framesEncoded++;
          }
        } finally {
          frame.close();
        }
      })
      .catch((err) => {
        console.warn(`[GPU encode] ${this.source.kind} frame skipped:`, err);
      })
      .finally(() => {
        this.grabbing = false;
      });
  };

  async stop(): Promise<Blob> {
    if (!this.stopped) {
      this.stopped = true;
      if (this.rafId !== null) this.raf.cancel(this.rafId);
      this.rafId = null;
    }
    if (this.encodeError) {
      if (this.encoder.state !== 'closed') this.encoder.close();
      throw this.encodeError;
    }
    if (this.framesEncoded === 0) {
      if (this.encoder.state !== 'closed') this.encoder.close();
      throw new Error('[GPU encode] no frames were captured');
    }
    await this.encoder.flush();
    this.encoder.close();
    this.muxer.finalize();
    return new Blob([this.muxer.target.buffer], { type: 'video/webm' });
  }
}
