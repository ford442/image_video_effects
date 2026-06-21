import { WASMRenderer } from '../renderer/WASMRenderer';
import { DEFAULT_CONFIG } from '../renderer/Renderer';

jest.mock('../wasm/wasm_bridge.js', () => ({
  initWasmRenderer: jest.fn().mockResolvedValue(true),
  shutdownWasmRenderer: jest.fn(),
  setInputSource: jest.fn(),
  uploadVideoFrame: jest.fn(),
  updateUniforms: jest.fn(),
  getFPS: jest.fn().mockReturnValue(60),
}));

import * as WasmBridge from '../wasm/wasm_bridge.js';

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
    } as unknown as CanvasRenderingContext2D);

    for (const source of ['video', 'webcam', 'live'] as const) {
      jest.clearAllMocks();
      renderer.setInputSource(source);
      renderer.updateVideoFrame();
      expect(WasmBridge.uploadVideoFrame).toHaveBeenCalledWith(fakeImageData, 640, 480);
    }
  });
});
