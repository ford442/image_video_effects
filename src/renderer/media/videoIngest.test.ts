import { LatestFrameQueue } from './latestFrameQueue';
import { supportsVideoFrameIngest, VideoFramePump } from './videoFramePump';
import { VideoIngest } from './videoIngest';
import { createMediaInputState, WebGPUMediaInputContext } from '../webgpu/WebGPUMediaInput';
import { createFakeGpu, summarizeOps } from '../testing/fakeGpu';

/** Fake VideoFrame that records close() calls (installed as the global). */
class FakeVideoFrame {
  static live = new Set<FakeVideoFrame>();
  static closes = 0;
  closed = false;
  label = 'videoFrame';
  constructor(public readonly source: unknown, public readonly init?: { timestamp: number }) {
    FakeVideoFrame.live.add(this);
  }
  close(): void {
    if (this.closed) throw new Error('closed twice');
    this.closed = true;
    FakeVideoFrame.closes++;
    FakeVideoFrame.live.delete(this);
  }
}

type FrameCb = (now: number, meta: VideoFrameCallbackMetadata) => void;

function fakeVideo() {
  let cb: FrameCb | null = null;
  let presented = 0;
  const video = {
    label: 'video',
    paused: false,
    readyState: 4,
    videoWidth: 640,
    videoHeight: 360,
    error: null as MediaError | null,
    requestVideoFrameCallback: jest.fn((fn: FrameCb) => { cb = fn; return 1; }),
    cancelVideoFrameCallback: jest.fn(() => { cb = null; }),
  };
  const present = (skip = 0) => {
    presented += 1 + skip;
    const fn = cb;
    cb = null;
    fn?.(0, { presentedFrames: presented, mediaTime: presented / 30 } as VideoFrameCallbackMetadata);
  };
  return { video: video as unknown as HTMLVideoElement, present, hasCallback: () => cb !== null };
}

beforeAll(() => {
  (globalThis as Record<string, unknown>).VideoFrame = FakeVideoFrame;
});
beforeEach(() => {
  FakeVideoFrame.live.clear();
  FakeVideoFrame.closes = 0;
});

describe('LatestFrameQueue', () => {
  it('keeps at most `depth` frames, dropping (and closing) the oldest', () => {
    const q = new LatestFrameQueue<FakeVideoFrame>(2);
    const frames = [1, 2, 3].map((i) => new FakeVideoFrame(i));
    frames.forEach((f) => q.push(f));
    expect(frames[0].closed).toBe(true);
    expect(q.getStats()).toEqual({ enqueued: 3, consumed: 0, dropped: 1 });
    expect(q.takeLatest()).toBe(frames[2]);
    expect(frames[1].closed).toBe(true); // superseded
    expect(q.getStats()).toEqual({ enqueued: 3, consumed: 1, dropped: 2 });
    expect(q.takeLatest()).toBeNull();
  });

  it('clear() closes queued frames without counting them as drops', () => {
    const q = new LatestFrameQueue<FakeVideoFrame>(2);
    q.push(new FakeVideoFrame(1));
    q.clear();
    expect(FakeVideoFrame.live.size).toBe(0);
    expect(q.getStats().dropped).toBe(0);
  });
});

describe('VideoFramePump', () => {
  it('turns presented frames into VideoFrames and counts missed presentations', () => {
    const v = fakeVideo();
    const pump = new VideoFramePump(v.video);
    v.present();
    v.present(2); // the browser presented two frames the callback never saw
    expect(pump.getStats()).toMatchObject({ ingestPath: 'videoframe', missedFrames: 2, queueDepth: 2 });
    const frame = pump.takeLatest() as unknown as FakeVideoFrame;
    expect(frame.init?.timestamp).toBe(Math.round((4 / 30) * 1e6));
    expect(v.hasCallback()).toBe(true);
    pump.detach();
    expect(v.video.cancelVideoFrameCallback).toHaveBeenCalled();
  });

  it('falls back on a SecurityError (tainted cross-origin source)', () => {
    const v = fakeVideo();
    const Original = (globalThis as Record<string, unknown>).VideoFrame;
    (globalThis as Record<string, unknown>).VideoFrame = class {
      constructor() { throw new DOMException('tainted', 'SecurityError'); }
    };
    const pump = new VideoFramePump(v.video);
    v.present();
    (globalThis as Record<string, unknown>).VideoFrame = Original;
    expect(pump.healthy).toBe(false);
    expect(pump.getStats()).toMatchObject({ ingestPath: 'element', fallbackReason: 'cross-origin video without CORS' });
  });

  it('requires WebCodecs, rVFC and importExternalTexture', () => {
    const fake = createFakeGpu();
    const v = fakeVideo();
    expect(supportsVideoFrameIngest(fake.device, v.video)).toBe(true);
    expect(supportsVideoFrameIngest(createFakeGpu({ externalTexture: false }).device, v.video)).toBe(false);
    expect(supportsVideoFrameIngest(fake.device, { } as HTMLVideoElement)).toBe(false);
  });
});

