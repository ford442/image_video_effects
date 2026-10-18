import type { Mock, MockInstance } from 'vitest';
import { WebGPURenderer } from './WebGPURenderer';
import { DEFAULT_CONFIG } from './Renderer';
import { createWorkerRenderer } from './worker/workerRenderer';
import { initializeWebGPUDevice } from './webgpu/device';
import { setRendererErrorHandler as setErrorSink } from './ErrorHandling';
import { createFrameState } from './webgpu/frame';
import type { WebGPUResourcePool } from './webgpu/resources';
import {
  getDeviceGeneration,
  getRendererDevice,
  getRendererDeviceEntry,
  resetRendererDeviceRegistryForTests,
} from './deviceRegistry';

vi.mock('./webgpu/device', async () => {
  const actual = await vi.importActual<Record<string, unknown>>('./webgpu/device');
  return { ...actual, initializeWebGPUDevice: vi.fn() };
});

vi.mock('./webgpu/frame', async () => {
  const actual = await vi.importActual<Record<string, unknown>>('./webgpu/frame');
  return {
    ...actual,
    createFrameState: vi.fn(() => ({ maxPassesPerFrame: 12 })),
    createRendererFrameHost: vi.fn(() => ({})),
    WebGPUFrameRenderer: class {
      startRenderLoop = vi.fn();
      stopRenderLoop = vi.fn();
    },
  };
});

// Jest has no WebGPU globals; the retry test runs the real buffer allocation.
(global as unknown as { GPUBufferUsage: Record<string, number> }).GPUBufferUsage = {
  UNIFORM: 0x40, COPY_DST: 0x08, STORAGE: 0x80,
};

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
    destroy: vi.fn(() => resolveLost({ reason: 'destroyed', message: '' } as GPUDeviceLostInfo)),
    loseUnexpectedly: () => resolveLost({ reason: 'unknown', message: 'driver reset' } as GPUDeviceLostInfo),
    addEventListener: vi.fn((type: string, fn: (ev: Event) => void) => {
      if (!listeners.has(type)) listeners.set(type, new Set());
      listeners.get(type)!.add(fn);
    }),
    removeEventListener: vi.fn((type: string, fn: (ev: Event) => void) => {
      listeners.get(type)?.delete(fn);
    }),
  };
  return device as unknown as FakeDevice;
}

