/**
 * WorkerWebGPUBackend.ts
 *
 * Main-thread proxy for the TS WebGPU renderer running in the render worker
 * (#1314 WP-1). It has the same surface as WebGPURenderer (WebGPUBackendApi),
 * so RendererManager, hooks and App are unchanged.
 *
 *  - The canvas is transferred to the worker. The worker runs the boot probe
 *    and owns the GPUDevice; this side publishes the probe breadcrumb so the
 *    failure overlay still works.
 *  - Per-frame input (mouse, sliders, audio, ripples) is coalesced into one
 *    `frameInput` message per main-thread animation frame.
 *  - Video: a VideoFramePump on the page's <video> feeds frames that are
 *    transferred, never copied.
 *  - Images are decoded here and transferred as ImageBitmaps.
 *  - Synchronous getters read the latest worker snapshot (~4 Hz) or the
 *    optimistic local shadow (slots, params, input source).
 */

import { DEFAULT_FORMAT_CAPABILITIES, DeviceFormatCapabilities, InternalColorFormat } from '../../config/formatPolicy';
import { createDefaultBreadcrumbs } from '../../gpuChores/types';
import { reportError } from '../ErrorHandling';
import { VideoFramePump, VideoIngestStats } from '../media/videoFramePump';
import type { PassTiming } from '../passTimings';
import type { GPUTimings, RendererConfig, SlotZoomParamsUpdate } from '../Renderer';
import type { InputSource } from '../types';
import { createFrameStats, type FrameStats } from '../webgpu/deviceCounters';
import { resolveCanvasColorOptIns } from '../webgpu/device';
import { snapNodeScale } from '../webgpu/nodeScale';
import type { SlotMode } from '../webgpu/webgpuConstants';
import type { WebGPUBackendApi } from '../webgpuBackendApi';
import type { WebGpuProbeHandoff } from '../webgpuBootProbe';
import { publishWebGpuProbeBreadcrumb } from '../webgpuBootProbe';
import type { FrameInput, RenderEvent, RenderInitInfo, RenderSnapshot, TestRenderState } from './protocol';
import { connectRenderWorker, RenderWorkerClient } from './renderWorkerClient';

const SLOT_COUNT = 6;
const FFT_BINS = 128;

type SlotShadow = { shaderId: string | null; enabled: boolean; mode: SlotMode };

const WALL_CLOCK_TIMINGS: GPUTimings = {
  parallelTime: 0,
  chainedTime: 0,
  totalTime: 0,
  available: false,
  timingSource: 'wall-clock',
};

/** Canvases whose control moved to a render worker (unusable for other backends). */
const transferredCanvases = new WeakSet<HTMLCanvasElement>();

export function isCanvasTransferred(canvas: HTMLCanvasElement | null | undefined): boolean {
  return !!canvas && transferredCanvases.has(canvas);
}

async function spawnAndConnect(): Promise<RenderWorkerClient> {
  const { spawnRenderWorker } = await import('./renderWorkerSpawn');
  return connectRenderWorker(spawnRenderWorker());
}

/** A failure breadcrumb for problems before the worker could run the probe. */
function publishWorkerFailure(reason: string): void {
  publishWebGpuProbeBreadcrumb({
    ok: false,
    finishedAt: new Date().toISOString(),
    userAgent: typeof navigator !== 'undefined' ? navigator.userAgent : '',
    userAgentBrands: [],
    attempts: [],
    failedStage: 'requestAdapter',
    lastError: `render worker: ${reason}`,
    backend: 'webgpu',
    renderThread: 'worker',
  });
}

function scheduleOnMainFrame(cb: () => void): void {
  if (typeof requestAnimationFrame === 'function') requestAnimationFrame(cb);
  else setTimeout(cb, 16);
}

function absoluteUrl(url: string): string {
  try {
    return new URL(url, document.baseURI).href;
  } catch {
    return url;
  }
}

export class WorkerWebGPUBackend implements WebGPUBackendApi {
  readonly backendKind = 'webgpu' as const;
  readonly renderThread: 'main' | 'worker' = 'worker';
  initialized = false;

  private client: RenderWorkerClient | null = null;
  private unsubscribe: (() => void) | null = null;
  private info: RenderInitInfo | null = null;
  private snap: RenderSnapshot | null = null;

