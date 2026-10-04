/**
 * Render-worker protocol (#1314 WP-1): the contract between protocol lists,
 * the worker host's handler tables and the main-thread proxy, exercised over
 * an in-memory port pair with a fake renderer.
 */

import { createPortPair, flushPorts, FakePort } from '../testing/fakePorts';
import { setRendererErrorHandler } from '../ErrorHandling';
import type { RendererError } from '../ErrorHandling';
import {
  PROTOCOL_LISTS_ARE_EXHAUSTIVE,
  RENDER_COMMAND_TYPES,
  RENDER_RPC_TYPES,
  RenderEvent,
  RenderToWorker,
  transferablesOf,
} from './protocol';
import { createRenderWorkerHost, HostedRenderer, RenderWorkerHostDeps } from './renderWorkerHost';
import { createInputRingBuffer, InputRingWriter } from './inputRing';
import { connectRenderWorker } from './renderWorkerClient';
import { isCanvasTransferred, WorkerWebGPUBackend } from './WorkerWebGPUBackend';
import type { WebGpuProbeResult } from '../webgpuBootProbe';

const CONFIG = { width: 256, height: 256, agentCount: 0 };

function fakeRenderer() {
  const calls: Array<[string, unknown[]]> = [];
  const record = (name: string) => (...args: unknown[]) => {
    calls.push([name, args]);
    return undefined;
  };
  const r = {
    initialized: false,
    init: jest.fn(async () => {
      r.initialized = true;
      return true;
    }),
    destroy: jest.fn(async () => undefined),
    updateMouse: record('updateMouse'),
    setParam: record('setParam'),
    updateAudioData: record('updateAudioData'),
    updateAudioFrequencyBins: record('updateAudioFrequencyBins'),
    setSlotParams: record('setSlotParams'),
    addRipple: record('addRipple'),
    clearRipples: record('clearRipples'),
    setActiveShader: record('setActiveShader'),
    setSlotShader: record('setSlotShader'),
    setSlotEnabled: record('setSlotEnabled'),
    setSlotMode: record('setSlotMode'),
    getSlotState: () => ({ shaderId: null, enabled: false, mode: 'chained' as const }),
    setInputSource: record('setInputSource'),
    updateDepthMap: record('updateDepthMap'),
    setTransferredVideo: record('setTransferredVideo'),
    setResolutionScale: record('setResolutionScale'),
    setColorFormat: record('setColorFormat'),
    setMaxPassesPerFrame: record('setMaxPassesPerFrame'),
    setFramePassBudget: record('setFramePassBudget'),
    setNodeScale: (...args: unknown[]) => {
      calls.push(['setNodeScale', args]);
      return 0.5;
    },
    setAdaptiveQuality: record('setAdaptiveQuality'),
    setSourceAutoExposure: record('setSourceAutoExposure'),
    applyTestRenderState: record('applyTestRenderState'),
    setCanvasCopySrc: (...args: unknown[]) => {
      calls.push(['setCanvasCopySrc', args]);
      return true;
    },
    warmShaders: record('warmShaders'),
    loadShader: jest.fn(async (id: string) => id !== 'broken'),
    loadImageBitmap: jest.fn(async () => undefined),
    captureChoresThumbnailPng: jest.fn(async () => 'cG5n'),
    getFPS: () => 59,
    getGPUTimings: () => ({ parallelTime: 0, chainedTime: 1, totalTime: 2, available: true, timingSource: 'gpu-timestamp' as const }),
    getPassTimings: () => [{ key: '0:a', label: 'a', kind: 'compute' as const, slot: 0, scale: 1, gpuMs: 1, iterations: 1 }],
    getTimingInfo: () => ({ source: 'gpu-timestamp' as const, periodNs: 1, profiledPasses: 2, overflow: 0 }),
    getFrameStats: () => ({ submitsLastFrame: 1, bindGroupsLastFrame: 0, framesRendered: 10 }),
    getVideoIngestStats: () => ({ ingestPath: 'none' as const, framesIngested: 0, droppedFrames: 0, missedFrames: 0, queueDepth: 0 }),
    getNodeScales: () => ({}),
    getScalableNodes: () => [{ slot: 0, nodeId: 'tensor', minScale: 0.5, scale: 1 }],
    getLastGraphReport: () => null,
    getGpuChoresBreadcrumbs: () => ({}) as never,
    getPipelineCacheStats: () => ({ cachedCount: 1, cachedIds: ['warm-one'] }),
    getColorFormat: () => 'rgba16float' as const,
    getHistoryLayers: () => 4,
    getWorkingSizeCap: () => 1024,
    getResolutionScale: () => ({ scale: 1, full: { w: 256, h: 256 }, scaled: { w: 256, h: 256 }, pixelReduction: '0%' }),
    getFormatCapabilities: () => ({}) as never,
    getSupportsDeepWorkgroup: () => true,
    supportsCanvasCopySrc: () => true,
    getAdapterSummary: () => 'fake adapter',
    getAdapterAttemptLabel: () => 'HighPerformance',
    getSupportsSubgroups: () => true,
    setBeforeFrame: jest.fn(),
    getInputEcho: () => ({ mouse: [0.5, 0.5] as [number, number], mouseDown: false, audio: [0, 0, 0] as [number, number, number], slot0: [0.5, 0.5, 0.5, 0.5] }),
    grabPresentedFrame: jest.fn(async () => null),
    compileCheck: jest.fn(async (_id: string, code: string) =>
      code.includes('oops') ? [{ type: 'error' as const, lineNum: 1, linePos: 2, message: 'bad' }] : []),
  };
  return { r: r as unknown as HostedRenderer & { initialized: boolean }, calls, raw: r };
}

