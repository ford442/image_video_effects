import type { Mock } from 'vitest';
import { WASMRenderer } from '../renderer/WASMRenderer';
import { DEFAULT_CONFIG } from '../renderer/Renderer';

import * as WasmBridge from '../wasm/wasm_bridge';

vi.mock('../wasm/wasm_bridge', () => ({
  initWasmRenderer: vi.fn().mockResolvedValue(true),
  shutdownWasmRenderer: vi.fn(),
  setInputSource: vi.fn(),
  uploadVideoFrame: vi.fn(),
  uploadImageData: vi.fn(),
  // GPU still ingest unavailable by default so the CPU fallback path is exercised.
  uploadImageSource: vi.fn().mockReturnValue(false),
  updateUniforms: vi.fn(),
  getFPS: vi.fn().mockReturnValue(60),
}));

describe('WASMRenderer input sources', () => {
  let renderer: WASMRenderer;

  beforeEach(() => {
    vi.clearAllMocks();
    renderer = new WASMRenderer(DEFAULT_CONFIG);
  });

  it('forwards setInputSource to the WASM bridge', () => {
    renderer.setInputSource('generative');
    expect(WasmBridge.setInputSource).toHaveBeenCalledWith('generative');
    expect(renderer.getInputSource()).toBe('generative');
  });

  it('skips updateVideoFrame when input is image or generative', () => {
    const video = {
      readyState: 4,
      videoWidth: 640,
      videoHeight: 480,
    } as HTMLVideoElement;

    renderer.setVideo(video);
    renderer.setInputSource('generative');
    renderer.updateVideoFrame();
    expect(WasmBridge.uploadVideoFrame).not.toHaveBeenCalled();

    renderer.setInputSource('image');
    renderer.updateVideoFrame();
    expect(WasmBridge.uploadVideoFrame).not.toHaveBeenCalled();
  });

  it('uploads video frames when input is video, webcam, or live', () => {
    const fakeImageData = new Uint8ClampedArray(640 * 480 * 4);
    const video = {
      readyState: 4,
      videoWidth: 640,
      videoHeight: 480,
    } as HTMLVideoElement;

    renderer.setVideo(video);

    vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue({
      drawImage: vi.fn(),
      getImageData: vi.fn().mockReturnValue({ data: fakeImageData, width: 640, height: 480 }),
      clearRect: vi.fn(),
    } as unknown as GPUCanvasContext);

    for (const source of ['video', 'webcam', 'live'] as const) {
      vi.clearAllMocks();
      renderer.setInputSource(source);
      renderer.updateVideoFrame();
      // Identity check: deep-equality on a 1.2 MB typed array takes seconds under Vitest.
      const [data, width, height] = vi.mocked(WasmBridge.uploadVideoFrame).mock.calls[0] ?? [];
      expect(data).toBe(fakeImageData);
      expect([width, height]).toEqual([640, 480]);
    }
  });

  it('loadImageFromURL uploads decoded RGBA pixels via the bridge', async () => {
    const fakeImageData = new Uint8ClampedArray(32 * 24 * 4);
    fakeImageData[0] = 200;

    const drawImage = vi.fn();
    const getImageData = vi.fn().mockReturnValue({
      data: fakeImageData,
      width: 32,
      height: 24,
    });

    vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue({
      drawImage,
      getImageData,
      clearRect: vi.fn(),
    } as unknown as GPUCanvasContext);

    const decode = vi.fn().mockResolvedValue(undefined);
    vi.spyOn(global, 'Image').mockImplementation(() => {
      const img = document.createElement('img');
      Object.defineProperty(img, 'naturalWidth', { value: 32 });
      Object.defineProperty(img, 'naturalHeight', { value: 24 });
      img.decode = decode;
      return img;
    });

    await renderer.loadImageFromURL('https://example.com/test.png');

    expect(decode).toHaveBeenCalled();
    expect(drawImage).toHaveBeenCalled();
    expect(getImageData).toHaveBeenCalledWith(0, 0, 32, 24);
    expect(WasmBridge.uploadImageData).toHaveBeenCalledWith(fakeImageData, 32, 24);
  });

  it('logs input w×h when the image upload runs', async () => {
    const log = vi.spyOn(console, 'log').mockImplementation(() => {});
    vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue({
      drawImage: vi.fn(),
      getImageData: vi.fn().mockReturnValue({
        data: new Uint8ClampedArray(8 * 4 * 4),
        width: 8,
        height: 4,
      }),
      clearRect: vi.fn(),
    } as unknown as GPUCanvasContext);

    vi.spyOn(global, 'Image').mockImplementation(() => {
      const img = document.createElement('img');
      Object.defineProperty(img, 'naturalWidth', { value: 8 });
      Object.defineProperty(img, 'naturalHeight', { value: 4 });
      img.decode = vi.fn().mockResolvedValue(undefined);
      return img;
    });

    await renderer.loadImageFromURL('https://example.com/rebind.png');
    expect(log).toHaveBeenCalledWith('[WASM] Input upload ran: 8×4 (image, CPU fallback)');
    log.mockRestore();
  });

  it('loadImageFromElement uploads decoded RGBA and logs w×h', () => {
    const log = vi.spyOn(console, 'log').mockImplementation(() => {});
    const fakeImageData = new Uint8ClampedArray(4 * 2 * 4);
    vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue({
      drawImage: vi.fn(),
      clearRect: vi.fn(),
      getImageData: vi.fn().mockReturnValue({
        data: fakeImageData,
        width: 4,
        height: 2,
      }),
    } as unknown as GPUCanvasContext);

    const src = document.createElement('canvas');
    src.width = 4;
    src.height = 2;

    const size = renderer.loadImageFromElement(src);
    expect(size).toEqual({ width: 4, height: 2 });
    expect(WasmBridge.uploadImageData).toHaveBeenCalledWith(fakeImageData, 4, 2);
    expect(log).toHaveBeenCalledWith('[WASM] Input upload ran: 4×2 (image, CPU fallback)');
    log.mockRestore();
  });

  it('loadImageFromElement prefers GPU copyExternalImageToTexture and skips getImageData', () => {
    const log = vi.spyOn(console, 'log').mockImplementation(() => {});
    (WasmBridge.uploadImageSource as Mock).mockReturnValueOnce(true);
    const drawImage = vi.fn();
    const getImageData = vi.fn();
    const getContext = vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue({
      drawImage,
      clearRect: vi.fn(),
      getImageData,
    } as unknown as GPUCanvasContext);

    const src = document.createElement('canvas');
    src.width = 4;
    src.height = 2;

    expect(renderer.loadImageFromElement(src)).toEqual({ width: 4, height: 2 });
    expect(WasmBridge.uploadImageSource).toHaveBeenCalledWith(src, 4, 2);
    expect(WasmBridge.uploadImageData).not.toHaveBeenCalled();
    expect(getImageData).not.toHaveBeenCalled();
    expect(log).toHaveBeenCalledWith('[WASM] Input upload ran: 4×2 (image, GPU copy)');

    // The CPU mirror still gets the new still, so a backend switch rebinds it.
    expect(drawImage).toHaveBeenCalledWith(src, 0, 0, 4, 2);
    const bitmap = renderer.getCpuInputBitmap() as HTMLCanvasElement;
    expect(bitmap).not.toBe(src);
    expect(bitmap.width).toBe(4);
    expect(bitmap.height).toBe(2);
    log.mockRestore();
    getContext.mockRestore();
  });
});
