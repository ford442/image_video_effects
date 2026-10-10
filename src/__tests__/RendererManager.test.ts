import { RendererManager } from '../renderer/RendererManager';
import { WebGPURenderer } from '../renderer/WebGPURenderer';
import { WASMRenderer } from '../renderer/WASMRenderer';
import { JSRenderer } from '../renderer/JSRenderer';
import { DEFAULT_CONFIG } from '../renderer/Renderer';
import { SlotParams } from '../renderer/types';

jest.mock('../renderer/WebGPURenderer');
jest.mock('../renderer/WASMRenderer');
jest.mock('../renderer/JSRenderer');
jest.mock('../wasm/wasm_bridge', () => ({
  initWasmRenderer: jest.fn().mockResolvedValue(true),
  shutdownWasmRenderer: jest.fn(),
}));

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
    loadImage: jest.fn().mockResolvedValue('https://example.com/webgpu.png'),
    reloadShaderFromURL: jest.fn().mockResolvedValue(true),
    setVideo: jest.fn(),
    getVideo: jest.fn().mockReturnValue(null),
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
    getGPUTimings: jest.fn().mockReturnValue({ parallelTime: 1, chainedTime: 2, totalTime: 3, available: false, timingSource: 'wall-clock' }),
    getAudioData: jest.fn().mockReturnValue({ bass: 0, mid: 0, treble: 0, freqBins: new Float32Array(128) }),
    isRecording: jest.fn().mockReturnValue(false),
    getSupportsDeepWorkgroup: jest.fn().mockReturnValue(true),
    setRecording: jest.fn(),
    startRecording: jest.fn().mockResolvedValue(new Blob()),
    stopRecording: jest.fn(),
    loadImage: jest.fn().mockResolvedValue('https://example.com/img.png'),
    reloadShaderFromURL: jest.fn().mockResolvedValue(true),
    setVideo: jest.fn(),
    getVideo: jest.fn().mockReturnValue(null),
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

  it('does not auto-fallback to Canvas2D when WebGPU init fails', async () => {
    const js = makeMockJS();
    (JSRenderer as jest.Mock).mockImplementation(() => js);
    (WebGPURenderer as jest.Mock).mockImplementation(() => ({
      init: jest.fn().mockResolvedValue(false),
      destroy: jest.fn(),
    }));

    const manager = new RendererManager(DEFAULT_CONFIG);
    const ok = await manager.init(canvas);
    expect(ok).toBe(false);
    expect(js.init).not.toHaveBeenCalled();
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

  it('delegates startRecording and stopRendererRecording to WASMRenderer', async () => {
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

    expect(manager.usesInternalRecording()).toBe(true);

    const canvas = document.createElement('canvas');
    await manager.startRecording(canvas, { durationMs: 8000 });
    expect(wasm.startRecording).toHaveBeenCalledWith(canvas, { durationMs: 8000 });

    manager.stopRendererRecording();
    expect(wasm.stopRecording).toHaveBeenCalled();
  });

  it('delegates getAudioData and isRecording from WASMRenderer', async () => {
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

    manager.getAudioData();
    manager.isRecording();

    expect(wasm.getAudioData).toHaveBeenCalled();
    expect(wasm.isRecording).toHaveBeenCalled();
  });

  it('delegates loadImage to WASMRenderer via duck-typed loadImage', async () => {
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

    const url = await manager.loadImage('https://example.com/a.png');
    expect(wasm.loadImage).toHaveBeenCalledWith('https://example.com/a.png');
    expect(url).toBe('https://example.com/img.png');
  });

  it('delegates loadImage to WebGPURenderer', async () => {
    const webgpu = makeMockWebGPU();
    (WebGPURenderer as jest.Mock).mockImplementation(() => webgpu);
    (WASMRenderer as jest.Mock).mockImplementation(() => ({
      init: jest.fn().mockResolvedValue(false),
      destroy: jest.fn(),
    }));
    (JSRenderer as jest.Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(document.createElement('canvas'));

    const url = await manager.loadImage('https://example.com/b.png');
    expect(webgpu.loadImage).toHaveBeenCalledWith('https://example.com/b.png');
    expect(url).toBe('https://example.com/webgpu.png');
  });

  it('re-uploads the current image after switching to WASM (#1206)', async () => {
    const webgpu = makeMockWebGPU();
    const wasm = makeMockWASM();
    (WebGPURenderer as jest.Mock).mockImplementation(() => webgpu);
    (WASMRenderer as jest.Mock).mockImplementation(() => wasm);
    (JSRenderer as jest.Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(canvas);
    await manager.loadImage('https://example.com/photo.png');
    wasm.loadImage.mockClear();

    await manager.switchRenderer('wasm');

    expect(wasm.setInputSource).toHaveBeenCalledWith('image');
    expect(wasm.loadImage).toHaveBeenCalledWith('https://example.com/webgpu.png');
  });

  it('re-uploads a live CPU canvas after switching to WASM without a URL refetch', async () => {
    const offscreen = document.createElement('canvas');
    offscreen.width = 16;
    offscreen.height = 8;
    const webgpu = makeMockWebGPU();
    (webgpu as unknown as { getCpuInputBitmap: () => HTMLCanvasElement }).getCpuInputBitmap = () => offscreen;
    const wasm = makeMockWASM();
    (wasm as unknown as { loadImageFromElement: jest.Mock }).loadImageFromElement = jest
      .fn()
      .mockReturnValue({ width: 16, height: 8 });
    (WebGPURenderer as jest.Mock).mockImplementation(() => webgpu);
    (WASMRenderer as jest.Mock).mockImplementation(() => wasm);
    (JSRenderer as jest.Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(canvas);
    wasm.loadImage.mockClear();

    await manager.switchRenderer('wasm');

    expect((wasm as unknown as { loadImageFromElement: jest.Mock }).loadImageFromElement).toHaveBeenCalledWith(offscreen);
    expect(wasm.loadImage).not.toHaveBeenCalled();
  });

  it('resyncs the stored shader stack as part of switchRenderer (#1206)', async () => {
    const webgpu = makeMockWebGPU();
    const wasm = makeMockWASM();
    (WebGPURenderer as jest.Mock).mockImplementation(() => webgpu);
    (WASMRenderer as jest.Mock).mockImplementation(() => wasm);
    (JSRenderer as jest.Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(canvas);
    await manager.resyncShaderStack({
      modes: ['rain', 'none', 'liquid'],
      slotParams: [defaultSlotParams, defaultSlotParams, defaultSlotParams],
      resolveShader: (id) =>
        id === 'rain'
          ? { id: 'rain', name: 'Rain', url: '/rain.wgsl', category: 'image' }
          : id === 'liquid'
            ? { id: 'liquid', name: 'Liquid', url: '/liquid.wgsl', category: 'image' }
            : undefined,
      inputSource: 'image',
    });
    wasm.loadShader.mockClear();
    wasm.setSlotShader.mockClear();

    await manager.switchRenderer('wasm');

    expect(wasm.loadShader).toHaveBeenCalledWith('rain', '/rain.wgsl');
    expect(wasm.setSlotShader).toHaveBeenCalledWith(0, 'rain');
    expect(wasm.setSlotShader).toHaveBeenCalledWith(1, '');
    expect(wasm.loadShader).toHaveBeenCalledWith('liquid', '/liquid.wgsl');
    expect(wasm.setSlotShader).toHaveBeenCalledWith(2, 'liquid');
  });

  it('reloadShader prefers reloadShaderFromURL on shader backends', async () => {
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

    await manager.reloadShader('rain', '/shaders/rain.wgsl');
    expect(wasm.reloadShaderFromURL).toHaveBeenCalledWith('rain', '/shaders/rain.wgsl');
  });

  it('firePlasma falls back to addRipple when backend has no firePlasma', async () => {
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

    manager.firePlasma(0.5, 0.5, 1, 0);
    expect(wasm.addRipple).toHaveBeenCalledWith(0.5, 0.5);
  });

  it('reports renderer type from metrics rather than instanceof', async () => {
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

    expect(manager.getActiveRendererType()).toBe('wasm');
  });

  it('releases WebGPU before WASM init (exclusive adapter ownership)', async () => {
    const order: string[] = [];
    const webgpu = makeMockWebGPU();
    webgpu.destroy = jest.fn(async () => {
      order.push('webgpu.destroy');
    });
    const wasm = makeMockWASM();
    wasm.init = jest.fn(async (canvas: HTMLCanvasElement) => {
      order.push('wasm.init');
      return true;
    });

    (WebGPURenderer as jest.Mock).mockImplementation(() => webgpu);
    (WASMRenderer as jest.Mock).mockImplementation(() => wasm);
    (JSRenderer as jest.Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(canvas);
    expect(manager.getActiveRendererType()).toBe('webgpu');

    const switched = await manager.switchRenderer('wasm');
    expect(switched).toBe(true);
    expect(order.indexOf('webgpu.destroy')).toBeGreaterThanOrEqual(0);
    expect(order.indexOf('wasm.init')).toBeGreaterThan(order.indexOf('webgpu.destroy'));
    expect(manager.getActiveRendererType()).toBe('wasm');
  });

  it('restores WebGPU when WASM init fails after exclusive release', async () => {
    let webgpuInitCount = 0;
    const webgpuInstances: Array<{ init: jest.Mock; destroy: jest.Mock }> = [];

    (WebGPURenderer as jest.Mock).mockImplementation(() => {
      const instance = {
        init: jest.fn(async () => {
          webgpuInitCount += 1;
          return true;
        }),
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
        loadImage: jest.fn().mockResolvedValue('https://example.com/webgpu.png'),
        reloadShaderFromURL: jest.fn().mockResolvedValue(true),
        getDiagnostics: jest.fn().mockReturnValue({ initialized: true }),
      };
      webgpuInstances.push(instance);
      return instance;
    });

    const wasm = makeMockWASM();
    wasm.init = jest.fn().mockResolvedValue(false);
    (WASMRenderer as jest.Mock).mockImplementation(() => wasm);
    (JSRenderer as jest.Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(canvas);
    expect(webgpuInitCount).toBe(1);
    expect(manager.getActiveRendererType()).toBe('webgpu');

    const switched = await manager.switchRenderer('wasm');
    expect(switched).toBe(false);
    // First WebGPU destroyed for exclusive release; second created to restore.
    expect(webgpuInstances[0]!.destroy).toHaveBeenCalled();
    expect(webgpuInitCount).toBe(2);
    expect(manager.getActiveRendererType()).toBe('webgpu');
  });
});

describe('RendererManager lifecycle', () => {
  let canvas: HTMLCanvasElement;
  let rafCallbacks: Map<number, FrameRequestCallback>;
  let nextRafId: number;
  let rafSpy: jest.SpyInstance;
  let cancelSpy: jest.SpyInstance;

  /** Run one frame of every pending rAF callback (loops re-register themselves). */
  function flushFrame(): void {
    const pending = Array.from(rafCallbacks.entries());
    rafCallbacks.clear();
    for (const [, cb] of pending) cb(performance.now());
  }

  beforeEach(() => {
    canvas = document.createElement('canvas');
    jest.clearAllMocks();
    rafCallbacks = new Map();
    nextRafId = 1;
    rafSpy = jest.spyOn(window, 'requestAnimationFrame').mockImplementation((cb: FrameRequestCallback) => {
      const id = nextRafId++;
      rafCallbacks.set(id, cb);
      // Backend switches await yieldForGpuRelease(); resolve those frames promptly.
      setTimeout(() => {
        const pending = rafCallbacks.get(id);
        if (pending && pending.toString().includes('resolve')) {
          rafCallbacks.delete(id);
          pending(performance.now());
        }
      }, 0);
      return id;
    });
    cancelSpy = jest.spyOn(window, 'cancelAnimationFrame').mockImplementation((id: number) => {
      rafCallbacks.delete(id);
    });
    (WebGPURenderer as jest.Mock).mockImplementation(() => makeMockWebGPU());
    (WASMRenderer as jest.Mock).mockImplementation(() => makeMockWASM());
    (JSRenderer as jest.Mock).mockImplementation(() => makeMockJS());
  });

  afterEach(() => {
    rafSpy.mockRestore();
    cancelSpy.mockRestore();
  });

  it('keeps exactly one metrics loop across 10 backend toggles', async () => {
    const onMetrics = jest.fn();
    const manager = new RendererManager(DEFAULT_CONFIG, onMetrics);
    await manager.init(canvas);
    for (let i = 0; i < 10; i++) {
      await manager.switchRenderer(i % 2 === 0 ? 'wasm' : 'webgpu');
    }
    await new Promise((r) => setTimeout(r, 0));
    onMetrics.mockClear();
    flushFrame();
    expect(onMetrics).toHaveBeenCalledTimes(1);
    expect(rafCallbacks.size).toBe(1);

    await manager.destroy();
    flushFrame();
    expect(rafCallbacks.size).toBe(0);
  });

  it('runs no metrics loop without a listener but still reports live FPS', async () => {
    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(canvas);
    await manager.switchRenderer('wasm');
    await manager.switchRenderer('webgpu');
    expect(rafCallbacks.size).toBe(0);
    expect(manager.getCurrentFPS()).toBe(60);
  });

  it('render() takes no arguments and uploads video frames only on WASM', async () => {
    const wasm = makeMockWASM();
    (WASMRenderer as jest.Mock).mockImplementation(() => wasm);
    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(canvas);
    await manager.switchRenderer('wasm');
    expect(manager.render.length).toBe(0);
    manager.render();
    expect(wasm.updateVideoFrame).toHaveBeenCalled();
  });

  it('destroy() resolves after the backend releases its GPU device', async () => {
    let releaseDone = false;
    const webgpu = makeMockWebGPU();
    (webgpu as unknown as { releaseExclusiveGpu: () => Promise<void> }).releaseExclusiveGpu = jest.fn(
      () => new Promise<void>((resolve) => setTimeout(() => { releaseDone = true; resolve(); }, 5)),
    );
    (WebGPURenderer as jest.Mock).mockImplementation(() => webgpu);
    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(canvas);
    await manager.destroy();
    expect(releaseDone).toBe(true);
    expect(manager.getActiveRendererType()).toBe('js');
  });

  it('falls back to WebGPU when the WASM loop reports a fatal error', async () => {
    let fatal: ((message: string) => void) | null = null;
    const wasm = makeMockWASM();
    (wasm as unknown as { setFatalErrorHandler: jest.Mock }).setFatalErrorHandler = jest.fn((h) => { fatal = h; });
    (WASMRenderer as jest.Mock).mockImplementation(() => wasm);
    const onBackendFailure = jest.fn();
    const manager = new RendererManager(DEFAULT_CONFIG, undefined, { onBackendFailure });
    await manager.init(canvas);
    await manager.switchRenderer('wasm');
    expect(manager.getActiveRendererType()).toBe('wasm');
    expect(fatal).not.toBeNull();

    fatal!('render loop stopped');
    await new Promise((r) => setTimeout(r, 20));
    expect(manager.getActiveRendererType()).toBe('webgpu');
    expect(onBackendFailure).not.toHaveBeenCalled();
  });

  it('reports backend failure when no fallback can take over', async () => {
    let fatal: ((message: string) => void) | null = null;
    const wasm = makeMockWASM();
    (wasm as unknown as { setFatalErrorHandler: jest.Mock }).setFatalErrorHandler = jest.fn((h) => { fatal = h; });
    (WASMRenderer as jest.Mock).mockImplementation(() => wasm);
    const onBackendFailure = jest.fn();
    const manager = new RendererManager(DEFAULT_CONFIG, undefined, { onBackendFailure });
    await manager.init(canvas);
    await manager.switchRenderer('wasm');
    (WebGPURenderer as jest.Mock).mockImplementation(() => ({ init: jest.fn().mockResolvedValue(false), destroy: jest.fn() }));

    fatal!('render loop stopped');
    await new Promise((r) => setTimeout(r, 20));
    expect(onBackendFailure).toHaveBeenCalledWith('wasm', 'render loop stopped');
  });
});

describe('RendererManager device-loss recovery', () => {
  let canvas: HTMLCanvasElement;
  let rafSpy: jest.SpyInstance;

  type LossHandler = (message: string, info?: import('../renderer/Renderer').DeviceLossInfo) => void;
  const loss = (reason = 'unknown') => ({ kind: 'device-lost' as const, reason, message: 'driver reset', at: Date.now() });

  /** A TS WebGPU mock that captures the manager's fatal handler. */
  function lossAwareWebGPU(initOk = true) {
    const r = makeMockWebGPU() as unknown as jest.Mocked<WebGPURenderer> & { fatal: LossHandler | null };
    r.fatal = null;
    (r.init as jest.Mock).mockResolvedValue(initOk);
    (r as unknown as { setFatalErrorHandler: jest.Mock }).setFatalErrorHandler = jest.fn((h: LossHandler) => {
      r.fatal = h;
    });
    return r;
  }

  const rainStack = {
    modes: ['rain', 'none'] as import('../renderer/types').RenderMode[],
    slotParams: [defaultSlotParams, defaultSlotParams],
    resolveShader: (id: string) => (id === 'rain' ? { id: 'rain', name: 'Rain', url: '/rain.wgsl', category: 'image' as const } : undefined),
    inputSource: 'image' as const,
  };
  const settle = () => new Promise((r) => setTimeout(r, 10));

  beforeEach(() => {
    canvas = document.createElement('canvas');
    jest.clearAllMocks();
    rafSpy = jest.spyOn(window, 'requestAnimationFrame').mockImplementation((cb: FrameRequestCallback) =>
      setTimeout(() => cb(performance.now()), 0) as unknown as number);
    (WASMRenderer as jest.Mock).mockImplementation(() => makeMockWASM());
    (JSRenderer as jest.Mock).mockImplementation(() => makeMockJS());
  });

  afterEach(() => {
    rafSpy.mockRestore();
  });

  async function bootWith(first: ReturnType<typeof lossAwareWebGPU>, options = {}) {
    (WebGPURenderer as jest.Mock).mockImplementationOnce(() => first);
    const statuses: string[] = [];
    const onBackendFailure = jest.fn();
    const manager = new RendererManager(DEFAULT_CONFIG, undefined, {
      onBackendFailure,
      getSessionState: () => rainStack,
      onDeviceRecovery: (s) => statuses.push(s.state),
      ...options,
    });
    expect(await manager.init(canvas)).toBe(true);
    expect(first.fatal).toEqual(expect.any(Function));
    return { manager, statuses, onBackendFailure };
  }

  it('rebuilds the WebGPU backend once and replays the live shader stack', async () => {
    const first = lossAwareWebGPU();
    const second = lossAwareWebGPU();
    const { manager, statuses, onBackendFailure } = await bootWith(first);
    (WebGPURenderer as jest.Mock).mockImplementation(() => second);

    first.fatal!('GPU device lost (unknown)', loss());
    await settle();

    expect(statuses).toEqual(['lost', 'recovering', 'idle']);
    expect(first.destroy).toHaveBeenCalled();
    expect(second.init).toHaveBeenCalledTimes(1);
    expect(second.loadShader).toHaveBeenCalledWith('rain', '/rain.wgsl');
    expect(second.setSlotShader).toHaveBeenCalledWith(0, 'rain');
    expect(second.setInputSource).toHaveBeenCalledWith('image');
    expect(manager.getDeviceRecoveryStatus()).toMatchObject({ state: 'idle', attempts: 1, lastLoss: { reason: 'unknown' } });
    expect(manager.getDiagnostics().deviceRecovery).toMatchObject({ state: 'idle', attempts: 1 });
    expect(manager.getDevice()).toBeNull(); // the dead device is no longer adopted
    // Never another backend type.
    expect(WASMRenderer).not.toHaveBeenCalled();
    expect(JSRenderer).not.toHaveBeenCalled();
    expect(onBackendFailure).not.toHaveBeenCalled();

    // A late report from the replaced renderer is ignored.
    first.fatal!('GPU device lost (unknown)', loss());
    await settle();
    expect(statuses).toEqual(['lost', 'recovering', 'idle']);
  });

  it('a render-worker crash (worker-died) takes the same recovery path (#1395)', async () => {
    const first = lossAwareWebGPU();
    const second = lossAwareWebGPU();
    const { manager, statuses } = await bootWith(first);
    let releaseInit!: (ok: boolean) => void;
    (second.init as jest.Mock).mockReturnValue(new Promise<boolean>((r) => { releaseInit = r; }));
    (WebGPURenderer as jest.Mock).mockImplementation(() => second);

    first.fatal!('Render worker crashed (boom)', {
      kind: 'worker-died', reason: 'render worker crashed', message: 'boom', at: Date.now(),
    });
    await settle();
    // The gap between the crash and the rebuilt device still counts as "a renderer owns the
    // GPU", so depth estimation does not open a second WebGPU device meanwhile.
    expect(statuses).toEqual(['lost', 'recovering']);
    expect(manager.isGpuDeviceActive()).toBe(true);

    releaseInit(true);
    await settle();
    expect(statuses).toEqual(['lost', 'recovering', 'idle']);
    expect(second.loadShader).toHaveBeenCalledWith('rain', '/rain.wgsl');
    expect(manager.getDeviceRecoveryStatus().lastLoss).toMatchObject({ kind: 'worker-died' });
  });

  it('a failed recovery blocks with diagnostics (no fallback, no restore loop) until Retry', async () => {
    const first = lossAwareWebGPU();
    const failing = lossAwareWebGPU(false);
    const { manager, statuses, onBackendFailure } = await bootWith(first);
    (WebGPURenderer as jest.Mock).mockImplementation(() => failing);

    first.fatal!('GPU device lost (unknown)', loss());
    await settle();

    expect(statuses).toEqual(['lost', 'recovering', 'failed']);
    expect(failing.init).toHaveBeenCalledTimes(1); // switchRenderer did not retry/restore on its own
    expect(onBackendFailure).toHaveBeenCalledWith('webgpu', expect.any(String));
    expect(WASMRenderer).not.toHaveBeenCalled();
    expect(JSRenderer).not.toHaveBeenCalled();

    const third = lossAwareWebGPU();
    (WebGPURenderer as jest.Mock).mockImplementation(() => third);
    expect(await manager.recoverFromDeviceLoss()).toBe(true);
    expect(statuses.slice(-2)).toEqual(['recovering', 'idle']);
    expect(manager.getDeviceRecoveryStatus().attempts).toBe(2);
    expect(third.setSlotShader).toHaveBeenCalledWith(0, 'rain');
  });

  it('concurrent retries share one rebuild', async () => {
    const first = lossAwareWebGPU();
    const { manager } = await bootWith(first);
    const second = lossAwareWebGPU();
    (WebGPURenderer as jest.Mock).mockClear();
    (WebGPURenderer as jest.Mock).mockImplementation(() => second);
    const [a, b] = await Promise.all([manager.recoverFromDeviceLoss(), manager.recoverFromDeviceLoss()]);
    expect(a).toBe(true);
    expect(b).toBe(true);
    expect(WebGPURenderer).toHaveBeenCalledTimes(1);
  });

  it('a second loss right after a recovery waits for the user instead of looping', async () => {
    const first = lossAwareWebGPU();
    const second = lossAwareWebGPU();
    const { manager, statuses, onBackendFailure } = await bootWith(first);
    (WebGPURenderer as jest.Mock).mockImplementation(() => second);
    first.fatal!('lost', loss());
    await settle();
    (WebGPURenderer as jest.Mock).mockClear();

    second.fatal!('lost again', loss());
    await settle();
    expect(statuses.slice(-2)).toEqual(['lost', 'failed']);
    expect(WebGPURenderer).not.toHaveBeenCalled();
    expect(onBackendFailure).toHaveBeenCalledTimes(1);
    expect(manager.getDeviceRecoveryStatus().lastError).toMatch(/again/);
  });

  it('replays what the lost backend was rendering, even when the host session does not know it', async () => {
    const first = lossAwareWebGPU();
    (first as unknown as { getSlotState: jest.Mock }).getSlotState = jest.fn((i: number) =>
      i === 1 ? { shaderId: 'plasma', enabled: true, mode: 'parallel' } : { shaderId: null, enabled: false, mode: 'chained' });
    const second = lossAwareWebGPU();
    const { manager } = await bootWith(first, { getSessionState: () => ({ ...rainStack, modes: ['none', 'none'] }) });
    await manager.loadShader('plasma', '/shaders/plasma.wgsl', { requiresHistoryRing: true });
    manager.setInputSource('generative');
    (WebGPURenderer as jest.Mock).mockImplementation(() => second);

    first.fatal!('lost', loss());
    await settle();

    expect(second.loadShader).toHaveBeenCalledWith('plasma', '/shaders/plasma.wgsl');
    expect(second.setSlotShader).toHaveBeenCalledWith(1, 'plasma');
    expect(second.setSlotShader).toHaveBeenCalledWith(0, '');
    expect(second.setSlotMode).toHaveBeenCalledWith(1, 'parallel');
    expect(second.setInputSource).toHaveBeenLastCalledWith('generative');
  });

  it('a non-loss fatal error keeps the existing backend-failure path', async () => {
    const first = lossAwareWebGPU();
    const { statuses, onBackendFailure } = await bootWith(first);
    first.fatal!('render loop stopped');
    await settle();
    expect(statuses).toEqual([]);
    expect(onBackendFailure).toHaveBeenCalledWith('webgpu', 'render loop stopped');
  });

  it('destroy during a recovery waits for it and releases the rebuilt backend', async () => {
    const first = lossAwareWebGPU();
    const second = lossAwareWebGPU();
    let finishInit!: (ok: boolean) => void;
    (second.init as jest.Mock).mockImplementation(() => new Promise<boolean>((r) => { finishInit = r; }));
    const { manager } = await bootWith(first);
    (WebGPURenderer as jest.Mock).mockImplementation(() => second);
    first.fatal!('lost', loss());
    await settle();
    expect(second.init).toHaveBeenCalled();

    const destroyed = manager.destroy();
    finishInit(true);
    await destroyed;
    expect(second.destroy).toHaveBeenCalled();
  });

  it('does nothing after destroy', async () => {
    const first = lossAwareWebGPU();
    const { manager, statuses } = await bootWith(first);
    await manager.destroy();
    first.fatal!('lost', loss());
    await settle();
    expect(statuses).toEqual([]);
    expect(await manager.recoverFromDeviceLoss()).toBe(false);
  });
});
