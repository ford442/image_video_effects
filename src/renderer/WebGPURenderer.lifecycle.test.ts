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
