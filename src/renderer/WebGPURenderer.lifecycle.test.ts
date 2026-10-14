import { WebGPURenderer } from './WebGPURenderer';
import { DEFAULT_CONFIG } from './Renderer';
import { initializeWebGPUDevice } from './webgpu/device';
import { setRendererErrorHandler as setErrorSink } from './ErrorHandling';

jest.mock('./webgpu/device', () => {
  const actual = jest.requireActual('./webgpu/device');
  return { ...actual, initializeWebGPUDevice: jest.fn() };
});

jest.mock('./webgpu/frame', () => {
  const actual = jest.requireActual('./webgpu/frame');
  return {
    ...actual,
    createFrameState: jest.fn(() => ({ maxPassesPerFrame: 12 })),
    createRendererFrameHost: jest.fn(() => ({})),
    WebGPUFrameRenderer: class {
      startRenderLoop = jest.fn();
      stopRenderLoop = jest.fn();
    },
  };
});

type FakeDevice = GPUDevice & {
  loseUnexpectedly: () => void;
  listeners: Map<string, Set<(ev: Event) => void>>;
};

function makeDevice(): FakeDevice {
  let resolveLost!: (info: GPUDeviceLostInfo) => void;
  const lost = new Promise<GPUDeviceLostInfo>((r) => { resolveLost = r; });
  const listeners = new Map<string, Set<(ev: Event) => void>>();
  const device = {
    lost,
    listeners,
    destroy: jest.fn(() => resolveLost({ reason: 'destroyed', message: '' } as GPUDeviceLostInfo)),
    loseUnexpectedly: () => resolveLost({ reason: 'unknown', message: 'driver reset' } as GPUDeviceLostInfo),
    addEventListener: jest.fn((type: string, fn: (ev: Event) => void) => {
      if (!listeners.has(type)) listeners.set(type, new Set());
      listeners.get(type)!.add(fn);
    }),
    removeEventListener: jest.fn((type: string, fn: (ev: Event) => void) => {
      listeners.get(type)?.delete(fn);
    }),
  };
  return device as unknown as FakeDevice;
}

function outcomeFor(device: GPUDevice, detachUncapturedLog?: () => void) {
  return {
    ok: true as const,
    device,
    context: { configure: jest.fn(), unconfigure: jest.fn() } as unknown as GPUCanvasContext,
    canvasFormat: 'bgra8unorm' as GPUTextureFormat,
    canvasW: 1024,
    canvasH: 1024,
    supportsSubgroups: false,
    supportsDeepWorkgroup: false,
    hasF32Filterable: false,
    adapterGpuType: 'unknown' as const,
    formatCapabilities: {} as never,
    adapterSummary: 'test',
    adapterAttemptLabel: 'HighPerformance',
    canvasCopySrc: false,
    canvasColorOptIns: {},
    detachUncapturedLog,
  };
}

const flush = () => new Promise((r) => setTimeout(r, 0));