function probe(ok: boolean): WebGpuProbeResult {
  const device = { addEventListener: jest.fn() } as unknown as GPUDevice;
  return {
    ok,
    finishedAt: 'now',
    userAgent: 'test',
    userAgentBrands: [],
    attempts: [],
    ...(ok ? { handoff: { device } as never } : { lastError: 'no adapter', failedStage: 'requestAdapter' }),
  } as WebGpuProbeResult;
}

function setup(options: { probeOk?: boolean; post?: (e: RenderEvent) => void } = {}) {
  const [mainPort, workerPort] = createPortPair();
  const fake = fakeRenderer();
  let errorSink: ((e: RendererError) => void) | null = null;
  const deps: RenderWorkerHostDeps = {
    post: (event) => workerPort.postMessage(event),
    createRenderer: () => fake.r,
    runProbe: jest.fn(async () => probe(options.probeOk ?? true)),
    toBreadcrumb: (p) => {
      const { handoff: _h, ...rest } = p;
      return rest;
    },
    setErrorSink: (sink) => {
      errorSink = sink;
    },
    setFetchBase: jest.fn(),
    snapshotIntervalMs: 1_000_000,
  };
  const host = createRenderWorkerHost(deps);
  workerPort.addEventListener('message', (event) => host.handle(event.data as RenderToWorker));
  workerPort.postMessage({
    type: 'hello',
    caps: { gpu: true, offscreenWebgpu: true, raf: true, videoFrame: true, crossOriginIsolated: false, sharedArrayBuffer: false },
  });
  return { mainPort, workerPort, host, fake, deps, emitError: (e: RendererError) => errorSink?.(e) };
}

function fakeCanvas(): HTMLCanvasElement {
  const canvas = document.createElement('canvas');
  (canvas as unknown as { transferControlToOffscreen: () => OffscreenCanvas }).transferControlToOffscreen = () =>
    ({ width: 256, height: 256 }) as unknown as OffscreenCanvas;
  return canvas;
}

describe('render worker protocol contract', () => {
  it('the host handles exactly the listed commands and RPCs', () => {
    const { host } = setup();
    expect([...host.commandTypes].sort()).toEqual([...RENDER_COMMAND_TYPES].sort());
    expect([...host.rpcTypes].sort()).toEqual([...RENDER_RPC_TYPES].sort());
    expect(PROTOCOL_LISTS_ARE_EXHAUSTIVE).toEqual([true, true, true, true]);
  });

  it('moves canvases, frames, bitmaps and big arrays instead of copying them', () => {
    const canvas = {} as OffscreenCanvas;
    const bins = new Float32Array(128);
    expect(transferablesOf({ type: 'init', requestId: 1, canvas, config: CONFIG, colorOptIns: {}, appBaseUrl: '/' })).toEqual([canvas]);
    expect(transferablesOf({ type: 'frameInput', input: { bins } })).toEqual([bins.buffer]);
    expect(transferablesOf({ type: 'setSlotShader', index: 0, id: 'a' })).toEqual([]);
  });
});

