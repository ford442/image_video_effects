/**
 * Offline render job (#1401) over a fake host and encoder: frame count and times, the set's
 * shader / param / source changes landing on the right frame, audio per frame, cancel and
 * failure paths always handing the renderer back to the live picture.
 */
import { OfflineRenderCancelled, runOfflineRender, slotParamsFor, type OfflineRenderHost } from './offlineRenderJob';
import type { OfflineEncodeSession } from './offlineEncoder';
import type { FrameInputSnapshot } from '../renderer/offlineRender';
import type { VjTimeline } from '../services/vjSetExport';

class Frame {
  closed = false;
  constructor(readonly timestamp: number) {}
  close() {
    this.closed = true;
  }
}

function fakeHost() {
  const log: string[] = [];
  const inputs: Array<{ t: number; input: FrameInputSnapshot }> = [];
  const host: OfflineRenderHost & { failNextFrame?: boolean } = {
    beginOfflineRender: vi.fn(async (o) => {
      log.push(`begin ${o.width}x${o.height}@${o.fps}`);
      return { width: o.width, height: o.height, scaledW: o.width, scaledH: o.height, fps: o.fps, maxTextureDimension2D: 8192 };
    }),
    renderFrameAt: vi.fn(async (t: number, input: FrameInputSnapshot) => {
      inputs.push({ t, input });
      if (host.failNextFrame) return null;
      return new Frame(Math.round(t * 1e6)) as unknown as VideoFrame;
    }),
    endOfflineRender: vi.fn(async () => {
      log.push('end');
    }),
    loadShader: vi.fn(async (id: string) => {
      log.push(`load ${id}`);
      return id !== 'broken';
    }),
    setSlotShader: vi.fn((i: number, id: string) => {
      log.push(`slot${i}=${id || '∅'}@${inputs.length}`);
    }),
    setInputSource: vi.fn((s) => {
      log.push(`source ${s}@${inputs.length}`);
    }),
    loadImage: vi.fn(async (url: string) => {
      log.push(`image ${url}@${inputs.length}`);
    }),
    reloadInputStill: vi.fn(async () => true),
    restoreLive: vi.fn(async () => {
      log.push('restore');
    }),
  };
  return { host, log, inputs };
}

function fakeEncoder() {
  const encoded: Frame[] = [];
  const session = {
    candidate: { id: 'h264', container: 'mp4', codec: 'avc1.640028', muxCodec: 'avc' },
    framesEncoded: 0,
    encode: vi.fn(async (frame: Frame) => {
      encoded.push(frame);
      frame.close();
    }),
    finish: vi.fn(async () => new Blob(['mp4'], { type: 'video/mp4' })),
    abort: vi.fn(),
  };
  return { session, encoded, start: vi.fn(async () => session as unknown as OfflineEncodeSession) };
}

const SET: VjTimeline = {
  hz: 20,
  durationMs: 1000,
  events: [
    { t: 0, slot: 0, kind: 'source', value: { type: 'image', url: 'https://x/a.jpg' } },
    { t: 0, slot: 0, kind: 'shader', value: 'liquid' },
    { t: 0, slot: 0, kind: 'param', key: 'zoomParam1', value: 0.2 },
    { t: 500, slot: 1, kind: 'shader', value: 'plasma' },
    { t: 500, slot: 0, kind: 'param', key: 'zoomParam1', value: 0.8 },
  ],
};

const OPTS = { timeline: SET, width: 640, height: 360, fps: 10, container: 'mp4' as const, codec: 'auto' as const, quality: 'high' as const };

