import { RendererManager } from '../renderer/RendererManager';
import { WebGPURenderer } from '../renderer/WebGPURenderer';
import { WASMRenderer } from '../renderer/WASMRenderer';
import { JSRenderer } from '../renderer/JSRenderer';
import { DEFAULT_CONFIG } from '../renderer/Renderer';
import { SlotParams } from '../renderer/types';

jest.mock('../renderer/WebGPURenderer');
jest.mock('../renderer/WASMRenderer');
jest.mock('../renderer/JSRenderer');

const defaultSlotParams: SlotParams = {
  zoomParam1: 0.1,
  zoomParam2: 0.2,
  zoomParam3: 0.3,
  zoomParam4: 0.4,
  lightStrength: 1,
  ambient: 0.2,
  normalStrength: 0.1,
  fogFalloff: 4,
  depthThreshold: 0.5,
};

function makeMockWebGPU(): jest.Mocked<WebGPURenderer> {
  return {
    init: jest.fn().mockResolvedValue(true),
    destroy: jest.fn(),
    loadShader: jest.fn().mockResolvedValue(true),
    setActiveShader: jest.fn(),
    setSlotShader: jest.fn(),
    setSlotParams: jest.fn(),
    updateSlotParams: jest.fn(),
    setSlotMode: jest.fn(),
    addRipple: jest.fn(),
    clearRipples: jest.fn(),
    setInputSource: jest.fn(),
    getInputSource: jest.fn().mockReturnValue('image'),
    updateVideoFrame: jest.fn(),
    updateAudioData: jest.fn(),
    updateAudioFrequencyBins: jest.fn(),
    takeScreenshot: jest.fn().mockResolvedValue(undefined),
    refreshFrameImage: jest.fn().mockResolvedValue(''),
    getFrameImage: jest.fn().mockReturnValue(''),
    getFPS: jest.fn().mockReturnValue(60),
  } as unknown as jest.Mocked<WebGPURenderer>;
}

function makeMockWASM(): jest.Mocked<WASMRenderer> {
  return {
    init: jest.fn().mockResolvedValue(true),
    destroy: jest.fn(),
    loadShader: jest.fn().mockResolvedValue(true),
    setActiveShader: jest.fn(),
    setSlotShader: jest.fn(),
    setSlotParams: jest.fn(),
    updateSlotParams: jest.fn(),
    setSlotMode: jest.fn(),
    addRipple: jest.fn(),
    clearRipples: jest.fn(),
    setInputSource: jest.fn(),
    getInputSource: jest.fn().mockReturnValue('image'),
    updateVideoFrame: jest.fn(),
    updateAudioData: jest.fn(),
    updateAudioFrequencyBins: jest.fn(),
    takeScreenshot: jest.fn().mockResolvedValue(undefined),
    refreshFrameImage: jest.fn().mockResolvedValue('data:image/png;base64,x'),
    getFrameImage: jest.fn().mockReturnValue(''),
    getSlotState: jest.fn().mockReturnValue({ shaderId: 'rain', enabled: true, mode: 'chained' }),
    getGPUTimings: jest.fn().mockReturnValue({ parallelTime: 1, chainedTime: 2, totalTime: 3, available: false }),
    getSupportsDeepWorkgroup: jest.fn().mockReturnValue(true),
    setRecording: jest.fn(),
    getFPS: jest.fn().mockReturnValue(55),
    getDiagnostics: jest.fn().mockReturnValue({ initialized: true }),
  } as unknown as jest.Mocked<WASMRenderer>;
}

function makeMockJS(): jest.Mocked<JSRenderer> {
  return {
    init: jest.fn().mockResolvedValue(true),
    destroy: jest.fn(),
    setInputSource: jest.fn(),
    getInputSource: jest.fn().mockReturnValue('image'),
    updateVideoFrame: jest.fn(),
    getFPS: jest.fn().mockReturnValue(30),
  } as unknown as jest.Mocked<JSRenderer>;
}