describe('render worker host ↔ client', () => {
  it('handshakes, initializes through the worker probe, and answers RPCs', async () => {
    const { mainPort, fake, deps } = setup();
    const client = await connectRenderWorker(mainPort);
    expect(client.caps.offscreenWebgpu).toBe(true);
    const info = await client.rpc({ type: 'init', canvas: {} as OffscreenCanvas, config: CONFIG, colorOptIns: { displayP3: true }, appBaseUrl: 'http://app/' });
    expect(info).toMatchObject({ ok: true, adapterSummary: 'fake adapter', supportsDeepWorkgroup: true, canvasCopySrc: true });
    expect(deps.runProbe).toHaveBeenCalledWith(expect.anything(), 256, 256, { colorOptIns: { displayP3: true } });
    expect(deps.setFetchBase).toHaveBeenCalledWith('http://app/');
    expect(fake.raw.init).toHaveBeenCalled();
    expect(await client.rpc({ type: 'loadShader', id: 'ok', url: 'http://app/shaders/ok.wgsl' })).toBe(true);
    expect(await client.rpc({ type: 'loadShader', id: 'broken', url: 'x' })).toBe(false);
    expect(await client.rpc({ type: 'captureThumbnail', size: 64 })).toBe('cG5n');
    expect(await client.rpc({ type: 'dispose' })).toBe(true);
    expect(fake.raw.destroy).toHaveBeenCalled();
  });

  it('reports a failed probe without creating a renderer', async () => {
    const { mainPort, fake } = setup({ probeOk: false });
    const client = await connectRenderWorker(mainPort);
    const info = await client.rpc({ type: 'init', canvas: {} as OffscreenCanvas, config: CONFIG, colorOptIns: {}, appBaseUrl: '/' });
    expect(info).toMatchObject({ ok: false, lastInitError: 'no adapter', probe: { ok: false, failedStage: 'requestAdapter' } });
    expect(fake.raw.init).not.toHaveBeenCalled();
  });

  it('applies coalesced frame input in order (clear ripples before new ones)', async () => {
    const { mainPort, fake } = setup();
    const client = await connectRenderWorker(mainPort);
    await client.rpc({ type: 'init', canvas: {} as OffscreenCanvas, config: CONFIG, colorOptIns: {}, appBaseUrl: '/' });
    fake.calls.length = 0;
    client.send({
      type: 'frameInput',
      input: {
        mouse: [0.25, 0.75],
        mouseDown: true,
        slotParams: [[2, 0.1, 0.2, 0.3, 0.4]],
        clearRipples: true,
        ripples: [[0.5, 0.5]],
      },
    });
    await flushPorts();
    expect(fake.calls.map(([name]) => name)).toEqual(['updateMouse', 'setParam', 'setSlotParams', 'clearRipples', 'addRipple']);
    expect(fake.calls[2][1]).toEqual([2, 0.1, 0.2, 0.3, 0.4]);
  });

  it('drains the SAB input ring before every frame when the page shares memory', async () => {
    const { mainPort, fake } = setup();
    const client = await connectRenderWorker(mainPort);
    const ring = createInputRingBuffer();
    await client.rpc({ type: 'init', canvas: {} as OffscreenCanvas, config: CONFIG, colorOptIns: {}, appBaseUrl: '/', inputRing: ring });
    const hook = (fake.raw.setBeforeFrame as jest.Mock).mock.calls.at(-1)?.[0] as () => void;
    expect(typeof hook).toBe('function');
    const writer = new InputRingWriter(ring);
    writer.setMouse(0.1, 0.9);
    writer.setSlotParams(3, [0.2, 0.3, 0.4, 0.5]);
    writer.pushRipple(0.5, 0.5);
    fake.calls.length = 0;
    hook(); // what the renderer's frame loop does at frame start
    const names = fake.calls.map(([n]) => n);
    expect(names).toEqual(expect.arrayContaining(['updateMouse', 'setSlotParams', 'addRipple']));
    expect(fake.calls.find(([n]) => n === 'updateMouse')?.[1].map((v) => Number((v as number).toFixed(2)))).toEqual([0.1, 0.9]);
  });

  it('forwards worker-side reportError calls as events', async () => {
    const { mainPort, emitError } = setup();
    const client = await connectRenderWorker(mainPort);
    const events: RenderEvent[] = [];
    client.onEvent((e) => events.push(e));
    emitError({ type: 'gpu-validation', message: 'boom', recoverable: true });
    await flushPorts();
    expect(events).toContainEqual({ type: 'error', error: { type: 'gpu-validation', message: 'boom', recoverable: true } });
  });

  it('rejects the handshake when the worker never says hello', async () => {
    const [mainPort] = createPortPair();
    jest.useFakeTimers();
    const pending = connectRenderWorker(mainPort, 50);
    jest.advanceTimersByTime(60);
    jest.useRealTimers();
    await expect(pending).rejects.toThrow('did not say hello');
  });
});