function outcomeFor(device: GPUDevice, detachUncapturedLog?: () => void) {
  return {
    ok: true as const,
    device,
    context: { configure: vi.fn(), unconfigure: vi.fn() } as unknown as GPUCanvasContext,
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
  let setupSpy: MockInstance;
  const errors: Array<{ type: string; message: string }> = [];

  beforeEach(() => {
    vi.clearAllMocks();
    errors.length = 0;
    setErrorSink((e) => errors.push(e));
    setupSpy = vi.spyOn(
      WebGPURenderer.prototype as unknown as { setupGpuResources: () => Promise<string> },
      'setupGpuResources',
    );
    vi.spyOn(console, 'error').mockImplementation(() => undefined);
    vi.spyOn(console, 'log').mockImplementation(() => undefined);
  });

  afterEach(() => {
    setupSpy.mockRestore();
    vi.restoreAllMocks();
    setErrorSink((e) => console.error(e));
  });

  function createWebGpu(): WebGPURenderer {
    const wgpu = new WebGPURenderer(DEFAULT_CONFIG);
    vi.spyOn(wgpu.gpuChores, 'attach').mockImplementation(() => undefined as never);
    return wgpu;
  }

  it('reacts to a genuine device loss after an OOM retry', async () => {
    const first = makeDevice();
    const second = makeDevice();
    (initializeWebGPUDevice as Mock)
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
      (initializeWebGPUDevice as Mock).mockClear();
      (initializeWebGPUDevice as Mock).mockResolvedValueOnce(out);
      setupSpy.mockResolvedValueOnce('ok');
      const wgpu = createWebGpu();
      await wgpu.init(document.createElement('canvas'));
      return { wgpu, context: out.context as unknown as { configure: Mock } };
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

  it('gives the retry device fresh buffers and samplers instead of the destroyed ones', async () => {
    const withAllocators = (d: FakeDevice) => {
      const created = { buffers: [] as GPUBuffer[], samplers: [] as GPUSampler[] };
      Object.assign(d, {
        createBuffer: vi.fn(() => {
          const b = { destroy: vi.fn() } as unknown as GPUBuffer;
          created.buffers.push(b);
          return b;
        }),
        createSampler: vi.fn(() => {
          const sampler = {} as GPUSampler;
          created.samplers.push(sampler);
          return sampler;
        }),
      });
      return created;
    };
    const first = makeDevice();
    const second = makeDevice();
    const firstCreated = withAllocators(first);
    const secondCreated = withAllocators(second);
    (initializeWebGPUDevice as Mock)
      .mockResolvedValueOnce(outcomeFor(first))
      .mockResolvedValueOnce(outcomeFor(second));
    // Stand-in for setupGpuResources: only the part that touches the pool's buffers/samplers.
    setupSpy.mockImplementation(async function (this: WebGPURenderer) {
      const pool = (this as unknown as { resources: { ensureSamplersAndBuffers(d: GPUDevice): void } }).resources;
      pool.ensureSamplersAndBuffers((this as unknown as { device: GPUDevice }).device);
      return setupSpy.mock.calls.length === 1 ? 'lost' : 'ok';
    });

    const wgpu = createWebGpu();
    expect(await wgpu.init(document.createElement('canvas'))).toBe(true);

    expect(first.createBuffer).toHaveBeenCalledTimes(3);
    expect(first.createSampler).toHaveBeenCalledTimes(3);
    expect(second.createBuffer).toHaveBeenCalledTimes(3);
    expect(second.createSampler).toHaveBeenCalledTimes(3);
    firstCreated.buffers.forEach((b) => expect(b.destroy).toHaveBeenCalledTimes(1));

    const pool = (wgpu as unknown as { resources: WebGPUResourcePool }).resources;
    const live = [pool.uniformBuf, pool.extraBuf, pool.plasmaBuf];
    live.forEach((b) => {
      expect(secondCreated.buffers).toContain(b);
      expect(firstCreated.buffers).not.toContain(b);
    });
    [pool.filterSampler, pool.nearestSampler, pool.compSampler].forEach((sampler) => {
      expect(secondCreated.samplers).toContain(sampler);
      expect(firstCreated.samplers).not.toContain(sampler);
    });
  });

  describe('published device thread', () => {
    beforeEach(() => resetRendererDeviceRegistryForTests());

    async function initAndReadThread(renderer: WebGPURenderer) {
      vi.spyOn(renderer.gpuChores, 'attach').mockImplementation(() => undefined as never);
      (initializeWebGPUDevice as Mock).mockResolvedValueOnce(outcomeFor(makeDevice()));
      setupSpy.mockResolvedValueOnce('ok');
      expect(await renderer.init(document.createElement('canvas'))).toBe(true);
      return getRendererDeviceEntry().thread;
    }

    it("reports 'main' on the page by default", async () => {
      expect(await initAndReadThread(new WebGPURenderer(DEFAULT_CONFIG))).toBe('main');
    });

    it("reports 'worker' when the render worker hosts the renderer", async () => {
      expect(await initAndReadThread(createWorkerRenderer(DEFAULT_CONFIG))).toBe('worker');
    });
  });

  it('releases the device when init fails after acquiring it', async () => {
    const device = makeDevice();
    (initializeWebGPUDevice as Mock).mockResolvedValueOnce(outcomeFor(device));
    setupSpy.mockResolvedValueOnce('oom');

    const wgpu = createWebGpu();
    expect(await wgpu.init(document.createElement('canvas'))).toBe(false);
    expect(device.destroy).toHaveBeenCalled();
    expect(device.listeners.get('uncapturederror')?.size ?? 0).toBe(0);
  });

  it('destroy() resolves only after device.lost settles', async () => {
    const device = makeDevice();
    (initializeWebGPUDevice as Mock).mockResolvedValueOnce(outcomeFor(device));
    setupSpy.mockResolvedValueOnce('ok');
    const wgpu = createWebGpu();
    await wgpu.init(document.createElement('canvas'));

    let settled = false;
    (device.destroy as Mock).mockImplementation(() => undefined); // lost stays pending
    const done = wgpu.destroy().then(() => { settled = true; });
    await flush();
    expect(settled).toBe(false);

    (device as FakeDevice).loseUnexpectedly();
    await done;
    expect(settled).toBe(true);
  });

  it('replaces the probe log listener with one routed listener', async () => {
    const device = makeDevice();
    const detachUncapturedLog = vi.fn();
    (initializeWebGPUDevice as Mock).mockResolvedValueOnce(outcomeFor(device, detachUncapturedLog));
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
      (createFrameState as Mock).mockReturnValue({ maxPassesPerFrame: 12 });
      const device = makeDevice();
      (initializeWebGPUDevice as Mock).mockResolvedValueOnce(outcomeFor(device));
      setupSpy.mockResolvedValueOnce('ok');
      const wgpu = createWebGpu();
      const detach = vi.spyOn(wgpu.gpuChores, 'detach');
      const fatal = vi.fn();
      wgpu.setFatalErrorHandler(fatal);
      expect(await wgpu.init(document.createElement('canvas'))).toBe(true);
      const loop = (wgpu as unknown as { frameRenderer: { stopRenderLoop: Mock } }).frameRenderer;
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
      expect(fatal.mock.calls[0]![1]).toMatchObject({ kind: 'device-lost', reason: 'unknown', message: 'driver reset' });
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
      expect(fatal.mock.calls[0]![1]).toMatchObject({ reason: 'simulated' });
      expect(wgpu.simulateDeviceLoss()).toBe(false);
    });

    it('a loss while init is still allocating (OOM retry) does not fire the runtime handler', async () => {
      const first = makeDevice();
      const second = makeDevice();
      (initializeWebGPUDevice as Mock)
        .mockResolvedValueOnce(outcomeFor(first))
        .mockResolvedValueOnce(outcomeFor(second));
      setupSpy.mockResolvedValueOnce('lost').mockResolvedValueOnce('ok');
      const wgpu = createWebGpu();
      const fatal = vi.fn();
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
      (initializeWebGPUDevice as Mock)
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
      (first.destroy as Mock).mockImplementation(() => undefined);
      const order: string[] = [];
      (initializeWebGPUDevice as Mock)
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
      (initializeWebGPUDevice as Mock).mockResolvedValueOnce(outcomeFor(device));
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
      (initializeWebGPUDevice as Mock).mockResolvedValueOnce(outcomeFor(next));
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

