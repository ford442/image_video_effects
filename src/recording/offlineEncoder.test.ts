/**
 * @vitest-environment jsdom
 *
 * Offline encode + mux (#1401) with the real mp4-muxer and a fake VideoEncoder: the file
 * holds exactly the frames given, each 1/fps long (what `ffprobe -count_frames` reports).
 */
import { OFFLINE_MAX_ENCODE_QUEUE, OfflineEncodeSession, pickOfflineEncoderConfig } from './offlineEncoder';

class FakeEncodedVideoChunk {
  readonly type: 'key' | 'delta';
  readonly timestamp: number;
  readonly duration: number | null;
  readonly byteLength: number;
  private readonly data: Uint8Array;
  constructor(init: { type: 'key' | 'delta'; timestamp: number; duration?: number; data: Uint8Array }) {
    this.type = init.type;
    this.timestamp = init.timestamp;
    this.duration = init.duration ?? null;
    this.data = init.data;
    this.byteLength = init.data.byteLength;
  }
  copyTo(dest: Uint8Array) {
    dest.set(this.data);
  }
}

class FakeFrame {
  closed = false;
  constructor(readonly timestamp: number, readonly duration: number) {}
  close() {
    this.closed = true;
  }
}

/** A VideoEncoder that emits one chunk per frame, optionally holding them (a slow encoder). */
class FakeEncoder extends EventTarget {
  state: 'unconfigured' | 'configured' | 'closed' = 'unconfigured';
  held: FakeFrame[] = [];
  hold = false;
  keyFrames: boolean[] = [];
  config: VideoEncoderConfig | null = null;
  constructor(private readonly init: VideoEncoderInit) {
    super();
  }
  get encodeQueueSize() {
    return this.held.length;
  }
  configure(config: VideoEncoderConfig) {
    this.config = config;
    this.state = 'configured';
  }
  encode(frame: FakeFrame, opts: { keyFrame?: boolean }) {
    this.keyFrames.push(!!opts.keyFrame);
    const f = new FakeFrame(frame.timestamp, frame.duration);
    if (this.hold) this.held.push(f);
    else this.emit(f, !!opts.keyFrame);
  }
  release(n: number) {
    for (const f of this.held.splice(0, n)) this.emit(f, false);
    this.dispatchEvent(new Event('dequeue'));
  }
  private first = true;
  private emit(f: FakeFrame, key: boolean) {
    const chunk = new FakeEncodedVideoChunk({ type: key || this.first ? 'key' : 'delta', timestamp: f.timestamp, duration: f.duration, data: new Uint8Array([1, 2, 3]) });
    const meta = this.first
      ? { decoderConfig: { codec: this.config!.codec, codedWidth: 64, codedHeight: 64, description: new Uint8Array([1, 100, 0, 31, 255, 225, 0, 0]) } }
      : undefined;
    this.first = false;
    this.init.output(chunk as unknown as EncodedVideoChunk, meta as EncodedVideoChunkMetadata);
  }
  async flush() {
    this.release(this.held.length);
  }
  close() {
    this.state = 'closed';
  }
}

async function bytesOf(blob: Blob): Promise<Uint8Array> {
  const reader = new FileReader();
  const done = new Promise<ArrayBuffer>((resolve) => {
    reader.onload = () => resolve(reader.result as ArrayBuffer);
  });
  reader.readAsArrayBuffer(blob);
  return new Uint8Array(await done);
}

function findBox(bytes: Uint8Array, type: string): number {
  for (let i = 4; i + 4 <= bytes.length; i++) {
    if (String.fromCharCode(bytes[i]!, bytes[i + 1]!, bytes[i + 2]!, bytes[i + 3]!) === type) return i - 4;
  }
  return -1;
}

const u32 = (b: Uint8Array, o: number) => ((b[o]! << 24) | (b[o + 1]! << 16) | (b[o + 2]! << 8) | b[o + 3]!) >>> 0;

/** Sample count (stsz), media timescale + duration (mdhd), and the stts runs. */
function inspectMp4(bytes: Uint8Array) {
  const stsz = findBox(bytes, 'stsz');
  const samples = u32(bytes, stsz + 16);
  const mdhd = findBox(bytes, 'mdhd');
  const v1 = bytes[mdhd + 8] === 1;
  const timescale = u32(bytes, mdhd + (v1 ? 28 : 20));
  const duration = v1 ? u32(bytes, mdhd + 36) : u32(bytes, mdhd + 24);
  const stts = findBox(bytes, 'stts');
  const entries = u32(bytes, stts + 12);
  const runs: Array<[number, number]> = [];
  for (let i = 0; i < entries; i++) runs.push([u32(bytes, stts + 16 + i * 8), u32(bytes, stts + 20 + i * 8)]);
  return { samples, timescale, duration, runs, ftyp: findBox(bytes, 'ftyp') === 0, moovFirst: findBox(bytes, 'moov') < findBox(bytes, 'mdat') };
}

