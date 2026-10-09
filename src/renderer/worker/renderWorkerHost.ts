/**
 * renderWorkerHost.ts
 *
 * Worker-side half of the render-worker protocol (#1314 WP-1). Owns the real
 * WebGPURenderer (and so the only GPUDevice). It runs the boot probe against
 * the transferred OffscreenCanvas, applies commands, answers RPCs and posts a
 * state snapshot ~4×/s for the main thread's synchronous getters.
 *
 * Pure apart from its injected deps, so Jest drives it with a fake renderer.
 */

import type { RendererError } from '../ErrorHandling';
import { safeClose, TransferredVideoFrames } from '../media/videoFramePump';
import { InputRingReader, InputRingSnapshot } from './inputRing';
import type { RendererConfig } from '../Renderer';
import type { WebGPURenderer } from '../WebGPURenderer';
import type { WebGpuProbeOptions, WebGpuProbeResult, WebGpuProbeSerializable } from '../webgpuBootProbe';
import {
  FrameInput,
  RENDER_COMMAND_TYPES,
  RENDER_RPC_TYPES,
  RenderCommand,
  RenderEvent,
  RenderRpc,
  RenderRpcResults,
  RenderSnapshot,
  RenderToWorker,
  transferablesOf,
} from './protocol';

/** The slice of WebGPURenderer the host drives. */
export type HostedRenderer = Pick<
  WebGPURenderer,
  | 'init'
  | 'destroy'
  | 'initialized'
  | 'updateMouse'
  | 'setParam'
  | 'updateAudioData'
  | 'updateAudioFrequencyBins'
  | 'setSlotParams'
  | 'addRipple'
  | 'clearRipples'
  | 'setActiveShader'
  | 'setSlotShader'
  | 'setSlotEnabled'
  | 'setSlotMode'
  | 'getSlotState'
  | 'setInputSource'
  | 'updateDepthMap'
  | 'setTransferredVideo'
  | 'setResolutionScale'
  | 'setColorFormat'
  | 'setMaxPassesPerFrame'
  | 'setFramePassBudget'
  | 'setNodeScale'
  | 'setAdaptiveQuality'
  | 'setSourceAutoExposure'
  | 'applyTestRenderState'
  | 'setCanvasCopySrc'
  | 'warmShaders'
  | 'loadShader'
  | 'loadImageBitmap'
  | 'captureChoresThumbnailPng'
  | 'getFPS'
  | 'getGPUTimings'
  | 'getPassTimings'
  | 'getTimingInfo'
  | 'getFrameStats'
  | 'getVideoIngestStats'
  | 'getNodeScales'
  | 'getScalableNodes'
  | 'getLastGraphReport'
  | 'getGpuChoresBreadcrumbs'
  | 'getPipelineCacheStats'
  | 'getColorFormat'
  | 'getHistoryLayers'
  | 'getWorkingSizeCap'
  | 'getResolutionScale'
  | 'getFormatCapabilities'
  | 'getSupportsDeepWorkgroup'
  | 'supportsCanvasCopySrc'
  | 'getAdapterSummary'
  | 'getAdapterAttemptLabel'
  | 'getSupportsSubgroups'
  | 'grabPresentedFrame'
  | 'compileCheck'
  | 'benchmarkUncapped'
  | 'setBeforeFrame'
  | 'getInputEcho'
  | 'setFatalErrorHandler'
  | 'simulateDeviceLoss'
>;

export interface RenderWorkerHostDeps {
  post(event: RenderEvent, transfer?: Transferable[]): void;
  createRenderer(config: RendererConfig): HostedRenderer;
  runProbe(
    canvas: OffscreenCanvas,
    width: number,
    height: number,
    options: WebGpuProbeOptions,
  ): Promise<WebGpuProbeResult>;
  toBreadcrumb(probe: WebGpuProbeResult): WebGpuProbeSerializable;
  /** Route reportError() inside the worker back to the main thread. */
  setErrorSink(sink: (error: RendererError) => void): void;
  /** Anchor relative fetches (shaders, includes) at the app root. */
  setFetchBase(url: string): void;
  /** PNG-encode a presented frame (base64, no prefix); absent → captureFrame answers null. */
  encodeFramePng?(frame: VideoFrame): Promise<string | null>;
  snapshotIntervalMs?: number;
}

