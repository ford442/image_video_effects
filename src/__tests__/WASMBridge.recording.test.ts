/**
 * @jest-environment jsdom
 *
 * WASM bridge recording: Recording 2.0 (WebCodecs) is the default whenever
 * VideoEncoder exists; the Canvas2D putImageData → MediaRecorder pump is only a
 * last resort. Also covers the C++ swapchain COPY_SRC toggle.
 */

const mockCaptureFrame = jest.fn();
jest.mock('../wasm/bridge/capture', () => ({
  captureFrame: () => mockCaptureFrame(),
}));

type Recording = typeof import('../wasm/bridge/recording');
type BridgeState = typeof import('../wasm/bridge/state');

const putImageData = jest.fn();
const rafQueue: FrameRequestCallback[] = [];
const mediaRecorders: FakeMediaRecorder[] = [];

class FakeMediaRecorder {
  static isTypeSupported = jest.fn().mockReturnValue(true);
  state: RecordingState = 'inactive';
  ondataavailable: ((e: { data: Blob }) => void) | null = null;
  onstop: (() => void) | null = null;
  onerror: ((e: unknown) => void) | null = null;
  constructor(public stream: unknown, public options: unknown) {
    mediaRecorders.push(this);
  }
  start() {
    this.state = 'recording';
  }
  stop() {
    this.state = 'inactive';
    this.onstop?.();
  }
}

/** Let the bridge's awaited encoder start / readback promises settle (works under fake timers). */
async function settle(): Promise<void> {
  for (let i = 0; i < 10; i++) await Promise.resolve();
}

function flushRaf(): void {
  const pending = rafQueue.splice(0);
  pending.forEach((cb) => cb(performance.now()));
}

function installVideoEncoder(): void {
  (globalThis as Record<string, unknown>).VideoEncoder = class {};
  (globalThis as Record<string, unknown>).VideoFrame = class {};
}

function removeVideoEncoder(): void {
  delete (globalThis as Record<string, unknown>).VideoEncoder;
  delete (globalThis as Record<string, unknown>).VideoFrame;
}

