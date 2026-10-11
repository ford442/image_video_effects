/**
 * @jest-environment jsdom
 */
import {
  GPU_ENCODE_CODECS,
  GpuEncodeRecorder,
  GpuFrameSource,
  pickEncoderConfig,
  readbackFrameSource,
} from './gpuEncoder';

const mockMuxerInstances: Array<{ addVideoChunk: jest.Mock; finalize: jest.Mock; options: unknown; target: { buffer: ArrayBuffer } }> = [];

jest.mock('webm-muxer', () => ({
  ArrayBufferTarget: class {
    buffer = new ArrayBuffer(16);
  },
  Muxer: class {
    addVideoChunk = jest.fn();
    finalize = jest.fn();
    target: { buffer: ArrayBuffer };
    options: { target: { buffer: ArrayBuffer } };
    constructor(opts: { target: { buffer: ArrayBuffer } }) {
      this.options = opts;
      this.target = opts.target;
      mockMuxerInstances.push(this as never);
    }
  },
}));

class FakeVideoFrame {
  close = jest.fn();
  constructor(public source: unknown, public init: Record<string, unknown>) {}
}

let supportedCodecs = new Set<string>(['vp09.00.10.08']);
const encoders: FakeVideoEncoder[] = [];

class FakeVideoEncoder {
  static async isConfigSupported(config: VideoEncoderConfig) {
    return { supported: supportedCodecs.has(config.codec), config };
  }
  state: 'unconfigured' | 'configured' | 'closed' = 'unconfigured';
  encodeQueueSize = 0;
  configure = jest.fn(() => { this.state = 'configured'; });
  encode = jest.fn((_frame: unknown, _opts: { keyFrame: boolean }) => {
    this.init.output({ byteLength: 1 }, {});
  });
  flush = jest.fn(async () => {});
  close = jest.fn(() => { this.state = 'closed'; });
  constructor(public init: { output: (c: unknown, m: unknown) => void; error: (e: unknown) => void }) {
    encoders.push(this);
  }
}

function manualRaf() {
  let t = 0;
  let pending: ((now: number) => void) | null = null;
  return {
    request: (cb: (now: number) => void) => { pending = cb; return 1; },
    cancel: () => { pending = null; },
    now: () => t,
    async advance(ms: number) {
      t += ms;
      const cb = pending;
      pending = null;
      cb?.(t);
      await new Promise((r) => setTimeout(r, 0));
    },
  };
}

beforeEach(() => {
  supportedCodecs = new Set(['vp09.00.10.08']);
  encoders.length = 0;
  mockMuxerInstances.length = 0;
  (global as Record<string, unknown>).VideoEncoder = FakeVideoEncoder;
  (global as Record<string, unknown>).VideoFrame = FakeVideoFrame;
});

const opts = { width: 64, height: 48, fps: 30, bitrate: 1_000_000 };

describe('pickEncoderConfig', () => {
  it('returns the first supported WebM codec in preference order', async () => {
    supportedCodecs = new Set(['vp8', 'av01.0.04M.08']);
    const picked = await pickEncoderConfig(opts);
    expect(picked?.codec.muxCodec).toBe('V_AV1');
  });

  it('returns null when nothing is supported, and survives throwing probes', async () => {
    const probe = jest.fn(async () => { throw new Error('bad codec'); });
    expect(await pickEncoderConfig(opts, probe)).toBeNull();
    expect(probe).toHaveBeenCalledTimes(GPU_ENCODE_CODECS.length);
  });
});