const SLOT_COUNT = 6;
const MAX_GPU_ERRORS = 16;

type CommandHandlers = { [K in RenderCommand['type']]: (msg: Extract<RenderCommand, { type: K }>) => void };
type RpcHandlers = {
  [K in RenderRpc['type']]: (msg: Extract<RenderRpc, { type: K }>) => Promise<RenderRpcResults[K]>;
};

export interface RenderWorkerHost {
  handle(message: RenderToWorker): void;
  /** Exposed for the contract test. */
  readonly commandTypes: string[];
  readonly rpcTypes: string[];
}

export function createRenderWorkerHost(deps: RenderWorkerHostDeps): RenderWorkerHost {
  let renderer: HostedRenderer | null = null;
  /** The renderer whose device was lost: no commands or RPCs reach it, only dispose. */
  let lostRenderer: HostedRenderer | null = null;
  let detachProbeErrorLog: (() => void) | null = null;
  let video: TransferredVideoFrames | null = null;
  let snapshotTimer: ReturnType<typeof setInterval> | null = null;
  let inputRing: InputRingReader | null = null;
  const gpuErrors: string[] = [];

  deps.setErrorSink((error) => deps.post({ type: 'error', error }));

  const applyFrameInput = (r: HostedRenderer, input: FrameInput) => {
    if (input.mouse) r.updateMouse(input.mouse[0], input.mouse[1]);
    if (input.mouseDown !== undefined) r.setParam('mouseDown', input.mouseDown ? 1 : 0);
    if (input.audio) r.updateAudioData(input.audio[0], input.audio[1], input.audio[2]);
    if (input.bins) r.updateAudioFrequencyBins(input.bins);
    for (const [slot, p1, p2, p3, p4] of input.slotParams ?? []) r.setSlotParams(slot, p1, p2, p3, p4);
    if (input.clearRipples) r.clearRipples();
    for (const [x, y] of input.ripples ?? []) r.addRipple(x, y);
    if (input.videoStats) video?.setUpstreamStats(input.videoStats);
  };

  const applyRing = (r: HostedRenderer, input: InputRingSnapshot) => {
    if (input.state) {
      r.updateMouse(input.state.mouse[0], input.state.mouse[1]);
      r.setParam('mouseDown', input.state.mouseDown ? 1 : 0);
      r.updateAudioData(input.state.audio[0], input.state.audio[1], input.state.audio[2]);
      r.updateAudioFrequencyBins(input.state.bins);
    }
    for (const [slot, p1, p2, p3, p4] of input.slotParams) r.setSlotParams(slot, p1, p2, p3, p4);
    if (input.clearRipples) r.clearRipples();
    for (const [x, y] of input.ripples) r.addRipple(x, y);
  };

  const snapshot = (r: HostedRenderer): RenderSnapshot => ({
    initialized: r.initialized,
    fps: r.getFPS(),
    gpuTimings: r.getGPUTimings(),
    passTimings: r.getPassTimings(),
    timing: r.getTimingInfo(),
    frameStats: r.getFrameStats(),
    video: r.getVideoIngestStats(),
    nodeScales: r.getNodeScales(),
    scalableNodes: r.getScalableNodes(),
    slots: Array.from({ length: SLOT_COUNT }, (_, i) => r.getSlotState(i)),
    graphReport: r.getLastGraphReport(),
    chores: r.getGpuChoresBreadcrumbs(),
    cachedShaderIds: r.getPipelineCacheStats().cachedIds,
    colorFormat: r.getColorFormat(),
    historyLayers: r.getHistoryLayers(),
    workingSizeCap: r.getWorkingSizeCap(),
    resolution: r.getResolutionScale(),
    gpuErrors: [...gpuErrors],
    inputChannel: inputRing ? 'sab' : 'postMessage',
    input: r.getInputEcho(),
  });

  const postSnapshot = () => {
    if (renderer) deps.post({ type: 'snapshot', snapshot: snapshot(renderer) });
  };

  const withRenderer = (fn: (r: HostedRenderer) => void) => {
    if (renderer) fn(renderer);
  };

  const stopSnapshots = () => {
    if (snapshotTimer !== null) clearInterval(snapshotTimer);
    snapshotTimer = null;
  };

  /**
   * A runtime device loss: one last snapshot (initialized:false), then `deviceLost`. The
   * page recovers on a new worker; this one only answers dispose from here on.
   */
  const onDeviceLost = (r: HostedRenderer, reason: string, message: string) => {
    if (renderer !== r) return;
    stopSnapshots();
    postSnapshot();
    renderer = null;
    lostRenderer = r;
    r.setBeforeFrame(null);
    video?.detach();
    video = null;
    deps.post({ type: 'deviceLost', reason, message });
  };

  const commands: CommandHandlers = {
    frameInput: ({ input }) => withRenderer((r) => applyFrameInput(r, input)),
    setActiveShader: ({ id }) => withRenderer((r) => r.setActiveShader(id)),
    setSlotShader: ({ index, id }) => withRenderer((r) => r.setSlotShader(index, id)),
    setSlotEnabled: ({ index, enabled }) => withRenderer((r) => r.setSlotEnabled(index, enabled)),
    setSlotMode: ({ index, mode }) => withRenderer((r) => r.setSlotMode(index, mode)),
    setInputSource: ({ source }) => withRenderer((r) => r.setInputSource(source)),
    updateDepthMap: ({ data, width, height }) => withRenderer((r) => r.updateDepthMap(data, width, height)),
    setVideoActive: ({ active }) => {
      if (active && !video) {
        video = new TransferredVideoFrames();
        renderer?.setTransferredVideo(video);
      } else if (!active && video) {
        renderer?.setTransferredVideo(null);
        video = null;
      }
    },
    videoFrame: ({ frame }) => {
      if (video && renderer) video.push(frame);
      else safeClose(frame);
    },
    setResolutionScale: ({ scale }) => withRenderer((r) => r.setResolutionScale(scale)),
    setColorFormat: ({ format }) => withRenderer((r) => r.setColorFormat(format)),
    setMaxPassesPerFrame: ({ cap }) => withRenderer((r) => r.setMaxPassesPerFrame(cap)),
    setFramePassBudget: ({ budget }) => withRenderer((r) => r.setFramePassBudget(budget)),
    setNodeScale: ({ slot, nodeId, scale }) => withRenderer((r) => {
      r.setNodeScale(slot, nodeId, scale);
    }),
    setAdaptiveQuality: ({ enabled, targetFps }) => withRenderer((r) => r.setAdaptiveQuality(enabled, targetFps)),
    setSourceAutoExposure: ({ enabled }) => withRenderer((r) => r.setSourceAutoExposure(enabled)),
    applyTestRenderState: ({ state }) => withRenderer((r) => r.applyTestRenderState(state)),
    setCanvasCopySrc: ({ enabled }) => withRenderer((r) => {
      r.setCanvasCopySrc(enabled);
    }),
    warmShaders: ({ entries }) => withRenderer((r) => r.warmShaders(entries)),
    simulateDeviceLoss: () => withRenderer((r) => {
      r.simulateDeviceLoss();
    }),
  };

  const rpcs: RpcHandlers = {
    init: async ({ canvas, config, colorOptIns, appBaseUrl, inputRing: ringBuffer }) => {
      // One renderer (one GPUDevice) per worker: recovery spawns a new worker.
      if (renderer || lostRenderer) throw new Error('render worker is already initialized');
      deps.setFetchBase(appBaseUrl);
      const probe = await deps.runProbe(canvas, config.width, config.height, { colorOptIns });
      const breadcrumb = deps.toBreadcrumb(probe);
      if (!probe.ok || !probe.handoff) {
        return { ok: false, probe: breadcrumb, lastInitError: probe.lastError ?? 'WebGPU boot probe failed' };
      }
      const device = probe.handoff.device;
      const logGpuError = (event: Event) => {
        const message = (event as GPUUncapturedErrorEvent).error?.message ?? 'GPU error';
        gpuErrors.push(message);
        if (gpuErrors.length > MAX_GPU_ERRORS) gpuErrors.shift();
      };
      device.addEventListener?.('uncapturederror', logGpuError);
      detachProbeErrorLog = () => device.removeEventListener?.('uncapturederror', logGpuError);
      const r = deps.createRenderer(config);
      const ok = await r.init(canvas, probe.handoff);
      if (!ok) {
        detachProbeErrorLog?.();
        detachProbeErrorLog = null;
        return { ok: false, probe: breadcrumb, lastInitError: 'WebGPU renderer init failed in the render worker' };
      }
      renderer = r;
      r.setFatalErrorHandler((message, info) => {
        if (info?.kind === 'device-lost') onDeviceLost(r, info.reason, info.message);
      });
      if (video) r.setTransferredVideo(video);
      if (ringBuffer) {
        const reader = new InputRingReader(ringBuffer);
        inputRing = reader;
        // Drained once per frame, right before the frame is encoded.
        r.setBeforeFrame(() => applyRing(r, reader.drain()));
      }
      snapshotTimer = setInterval(postSnapshot, deps.snapshotIntervalMs ?? 250);
      postSnapshot();
      return {
        ok: true,
        probe: breadcrumb,
        formatCapabilities: r.getFormatCapabilities(),
        supportsDeepWorkgroup: r.getSupportsDeepWorkgroup(),
        canvasCopySrc: r.supportsCanvasCopySrc(),
        adapterSummary: r.getAdapterSummary(),
        adapterAttemptLabel: r.getAdapterAttemptLabel(),
        supportsSubgroups: r.getSupportsSubgroups(),
      };
    },
    loadShader: async ({ id, url }) => (renderer ? renderer.loadShader(id, url) : false),
    loadImageBitmap: async ({ bitmap }) => {
      if (renderer) await renderer.loadImageBitmap(bitmap);
      bitmap.close();
      return true;
    },
    captureThumbnail: async ({ size }) => (renderer ? renderer.captureChoresThumbnailPng(size) : null),
    grabVideoFrame: async ({ timestampUs }) => (renderer ? renderer.grabPresentedFrame(timestampUs) : null),
    captureFrame: async () => {
      const frame = renderer ? await renderer.grabPresentedFrame(0) : null;
      if (!frame) return null;
      try {
        return deps.encodeFramePng ? await deps.encodeFramePng(frame) : null;
      } finally {
        safeClose(frame);
      }
    },
    compileCheck: async ({ id, code }) => {
      if (!renderer) throw new Error(lostRenderer ? 'render device lost' : 'render worker has no renderer');
      return renderer.compileCheck(id, code);
    },
    benchmarkUncapped: async ({ frames }) => (renderer ? renderer.benchmarkUncapped(frames) : null),
    dispose: async () => {
      stopSnapshots();
      const r = renderer ?? lostRenderer;
      renderer = null;
      lostRenderer = null;
      r?.setBeforeFrame(null);
      r?.setFatalErrorHandler(null);
      inputRing = null;
      video?.detach();
      video = null;
      detachProbeErrorLog?.();
      detachProbeErrorLog = null;
      if (r) await r.destroy();
      return true;
    },
  };

  const isRpc = (message: RenderToWorker): message is RenderRpc =>
    (RENDER_RPC_TYPES as readonly string[]).includes(message.type);

  const isVideoFrame = (value: unknown): value is VideoFrame =>
    typeof VideoFrame !== 'undefined' && value instanceof VideoFrame;

  const answer = (requestId: number, run: () => Promise<unknown>) => {
    run()
      .then((value) => deps.post(
        { type: 'rpcResult', requestId, ok: true, value },
        isVideoFrame(value) ? [value as unknown as Transferable] : undefined,
      ))
      .catch((e: unknown) =>
        deps.post({ type: 'rpcResult', requestId, ok: false, error: e instanceof Error ? e.message : String(e) }));
  };

  return {
    commandTypes: Object.keys(commands),
    rpcTypes: Object.keys(rpcs),
    handle(message) {
      if (isRpc(message)) {
        const handler = rpcs[message.type] as (m: RenderRpc) => Promise<unknown>;
        answer(message.requestId, () => handler(message));
        return;
      }
      const handler = commands[message.type] as ((m: RenderCommand) => void) | undefined;
      if (!handler) {
        // A message we do not know; drop transferables so frames/bitmaps are not leaked.
        for (const t of transferablesOf(message)) safeClose(t as unknown as { close(): void });
        return;
      }
      handler(message);
    },
  };
}

/** Exposed for the contract test: the protocol lists the host must cover. */
export const HOST_PROTOCOL = { commands: RENDER_COMMAND_TYPES, rpcs: RENDER_RPC_TYPES };