describe('RendererManager shader forwarding', () => {
  let canvas: HTMLCanvasElement;

  beforeEach(() => {
    canvas = document.createElement('canvas');
    jest.clearAllMocks();
  });

  it('forwards setSlotShader and updateSlotParams to WASMRenderer', async () => {
    const wasm = makeMockWASM();
    (WASMRenderer as jest.Mock).mockImplementation(() => wasm);
    (WebGPURenderer as jest.Mock).mockImplementation(() => ({
      init: jest.fn().mockResolvedValue(false),
      destroy: jest.fn(),
    }));
    (JSRenderer as jest.Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(canvas);
    const switched = await manager.switchRenderer('wasm');
    expect(switched).toBe(true);

    manager.setSlotShader(1, 'rain');
    manager.updateSlotParams({ zoomParam1: 0.7 }, 1);
    manager.setSlotParams(2, 0.1, 0.2, 0.3, 0.4);

    expect(wasm.setSlotShader).toHaveBeenCalledWith(1, 'rain');
    expect(wasm.updateSlotParams).toHaveBeenCalledWith({ zoomParam1: 0.7 }, 1);
    expect(wasm.setSlotParams).toHaveBeenCalledWith(2, 0.1, 0.2, 0.3, 0.4);
  });

  it('forwards setSlotShader and updateSlotParams to WebGPURenderer', async () => {
    const webgpu = makeMockWebGPU();
    (WebGPURenderer as jest.Mock).mockImplementation(() => webgpu);
    (WASMRenderer as jest.Mock).mockImplementation(() => makeMockWASM());
    (JSRenderer as jest.Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(canvas);

    manager.setSlotShader(0, 'liquid');
    manager.updateSlotParams({ zoomParam2: 0.8 }, 0);
    manager.setSlotParams(0, 0.1, 0.2, 0.3, 0.4);

    expect(webgpu.setSlotShader).toHaveBeenCalledWith(0, 'liquid');
    expect(webgpu.updateSlotParams).toHaveBeenCalledWith({ zoomParam2: 0.8 }, 0);
    expect(webgpu.setSlotParams).toHaveBeenCalledWith(0, 0.1, 0.2, 0.3, 0.4);
  });

  it('forwards loadShaders to WASMRenderer', async () => {
    const wasm = makeMockWASM();
    (WASMRenderer as jest.Mock).mockImplementation(() => wasm);
    (WebGPURenderer as jest.Mock).mockImplementation(() => ({
      init: jest.fn().mockResolvedValue(false),
      destroy: jest.fn(),
    }));
    (JSRenderer as jest.Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(canvas);
    await manager.switchRenderer('wasm');

    await manager.loadShaders([
      { id: 'a', name: 'A', url: '/a.wgsl', category: 'image' },
      { id: 'b', name: 'B', url: '/b.wgsl', category: 'image' },
    ]);

    expect(wasm.loadShader).toHaveBeenCalledTimes(2);
    expect(wasm.loadShader).toHaveBeenCalledWith('a', '/a.wgsl');
    expect(wasm.loadShader).toHaveBeenCalledWith('b', '/b.wgsl');
  });

  it('syncAllSlotParams pushes each slot to WASM', async () => {
    const wasm = makeMockWASM();
    (WASMRenderer as jest.Mock).mockImplementation(() => wasm);
    (WebGPURenderer as jest.Mock).mockImplementation(() => ({
      init: jest.fn().mockResolvedValue(false),
      destroy: jest.fn(),
    }));
    (JSRenderer as jest.Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(canvas);
    await manager.switchRenderer('wasm');

    const slots = [
      { ...defaultSlotParams, zoomParam1: 0.11 },
      { ...defaultSlotParams, zoomParam2: 0.22 },
      { ...defaultSlotParams, zoomParam3: 0.33 },
    ];
    manager.syncAllSlotParams(slots);

    expect(wasm.updateSlotParams).toHaveBeenCalledTimes(3);
    expect(wasm.updateSlotParams).toHaveBeenNthCalledWith(1, expect.objectContaining({ zoomParam1: 0.11 }), 0);
    expect(wasm.updateSlotParams).toHaveBeenNthCalledWith(2, expect.objectContaining({ zoomParam2: 0.22 }), 1);
    expect(wasm.updateSlotParams).toHaveBeenNthCalledWith(3, expect.objectContaining({ zoomParam3: 0.33 }), 2);
  });

  it('resyncShaderStack reloads active modes after backend switch', async () => {
    const wasm = makeMockWASM();
    (WASMRenderer as jest.Mock).mockImplementation(() => wasm);
    (WebGPURenderer as jest.Mock).mockImplementation(() => ({
      init: jest.fn().mockResolvedValue(false),
      destroy: jest.fn(),
    }));
    (JSRenderer as jest.Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(canvas);
    await manager.switchRenderer('wasm');

    await manager.resyncShaderStack({
      modes: ['rain', 'none', 'liquid'],
      slotParams: [defaultSlotParams, defaultSlotParams, defaultSlotParams],
      resolveShader: (id) =>
        id === 'rain'
          ? { id: 'rain', name: 'Rain', url: '/rain.wgsl', category: 'image' }
          : id === 'liquid'
            ? { id: 'liquid', name: 'Liquid', url: '/liquid.wgsl', category: 'image' }
            : undefined,
      inputSource: 'generative',
    });

    expect(wasm.setInputSource).toHaveBeenCalledWith('generative');
    expect(wasm.loadShader).toHaveBeenCalledWith('rain', '/rain.wgsl');
    expect(wasm.setSlotShader).toHaveBeenCalledWith(0, 'rain');
    expect(wasm.setSlotShader).toHaveBeenCalledWith(1, '');
    expect(wasm.loadShader).toHaveBeenCalledWith('liquid', '/liquid.wgsl');
    expect(wasm.setSlotShader).toHaveBeenCalledWith(2, 'liquid');
  });

  it('no-ops shader calls when Canvas2D fallback is active', async () => {
    const js = makeMockJS();
    (JSRenderer as jest.Mock).mockImplementation(() => js);
    (WebGPURenderer as jest.Mock).mockImplementation(() => ({
      init: jest.fn().mockResolvedValue(false),
      destroy: jest.fn(),
    }));

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(canvas);
    await manager.switchRenderer('js');

    expect(manager.supportsShaderEffects()).toBe(false);
    manager.setSlotShader(0, 'rain');
    const loaded = await manager.loadShader('rain', '/rain.wgsl');
    expect(loaded).toBe(false);
  });

  it('forwards setInputSource to WASMRenderer', async () => {
    const wasm = makeMockWASM();
    (WASMRenderer as jest.Mock).mockImplementation(() => wasm);
    (WebGPURenderer as jest.Mock).mockImplementation(() => ({
      init: jest.fn().mockResolvedValue(false),
      destroy: jest.fn(),
    }));
    (JSRenderer as jest.Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(document.createElement('canvas'));
    await manager.switchRenderer('wasm');

    manager.setInputSource('generative');
    expect(wasm.setInputSource).toHaveBeenCalledWith('generative');

    manager.setInputSource('webcam');
    expect(wasm.setInputSource).toHaveBeenCalledWith('webcam');

    manager.setInputSource('live');
    expect(wasm.setInputSource).toHaveBeenCalledWith('live');
  });

  it('forwards setInputSource to WebGPURenderer', async () => {
    const webgpu = makeMockWebGPU();
    (WebGPURenderer as jest.Mock).mockImplementation(() => webgpu);
    (WASMRenderer as jest.Mock).mockImplementation(() => makeMockWASM());
    (JSRenderer as jest.Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(canvas);

    manager.setInputSource('video');
    expect(webgpu.setInputSource).toHaveBeenCalledWith('video');
  });

  it('render() uploads video frames on WASM backend', async () => {
    const wasm = makeMockWASM();
    (WASMRenderer as jest.Mock).mockImplementation(() => wasm);
    (WebGPURenderer as jest.Mock).mockImplementation(() => ({
      init: jest.fn().mockResolvedValue(false),
      destroy: jest.fn(),
    }));
    (JSRenderer as jest.Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(document.createElement('canvas'));
    await manager.switchRenderer('wasm');

    manager.render();
    expect(wasm.updateVideoFrame).toHaveBeenCalled();
  });

  it('addRipplePoint forwards to addRipple on shader backends', async () => {
    const webgpu = makeMockWebGPU();
    (WebGPURenderer as jest.Mock).mockImplementation(() => webgpu);
    (WASMRenderer as jest.Mock).mockImplementation(() => makeMockWASM());
    (JSRenderer as jest.Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(canvas);
    await manager.switchRenderer('webgpu');

    manager.addRipplePoint(0.5, 0.25);
    expect(webgpu.addRipple).toHaveBeenCalledWith(0.5, 0.25);
  });

  it('forwards updateAudioFrequencyBins to WASMRenderer', async () => {
    const wasm = makeMockWASM();
    (WASMRenderer as jest.Mock).mockImplementation(() => wasm);
    (WebGPURenderer as jest.Mock).mockImplementation(() => ({
      init: jest.fn().mockResolvedValue(false),
      destroy: jest.fn(),
    }));
    (JSRenderer as jest.Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(document.createElement('canvas'));
    await manager.switchRenderer('wasm');

    const bins = new Float32Array([0.1, 0.5, 0.9]);
    manager.updateAudioFrequencyBins(bins);
    expect(wasm.updateAudioFrequencyBins).toHaveBeenCalledWith(bins);
  });

  it('delegates takeScreenshot to WASMRenderer', async () => {
    const wasm = makeMockWASM();
    (WASMRenderer as jest.Mock).mockImplementation(() => wasm);
    (WebGPURenderer as jest.Mock).mockImplementation(() => ({
      init: jest.fn().mockResolvedValue(false),
      destroy: jest.fn(),
    }));
    (JSRenderer as jest.Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(document.createElement('canvas'));
    await manager.switchRenderer('wasm');

    await manager.takeScreenshot('test.png');
    expect(wasm.takeScreenshot).toHaveBeenCalledWith('test.png');
  });

  it('exposes getSlotState and getGPUTimings from WASMRenderer', async () => {
    const wasm = makeMockWASM();
    (WASMRenderer as jest.Mock).mockImplementation(() => wasm);
    (WebGPURenderer as jest.Mock).mockImplementation(() => ({
      init: jest.fn().mockResolvedValue(false),
      destroy: jest.fn(),
    }));
    (JSRenderer as jest.Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(document.createElement('canvas'));
    await manager.switchRenderer('wasm');

    manager.getSlotState(0);
    manager.getGPUTimings();
    manager.getSupportsDeepWorkgroup();

    expect(wasm.getSlotState).toHaveBeenCalledWith(0);
    expect(wasm.getGPUTimings).toHaveBeenCalled();
    expect(wasm.getSupportsDeepWorkgroup).toHaveBeenCalled();
  });
});