  private readonly slots: SlotShadow[] = Array.from({ length: SLOT_COUNT }, () => ({
    shaderId: null,
    enabled: false,
    mode: 'chained' as SlotMode,
  }));
  private readonly slotParams: number[][] = Array.from({ length: SLOT_COUNT }, () => [0.5, 0.5, 0.5, 0.5]);
  private readonly dirtySlots = new Set<number>();
  private pending: FrameInput = {};
  private flushScheduled = false;

  private inputSource: InputSource = 'image';
  private colorFormat: InternalColorFormat | null = null;
  private video: HTMLVideoElement | null = null;
  private pump: VideoFramePump | null = null;
  private cpuImage: HTMLImageElement | HTMLCanvasElement | null = null;
  private readonly cachedIds = new Set<string>();
  private readonly audio = { bass: 0, mid: 0, treble: 0, freqBins: new Float32Array(FFT_BINS) };

  constructor(
    private readonly config: RendererConfig,
    private readonly connect: () => Promise<RenderWorkerClient> = spawnAndConnect,
  ) {}

  /** Transfers `canvas` to the worker; it cannot be used for another backend afterwards. */
  async init(canvas: HTMLCanvasElement | OffscreenCanvas, _handoff?: WebGpuProbeHandoff): Promise<boolean> {
    if (typeof HTMLCanvasElement === 'undefined' || !(canvas instanceof HTMLCanvasElement)) return false;
    try {
      this.client = await this.connect();
    } catch (e) {
      console.warn('[RenderWorker] worker failed to start:', e);
      publishWorkerFailure(`failed to start (${e instanceof Error ? e.message : String(e)})`);
      return false;
    }
    const { caps } = this.client;
    if (!caps.gpu || !caps.offscreenWebgpu) {
      console.warn(`[RenderWorker] no WebGPU in the worker (gpu=${caps.gpu}, offscreen=${caps.offscreenWebgpu})`);
      publishWorkerFailure(`no WebGPU in the worker (gpu=${caps.gpu}, offscreenWebgpu=${caps.offscreenWebgpu})`);
      this.shutdownClient();
      return false;
    }

    let offscreen: OffscreenCanvas;
    try {
      offscreen = canvas.transferControlToOffscreen();
      transferredCanvases.add(canvas);
    } catch (e) {
      console.warn('[RenderWorker] transferControlToOffscreen failed:', e);
      publishWorkerFailure('transferControlToOffscreen failed');
      this.shutdownClient();
      return false;
    }

    this.unsubscribe = this.client.onEvent((event) => this.onEvent(event));
    try {
      this.info = await this.client.rpc({
        type: 'init',
        canvas: offscreen,
        config: this.config,
        colorOptIns: resolveCanvasColorOptIns(),
        appBaseUrl: absoluteUrl('.'),
      });
    } catch (e) {
      console.warn('[RenderWorker] init failed:', e);
      publishWorkerFailure(`init failed (${e instanceof Error ? e.message : String(e)})`);
      this.shutdownClient();
      return false;
    }
    publishWebGpuProbeBreadcrumb({ ...this.info.probe, renderThread: 'worker' });
    this.initialized = this.info.ok;
    if (!this.info.ok) {
      console.warn(`[RenderWorker] ${this.info.lastInitError ?? 'init failed'}`);
      this.shutdownClient();
      return false;
    }
    console.log('✅ TypeScript WebGPU renderer running in the render worker');
    return true;
  }

  async destroy(): Promise<void> {
    this.pump?.detach();
    this.pump = null;
    const client = this.client;
    if (client) {
      try {
        await client.rpc({ type: 'dispose' }, 5000);
      } catch {
        /* worker gone or slow: terminate anyway */
      }
    }
    this.shutdownClient();
    this.initialized = false;
  }

  releaseExclusiveGpu(): Promise<void> {
    return this.destroy();
  }

  private shutdownClient(): void {
    this.unsubscribe?.();
    this.unsubscribe = null;
    this.client?.terminate();
    this.client = null;
  }

  private onEvent(event: RenderEvent): void {
    if (event.type === 'snapshot') {
      this.snap = event.snapshot;
      this.initialized = event.snapshot.initialized;
      for (const id of event.snapshot.cachedShaderIds) this.cachedIds.add(id);
    } else if (event.type === 'error') {
      reportError(event.error);
    }
  }

  // ── Per-frame input: coalesced, one message per main animation frame ──────

  private markDirty(): void {
    if (this.flushScheduled) return;
    this.flushScheduled = true;
    scheduleOnMainFrame(() => this.flush());
  }