describe('GpuEncodeRecorder', () => {
  it('encodes paced frames and produces a WebM blob without putImageData', async () => {
    const raf = manualRaf();
    const source: GpuFrameSource = {
      kind: 'canvas',
      grab: jest.fn((timestamp: number) => new FakeVideoFrame('canvas', { timestamp }) as unknown as VideoFrame),
    };
    const getContext = jest.spyOn(HTMLCanvasElement.prototype, 'getContext');

    const recorder = await GpuEncodeRecorder.start(source, opts, raf);
    expect(recorder).not.toBeNull();
    expect(mockMuxerInstances[0]!.options).toMatchObject({ video: { codec: 'V_VP9', width: 64, height: 48 } });

    await raf.advance(34);
    await raf.advance(10); // under 1/fps — skipped
    await raf.advance(34);

    expect(source.grab).toHaveBeenCalledTimes(2);
    const enc = encoders[0];
    expect(enc).toBeDefined();
    expect(enc!.encode).toHaveBeenCalledTimes(2);
    expect(enc!.encode.mock.calls[0]![1]).toEqual({ keyFrame: true });
    expect(enc!.encode.mock.calls[1]![1]).toEqual({ keyFrame: false });

    const blob = await recorder!.stop();
    expect(blob.type).toBe('video/webm');
    expect(enc!.flush).toHaveBeenCalled();
    expect(mockMuxerInstances[0]!.finalize).toHaveBeenCalled();
    expect(mockMuxerInstances[0]!.addVideoChunk).toHaveBeenCalledTimes(2);
    expect(getContext).not.toHaveBeenCalled();
  });

  describe('colour tag', () => {
    class ColourFrame extends FakeVideoFrame {
      constructor(source: unknown, init: Record<string, unknown>, public colorSpace: { primaries: string | null }) {
        super(source, init);
      }
    }
    /** Replace the mocked muxer's output with a header that carries a webm-muxer-style Colour element. */
    function seedColourHeader(): ArrayBuffer {
      const header = new Uint8Array([
        0x55, 0xb0, 0x10, 0x00, 0x00, 0x10,
        0x55, 0xb1, 0x81, 6, 0x55, 0xba, 0x81, 6, 0x55, 0xbb, 0x81, 6, 0x55, 0xb9, 0x81, 1,
      ]);
      mockMuxerInstances[0]!.target.buffer = header.buffer as ArrayBuffer;
      return header.buffer as ArrayBuffer;
    }
    async function record(primaries: Array<string | null>) {
      const raf = manualRaf();
      let n = 0;
      const source: GpuFrameSource = {
        kind: 'canvas',
        grab: (timestamp: number) =>
          new ColourFrame('canvas', { timestamp }, { primaries: primaries[n++ % primaries.length]! }) as unknown as VideoFrame,
      };
      const recorder = await GpuEncodeRecorder.start(source, opts, raf);
      const buffer = seedColourHeader();
      for (let i = 0; i < primaries.length; i++) await raf.advance(34);
      const blob = await recorder!.stop();
      return { recorder: recorder!, blob, bytes: new Uint8Array(buffer) };
    }

    it('tags the file Display P3 when every frame reports smpte432 primaries', async () => {
      const { recorder, bytes } = await record(['smpte432', 'smpte432']);
      expect(recorder.colorTag).toBe('display-p3');
      expect(bytes[17]).toBe(12); // Primaries
      expect(bytes[13]).toBe(13); // Transfer
    });

    it('leaves sRGB takes with the encoder default tag', async () => {
      const { recorder, bytes } = await record(['bt709', 'bt709']);
      expect(recorder.colorTag).toBe('encoder-default');
      expect(bytes[17]).toBe(6);
    });

    it('does not tag a take that mixes color spaces', async () => {
      const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
      const { recorder, bytes } = await record(['smpte432', 'bt709']);
      expect(recorder.colorTag).toBe('encoder-default');
      expect(bytes[17]).toBe(6);
      expect(warn).toHaveBeenCalledWith(expect.stringContaining('not tagged'));
      warn.mockRestore();
    });

    it('warns when P3 frames could not be tagged (no Colour element found)', async () => {
      const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
      const raf = manualRaf();
      const source: GpuFrameSource = {
        kind: 'canvas',
        grab: (timestamp: number) => new ColourFrame('c', { timestamp }, { primaries: 'smpte432' }) as unknown as VideoFrame,
      };
      const recorder = await GpuEncodeRecorder.start(source, opts, raf);
      await raf.advance(34);
      await recorder!.stop();
      expect(recorder!.colorTag).toBe('encoder-default');
      expect(warn).toHaveBeenCalledWith(expect.stringContaining('not tagged'));
      warn.mockRestore();
    });
  });

  it('resolves null when no codec is supported', async () => {
    supportedCodecs = new Set();
    const source: GpuFrameSource = { kind: 'canvas', grab: jest.fn() };
    expect(await GpuEncodeRecorder.start(source, opts, manualRaf())).toBeNull();
  });

  it('rejects on stop when no frame was captured', async () => {
    const source: GpuFrameSource = { kind: 'canvas', grab: () => null };
    const recorder = await GpuEncodeRecorder.start(source, opts, manualRaf());
    await expect(recorder!.stop()).rejects.toThrow('no frames');
    expect(encoders[0]!.close).toHaveBeenCalled();
  });

  it('readbackFrameSource wraps RGBA readback into an RGBA VideoFrame', async () => {
    const data = new Uint8ClampedArray(4 * 2 * 2);
    const source = readbackFrameSource(async () => ({ data, width: 2, height: 2 }) as ImageData);
    const frame = (await source.grab(1234)) as unknown as FakeVideoFrame;
    expect(frame.source).toBe(data);
    expect(frame.init).toEqual({ format: 'RGBA', codedWidth: 2, codedHeight: 2, timestamp: 1234 });
  });
});
