/**
 * @jest-environment jsdom
 */
import { forcesMediaRecorder, GpuEncodeFrames, startGpuEncodeSession } from './gpuEncodeSupport';

const mockStart = jest.fn();
jest.mock('./gpuEncoder', () => ({
  GpuEncodeRecorder: { start: (...args: unknown[]) => mockStart(...args) },
  canvasFrameSource: (canvas: HTMLCanvasElement) => ({ kind: 'canvas', canvas }),
  readbackFrameSource: (capture: () => Promise<ImageData>) => ({ kind: 'readback', capture }),
}));

const OPTS = { width: 64, height: 64, fps: 60, bitrate: 1e6 };

function frames(overrides: Partial<GpuEncodeFrames> = {}): GpuEncodeFrames & { setCanvasCopySrc: jest.Mock } {
  return {
    canvas: document.createElement('canvas'),
    supportsCanvasCopySrc: () => false,
    setCanvasCopySrc: jest.fn().mockReturnValue(true),
    readback: null,
    ...overrides,
  } as GpuEncodeFrames & { setCanvasCopySrc: jest.Mock };
}

describe('startGpuEncodeSession', () => {
  beforeEach(() => mockStart.mockReset());

  it('prefers the canvas VideoFrame when COPY_SRC is available and restores render-only on stop', async () => {
    const blob = new Blob(['x']);
    mockStart.mockResolvedValue({ stop: jest.fn().mockResolvedValue(blob) });
    const f = frames({ supportsCanvasCopySrc: () => true, readback: jest.fn() });

    const session = await startGpuEncodeSession(f, OPTS);
    expect(session?.kind).toBe('canvas');
    expect(mockStart.mock.calls[0][0]).toMatchObject({ kind: 'canvas', canvas: f.canvas });
    expect(f.setCanvasCopySrc.mock.calls).toEqual([[true]]);

    await expect(session!.stop()).resolves.toBe(blob);
    expect(f.setCanvasCopySrc.mock.calls).toEqual([[true], [false]]);
  });

  it('uses the RGBA readback when COPY_SRC is refused (probe red or bit dropped)', async () => {
    mockStart.mockResolvedValue({ stop: jest.fn().mockResolvedValue(new Blob()) });
    const readback = jest.fn();
    const f = frames({ supportsCanvasCopySrc: () => true, readback });
    f.setCanvasCopySrc.mockReturnValue(false);

    const session = await startGpuEncodeSession(f, OPTS);
    expect(session?.kind).toBe('readback');
    expect(mockStart.mock.calls[0][0]).toMatchObject({ kind: 'readback', capture: readback });
    await session!.stop();
    expect(f.setCanvasCopySrc.mock.calls).toEqual([[true]]);
  });

  it('resolves null without a frame source', async () => {
    await expect(startGpuEncodeSession(frames(), OPTS)).resolves.toBeNull();
    expect(mockStart).not.toHaveBeenCalled();
  });

  it('restores render-only when no codec is supported or start throws', async () => {
    const f = frames({ supportsCanvasCopySrc: () => true });
    mockStart.mockResolvedValueOnce(null);
    await expect(startGpuEncodeSession(f, OPTS)).resolves.toBeNull();
    expect(f.setCanvasCopySrc.mock.calls).toEqual([[true], [false]]);

    f.setCanvasCopySrc.mockClear();
    mockStart.mockRejectedValueOnce(new Error('configure failed'));
    await expect(startGpuEncodeSession(f, OPTS)).rejects.toThrow('configure failed');
    expect(f.setCanvasCopySrc.mock.calls).toEqual([[true], [false]]);
  });
});

describe('forcesMediaRecorder', () => {
  it('is only on for ?record=mediarecorder', () => {
    expect(forcesMediaRecorder('')).toBe(false);
    expect(forcesMediaRecorder('?renderer=wasm')).toBe(false);
    expect(forcesMediaRecorder('?renderer=wasm&record=mediarecorder')).toBe(true);
  });
});