describe('runOfflineRender (#1401)', () => {
  it('renders exactly duration × fps frames at n / fps, encodes each once, and returns the file', async () => {
    const { host, log, inputs } = fakeHost();
    const enc = fakeEncoder();
    const result = await runOfflineRender(host, OPTS, { startEncoder: enc.start });
    expect(result.frames).toBe(10);
    expect(inputs.map((f) => f.t)).toEqual([0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]);
    expect(enc.encoded.map((f) => f.timestamp)).toEqual([0, 100_000, 200_000, 300_000, 400_000, 500_000, 600_000, 700_000, 800_000, 900_000]);
    expect(new Set(enc.encoded.map((f) => f.timestamp)).size).toBe(10);
    expect(result.blob?.type).toBe('video/mp4');
    expect(log[0]).toBe('begin 640x360@10');
    expect(log.slice(-2)).toEqual(['end', 'restore']);
  });

  it('compiles every shader before frame 0 and applies changes on the frame they happen', async () => {
    const { host, log, inputs } = fakeHost();
    await runOfflineRender(host, OPTS, { startEncoder: fakeEncoder().start });
    const begin = log.indexOf('begin 640x360@10');
    expect(log.slice(begin + 1, begin + 3).sort()).toEqual(['load liquid', 'load plasma']);
    expect(log).toContain('source image@0');
    expect(log).toContain('image https://x/a.jpg@0');
    expect(log).toContain('slot0=liquid@0');
    expect(log).toContain('slot1=plasma@5'); // t = 500 ms is frame 5 at 10 fps
    expect(inputs[4]!.input.slotParams?.[0]).toEqual([0, 0.2, 0.5, 0.5, 0.5]);
    expect(inputs[5]!.input.slotParams?.[0]).toEqual([0, 0.8, 0.5, 0.5, 0.5]);
    expect(log.filter((l) => l.startsWith('slot0='))).toHaveLength(1);
  });

  it('two runs of the same set hand the renderer identical inputs (deterministic)', async () => {
    const a = fakeHost();
    const b = fakeHost();
    const audio = { samples: Float32Array.from({ length: 44_100 }, (_, i) => Math.sin(i / 3)), sampleRate: 44_100, durationSec: 1 };
    await runOfflineRender(a.host, { ...OPTS, audio }, { startEncoder: fakeEncoder().start });
    await runOfflineRender(b.host, { ...OPTS, audio }, { startEncoder: fakeEncoder().start });
    expect(b.inputs).toEqual(a.inputs);
    expect(a.inputs[3]!.input.audio?.some((v) => v > 0)).toBe(true);
    expect(a.inputs[3]!.input.bins).toHaveLength(128);
  });

  it('cancel stops between frames, aborts the encoder and restores the live picture', async () => {
    const { host, log, inputs } = fakeHost();
    const enc = fakeEncoder();
    const controller = new AbortController();
    const run = runOfflineRender(host, {
      ...OPTS,
      signal: controller.signal,
      onProgress: (p) => {
        if (p.frame === 3) controller.abort();
      },
    }, { startEncoder: enc.start });
    await expect(run).rejects.toBeInstanceOf(OfflineRenderCancelled);
    expect(inputs).toHaveLength(3);
    expect(enc.session.abort).toHaveBeenCalled();
    expect(enc.session.finish).not.toHaveBeenCalled();
    expect(log.slice(-2)).toEqual(['end', 'restore']);
  });

  it('a lost device (no picture) fails the job with a reason, still restoring the live picture', async () => {
    const { host, log } = fakeHost();
    host.failNextFrame = true;
    await expect(runOfflineRender(host, OPTS, { startEncoder: fakeEncoder().start })).rejects.toThrow(/no picture for frame 0/);
    expect(log.slice(-2)).toEqual(['end', 'restore']);
  });

  it('no encoder for the format: fails before touching the renderer', async () => {
    const { host } = fakeHost();
    await expect(runOfflineRender(host, OPTS, { startEncoder: vi.fn(async () => null) })).rejects.toThrow(/no MP4 encoder/);
    expect(host.beginOfflineRender).not.toHaveBeenCalled();
    expect(host.restoreLive).not.toHaveBeenCalled();
  });

  it('a shader that fails to compile empties its slot and is reported, the render continues', async () => {
    const { host, log } = fakeHost();
    const broken: VjTimeline = { ...SET, events: [...SET.events, { t: 300, slot: 2, kind: 'shader', value: 'broken' }] };
    const result = await runOfflineRender(host, { ...OPTS, timeline: broken }, { startEncoder: fakeEncoder().start });
    expect(result.failedShaders).toEqual(['broken']);
    expect(log).toContain('slot2=∅@3');
    expect(result.frames).toBe(10);
  });

  it('a video source gets the source frame at the timeline time, through its own element', async () => {
    const { host, inputs } = fakeHost();
    const seeks: number[] = [];
    const openVideo = vi.fn(async (url: string) => ({
      url,
      durationSec: 60,
      frameAt: vi.fn(async (t: number, ts: number) => {
        seeks.push(Math.round(t * 1000) / 1000);
        return new Frame(ts) as unknown as VideoFrame;
      }),
      close: vi.fn(),
    }));
    const timeline: VjTimeline = {
      hz: 20,
      durationMs: 400,
      events: [{ t: 0, slot: 0, kind: 'source', value: { type: 'video', url: 'https://x/v.mp4', seekSec: 30 } }],
    };
    await runOfflineRender(host, { ...OPTS, timeline }, { startEncoder: fakeEncoder().start, openVideo });
    expect(openVideo).toHaveBeenCalledWith('https://x/v.mp4');
    expect(seeks).toEqual([30, 30.1, 30.2, 30.3]);
    expect(inputs.every((f) => !!f.input.videoFrame)).toBe(true);
  });

  it('slotParamsFor fills every slot, defaulting params to 0.5', () => {
    expect(slotParamsFor({ params: [{ zoomParam2: 0.1 }] })).toEqual([
      [0, 0.5, 0.1, 0.5, 0.5],
      [1, 0.5, 0.5, 0.5, 0.5],
      [2, 0.5, 0.5, 0.5, 0.5],
      [3, 0.5, 0.5, 0.5, 0.5],
      [4, 0.5, 0.5, 0.5, 0.5],
      [5, 0.5, 0.5, 0.5, 0.5],
    ]);
  });
});