  /** Exposed for tests; normally runs on the next animation frame. */
  flush(): void {
    this.flushScheduled = false;
    const client = this.client;
    if (!client) return;
    const input = this.pending;
    this.pending = {};
    if (this.dirtySlots.size > 0) {
      input.slotParams = Array.from(this.dirtySlots, (slot) => {
        const p = this.slotParams[slot];
        return [slot, p[0], p[1], p[2], p[3]] as [number, number, number, number, number];
      });
      this.dirtySlots.clear();
    }
    const pump = this.pump;
    if (pump) {
      const frame = pump.takeLatest();
      if (frame) client.send({ type: 'videoFrame', frame });
      const stats = pump.getStats();
      input.videoStats = { missedFrames: stats.missedFrames, droppedFrames: stats.droppedFrames };
      // Keep forwarding frames while a video source is attached.
      this.markDirty();
    }
    if (Object.keys(input).length > 0) client.send({ type: 'frameInput', input });
  }

  updateMouse(x: number, y: number): void {
    this.pending.mouse = [x, y];
    this.markDirty();
  }

  setParam(name: string, value: number): void {
    switch (name) {
      case 'mouseDown':
        this.pending.mouseDown = value > 0;
        this.markDirty();
        break;
      case 'zoomParam1': this.updateSlotParams({ zoomParam1: value }, 0); break;
      case 'zoomParam2': this.updateSlotParams({ zoomParam2: value }, 0); break;
      case 'zoomParam3': this.updateSlotParams({ zoomParam3: value }, 0); break;
      case 'zoomParam4': this.updateSlotParams({ zoomParam4: value }, 0); break;
    }
  }

  updateAudioData(bass: number, mid: number, treble: number): void {
    this.audio.bass = bass;
    this.audio.mid = mid;
    this.audio.treble = treble;
    this.pending.audio = [bass, mid, treble];
    this.markDirty();
  }

  updateAudioFrequencyBins(bins: Float32Array): void {
    this.audio.freqBins.set(bins.subarray(0, FFT_BINS));
    // Copy: the caller reuses its array, and ours is transferred.
    this.pending.bins = bins.slice();
    this.markDirty();
  }

  setSlotParams(slotIndex: number, p1: number, p2: number, p3: number, p4: number): void {
    this.updateSlotParams({ zoomParam1: p1, zoomParam2: p2, zoomParam3: p3, zoomParam4: p4 }, slotIndex);
  }

  updateSlotParams(params: SlotZoomParamsUpdate, slotIndex = 0): void {
    const target = this.slotParams[slotIndex];
    if (!target) return;
    if (params.zoomParam1 !== undefined) target[0] = params.zoomParam1;
    if (params.zoomParam2 !== undefined) target[1] = params.zoomParam2;
    if (params.zoomParam3 !== undefined) target[2] = params.zoomParam3;
    if (params.zoomParam4 !== undefined) target[3] = params.zoomParam4;
    this.dirtySlots.add(slotIndex);
    this.markDirty();
  }

  addRipple(x: number, y: number): void {
    (this.pending.ripples ??= []).push([x, y]);
    this.markDirty();
  }

  clearRipples(): void {
    this.pending.clearRipples = true;
    this.pending.ripples = [];
    this.markDirty();
  }

  // ── Slots and shaders (optimistic shadow + command) ───────────────────────

  async loadShader(id: string, url: string): Promise<boolean> {
    if (!this.client) return false;
    const ok = await this.client.rpc({ type: 'loadShader', id, url: absoluteUrl(url) });
    if (ok) this.cachedIds.add(id);
    return ok;
  }

  preloadShader(id: string, url: string): Promise<boolean> {
    return this.loadShader(id, url);
  }

  isShaderCached(id: string): boolean {
    return this.cachedIds.has(id);
  }

  warmShaders(entries: Array<{ id: string; url: string }>): void {
    this.client?.send({
      type: 'warmShaders',
      entries: entries.map((e) => ({ id: e.id, url: absoluteUrl(e.url) })),
    });
  }

  setActiveShader(id: string): void {
    this.slots[0] = { shaderId: id, enabled: true, mode: 'chained' };
    for (let i = 1; i < SLOT_COUNT; i++) this.slots[i] = { shaderId: null, enabled: false, mode: 'chained' };
    this.client?.send({ type: 'setActiveShader', id });
  }