describe('WebGPURenderer lifecycle', () => {
  let setupSpy: jest.SpyInstance;
  const errors: Array<{ type: string; message: string }> = [];

  beforeEach(() => {
    jest.clearAllMocks();
    errors.length = 0;
    setErrorSink((e) => errors.push(e));
    setupSpy = jest.spyOn(
      WebGPURenderer.prototype as unknown as { setupGpuResources: () => Promise<string> },
      'setupGpuResources',
    );
    jest.spyOn(console, 'error').mockImplementation(() => undefined);
    jest.spyOn(console, 'log').mockImplementation(() => undefined);
  });

  afterEach(() => {
    setupSpy.mockRestore();
    jest.restoreAllMocks();
    setErrorSink((e) => console.error(e));
  });

  function createWebGpu(): WebGPURenderer {
    const wgpu = new WebGPURenderer(DEFAULT_CONFIG);
    jest.spyOn(wgpu.gpuChores, 'attach').mockImplementation(() => undefined as never);
    return wgpu;
  }

  it('reacts to a genuine device loss after an OOM retry', async () => {
    const first = makeDevice();
    const second = makeDevice();
    (initializeWebGPUDevice as jest.Mock)
      .mockResolvedValueOnce(outcomeFor(first))
      .mockResolvedValueOnce(outcomeFor(second));
    setupSpy.mockResolvedValueOnce('lost').mockResolvedValueOnce('ok');

    const wgpu = createWebGpu();
    expect(await wgpu.init(document.createElement('canvas'))).toBe(true);
    expect(first.destroy).toHaveBeenCalled();
    expect((wgpu as unknown as { initialized: boolean }).initialized).toBe(true);

    second.loseUnexpectedly();
    await flush();
    expect((wgpu as unknown as { initialized: boolean }).initialized).toBe(false);
    expect(errors.some((e) => e.type === 'device-lost')).toBe(true);
  });

  describe('setDisplayP3', () => {
    async function ready(copySrcSupported = false) {
      const device = makeDevice();
      const out = outcomeFor(device);
      (out as { canvasCopySrc: boolean }).canvasCopySrc = copySrcSupported;
      (initializeWebGPUDevice as jest.Mock).mockClear();
      (initializeWebGPUDevice as jest.Mock).mockResolvedValueOnce(out);
      setupSpy.mockResolvedValueOnce('ok');
      const wgpu = createWebGpu();
      await wgpu.init(document.createElement('canvas'));
      return { wgpu, context: out.context as unknown as { configure: jest.Mock } };
    }

    it('reconfigures the same context without requesting a second device', async () => {
      const { wgpu, context } = await ready();
      context.configure.mockClear();
      const r = await wgpu.setDisplayP3(true, false);
      expect(r.colorSpace).toBe('display-p3');
      expect(context.configure).toHaveBeenCalledWith(expect.objectContaining({ colorSpace: 'display-p3' }));
      expect(initializeWebGPUDevice).toHaveBeenCalledTimes(1);
      expect(wgpu.getCanvasColorState()).toMatchObject({ requestedDisplayP3: true, colorSpace: 'display-p3' });
    });

    it('retains the applied color through COPY_SRC capture reconfigures and back to sRGB', async () => {
      const { wgpu, context } = await ready(true);
      await wgpu.setDisplayP3(true, false);
      context.configure.mockClear();
      expect(wgpu.setCanvasCopySrc(true)).toBe(true);
      expect(context.configure).toHaveBeenLastCalledWith(
        expect.objectContaining({ colorSpace: 'display-p3', usage: 0x10 | 0x01 }),
      );
      // A toggle during capture is deferred: nothing is reconfigured.
      context.configure.mockClear();
      const deferred = await wgpu.setDisplayP3(false, false);
      expect(deferred.deferred).toBe(true);
      expect(context.configure).not.toHaveBeenCalled();
      expect(wgpu.getCanvasColorState().colorSpace).toBe('display-p3');
      wgpu.setCanvasCopySrc(false);
      const off = await wgpu.setDisplayP3(false, false);
      expect(off).toMatchObject({ colorSpace: 'srgb', toneMapping: 'standard' });
      expect(context.configure).toHaveBeenLastCalledWith(expect.not.objectContaining({ colorSpace: 'display-p3' }));
    });

    it('reports an sRGB fallback with a reason when the browser rejects display-p3', async () => {
      const { wgpu, context } = await ready();
      context.configure.mockImplementation((c: { colorSpace?: string }) => {
        if (c.colorSpace) throw new Error('rejected');
      });
      const r = await wgpu.setDisplayP3(true, true);
      expect(r).toMatchObject({ colorSpace: 'srgb', reason: 'unsupported-p3' });
      expect(wgpu.getCanvasColorState()).toMatchObject({
        requestedDisplayP3: true, colorSpace: 'srgb', fallbackReason: 'unsupported-p3',
      });
    });
  });

  it('releases the device when init fails after acquiring it', async () => {
    const device = makeDevice();
    (initializeWebGPUDevice as jest.Mock).mockResolvedValueOnce(outcomeFor(device));
    setupSpy.mockResolvedValueOnce('oom');

    const wgpu = createWebGpu();
    expect(await wgpu.init(document.createElement('canvas'))).toBe(false);
    expect(device.destroy).toHaveBeenCalled();
    expect(device.listeners.get('uncapturederror')?.size ?? 0).toBe(0);
  });

  it('destroy() resolves only after device.lost settles', async () => {
    const device = makeDevice();
    (initializeWebGPUDevice as jest.Mock).mockResolvedValueOnce(outcomeFor(device));
    setupSpy.mockResolvedValueOnce('ok');
    const wgpu = createWebGpu();
    await wgpu.init(document.createElement('canvas'));

    let settled = false;
    (device.destroy as jest.Mock).mockImplementation(() => undefined); // lost stays pending
    const done = wgpu.destroy().then(() => { settled = true; });
    await flush();
    expect(settled).toBe(false);

    (device as FakeDevice).loseUnexpectedly();
    await done;
    expect(settled).toBe(true);
  });

  it('replaces the probe log listener with one routed listener', async () => {
    const device = makeDevice();
    const detachUncapturedLog = jest.fn();
    (initializeWebGPUDevice as jest.Mock).mockResolvedValueOnce(outcomeFor(device, detachUncapturedLog));
    setupSpy.mockResolvedValueOnce('ok');
    const wgpu = createWebGpu();
    await wgpu.init(document.createElement('canvas'));

    expect(detachUncapturedLog).toHaveBeenCalledTimes(1);
    const listeners = device.listeners.get('uncapturederror')!;
    expect(listeners.size).toBe(1);

    const validation = { name: 'GPUValidationError', message: 'bad bind group' };
    const fire = () => listeners.forEach((fn) => fn({ error: validation } as unknown as Event));
    fire();
    fire();
    expect(errors.filter((e) => e.type === 'gpu-validation')).toHaveLength(1);

    await wgpu.destroy().catch(() => undefined);
    expect(device.listeners.get('uncapturederror')!.size).toBe(0);
  });
});
