/**
 * @jest-environment jsdom
 *
 * WASM bridge capture ABI (wasm_renderer/main.cpp): getFrameCaptureState is
 * 0=idle 1=pending 2=ready 3=error, and readCapturedFrame(outPtr, maxBytes)
 * writes RGBA8 into a caller-owned buffer. Also covers GPU still ingest
 * (loadImageExternal) and its CPU fallback signal.
 */
import { captureFrame, uploadImageSource } from '../wasm/bridge/capture';
import { state, wasmRef, EmscriptenModule } from '../wasm/bridge/state';

const W = 2;
const H = 2;
const PTR = 64;

class FakeImageData {
  constructor(public data: Uint8ClampedArray, public width: number, public height: number) {}
}

type CaptureModule = EmscriptenModule & { ccall: jest.Mock; _malloc: jest.Mock; _free: jest.Mock };

/** Fake module whose capture goes pending → `finalState` after `pendingPolls` polls. */
function makeCaptureModule(finalState: 2 | 3, pendingPolls = 1, written = W * H * 4): CaptureModule {
  const heap = new Uint8Array(PTR + W * H * 4 + 16);
  let polls = 0;
  const ccall = jest.fn((name: string, _ret: unknown, _types: unknown, args: unknown[]) => {
    switch (name) {
      case 'getFrameCaptureState':
        polls += 1;
        return polls > pendingPolls ? finalState : 1;
      case 'getCanvasWidth':
        return W;
      case 'getCanvasHeight':
        return H;
      case 'readCapturedFrame': {
        const [ptr, maxBytes] = args as [number, number];
        if (maxBytes < W * H * 4) return 0;
        for (let i = 0; i < W * H * 4; i++) heap[ptr + i] = (i * 10) & 0xff;
        return written;
      }
      default:
        return 0;
    }
  });
  return {
    ccall,
    _malloc: jest.fn(() => PTR),
    _free: jest.fn(),
    getValue: jest.fn(() => 0),
    stringToUTF8: jest.fn(),
    HEAPU8: heap,
    HEAPF32: new Float32Array(heap.buffer),
  } as unknown as CaptureModule;
}

const rafQueue: FrameRequestCallback[] = [];
function flushRaf(): void {
  rafQueue.splice(0).forEach((cb) => cb(performance.now()));
}

beforeEach(() => {
  rafQueue.length = 0;
  (globalThis as Record<string, unknown>).ImageData = FakeImageData;
  jest.spyOn(window, 'requestAnimationFrame').mockImplementation((cb) => {
    rafQueue.push(cb);
    return rafQueue.length;
  });
  jest.spyOn(console, 'warn').mockImplementation(() => {});
  state.initialized = true;
});

afterEach(() => {
  jest.restoreAllMocks();
  state.initialized = false;
  wasmRef.module = null;
});

describe('captureFrame', () => {
  it('waits for Ready (2) and reads RGBA8 through a malloc\'d buffer', async () => {
    const mod = makeCaptureModule(2);
    wasmRef.module = mod;
    const p = captureFrame();
    flushRaf(); // pending
    flushRaf(); // ready
    const img = await p;
    expect(img.width).toBe(W);
    expect(img.height).toBe(H);
    expect(Array.from(img.data.slice(0, 4))).toEqual([0, 10, 20, 30]);
    expect(mod.ccall).toHaveBeenCalledWith('readCapturedFrame', 'number', ['number', 'number'], [PTR, W * H * 4]);
    expect(mod._malloc).toHaveBeenCalledWith(W * H * 4);
    expect(mod._free).toHaveBeenCalledWith(PTR);
    expect(mod.ccall).toHaveBeenLastCalledWith('endFrameCapture', null, [], []);
  });

  it('rejects on Error (3) without reading', async () => {
    const mod = makeCaptureModule(3, 0);
    wasmRef.module = mod;
    const p = captureFrame();
    flushRaf();
    await expect(p).rejects.toThrow(/capture failed on C\+\+ side/);
    expect(mod.ccall).not.toHaveBeenCalledWith('readCapturedFrame', expect.anything(), expect.anything(), expect.anything());
    expect(mod.ccall).toHaveBeenLastCalledWith('endFrameCapture', null, [], []);
  });

  it('rejects (and still frees + ends) when C++ writes a short frame', async () => {
    const mod = makeCaptureModule(2, 0, 4);
    wasmRef.module = mod;
    const p = captureFrame();
    flushRaf();
    await expect(p).rejects.toThrow(/wrote 4 of 16 bytes/);
    expect(mod._free).toHaveBeenCalledWith(PTR);
    expect(mod.ccall).toHaveBeenLastCalledWith('endFrameCapture', null, [], []);
  });

  it('shares one in-flight capture instead of a second beginFrameCapture', async () => {
    const mod = makeCaptureModule(2);
    wasmRef.module = mod;
    const a = captureFrame();
    const b = captureFrame();
    expect(b).toBe(a);
    flushRaf();
    flushRaf();
    await a;
    const begins = mod.ccall.mock.calls.filter(([n]) => n === 'beginFrameCapture');
    expect(begins).toHaveLength(1);

    // Once settled, a new capture starts a new readback.
    const c = captureFrame();
    expect(c).not.toBe(a);
    flushRaf();
    await c;
    expect(mod.ccall.mock.calls.filter(([n]) => n === 'beginFrameCapture')).toHaveLength(2);
  });
});

describe('uploadImageSource (GPU still ingest)', () => {
  it('parks the source for the EM_JS, returns true on 1, and clears the hand-off', () => {
    const img = document.createElement('img');
    let parked: unknown;
    const mod = makeCaptureModule(2);
    mod.ccall.mockImplementation((name: string) => {
      if (name === 'loadImageExternal') {
        parked = (wasmRef.module as EmscriptenModule).pixelocityPendingImage;
        return 1;
      }
      return 0;
    });
    wasmRef.module = mod;
    expect(uploadImageSource(img, 640, 480)).toBe(true);
    expect(parked).toBe(img);
    expect(mod.ccall).toHaveBeenCalledWith('loadImageExternal', 'number', ['number', 'number'], [640, 480]);
    expect(mod.pixelocityPendingImage).toBeUndefined();
  });

  it('returns false (caller falls back to the CPU upload) on 0 or a throw', () => {
    const mod = makeCaptureModule(2);
    wasmRef.module = mod;
    mod.ccall.mockReturnValue(0);
    expect(uploadImageSource(document.createElement('canvas'), 4, 4)).toBe(false);
    mod.ccall.mockImplementation(() => {
      throw new Error('missing export');
    });
    expect(uploadImageSource(document.createElement('canvas'), 4, 4)).toBe(false);
    expect(mod.pixelocityPendingImage).toBeUndefined();
  });

  it('is a no-op before init', () => {
    state.initialized = false;
    wasmRef.module = makeCaptureModule(2);
    expect(uploadImageSource(document.createElement('canvas'), 4, 4)).toBe(false);
  });
});