  setSlotShader(index: number, id: string): void {
    const slot = this.slots[index];
    if (!slot) return;
    this.slots[index] = { shaderId: id, enabled: !!id, mode: slot.mode };
    this.client?.send({ type: 'setSlotShader', index, id });
  }

  setSlotEnabled(index: number, enabled: boolean): void {
    if (this.slots[index]) this.slots[index].enabled = enabled;
    this.client?.send({ type: 'setSlotEnabled', index, enabled });
  }

  setSlotMode(index: number, mode: SlotMode): void {
    if (this.slots[index]) this.slots[index].mode = mode;
    this.client?.send({ type: 'setSlotMode', index, mode });
  }

  getSlotMode(index: number): SlotMode | null {
    return this.slots[index]?.mode ?? null;
  }

  getSlotState(index: number): SlotShadow | null {
    const slot = this.slots[index];
    return slot ? { ...slot } : null;
  }

  setInputSource(source: InputSource): void {
    this.inputSource = source;
    this.client?.send({ type: 'setInputSource', source });
  }

  getInputSource(): InputSource {
    return this.inputSource;
  }

  // ── Media ──────────────────────────────────────────────────────────────────

  /** Idempotent (called every rAF). The worker receives this element's frames. */
  setVideo(video: HTMLVideoElement | undefined): void {
    const next = video ?? null;
    if (this.video === next) return;
    this.pump?.detach();
    this.pump = null;
    this.video = next;
    const canPump =
      !!next &&
      !!this.client?.caps.videoFrame &&
      typeof VideoFrame !== 'undefined' &&
      typeof (next as HTMLVideoElement & { requestVideoFrameCallback?: unknown }).requestVideoFrameCallback === 'function';
    if (next && canPump) this.pump = new VideoFramePump(next);
    this.client?.send({ type: 'setVideoActive', active: !!this.pump });
    if (this.pump) this.markDirty();
  }

  /** The worker drives its own frame loop; nothing to do per main-thread rAF. */
  updateVideoFrame(): void {}

  async loadImage(url: string): Promise<string> {
    try {
      const img = new Image();
      img.crossOrigin = 'anonymous';
      img.src = url;
      await img.decode();
      this.cpuImage = img;
      await this.sendBitmap(await createImageBitmap(img));
      return url;
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown error';
      reportError({ type: 'media-load', message: `Failed to load image "${url}": ${message}`, recoverable: true });
      throw error;
    }
  }

  async loadImageFromElement(
    element: HTMLCanvasElement | HTMLImageElement,
  ): Promise<{ width: number; height: number } | null> {
    try {
      await this.sendBitmap(await createImageBitmap(element));
    } catch (e) {
      console.warn('[RenderWorker] loadImageFromElement failed:', e);
      return null;
    }
    this.cpuImage = element;
    return { width: this.config.width, height: this.config.height };
  }

  private async sendBitmap(bitmap: ImageBitmap): Promise<void> {
    if (!this.client) {
      bitmap.close();
      return;
    }
    await this.client.rpc({ type: 'loadImageBitmap', bitmap });
  }

  getCpuInputBitmap(): HTMLCanvasElement | HTMLImageElement | HTMLVideoElement | null {
    if (this.inputSource === 'generative') return null;
    if (this.inputSource === 'video' || this.inputSource === 'webcam' || this.inputSource === 'live') {
      return this.video ?? this.cpuImage;
    }
    return this.cpuImage ?? this.video;
  }

  updateDepthMap(data: Float32Array, width: number, height: number): void {
    this.client?.send({ type: 'updateDepthMap', data: data.slice(), width, height });
  }

  // ── Quality / performance (commands) ───────────────────────────────────────

  setResolutionScale(scale: number): void {
    this.client?.send({ type: 'setResolutionScale', scale });
  }

  setColorFormat(format: InternalColorFormat): void {
    this.colorFormat = format;
    this.client?.send({ type: 'setColorFormat', format });
  }

  setAdaptiveQuality(enabled: boolean, targetFPS = 60): void {
    this.client?.send({ type: 'setAdaptiveQuality', enabled, targetFps: targetFPS });
  }

  setMaxPassesPerFrame(cap: number): void {
    this.client?.send({ type: 'setMaxPassesPerFrame', cap });
  }

  setFramePassBudget(budget: number): void {
    this.client?.send({ type: 'setFramePassBudget', budget });
  }