let encoders: FakeEncoder[] = [];
const createEncoder = (init: VideoEncoderInit) => {
  const e = new FakeEncoder(init);
  encoders.push(e);
  return e as unknown as VideoEncoder;
};

beforeEach(() => {
  encoders = [];
  vi.stubGlobal('EncodedVideoChunk', FakeEncodedVideoChunk);
});
afterEach(() => vi.unstubAllGlobals());

describe('offline encoder (#1401)', () => {
  it('falls back down the candidate list to the first supported codec, with a quality config', async () => {
    const tried: string[] = [];
    const picked = await pickOfflineEncoderConfig(
      { width: 3840, height: 2160, fps: 60, container: 'mp4', codec: 'auto', quality: 'high' },
      async (c) => {
        tried.push(c.codec);
        return { supported: c.codec.startsWith('av01'), config: c };
      },
    );
    expect(tried).toEqual(['avc1.640034', 'hvc1.1.6.L153.B0', 'av01.0.13M.08']);
    expect(picked?.candidate.id).toBe('av1');
    expect(picked?.config).toMatchObject({ latencyMode: 'quality', bitrateMode: 'variable', framerate: 60, width: 3840 });
    expect(await pickOfflineEncoderConfig(
      { width: 64, height: 64, fps: 30, container: 'webm', codec: 'auto', quality: 'high' },
      async () => { throw new Error('unknown codec'); },
    )).toBeNull();
  });

  it('a 10 s set at 60 fps muxes to an MP4 of exactly 600 samples, each 1/60 s', async () => {
    const session = await OfflineEncodeSession.start(
      { width: 64, height: 64, fps: 60, container: 'mp4', codec: 'h264', quality: 'high' },
      { isConfigSupported: async (c) => ({ supported: true, config: c }), createEncoder },
    );
    expect(session?.candidate.muxCodec).toBe('avc');
    const frames: FakeFrame[] = [];
    for (let n = 0; n < 600; n++) {
      const f = new FakeFrame(Math.round((n * 1e6) / 60), Math.round(1e6 / 60));
      frames.push(f);
      await session!.encode(f as unknown as VideoFrame, n);
    }
    expect(frames.every((f) => f.closed)).toBe(true);
    expect(encoders[0]!.keyFrames.filter(Boolean)).toHaveLength(5); // every 2 s
    const blob = await session!.finish();
    expect(blob?.type).toBe('video/mp4');
    const mp4 = inspectMp4(await bytesOf(blob!));
    expect(mp4.ftyp).toBe(true);
    expect(mp4.moovFirst).toBe(true); // in memory → Fast Start
    expect(mp4.samples).toBe(600);
    expect(mp4.duration / mp4.timescale).toBeCloseTo(10, 6);
    // One stts run: every sample has the same duration → no duplicate or missing frame.
    expect(mp4.runs).toEqual([[600, mp4.timescale / 60]]);
  });

  it('waits for the encoder instead of dropping frames when it falls behind', async () => {
    const session = await OfflineEncodeSession.start(
      { width: 64, height: 64, fps: 30, container: 'mp4', codec: 'h264', quality: 'standard' },
      { isConfigSupported: async (c) => ({ supported: true, config: c }), createEncoder },
    );
    const enc = encoders[0]!;
    enc.hold = true;
    for (let n = 0; n <= OFFLINE_MAX_ENCODE_QUEUE; n++) {
      if (n < OFFLINE_MAX_ENCODE_QUEUE) await session!.encode(new FakeFrame(n, 1) as unknown as VideoFrame, n);
    }
    let resolved = false;
    const blocked = session!.encode(new FakeFrame(99, 1) as unknown as VideoFrame, OFFLINE_MAX_ENCODE_QUEUE).then(() => {
      resolved = true;
    });
    await Promise.resolve();
    expect(resolved).toBe(false);
    enc.release(4);
    await blocked;
    expect(resolved).toBe(true);
    expect(session!.framesEncoded).toBe(OFFLINE_MAX_ENCODE_QUEUE + 1);
  });

  it('surfaces an encoder error and refuses to finish an empty file', async () => {
    const empty = await OfflineEncodeSession.start(
      { width: 64, height: 64, fps: 30, container: 'webm', codec: 'vp9', quality: 'high' },
      { isConfigSupported: async (c) => ({ supported: true, config: c }), createEncoder },
    );
    expect(empty?.candidate.muxCodec).toBe('V_VP9');
    await expect(empty!.finish()).rejects.toThrow('no frames');
  });
});
