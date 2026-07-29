import { WASMRenderer } from '../renderer/WASMRenderer';
import { DEFAULT_CONFIG } from '../renderer/Renderer';

import * as WasmBridge from '../wasm/wasm_bridge.js';

jest.mock('../wasm/wasm_bridge.js', () => ({
  initWasmRenderer: jest.fn().mockResolvedValue(true),
  shutdownWasmRenderer: jest.fn(),
  setInputSource: jest.fn(),
  uploadVideoFrame: jest.fn(),
  uploadImageData: jest.fn(),
  updateUniforms: jest.fn(),
  getFPS: jest.fn().mockReturnValue(60),
}));

describe('WASMRenderer input sources', () => {
  let renderer: WASMRenderer;

  beforeEach(() => {
    jest.clearAllMocks();
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

    jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue({
      drawImage: jest.fn(),
      getImageData: jest.fn().mockReturnValue({ data: fakeImageData, width: 640, height: 480 }),
    } as unknown as GPUCanvasContext);

    for (const source of ['video', 'webcam', 'live'] as const) {
      jest.clearAllMocks();
      renderer.setInputSource(source);
      renderer.updateVideoFrame();
      expect(WasmBridge.uploadVideoFrame).toHaveBeenCalledWith(fakeImageData, 640, 480);
    }
  });

  it('loadImageFromURL uploads decoded RGBA pixels via the bridge', async () => {
    const fakeImageData = new Uint8ClampedArray(32 * 24 * 4);
    fakeImageData[0] = 200;

    const drawImage = jest.fn();
    const getImageData = jest.fn().mockReturnValue({
      data: fakeImageData,
      width: 32,
      height: 24,
    });

    jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue({
      drawImage,
      getImageData,
    } as unknown as CanvasRenderingContext2D);

    const decode = jest.fn().mockResolvedValue(undefined);
    jest.spyOn(global, 'Image').mockImplementation(() => {
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
});
