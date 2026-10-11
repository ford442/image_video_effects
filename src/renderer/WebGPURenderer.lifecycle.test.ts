import { WebGPURenderer } from './WebGPURenderer';
import { DEFAULT_CONFIG } from './Renderer';
import { initializeWebGPUDevice } from './webgpu/device';
import { setRendererErrorHandler as setErrorSink } from './ErrorHandling';
import { createFrameState } from './webgpu/frame';
import {
  getDeviceGeneration,
  getRendererDevice,
  getRendererDeviceEntry,
  resetRendererDeviceRegistryForTests,
} from './deviceRegistry';

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

  describe('runtime device loss', () => {
    async function initialized() {
      // CRA's resetMocks clears the factory implementation; the loop needs a frame state.
      (createFrameState as jest.Mock).mockReturnValue({ maxPassesPerFrame: 12 });
      const device = makeDevice();
      (initializeWebGPUDevice as jest.Mock).mockResolvedValueOnce(outcomeFor(device));
      setupSpy.mockResolvedValueOnce('ok');
      const wgpu = createWebGpu();
      const detach = jest.spyOn(wgpu.gpuChores, 'detach');
      const fatal = jest.fn();
      wgpu.setFatalErrorHandler(fatal);
      expect(await wgpu.init(document.createElement('canvas'))).toBe(true);
      const loop = (wgpu as unknown as { frameRenderer: { stopRenderLoop: jest.Mock } }).frameRenderer;
      return { wgpu, device, fatal, detach, loop };
    }

    it('stops the loop, detaches chores and fires the fatal handler once with the loss', async () => {
      const { wgpu, device, fatal, detach, loop } = await initialized();
      device.loseUnexpectedly();
      await flush();
      expect((wgpu as unknown as { initialized: boolean }).initialized).toBe(false);
      expect(loop.stopRenderLoop).toHaveBeenCalled();
      expect(detach).toHaveBeenCalledWith('device lost');
      expect(fatal).toHaveBeenCalledTimes(1);
      expect(fatal.mock.calls[0][1]).toMatchObject({ kind: 'device-lost', reason: 'unknown', message: 'driver reset' });
      expect(wgpu.getLastDeviceLoss()).toMatchObject({ reason: 'unknown' });
      expect(wgpu.getGpuDevice()).toBeNull();
      expect(errors).toContainEqual(expect.objectContaining({ type: 'device-lost', recoverable: true }));

      // Teardown of the lost renderer settles at once and does not report again.
      await wgpu.destroy();
      expect(fatal).toHaveBeenCalledTimes(1);
    });

    it('an intentional destroy is not a loss', async () => {
      const { wgpu, fatal } = await initialized();
      await wgpu.destroy();
      await flush();
      expect(fatal).not.toHaveBeenCalled();
      expect(errors.filter((e) => e.type === 'device-lost')).toEqual([]);
    });

    it('simulateDeviceLoss destroys the live device but reports a runtime loss', async () => {
      const { wgpu, device, fatal } = await initialized();
      expect(wgpu.simulateDeviceLoss()).toBe(true);
      expect(device.destroy).toHaveBeenCalled();
      await flush();
      expect(fatal).toHaveBeenCalledTimes(1);
      expect(fatal.mock.calls[0][1]).toMatchObject({ reason: 'simulated' });
      expect(wgpu.simulateDeviceLoss()).toBe(false);
    });

    it('a loss while init is still allocating (OOM retry) does not fire the runtime handler', async () => {
      const first = makeDevice();
      const second = makeDevice();
      (initializeWebGPUDevice as jest.Mock)
        .mockResolvedValueOnce(outcomeFor(first))
        .mockResolvedValueOnce(outcomeFor(second));
      setupSpy.mockResolvedValueOnce('lost').mockResolvedValueOnce('ok');
      const wgpu = createWebGpu();
      const fatal = jest.fn();
      wgpu.setFatalErrorHandler(fatal);
      expect(await wgpu.init(document.createElement('canvas'))).toBe(true);
      await flush();
      expect(fatal).not.toHaveBeenCalled();
      expect(errors.filter((e) => e.type === 'device-lost')).toEqual([]);
    });
  });

  describe('device registry (#1395)', () => {
    beforeEach(() => resetRendererDeviceRegistryForTests());

    it('publishes the device it ended up with after an OOM retry, not the handoff', async () => {
      const handoffDevice = makeDevice();
      const retried = makeDevice();
      (initializeWebGPUDevice as jest.Mock)
        .mockResolvedValueOnce(outcomeFor(handoffDevice))
        .mockResolvedValueOnce(outcomeFor(retried));
      setupSpy.mockResolvedValueOnce('lost').mockResolvedValueOnce('ok');
      const wgpu = createWebGpu();
      expect(await wgpu.init(document.createElement('canvas'))).toBe(true);
      expect(getRendererDevice()).toBe(retried);
      expect(getRendererDeviceEntry().thread).toBe('main');
    });

    it('the OOM retry waits for the old device to be lost before probing again', async () => {
      const first = makeDevice();
      const second = makeDevice();
      let releaseLost!: () => void;
      (first.destroy as jest.Mock).mockImplementation(() => undefined);
      const order: string[] = [];
      (initializeWebGPUDevice as jest.Mock)
        .mockImplementationOnce(async () => outcomeFor(first))
        .mockImplementationOnce(async () => {
          order.push('probe-2');
          return outcomeFor(second);
        });
      Object.defineProperty(first, 'lost', {
        value: new Promise<GPUDeviceLostInfo>((r) => {
          releaseLost = () => {
            order.push('lost-1');
            r({ reason: 'destroyed', message: '' } as GPUDeviceLostInfo);
          };
        }),
      });
      setupSpy.mockResolvedValueOnce('lost').mockResolvedValueOnce('ok');
      const wgpu = createWebGpu();
      const init = wgpu.init(document.createElement('canvas'));
      await flush();
      expect(order).toEqual([]);
      releaseLost();
      expect(await init).toBe(true);
      expect(order).toEqual(['lost-1', 'probe-2']);
    });

    it('clears the registry on a runtime loss and on destroy, bumping the generation', async () => {
      const device = makeDevice();
      (initializeWebGPUDevice as jest.Mock).mockResolvedValueOnce(outcomeFor(device));
      setupSpy.mockResolvedValueOnce('ok');
      const wgpu = createWebGpu();
      await wgpu.init(document.createElement('canvas'));
      const published = getDeviceGeneration();
      device.loseUnexpectedly();
      await flush();
      expect(getRendererDevice()).toBeNull();
      expect(getRendererDeviceEntry().clearedBecause).toBe('device lost');
      expect(getDeviceGeneration()).toBe(published + 1);

      const next = makeDevice();
      (initializeWebGPUDevice as jest.Mock).mockResolvedValueOnce(outcomeFor(next));
      setupSpy.mockResolvedValueOnce('ok');
      const rebuilt = createWebGpu();
      await rebuilt.init(document.createElement('canvas'));
      expect(getRendererDevice()).toBe(next);
      // The old renderer's late teardown must not clear the new owner's device.
      await wgpu.destroy();
      expect(getRendererDevice()).toBe(next);
      await rebuilt.destroy();
      expect(getRendererDevice()).toBeNull();
    });
  });
});