describe('WorkerWebGPUBackend (main-thread proxy)', () => {
  async function backendWithWorker(probeOk = true) {
    const ctx = setup({ probeOk });
    const backend = new WorkerWebGPUBackend(CONFIG, () => connectRenderWorker(ctx.mainPort as FakePort));
    const canvas = fakeCanvas();
    const ok = await backend.init(canvas);
    return { ...ctx, backend, canvas, ok };
  }

  it('transfers the canvas, publishes the worker probe and reports itself as worker-backed', async () => {
    const { backend, canvas, ok } = await backendWithWorker();
    expect(ok).toBe(true);
    expect(backend.backendKind).toBe('webgpu');
    expect(backend.renderThread).toBe('worker');
    expect(isCanvasTransferred(canvas)).toBe(true);
    expect(window.webgpuProbe).toMatchObject({ ok: true, renderThread: 'worker' });
    expect(backend.getAdapterSummary()).toBe('fake adapter');
    await backend.destroy();
  });

  it('publishes the failure for the overlay when the worker probe fails', async () => {
    const { ok } = await backendWithWorker(false);
    expect(ok).toBe(false);
    expect(window.webgpuProbe).toMatchObject({ ok: false, lastError: 'no adapter', renderThread: 'worker' });
  });

  it('coalesces many input calls into one frameInput with the latest values', async () => {
    const { backend, fake } = await backendWithWorker();
    await flushPorts();
    fake.calls.length = 0;
    for (let i = 0; i < 20; i++) backend.updateMouse(i / 20, 0.5);
    backend.updateSlotParams({ zoomParam1: 0.9 }, 1);
    backend.updateSlotParams({ zoomParam2: 0.8 }, 1);
    backend.setParam('mouseDown', 1);
    backend.flush();
    await flushPorts();
    const mouseCalls = fake.calls.filter(([n]) => n === 'updateMouse');
    expect(mouseCalls).toEqual([['updateMouse', [19 / 20, 0.5]]]);
    expect(fake.calls.find(([n]) => n === 'setSlotParams')?.[1]).toEqual([1, 0.9, 0.8, 0.5, 0.5]);
    await backend.destroy();
  });

  it('serves synchronous getters from the optimistic shadow and the worker snapshot', async () => {
    const { backend } = await backendWithWorker();
    backend.setSlotShader(2, 'plasma');
    backend.setSlotMode(2, 'parallel');
    expect(backend.getSlotState(2)).toEqual({ shaderId: 'plasma', enabled: true, mode: 'parallel' });
    // Deliver a snapshot directly (the host's interval is effectively off here).
    (backend as unknown as { onEvent: (e: RenderEvent) => void }).onEvent({
      type: 'snapshot',
      snapshot: {
        initialized: true, fps: 42, gpuTimings: { parallelTime: 0, chainedTime: 0, totalTime: 3, available: true, timingSource: 'gpu-timestamp' },
        passTimings: [], timing: { source: 'gpu-timestamp', periodNs: 1, profiledPasses: 0, overflow: 0 },
        frameStats: { submitsLastFrame: 1, bindGroupsLastFrame: 0, framesRendered: 5 },
        video: { ingestPath: 'none', framesIngested: 0, droppedFrames: 0, missedFrames: 0, queueDepth: 0 },
        nodeScales: {}, scalableNodes: [{ slot: 0, nodeId: 'tensor', minScale: 0.5, scale: 1 }],
        slots: [], graphReport: null, chores: {} as never, cachedShaderIds: ['warm-one'],
        colorFormat: 'rgba16float', historyLayers: 4, workingSizeCap: 1024,
        resolution: { scale: 1, full: { w: 1, h: 1 }, scaled: { w: 1, h: 1 }, pixelReduction: '0%' },
        gpuErrors: ['oops'],
        inputChannel: 'postMessage',
        input: { mouse: [0.5, 0.5], mouseDown: false, audio: [0, 0, 0], slot0: [0.5, 0.5, 0.5, 0.5] },
      },
    });
    expect(backend.getFPS()).toBe(42);
    expect(backend.getGPUTimings().totalTime).toBe(3);
    expect(backend.getFrameStats().submitsLastFrame).toBe(1);
    expect(backend.isShaderCached('warm-one')).toBe(true);
    expect(backend.getColorFormat()).toBe('rgba16float');
    expect(backend.getGpuErrors()).toEqual(['oops']);
    expect(backend.setNodeScale(0, 'tensor', 0.3)).toBe(0.5);
    expect(backend.setNodeScale(0, 'not-scalable', 0.5)).toBe(1);
    await backend.destroy();
  });

  it('routes worker errors into the page error handler', async () => {
    const seen: RendererError[] = [];
    setRendererErrorHandler((e) => seen.push(e));
    const { emitError, backend } = await backendWithWorker();
    emitError({ type: 'shader-compile', message: 'bad wgsl', recoverable: true });
    await flushPorts();
    expect(seen).toContainEqual({ type: 'shader-compile', message: 'bad wgsl', recoverable: true });
    await backend.destroy();
  });
});