describe('WASM bridge recording', () => {
  let rec: Recording;
  let bridgeState: BridgeState;
  const ccall = jest.fn();

  beforeEach(() => {
    jest.resetModules();
    mediaRecorders.length = 0;
    rafQueue.length = 0;
    putImageData.mockReset();
    ccall.mockReset();
    mockCaptureFrame.mockReset();
    mockCaptureFrame.mockResolvedValue({ data: new Uint8ClampedArray(16), width: 2, height: 2 });

    (globalThis as Record<string, unknown>).MediaRecorder = FakeMediaRecorder;
    jest.spyOn(window, 'requestAnimationFrame').mockImplementation((cb) => {
      rafQueue.push(cb);
      return rafQueue.length;
    });
    jest.spyOn(window, 'cancelAnimationFrame').mockImplementation(() => {});
    jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockImplementation(
      ((type: string) => (type === '2d' ? { putImageData } : null)) as never,
    );
    (HTMLCanvasElement.prototype as unknown as { captureStream: () => unknown }).captureStream = jest
      .fn()
      .mockReturnValue({});
    window.history.replaceState(null, '', '/');

    rec = require('../wasm/bridge/recording');
    bridgeState = require('../wasm/bridge/state');
    bridgeState.state.initialized = true;
    bridgeState.state.canvasWidth = 640;
    bridgeState.state.canvasHeight = 360;
    bridgeState.wasmRef.module = { ccall } as never;
  });

  afterEach(() => {
    jest.restoreAllMocks();
    removeVideoEncoder();
  });

  it('uses the injected WebCodecs encoder, not putImageData, when VideoEncoder exists', async () => {
    installVideoEncoder();
    const blob = new Blob(['webm'], { type: 'video/webm' });
    const stop = jest.fn().mockResolvedValue(blob);
    const gpuEncode = jest.fn().mockResolvedValue({ stop });

    const promise = rec.startRecording(document.createElement('canvas'), { fps: 60, bitrate: 8e6, gpuEncode });
    await settle();

    expect(gpuEncode).toHaveBeenCalledWith(expect.any(Function), { width: 640, height: 360, fps: 60, bitrate: 8e6 });
    // The capture handed to the encoder is the C++ RGBA readback.
    await gpuEncode.mock.calls[0][0]();
    expect(mockCaptureFrame).toHaveBeenCalled();

    flushRaf();
    rec.stopRecording();
    await expect(promise).resolves.toBe(blob);

    expect(stop).toHaveBeenCalledTimes(1);
    expect(putImageData).not.toHaveBeenCalled();
    expect(mediaRecorders).toHaveLength(0);
    expect(ccall).toHaveBeenCalledWith('setRecording', null, ['number'], [1]);
    expect(ccall).toHaveBeenLastCalledWith('setRecording', null, ['number'], [0]);
  });

  it('auto-stops the WebCodecs take after durationMs', async () => {
    jest.useFakeTimers();
    try {
      installVideoEncoder();
      const blob = new Blob(['webm']);
      const gpuEncode = jest.fn().mockResolvedValue({ stop: jest.fn().mockResolvedValue(blob) });
      const promise = rec.startRecording(document.createElement('canvas'), { durationMs: 2000, gpuEncode });
      await settle();
      jest.advanceTimersByTime(2000);
      await expect(promise).resolves.toBe(blob);
    } finally {
      jest.useRealTimers();
    }
  });

  it('refuses a second take while one is running', async () => {
    installVideoEncoder();
    const gpuEncode = jest.fn().mockResolvedValue({ stop: jest.fn().mockResolvedValue(new Blob()) });
    const first = rec.startRecording(document.createElement('canvas'), { gpuEncode });
    await expect(rec.startRecording(document.createElement('canvas'), { gpuEncode })).rejects.toThrow(/already in progress/);
    await settle();
    rec.stopRecording();
    await first;
  });

  async function expectMediaRecorderPump(promise: Promise<Blob>): Promise<void> {
    await settle();
    expect(mediaRecorders).toHaveLength(1);
    flushRaf();
    await settle();
    expect(putImageData).toHaveBeenCalled();
    rec.stopRecording();
    await promise;
  }

  it('falls back to the MediaRecorder pump when VideoEncoder is missing', async () => {
    const gpuEncode = jest.fn();
    await expectMediaRecorderPump(rec.startRecording(document.createElement('canvas'), { gpuEncode }));
    expect(gpuEncode).not.toHaveBeenCalled();
  });

  it('honors ?record=mediarecorder even with VideoEncoder', async () => {
    installVideoEncoder();
    window.history.replaceState(null, '', '/?renderer=wasm&record=mediarecorder');
    const gpuEncode = jest.fn();
    await expectMediaRecorderPump(rec.startRecording(document.createElement('canvas'), { gpuEncode }));
    expect(gpuEncode).not.toHaveBeenCalled();
  });

  it('falls back to MediaRecorder when no WebM codec is supported or the encoder throws', async () => {
    installVideoEncoder();
    jest.spyOn(console, 'warn').mockImplementation(() => {});
    await expectMediaRecorderPump(
      rec.startRecording(document.createElement('canvas'), { gpuEncode: jest.fn().mockResolvedValue(null) }),
    );
    mediaRecorders.length = 0;
    putImageData.mockReset();
    await expectMediaRecorderPump(
      rec.startRecording(document.createElement('canvas'), { gpuEncode: jest.fn().mockRejectedValue(new Error('boom')) }),
    );
  });

  describe('canvas COPY_SRC (canvas_configure optIn.copySrc)', () => {
    const COPY_SRC = 0x01;
    const RENDER_ATTACHMENT = 0x10;

    function withModule(extra: Record<string, unknown>) {
      bridgeState.wasmRef.module = { ccall, ...extra } as never;
    }

    it('is unsupported until the probe is green and the binary has _setCanvasCopySrc', () => {
      withModule({});
      expect(rec.getCanvasCopySrcProbe()).toBeNull();
      expect(rec.supportsCanvasCopySrc()).toBe(false);
      expect(rec.setCanvasCopySrc(true)).toBe(false);

      withModule({ pixelocityCanvasCopySrc: true });
      expect(rec.supportsCanvasCopySrc()).toBe(false); // pre-v2 binary: no export

      const setter = jest.fn().mockReturnValue(1);
      withModule({ pixelocityCanvasCopySrc: false, _setCanvasCopySrc: setter });
      expect(rec.supportsCanvasCopySrc()).toBe(false);
      expect(rec.setCanvasCopySrc(true)).toBe(false);
      expect(setter).not.toHaveBeenCalled();
    });

    it('reconfigures through _setCanvasCopySrc and restores render-only', () => {
      const setter = jest.fn().mockReturnValue(1);
      withModule({ pixelocityCanvasCopySrc: true, _setCanvasCopySrc: setter });
      expect(rec.supportsCanvasCopySrc()).toBe(true);
      expect(rec.setCanvasCopySrc(true)).toBe(true);
      expect(rec.setCanvasCopySrc(false)).toBe(true);
      expect(setter.mock.calls).toEqual([[1], [0]]);
    });

    it('backs out when getConfiguration() shows the browser dropped COPY_SRC', () => {
      const setter = jest.fn().mockReturnValue(1);
      withModule({ pixelocityCanvasCopySrc: true, _setCanvasCopySrc: setter });
      const canvas = document.createElement('canvas');
      bridgeState.wasmRef.canvas = canvas;
      jest.spyOn(canvas, 'getContext').mockReturnValue({
        getConfiguration: () => ({ usage: RENDER_ATTACHMENT }),
      } as never);
      expect(rec.setCanvasCopySrc(true)).toBe(false);
      expect(setter.mock.calls).toEqual([[1], [0]]);

      jest.spyOn(canvas, 'getContext').mockReturnValue({
        getConfiguration: () => ({ usage: RENDER_ATTACHMENT | COPY_SRC }),
      } as never);
      setter.mockClear();
      expect(rec.setCanvasCopySrc(true)).toBe(true);
      expect(setter.mock.calls).toEqual([[1]]);
    });
  });
});