describe('VideoIngest', () => {
  function setup() {
    const fake = createFakeGpu();
    const v = fakeVideo();
    const media = createMediaInputState();
    media.video = v.video;
    const context = (): WebGPUMediaInputContext => ({
      device: fake.device,
      sourceTex: fake.texture('sourceTex'),
      readTex: fake.texture('readTex'),
      canvasW: 64,
      canvasH: 64,
      colorFormat: 'rgba32float',
      filterSampler: {} as GPUSampler,
      supportsExternalTexture: true,
      videoCopyPipeline: { label: 'videoCopyPipeline' } as unknown as GPURenderPipeline,
      videoCopyBindGroupLayout: { label: 'videoCopyBGL' } as unknown as GPUBindGroupLayout,
    });
    return { fake, v, media, deps: { device: fake.device, media, context } };
  }

  it('copies only when a new frame arrived and closes each frame exactly once after submit', () => {
    const { fake, v, deps } = setup();
    const ingest = new VideoIngest();
    const encoder = () => fake.device.createCommandEncoder({ label: 'frame' });

    expect(ingest.encode(encoder(), deps)).toBe(false); // pump starts; nothing decoded yet
    v.present();
    expect(ingest.encode(encoder(), deps)).toBe(true);
    expect(FakeVideoFrame.live.size).toBe(1); // held until submit
    ingest.afterSubmit();
    expect(FakeVideoFrame.live.size).toBe(0);
    expect(ingest.encode(encoder(), deps)).toBe(false); // no new frame → no copy

    v.present();
    v.present();
    v.present(); // three frames before the next render: two dropped
    expect(ingest.encode(encoder(), deps)).toBe(true);
    ingest.afterSubmit();
    expect(FakeVideoFrame.live.size).toBe(0);
    expect(ingest.stats(true)).toMatchObject({ ingestPath: 'videoframe', framesIngested: 2, droppedFrames: 2 });
    expect(summarizeOps(fake.ops).filter((op) => op.startsWith('render:videoCopyPass'))).toHaveLength(2);
    expect(FakeVideoFrame.closes).toBe(4);
  });

  it('detach() releases queued and in-flight frames', () => {
    const { fake, v, deps } = setup();
    const ingest = new VideoIngest();
    ingest.encode(fake.device.createCommandEncoder(), deps);
    v.present();
    ingest.encode(fake.device.createCommandEncoder(), deps); // one in flight
    v.present(); // one queued
    ingest.detach();
    expect(FakeVideoFrame.live.size).toBe(0);
  });

  it('falls back to the element path when importing a VideoFrame throws', () => {
    const { fake, v, deps } = setup();
    const ingest = new VideoIngest();
    ingest.encode(fake.device.createCommandEncoder(), deps);
    v.present();
    const original = fake.device.importExternalTexture;
    let calls = 0;
    (fake.device as { importExternalTexture: unknown }).importExternalTexture = (desc: { source: unknown }) => {
      calls++;
      if (desc.source instanceof FakeVideoFrame) throw new TypeError('unsupported source');
      return original.call(fake.device, desc as GPUExternalTextureDescriptor);
    };
    expect(ingest.encode(fake.device.createCommandEncoder(), deps)).toBe(true); // element path this frame
    expect(calls).toBe(2);
    expect(FakeVideoFrame.live.size).toBe(0);
    expect(ingest.stats(true).ingestPath).toBe('element');
  });

  it('honours the element-path override', () => {
    const { fake, deps } = setup();
    const ingest = new VideoIngest(true);
    expect(ingest.encode(fake.device.createCommandEncoder(), deps)).toBe(true);
    expect(ingest.stats(true)).toMatchObject({ ingestPath: 'element', framesIngested: 1, fallbackReason: '?video_ingest=element' });
  });
});
