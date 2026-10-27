import type { Mock, MockInstance, Mocked } from 'vitest';
import { RendererManager } from '../renderer/RendererManager';
import { WebGPURenderer } from '../renderer/WebGPURenderer';
import { WASMRenderer } from '../renderer/WASMRenderer';
import { JSRenderer } from '../renderer/JSRenderer';
import { DEFAULT_CONFIG } from '../renderer/Renderer';
import { SlotParams } from '../renderer/types';
import { createWaveTankGraph } from '../renderer/multipassGraph';
import { clearRuntimeGraphs, GRAPH_LAB_RUNTIME_ID } from '../renderer/runtimeGraphs';

vi.mock('../renderer/WebGPURenderer');
vi.mock('../renderer/WASMRenderer');
vi.mock('../renderer/JSRenderer');
vi.mock('../wasm/wasm_bridge', () => ({
  initWasmRenderer: vi.fn().mockResolvedValue(true),
  shutdownWasmRenderer: vi.fn(),
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

function makeMockWebGPU(): Mocked<WebGPURenderer> {
  return {
    init: vi.fn().mockResolvedValue(true),
    destroy: vi.fn(),
    loadShader: vi.fn().mockResolvedValue(true),
    setActiveShader: vi.fn(),
    setSlotShader: vi.fn(),
    setSlotParams: vi.fn(),
    updateSlotParams: vi.fn(),
    setSlotMode: vi.fn(),
    addRipple: vi.fn(),
    clearRipples: vi.fn(),
    setInputSource: vi.fn(),
    getInputSource: vi.fn().mockReturnValue('image'),
    updateVideoFrame: vi.fn(),
    updateAudioData: vi.fn(),
    updateAudioFrequencyBins: vi.fn(),
    takeScreenshot: vi.fn().mockResolvedValue(undefined),
    refreshFrameImage: vi.fn().mockResolvedValue(''),
    getFrameImage: vi.fn().mockReturnValue(''),
    getFPS: vi.fn().mockReturnValue(60),
    loadImage: vi.fn().mockResolvedValue('https://example.com/webgpu.png'),
    reloadShaderFromURL: vi.fn().mockResolvedValue(true),
    setVideo: vi.fn(),
    getVideo: vi.fn().mockReturnValue(null),
  } as unknown as Mocked<WebGPURenderer>;
}

function makeMockWASM(): Mocked<WASMRenderer> {
  return {
    init: vi.fn().mockResolvedValue(true),
    destroy: vi.fn(),
    loadShader: vi.fn().mockResolvedValue(true),
    setActiveShader: vi.fn(),
    setSlotShader: vi.fn(),
    setSlotParams: vi.fn(),
    updateSlotParams: vi.fn(),
    setSlotMode: vi.fn(),
    addRipple: vi.fn(),
    clearRipples: vi.fn(),
    setInputSource: vi.fn(),
    getInputSource: vi.fn().mockReturnValue('image'),
    updateVideoFrame: vi.fn(),
    updateAudioData: vi.fn(),
    updateAudioFrequencyBins: vi.fn(),
    takeScreenshot: vi.fn().mockResolvedValue(undefined),
    refreshFrameImage: vi.fn().mockResolvedValue('data:image/png;base64,x'),
    getFrameImage: vi.fn().mockReturnValue(''),
    getSlotState: vi.fn().mockReturnValue({ shaderId: 'rain', enabled: true, mode: 'chained' }),
    getGPUTimings: vi.fn().mockReturnValue({ parallelTime: 1, chainedTime: 2, totalTime: 3, available: false, timingSource: 'wall-clock' }),
    getAudioData: vi.fn().mockReturnValue({ bass: 0, mid: 0, treble: 0, freqBins: new Float32Array(128) }),
    isRecording: vi.fn().mockReturnValue(false),
    getSupportsDeepWorkgroup: vi.fn().mockReturnValue(true),
    setRecording: vi.fn(),
    startRecording: vi.fn().mockResolvedValue(new Blob()),
    stopRecording: vi.fn(),
    loadImage: vi.fn().mockResolvedValue('https://example.com/img.png'),
    reloadShaderFromURL: vi.fn().mockResolvedValue(true),
    setVideo: vi.fn(),
    getVideo: vi.fn().mockReturnValue(null),
    getFPS: vi.fn().mockReturnValue(55),
    getDiagnostics: vi.fn().mockReturnValue({ initialized: true }),
  } as unknown as Mocked<WASMRenderer>;
}

function makeMockJS(): Mocked<JSRenderer> {
  return {
    init: vi.fn().mockResolvedValue(true),
    destroy: vi.fn(),
    setInputSource: vi.fn(),
    getInputSource: vi.fn().mockReturnValue('image'),
    updateVideoFrame: vi.fn(),
    getFPS: vi.fn().mockReturnValue(30),
  } as unknown as Mocked<JSRenderer>;
}

describe('RendererManager shader forwarding', () => {
  let canvas: HTMLCanvasElement;

  beforeEach(() => {
    canvas = document.createElement('canvas');
    vi.clearAllMocks();
  });

  it('forwards setSlotShader and updateSlotParams to WASMRenderer', async () => {
    const wasm = makeMockWASM();
    (WASMRenderer as Mock).mockImplementation(() => wasm);
    (WebGPURenderer as Mock).mockImplementation(() => ({
      init: vi.fn().mockResolvedValue(false),
      destroy: vi.fn(),
    }));
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

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
    (WebGPURenderer as Mock).mockImplementation(() => webgpu);
    (WASMRenderer as Mock).mockImplementation(() => makeMockWASM());
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

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
    (WASMRenderer as Mock).mockImplementation(() => wasm);
    (WebGPURenderer as Mock).mockImplementation(() => ({
      init: vi.fn().mockResolvedValue(false),
      destroy: vi.fn(),
    }));
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

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
    (WASMRenderer as Mock).mockImplementation(() => wasm);
    (WebGPURenderer as Mock).mockImplementation(() => ({
      init: vi.fn().mockResolvedValue(false),
      destroy: vi.fn(),
    }));
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

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
    (WASMRenderer as Mock).mockImplementation(() => wasm);
    (WebGPURenderer as Mock).mockImplementation(() => ({
      init: vi.fn().mockResolvedValue(false),
      destroy: vi.fn(),
    }));
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

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
    (JSRenderer as Mock).mockImplementation(() => js);
    (WebGPURenderer as Mock).mockImplementation(() => ({
      init: vi.fn().mockResolvedValue(false),
      destroy: vi.fn(),
    }));

    const manager = new RendererManager(DEFAULT_CONFIG);
    const ok = await manager.init(canvas);
    expect(ok).toBe(false);
    expect(js.init).not.toHaveBeenCalled();
  });

  it('no-ops shader calls when Canvas2D fallback is active', async () => {
    const js = makeMockJS();
    (JSRenderer as Mock).mockImplementation(() => js);
    (WebGPURenderer as Mock).mockImplementation(() => ({
      init: vi.fn().mockResolvedValue(false),
      destroy: vi.fn(),
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
    (WASMRenderer as Mock).mockImplementation(() => wasm);
    (WebGPURenderer as Mock).mockImplementation(() => ({
      init: vi.fn().mockResolvedValue(false),
      destroy: vi.fn(),
    }));
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

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
    (WebGPURenderer as Mock).mockImplementation(() => webgpu);
    (WASMRenderer as Mock).mockImplementation(() => makeMockWASM());
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(canvas);

    manager.setInputSource('video');
    expect(webgpu.setInputSource).toHaveBeenCalledWith('video');
  });

  it('render() uploads video frames on WASM backend', async () => {
    const wasm = makeMockWASM();
    (WASMRenderer as Mock).mockImplementation(() => wasm);
    (WebGPURenderer as Mock).mockImplementation(() => ({
      init: vi.fn().mockResolvedValue(false),
      destroy: vi.fn(),
    }));
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(document.createElement('canvas'));
    await manager.switchRenderer('wasm');

    manager.render();
    expect(wasm.updateVideoFrame).toHaveBeenCalled();
  });

  it('addRipplePoint forwards to addRipple on shader backends', async () => {
    const webgpu = makeMockWebGPU();
    (WebGPURenderer as Mock).mockImplementation(() => webgpu);
    (WASMRenderer as Mock).mockImplementation(() => makeMockWASM());
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(canvas);
    await manager.switchRenderer('webgpu');

    manager.addRipplePoint(0.5, 0.25);
    expect(webgpu.addRipple).toHaveBeenCalledWith(0.5, 0.25);
  });

  it('forwards updateAudioFrequencyBins to WASMRenderer', async () => {
    const wasm = makeMockWASM();
    (WASMRenderer as Mock).mockImplementation(() => wasm);
    (WebGPURenderer as Mock).mockImplementation(() => ({
      init: vi.fn().mockResolvedValue(false),
      destroy: vi.fn(),
    }));
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(document.createElement('canvas'));
    await manager.switchRenderer('wasm');

    const bins = new Float32Array([0.1, 0.5, 0.9]);
    manager.updateAudioFrequencyBins(bins);
    expect(wasm.updateAudioFrequencyBins).toHaveBeenCalledWith(bins);
  });

  it('delegates takeScreenshot to WASMRenderer', async () => {
    const wasm = makeMockWASM();
    (WASMRenderer as Mock).mockImplementation(() => wasm);
    (WebGPURenderer as Mock).mockImplementation(() => ({
      init: vi.fn().mockResolvedValue(false),
      destroy: vi.fn(),
    }));
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(document.createElement('canvas'));
    await manager.switchRenderer('wasm');

    await manager.takeScreenshot('test.png');
    expect(wasm.takeScreenshot).toHaveBeenCalledWith('test.png');
  });

  it('exposes getSlotState and getGPUTimings from WASMRenderer', async () => {
    const wasm = makeMockWASM();
    (WASMRenderer as Mock).mockImplementation(() => wasm);
    (WebGPURenderer as Mock).mockImplementation(() => ({
      init: vi.fn().mockResolvedValue(false),
      destroy: vi.fn(),
    }));
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

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
    (WASMRenderer as Mock).mockImplementation(() => wasm);
    (WebGPURenderer as Mock).mockImplementation(() => ({
      init: vi.fn().mockResolvedValue(false),
      destroy: vi.fn(),
    }));
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

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
    (WASMRenderer as Mock).mockImplementation(() => wasm);
    (WebGPURenderer as Mock).mockImplementation(() => ({
      init: vi.fn().mockResolvedValue(false),
      destroy: vi.fn(),
    }));
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

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
    (WASMRenderer as Mock).mockImplementation(() => wasm);
    (WebGPURenderer as Mock).mockImplementation(() => ({
      init: vi.fn().mockResolvedValue(false),
      destroy: vi.fn(),
    }));
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(document.createElement('canvas'));
    await manager.switchRenderer('wasm');

    const url = await manager.loadImage('https://example.com/a.png');
    expect(wasm.loadImage).toHaveBeenCalledWith('https://example.com/a.png');
    expect(url).toBe('https://example.com/img.png');
  });

  it('delegates loadImage to WebGPURenderer', async () => {
    const webgpu = makeMockWebGPU();
    (WebGPURenderer as Mock).mockImplementation(() => webgpu);
    (WASMRenderer as Mock).mockImplementation(() => ({
      init: vi.fn().mockResolvedValue(false),
      destroy: vi.fn(),
    }));
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(document.createElement('canvas'));

    const url = await manager.loadImage('https://example.com/b.png');
    expect(webgpu.loadImage).toHaveBeenCalledWith('https://example.com/b.png');
    expect(url).toBe('https://example.com/webgpu.png');
  });

  it('re-uploads the current image after switching to WASM (#1206)', async () => {
    const webgpu = makeMockWebGPU();
    const wasm = makeMockWASM();
    (WebGPURenderer as Mock).mockImplementation(() => webgpu);
    (WASMRenderer as Mock).mockImplementation(() => wasm);
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

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
    (wasm as unknown as { loadImageFromElement: Mock }).loadImageFromElement = vi
      .fn()
      .mockReturnValue({ width: 16, height: 8 });
    (WebGPURenderer as Mock).mockImplementation(() => webgpu);
    (WASMRenderer as Mock).mockImplementation(() => wasm);
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(canvas);
    wasm.loadImage.mockClear();

    await manager.switchRenderer('wasm');

    expect((wasm as unknown as { loadImageFromElement: Mock }).loadImageFromElement).toHaveBeenCalledWith(offscreen);
    expect(wasm.loadImage).not.toHaveBeenCalled();
  });

  it('resyncs the stored shader stack as part of switchRenderer (#1206)', async () => {
    const webgpu = makeMockWebGPU();
    const wasm = makeMockWASM();
    (WebGPURenderer as Mock).mockImplementation(() => webgpu);
    (WASMRenderer as Mock).mockImplementation(() => wasm);
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

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
    (WASMRenderer as Mock).mockImplementation(() => wasm);
    (WebGPURenderer as Mock).mockImplementation(() => ({
      init: vi.fn().mockResolvedValue(false),
      destroy: vi.fn(),
    }));
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(document.createElement('canvas'));
    await manager.switchRenderer('wasm');

    await manager.reloadShader('rain', '/shaders/rain.wgsl');
    expect(wasm.reloadShaderFromURL).toHaveBeenCalledWith('rain', '/shaders/rain.wgsl');
  });

  it('firePlasma falls back to addRipple when backend has no firePlasma', async () => {
    const wasm = makeMockWASM();
    (WASMRenderer as Mock).mockImplementation(() => wasm);
    (WebGPURenderer as Mock).mockImplementation(() => ({
      init: vi.fn().mockResolvedValue(false),
      destroy: vi.fn(),
    }));
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(document.createElement('canvas'));
    await manager.switchRenderer('wasm');

    manager.firePlasma(0.5, 0.5, 1, 0);
    expect(wasm.addRipple).toHaveBeenCalledWith(0.5, 0.5);
  });

  it('reports renderer type from metrics rather than instanceof', async () => {
    const wasm = makeMockWASM();
    (WASMRenderer as Mock).mockImplementation(() => wasm);
    (WebGPURenderer as Mock).mockImplementation(() => ({
      init: vi.fn().mockResolvedValue(false),
      destroy: vi.fn(),
    }));
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(document.createElement('canvas'));
    await manager.switchRenderer('wasm');

    expect(manager.getActiveRendererType()).toBe('wasm');
  });

  it('releases WebGPU before WASM init (exclusive adapter ownership)', async () => {
    const order: string[] = [];
    const webgpu = makeMockWebGPU();
    webgpu.destroy = vi.fn(async () => {
      order.push('webgpu.destroy');
    });
    const wasm = makeMockWASM();
    wasm.init = vi.fn(async (_canvas: HTMLCanvasElement) => {
      order.push('wasm.init');
      return true;
    });

    (WebGPURenderer as Mock).mockImplementation(() => webgpu);
    (WASMRenderer as Mock).mockImplementation(() => wasm);
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

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
    const webgpuInstances: Array<{ init: Mock; destroy: Mock }> = [];

    (WebGPURenderer as Mock).mockImplementation(() => {
      const instance = {
        init: vi.fn(async () => {
          webgpuInitCount += 1;
          return true;
        }),
        destroy: vi.fn(),
        loadShader: vi.fn().mockResolvedValue(true),
        setActiveShader: vi.fn(),
        setSlotShader: vi.fn(),
        setSlotParams: vi.fn(),
        updateSlotParams: vi.fn(),
        setSlotMode: vi.fn(),
        addRipple: vi.fn(),
        clearRipples: vi.fn(),
        setInputSource: vi.fn(),
        getInputSource: vi.fn().mockReturnValue('image'),
        updateVideoFrame: vi.fn(),
        updateAudioData: vi.fn(),
        updateAudioFrequencyBins: vi.fn(),
        takeScreenshot: vi.fn().mockResolvedValue(undefined),
        refreshFrameImage: vi.fn().mockResolvedValue(''),
        getFrameImage: vi.fn().mockReturnValue(''),
        getFPS: vi.fn().mockReturnValue(60),
        loadImage: vi.fn().mockResolvedValue('https://example.com/webgpu.png'),
        reloadShaderFromURL: vi.fn().mockResolvedValue(true),
        getDiagnostics: vi.fn().mockReturnValue({ initialized: true }),
      };
      webgpuInstances.push(instance);
      return instance;
    });

    const wasm = makeMockWASM();
    wasm.init = vi.fn().mockResolvedValue(false);
    (WASMRenderer as Mock).mockImplementation(() => wasm);
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());

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

  it('restores WebGPU when WASM init fails after a worker-owned canvas was released', async () => {
    // The worker took the canvas, so switchRenderer releases it before WASM init and
    // performBackendSwitch has no previous renderer to restore by itself.
    const webgpu = makeMockWebGPU();
    (WebGPURenderer as Mock).mockImplementation(() => webgpu);
    const wasm = makeMockWASM();
    wasm.init = vi.fn().mockResolvedValue(false);
    (WASMRenderer as Mock).mockImplementation(() => wasm);

    const fresh = document.createElement('canvas');
    const acquireFreshCanvas = vi.fn(async () => fresh);
    const manager = new RendererManager(DEFAULT_CONFIG, undefined, { acquireFreshCanvas });
    await manager.init(canvas);
    expect(manager.getActiveRendererType()).toBe('webgpu');
    // Only now does the worker own the canvas the manager holds.
    const workerBackend = await import('../renderer/worker/WorkerWebGPUBackend');
    const transferredSpy = vi
      .spyOn(workerBackend, 'isCanvasTransferred')
      .mockImplementation((c) => c === canvas);

    expect(await manager.switchRenderer('wasm')).toBe(false);
    expect(acquireFreshCanvas).toHaveBeenCalled();
    expect(wasm.init).toHaveBeenCalledTimes(1);
    expect(webgpu.destroy).toHaveBeenCalled();
    expect(webgpu.init).toHaveBeenCalledTimes(2);
    expect(manager.getActiveRendererType()).toBe('webgpu');
    // The failed attempt stays inspectable after the restore.
    expect(manager.getDiagnostics().wasm).toBeDefined();
    transferredSpy.mockRestore();
  });
});

describe('RendererManager lifecycle', () => {
  let canvas: HTMLCanvasElement;
  let rafCallbacks: Map<number, FrameRequestCallback>;
  let nextRafId: number;
  let rafSpy: MockInstance;
  let cancelSpy: MockInstance;

  /** Run one frame of every pending rAF callback (loops re-register themselves). */
  function flushFrame(): void {
    const pending = Array.from(rafCallbacks.entries());
    rafCallbacks.clear();
    for (const [, cb] of pending) cb(performance.now());
  }

  beforeEach(() => {
    canvas = document.createElement('canvas');
    vi.clearAllMocks();
    rafCallbacks = new Map();
    nextRafId = 1;
    rafSpy = vi.spyOn(window, 'requestAnimationFrame').mockImplementation((cb: FrameRequestCallback) => {
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
    cancelSpy = vi.spyOn(window, 'cancelAnimationFrame').mockImplementation((id: number) => {
      rafCallbacks.delete(id);
    });
    (WebGPURenderer as Mock).mockImplementation(() => makeMockWebGPU());
    (WASMRenderer as Mock).mockImplementation(() => makeMockWASM());
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());
  });

  afterEach(() => {
    rafSpy.mockRestore();
    cancelSpy.mockRestore();
  });

  it('keeps exactly one metrics loop across 10 backend toggles', async () => {
    const onMetrics = vi.fn();
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
    (WASMRenderer as Mock).mockImplementation(() => wasm);
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
    (webgpu as unknown as { releaseExclusiveGpu: () => Promise<void> }).releaseExclusiveGpu = vi.fn(
      () => new Promise<void>((resolve) => setTimeout(() => { releaseDone = true; resolve(); }, 5)),
    );
    (WebGPURenderer as Mock).mockImplementation(() => webgpu);
    const manager = new RendererManager(DEFAULT_CONFIG);
    await manager.init(canvas);
    await manager.destroy();
    expect(releaseDone).toBe(true);
    expect(manager.getActiveRendererType()).toBe('js');
  });

  it('falls back to WebGPU when the WASM loop reports a fatal error', async () => {
    let fatal: ((message: string) => void) | null = null;
    const wasm = makeMockWASM();
    (wasm as unknown as { setFatalErrorHandler: Mock }).setFatalErrorHandler = vi.fn((h) => { fatal = h; });
    (WASMRenderer as Mock).mockImplementation(() => wasm);
    const onBackendFailure = vi.fn();
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
    (wasm as unknown as { setFatalErrorHandler: Mock }).setFatalErrorHandler = vi.fn((h) => { fatal = h; });
    (WASMRenderer as Mock).mockImplementation(() => wasm);
    const onBackendFailure = vi.fn();
    const manager = new RendererManager(DEFAULT_CONFIG, undefined, { onBackendFailure });
    await manager.init(canvas);
    await manager.switchRenderer('wasm');
    (WebGPURenderer as Mock).mockImplementation(() => ({ init: vi.fn().mockResolvedValue(false), destroy: vi.fn() }));

    fatal!('render loop stopped');
    await new Promise((r) => setTimeout(r, 20));
    expect(onBackendFailure).toHaveBeenCalledWith('wasm', 'render loop stopped');
  });
});

describe('RendererManager device-loss recovery', () => {
  let canvas: HTMLCanvasElement;
  let rafSpy: MockInstance;

  type LossHandler = (message: string, info?: import('../renderer/Renderer').DeviceLossInfo) => void;
  const loss = (reason = 'unknown') => ({ kind: 'device-lost' as const, reason, message: 'driver reset', at: Date.now() });

  /** A TS WebGPU mock that captures the manager's fatal handler. */
  function lossAwareWebGPU(initOk = true) {
    const r = makeMockWebGPU() as unknown as Mocked<WebGPURenderer> & { fatal: LossHandler | null };
    r.fatal = null;
    (r.init as Mock).mockResolvedValue(initOk);
    (r as unknown as { setFatalErrorHandler: Mock }).setFatalErrorHandler = vi.fn((h: LossHandler) => {
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
    vi.clearAllMocks();
    rafSpy = vi.spyOn(window, 'requestAnimationFrame').mockImplementation((cb: FrameRequestCallback) =>
      setTimeout(() => cb(performance.now()), 0) as unknown as number);
    (WASMRenderer as Mock).mockImplementation(() => makeMockWASM());
    (JSRenderer as Mock).mockImplementation(() => makeMockJS());
  });

  afterEach(() => {
    rafSpy.mockRestore();
  });

  async function bootWith(first: ReturnType<typeof lossAwareWebGPU>, options = {}) {
    (WebGPURenderer as Mock).mockImplementationOnce(() => first);
    const statuses: string[] = [];
    const onBackendFailure = vi.fn();
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
    (WebGPURenderer as Mock).mockImplementation(() => second);

    first.fatal!('GPU device lost (unknown)', loss());
    await settle();

    // Poll rather than trust one 10 ms tick: recovery takes several async hops and
    // a loaded CI worker can starve the timer.
    await vi.waitFor(() => expect(statuses).toEqual(['lost', 'recovering', 'idle']));
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
    (second.init as Mock).mockReturnValue(new Promise<boolean>((r) => { releaseInit = r; }));
    (WebGPURenderer as Mock).mockImplementation(() => second);

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
    (WebGPURenderer as Mock).mockImplementation(() => failing);

    first.fatal!('GPU device lost (unknown)', loss());
    await settle();

    expect(statuses).toEqual(['lost', 'recovering', 'failed']);
    expect(failing.init).toHaveBeenCalledTimes(1); // switchRenderer did not retry/restore on its own
    expect(onBackendFailure).toHaveBeenCalledWith('webgpu', expect.any(String));
    expect(WASMRenderer).not.toHaveBeenCalled();
    expect(JSRenderer).not.toHaveBeenCalled();

    const third = lossAwareWebGPU();
    (WebGPURenderer as Mock).mockImplementation(() => third);
    expect(await manager.recoverFromDeviceLoss()).toBe(true);
    expect(statuses.slice(-2)).toEqual(['recovering', 'idle']);
    expect(manager.getDeviceRecoveryStatus().attempts).toBe(2);
    expect(third.setSlotShader).toHaveBeenCalledWith(0, 'rain');
  });

  it('concurrent retries share one rebuild', async () => {
    const first = lossAwareWebGPU();
    const { manager } = await bootWith(first);
    const second = lossAwareWebGPU();
    (WebGPURenderer as Mock).mockClear();
    (WebGPURenderer as Mock).mockImplementation(() => second);
    const [a, b] = await Promise.all([manager.recoverFromDeviceLoss(), manager.recoverFromDeviceLoss()]);
    expect(a).toBe(true);
    expect(b).toBe(true);
    expect(WebGPURenderer).toHaveBeenCalledTimes(1);
  });

  it('a second loss right after a recovery waits for the user instead of looping', async () => {
    const first = lossAwareWebGPU();
    const second = lossAwareWebGPU();
    const { manager, statuses, onBackendFailure } = await bootWith(first);
    (WebGPURenderer as Mock).mockImplementation(() => second);
    first.fatal!('lost', loss());
    await settle();
    (WebGPURenderer as Mock).mockClear();

    second.fatal!('lost again', loss());
    await settle();
    expect(statuses.slice(-2)).toEqual(['lost', 'failed']);
    expect(WebGPURenderer).not.toHaveBeenCalled();
    expect(onBackendFailure).toHaveBeenCalledTimes(1);
    expect(manager.getDeviceRecoveryStatus().lastError).toMatch(/again/);
  });

  it('replays what the lost backend was rendering, even when the host session does not know it', async () => {
    const first = lossAwareWebGPU();
    (first as unknown as { getSlotState: Mock }).getSlotState = vi.fn((i: number) =>
      i === 1 ? { shaderId: 'plasma', enabled: true, mode: 'parallel' } : { shaderId: null, enabled: false, mode: 'chained' });
    const second = lossAwareWebGPU();
    const { manager } = await bootWith(first, { getSessionState: () => ({ ...rainStack, modes: ['none', 'none'] }) });
    await manager.loadShader('plasma', '/shaders/plasma.wgsl', { requiresHistoryRing: true });
    manager.setInputSource('generative');
    (WebGPURenderer as Mock).mockImplementation(() => second);

    first.fatal!('lost', loss());
    await settle();

    expect(second.loadShader).toHaveBeenCalledWith('plasma', '/shaders/plasma.wgsl');
    expect(second.setSlotShader).toHaveBeenCalledWith(1, 'plasma');
    expect(second.setSlotShader).toHaveBeenCalledWith(0, '');
    expect(second.setSlotMode).toHaveBeenCalledWith(1, 'parallel');
    expect(second.setInputSource).toHaveBeenLastCalledWith('generative');
  });

  it('restores all six slots, their modes and params — slots 3–5 are not dropped (#1425)', async () => {
    const ids = ['s0', 's1', 's2', 's3', 's4', 's5'];
    const modes = ['chained', 'parallel', 'chained', 'parallel', 'chained', 'parallel'] as const;
    const first = lossAwareWebGPU();
    (first as unknown as { getSlotState: Mock }).getSlotState = vi.fn((i: number) =>
      i < ids.length ? { shaderId: ids[i], enabled: true, mode: modes[i] } : null);
    const second = lossAwareWebGPU();
    const sixParams = ids.map((_, i) => ({ ...defaultSlotParams, zoomParam1: 0.1 * (i + 1) }));
    const { manager, statuses } = await bootWith(first, {
      getSessionState: () => ({ ...rainStack, modes: ['none', 'none', 'none'], slotParams: sixParams }),
    });
    manager.overrideSlotCapForTests(6); // the cap override outlives the backend, as in the harness / VJ
    for (const id of ids) await manager.loadShader(id, `/${id}.wgsl`);
    (WebGPURenderer as Mock).mockImplementation(() => second);

    first.fatal!('lost', loss());
    await settle();

    expect(statuses).toEqual(['lost', 'recovering', 'idle']);
    ids.forEach((id, i) => {
      expect(second.loadShader).toHaveBeenCalledWith(id, `/${id}.wgsl`);
      expect(second.setSlotShader).toHaveBeenCalledWith(i, id);
    });
    expect((second.setSlotMode as Mock).mock.calls).toEqual([[1, 'parallel'], [3, 'parallel'], [5, 'parallel']]);
    for (const slot of [3, 4, 5]) {
      expect(second.updateSlotParams).toHaveBeenCalledWith(
        expect.objectContaining({ zoomParam1: sixParams[slot]!.zoomParam1 }),
        slot,
      );
    }
  });

  it('re-sends the Graph Lab draft to the rebuilt backend before the shader stack (#1418)', async () => {
    const graph = createWaveTankGraph();
    const first = lossAwareWebGPU();
    const second = lossAwareWebGPU();
    for (const r of [first, second]) {
      Object.assign(r, {
        backendKind: 'webgpu',
        setRuntimeGraph: vi.fn(),
        setResolutionScale: vi.fn(),
        setAdaptiveQuality: vi.fn(),
        setMaxPassesPerFrame: vi.fn(),
        setFramePassBudget: vi.fn(),
        setColorFormat: vi.fn(),
      });
    }
    (first as unknown as { getSlotState: Mock }).getSlotState = vi.fn((i: number) =>
      i === 0 ? { shaderId: GRAPH_LAB_RUNTIME_ID, enabled: true, mode: 'chained' } : null);
    const { manager } = await bootWith(first);
    await manager.loadShader(GRAPH_LAB_RUNTIME_ID, '/graphlab-draft.wgsl');
    expect(manager.setRuntimeGraph(GRAPH_LAB_RUNTIME_ID, graph, { stateCount: 4096 })).toBe(true);
    (WebGPURenderer as Mock).mockImplementation(() => second);

    first.fatal!('lost', loss());
    await settle();
    // Recovery takes several async hops; poll rather than trust one 10 ms tick under load.
    await vi.waitFor(() => expect(second.setSlotShader).toHaveBeenCalled());

    const setGraph = second.setRuntimeGraph as unknown as Mock;
    expect(setGraph).toHaveBeenCalledTimes(1);
    expect(setGraph).toHaveBeenCalledWith(GRAPH_LAB_RUNTIME_ID, graph, { stateCount: 4096 });
    expect(setGraph.mock.invocationCallOrder[0]).toBeLessThan((second.loadShader as Mock).mock.invocationCallOrder[0]!);
    expect(setGraph.mock.invocationCallOrder[0]).toBeLessThan((second.setSlotShader as Mock).mock.invocationCallOrder[0]!);
    clearRuntimeGraphs();
  });

  it('replays compositor layers, depth map, auto-exposure, node scales and ripples after a loss (#1512)', async () => {
    const first = lossAwareWebGPU();
    const second = lossAwareWebGPU();
    const screen = { output: 'blend' as const, blend: 'screen' as const, opacity: 0.5, mask: { source: 'depth' as const, invert: true } };
    for (const r of [first, second]) {
      Object.assign(r, {
        backendKind: 'webgpu',
        setResolutionScale: vi.fn(),
        setAdaptiveQuality: vi.fn(),
        setMaxPassesPerFrame: vi.fn(),
        setFramePassBudget: vi.fn(),
        setColorFormat: vi.fn(),
        setSlotLayer: vi.fn(),
        getSlotLayer: vi.fn(() => null),
        updateDepthMap: vi.fn(),
        setSourceAutoExposure: vi.fn(),
        restoreNodeScales: vi.fn(),
        restoreRipples: vi.fn(),
        getNodeScales: vi.fn(() => ({})),
      });
    }
    // The lost backend is the ground truth for what each slot composited and which node was scaled.
    (first as unknown as { getSlotState: Mock }).getSlotState = vi.fn((i: number) =>
      i === 0
        ? { shaderId: 'rain', enabled: true, mode: 'parallel', layer: { ...screen, mask: { ...screen.mask } } }
        : { shaderId: null, enabled: false, mode: 'chained' });
    (first as unknown as { getNodeScales: Mock }).getNodeScales = vi.fn(() => ({ '0:tensor': 0.5 }));
    const { manager, statuses } = await bootWith(first);
    const depth = new Float32Array([0.1, 0.9, 0.5, 0.2]);
    manager.updateDepthMap(depth, 2, 2);
    depth.fill(0); // the manager keeps its own copy
    manager.setSourceAutoExposure(true);
    manager.addRipple(0.25, 0.75);
    (WebGPURenderer as Mock).mockImplementation(() => second);

    first.fatal!('lost', loss());
    await vi.waitFor(() => expect(statuses).toEqual(['lost', 'recovering', 'idle']));

    expect(second.setSlotLayer).toHaveBeenCalledWith(0, expect.objectContaining({ blend: 'screen', opacity: 0.5 }));
    const [data, width, height] = (second.updateDepthMap as Mock).mock.calls.at(-1)!;
    expect([...(data as Float32Array)].map((v) => Number(v.toFixed(2)))).toEqual([0.1, 0.9, 0.5, 0.2]);
    expect([width, height]).toEqual([2, 2]);
    expect(second.setSourceAutoExposure).toHaveBeenLastCalledWith(true);
    expect(second.restoreNodeScales).toHaveBeenCalledWith({ '0:tensor': 0.5 });
    const ripples = (second.restoreRipples as Mock).mock.calls.at(-1)![0] as Array<[number, number, number]>;
    expect(ripples).toHaveLength(1);
    expect(ripples[0]!.slice(0, 2)).toEqual([0.25, 0.75]);
    expect(ripples[0]![2]).toBeGreaterThanOrEqual(0);
    expect(manager.getSlotLayer(0)).toMatchObject({ output: 'blend', blend: 'screen' });
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
    (second.init as Mock).mockImplementation(() => new Promise<boolean>((r) => { finishInit = r; }));
    const { manager } = await bootWith(first);
    (WebGPURenderer as Mock).mockImplementation(() => second);
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