  setNodeScale(slot: number, nodeId: string, scale: number): number {
    const node = this.getScalableNodes().find((n) => n.slot === slot && n.nodeId === nodeId);
    if (!node) return 1;
    this.client?.send({ type: 'setNodeScale', slot, nodeId, scale });
    return snapNodeScale(scale, node.minScale);
  }

  getNodeScales(): Record<string, number> {
    return { ...(this.snap?.nodeScales ?? {}) };
  }

  getScalableNodes(): RenderSnapshot['scalableNodes'] {
    return this.snap?.scalableNodes.map((n) => ({ ...n })) ?? [];
  }

  setSourceAutoExposure(enabled: boolean): void {
    this.client?.send({ type: 'setSourceAutoExposure', enabled });
  }

  applyTestRenderState(state: TestRenderState): void {
    this.flush();
    this.client?.send({ type: 'applyTestRenderState', state });
  }

  supportsCanvasCopySrc(): boolean {
    return !!this.info?.canvasCopySrc;
  }

  setCanvasCopySrc(enabled: boolean): boolean {
    if (enabled && !this.supportsCanvasCopySrc()) return false;
    this.client?.send({ type: 'setCanvasCopySrc', enabled });
    return true;
  }

  async captureChoresThumbnailPng(outSize: number): Promise<string | null> {
    if (!this.client) return null;
    return this.client.rpc({ type: 'captureThumbnail', size: outSize });
  }

  // ── Snapshot-backed getters ────────────────────────────────────────────────

  getFPS(): number {
    return this.snap?.fps ?? 0;
  }

  getGPUTimings(): GPUTimings {
    return this.snap?.gpuTimings ?? { ...WALL_CLOCK_TIMINGS };
  }

  getPassTimings(): PassTiming[] {
    return this.snap?.passTimings.map((p) => ({ ...p })) ?? [];
  }

  getTimingInfo(): RenderSnapshot['timing'] {
    return this.snap?.timing ?? { source: 'wall-clock', periodNs: 0, profiledPasses: 0, overflow: 0 };
  }

  getFrameStats(): FrameStats {
    return this.snap ? { ...this.snap.frameStats } : createFrameStats();
  }

  getVideoIngestStats(): VideoIngestStats {
    const worker = this.snap?.video;
    if (worker && this.pump) return { ...worker };
    return worker ?? { ingestPath: this.video ? 'element' : 'none', framesIngested: 0, droppedFrames: 0, missedFrames: 0, queueDepth: 0 };
  }

  getVideoStatus() {
    const v = this.video;
    if (!v) return null;
    return {
      hasVideo: true, playing: !v.paused, readyState: v.readyState,
      currentTime: v.currentTime, videoWidth: v.videoWidth, videoHeight: v.videoHeight,
      ...this.getVideoIngestStats(),
    };
  }

  getAudioData() {
    return { ...this.audio, freqBins: this.audio.freqBins.slice() };
  }

  getSupportsDeepWorkgroup(): boolean {
    return !!this.info?.supportsDeepWorkgroup;
  }

  getFormatCapabilities(): DeviceFormatCapabilities {
    return this.info?.formatCapabilities ?? DEFAULT_FORMAT_CAPABILITIES;
  }

  getColorFormat(): InternalColorFormat {
    return this.snap?.colorFormat ?? this.colorFormat ?? 'rgba32float';
  }

  getHistoryLayers(): number {
    return this.snap?.historyLayers ?? 0;
  }

  getWorkingSizeCap(): number {
    return this.snap?.workingSizeCap ?? 0;
  }

  getResolutionScale(): RenderSnapshot['resolution'] {
    return this.snap?.resolution ?? {
      scale: 1,
      full: { w: this.config.width, h: this.config.height },
      scaled: { w: this.config.width, h: this.config.height },
      pixelReduction: '0%',
    };
  }

  getAdapterSummary(): string {
    return this.info?.adapterSummary ?? '';
  }

  getAdapterAttemptLabel(): string | null {
    return this.info?.adapterAttemptLabel ?? null;
  }

  getLastGraphReport(): RenderSnapshot['graphReport'] {
    return this.snap?.graphReport ?? null;
  }

  getGpuChoresBreadcrumbs(): RenderSnapshot['chores'] {
    return this.snap?.chores ?? createDefaultBreadcrumbs();
  }

  /** Uncaptured GPU errors seen in the worker (newest last). */
  getGpuErrors(): string[] {
    return [...(this.snap?.gpuErrors ?? [])];
  }
}
