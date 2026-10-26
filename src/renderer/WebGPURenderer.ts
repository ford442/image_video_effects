/**
 * WebGPURenderer.ts
 *
 * Thin facade implementing IRenderer / ShaderSlotRenderer.
 * Delegates to webgpu/* modules (device, resources, pipeline, frame, audioDepth).
 */

import { Renderer, RendererConfig, ShaderSlotRenderer, GPUTimings, UncappedBenchResult, DeviceLossInfo } from './Renderer';
import { Ripple, MAX_RIPPLES } from './UniformBuffer';
import { PHYSICAL_SLOT_LIMIT, checkPhysicalSlotIndex } from './slotOrchestrator';
import { clearRendererDevice, publishRendererDevice, type RendererDeviceThread } from './deviceRegistry';
import {
  initializeWebGPUDevice,
  attachDeviceLostHandler,
  attachUncapturedErrorRouter,
  buildCanvasConfigureOptions,
  CORE_TIER2,
  isHdrCanvas,
  type CanvasColorOptInsState,
  type DeviceTier2,
} from './webgpu/device';
import { HdrPresent, StoragePresent, type HdrPresentSettings, type PresentVariant } from './webgpu/presentVariants';
import { WebGPUResourcePool } from './webgpu/resources';
import { WebGPUPipelineModule, createComputeBindGroup } from './webgpu/pipeline';
import {
  setupTimestampQueries,
  buildGPUTimings,
  destroyTimestampQueries,
  profilePass,
  createDisabledTimestampQueries,
  WebGPUTimestampQueries,
} from './webgpu/WebGPUTiming';
import {
  createAudioDepthState,
  updateAudioData,
  updateAudioFrequencyBins,
  updateDepthMap,
  getAudioData,
} from './webgpu/audioDepth';
import {
  WebGPUFrameRenderer,
  createFrameState,
  createRendererFrameHost,
  computeScaledDimensions,
  WebGPUFrameState,
  FrameContext,
} from './webgpu/frame';
import {
  createMediaInputState,
  updateVideoFrame as mediaUpdateVideoFrame,
  loadImage as mediaLoadImage,
  ingestDecodedImage,
  ensureOffscreen,
  uploadRGBA8,
  copyExternalToSource,
  releaseStill,
  clearSourceTexture,
  restoreSourceFromOffscreen,
  WebGPUMediaInputContext,
} from './webgpu/WebGPUMediaInput';
import { HISTORY_DEPTH, ShaderSlot, SlotMode, WG_SIZE_X, WG_SIZE_Y, WG_SIZE_1D } from './webgpu/webgpuConstants';
import type { InternalColorFormat } from '../config/formatPolicy';
import { DEFAULT_FORMAT_CAPABILITIES, DeviceFormatCapabilities, inferRequiresRgba32Float } from '../config/formatPolicy';
import { UNKNOWN_ADAPTER_IDENTITY, type AdapterIdentity } from '../config/adapterIdentity';
import { allowsFullWorkingSize, HISTORY_FULL_WORKING_SIZE, HISTORY_SAFE_WORKING_SIZE, persistHistoryOomCap } from '../config/vramBudget';
import { graphRunner } from './GraphRunner';
import { GpuChoresHost } from '../gpuChores';
import {
  negotiateCanvasColor,
  updateWebGpuProbeColor,
  type CanvasColorFallbackReason,
  type CanvasColorOptIns,
  type CanvasColorState,
  type DisplayP3Result,
  type WebGpuProbeHandoff,
} from './webgpuBootProbe';
import { allocateWorkingPool, rungsForRequest } from './webgpu/historyTexProbe';
import { declaresBindGroup1, SimRing } from './webgpu/simRing';
import { armSimRingFor } from './webgpu/simRingArm';
import { rewriteWgslStorageFormats } from './wgslFormatRewrite';
import { applyF16Variant } from './wgslF16';
import { resolveGraphForShader, resolveSimHashRequest, resolveSimRingRequest, getGraphEntryIds, resolveMultipassChain } from './multipassRegistry';
import { graphUsesSimRing, type MultipassGraphDef } from './multipassGraph';
import { setRuntimeGraph as setRuntimeGraphOverlay, type RuntimeSimRingRequest } from './runtimeGraphs';
import { instrumentDevice, type FrameStats } from './webgpu/deviceCounters';
import type { PassTiming } from './passTimings';
import { ShaderWarmupQueue, type WarmupEntry } from './webgpu/shaderWarmup';
import { NodeScaleIslands, nodeScaleKey, snapNodeScale } from './webgpu/nodeScale';
import type { FrameIslands } from './webgpu/framePlan';
import { IDLE_COMPOSITOR_STATS, outputComposites, type CompositorStats, type FrameCompositor } from './webgpu/compositor';
import type { SlotCompositor } from './webgpu/slotCompositor';
import { DEFAULT_SLOT_OUTPUT, normalizeSlotOutput, patchSlotOutput, type SlotOutput } from './slotOutput';
import type { TransferredVideoFrames, VideoIngestStats } from './media/videoFramePump';
import { VideoIngest } from './media/videoIngest';
import { compileCheckWgsl } from './webgpu/compileCheck';
import { registerShaderCompileService } from '../utils/shaderCompileService';

/** `?video_ingest=element` forces the pre-#1314 per-rAF element import (A/B, debugging). */
function videoFrameIngestDisabledByUrl(): boolean {
  try {
    const search = globalThis.location?.search ?? '';
    return new URLSearchParams(search).get('video_ingest') === 'element';
  } catch {
    return false;
  }
}

export interface WebGPURendererOptions {
  /** The thread the renderer runs on; defaults to 'main'. */
  thread?: RendererDeviceThread;
}

export class WebGPURenderer implements Renderer, ShaderSlotRenderer {
  /** Backend tag shared with the render-worker proxy (see webgpuBackendApi.ts). */
  readonly backendKind = 'webgpu' as const;
  /** This instance renders on the thread that owns it (the proxy reports 'worker'). */
  readonly renderThread: 'main' | 'worker' = 'main';
  private device: GPUDevice | null = null;
  private context: GPUCanvasContext | null = null;
  /** The live swapchain format (rgba16float for the HDR canvas, #1512). */
  private canvasFormat: GPUTextureFormat = 'bgra8unorm';
  /** getPreferredCanvasFormat() (or ?canvas_format=): what every SDR configure uses. */
  private preferredCanvasFormat: GPUTextureFormat = 'bgra8unorm';
  /** Boot probe accepted STORAGE_BINDING on the swapchain (bgra8unorm-storage, #1512). */
  private storagePresentSupported = false;
  private readonly hdrPresent = new HdrPresent();
  private readonly storagePresent = new StoragePresent(() => this.device);
  /** Test hook: read presented texels back from the next frame (needs a COPY_SRC canvas). */
  private texelProbe: { points: Array<[number, number]>; resolve: (texels: number[][] | null) => void } | null = null;
  private texelReadback: { buffer: GPUBuffer; format: GPUTextureFormat; count: number; resolve: (texels: number[][] | null) => void } | null = null;
  private canvasCopySrcSupported = false;
  private canvasCopySrcActive = false;
  private canvasColorOptIns: CanvasColorOptInsState = {};
  private canvasColorRequested = false;
  private canvasColorFallback: CanvasColorFallbackReason | undefined;

  readonly resources = new WebGPUResourcePool();
  readonly pipeline = new WebGPUPipelineModule();
  private readonly frameRenderer = new WebGPUFrameRenderer();
  private readonly audioDepth = createAudioDepthState();
  private readonly mediaState = createMediaInputState();

  private computeBindGroup!: GPUBindGroup;
  private blitReadTex!: GPUTexture;
  private lastBlitReadTex: GPUTexture | null = null;
  private lastBlitScaledW = 0;
  private lastBlitScaledH = 0;

  /** Per-slot zoom_params; slot objects hold these arrays by reference. */
  private slotZoomParams: number[][] = Array.from({ length: PHYSICAL_SLOT_LIMIT }, () => [0.5, 0.5, 0.5, 0.5]);

  /** Per-slot compositor output (#1512); survives shader changes like the params do. */
  private slotOutputs: SlotOutput[] = Array.from({ length: PHYSICAL_SLOT_LIMIT }, () => ({ ...DEFAULT_SLOT_OUTPUT }));

  private slots: ShaderSlot[] = Array.from({ length: PHYSICAL_SLOT_LIMIT }, (_, i) => ({
    shaderId: null, enabled: false, mode: 'chained' as SlotMode, params: this.slotZoomParams[i],
    output: this.slotOutputs[i],
  }));

  private currentTime = 0;
  private mouseX = 0.5;
  private mouseYShader = 0.5;
  private mouseDown = false;
  private zoomParams = [0.5, 0.5, 0.5, 0.5];
  private ripples: Ripple[] = [];

  private canvasW = 0;
  private canvasH = 0;
  private resolutionScale = 1.0;
  private scaledW = 0;
  private scaledH = 0;
  private workingSizeCap = HISTORY_SAFE_WORKING_SIZE;

  private supportsTimestampQuery = false;
  private timestampRuntime: WebGPUTimestampQueries = createDisabledTimestampQueries();
  private gpuTimings = this.timestampRuntime.gpuTimings;

  /** Read by diagnostics; written only by init / teardown / device loss. */
  initialized = false;
  private animationId: number | null = null;
  private startTime = 0;
  private frameCount = 0;
  private lastFPSTime = 0;
  private fps = 0;
  private targetFPS = 60;
  private adaptiveQuality = false;
  maxPassesPerFrame = 12;
  /** Frame-wide compute pass budget (render-quality passes × active slots). */
  framePassBudget = Number.POSITIVE_INFINITY;

  private inputSource: 'image' | 'video' | 'webcam' | 'generative' | 'live' = 'image';
  private supportsSubgroups = false;
  private supportsDeepWorkgroup = false;
  private colorFormat: InternalColorFormat = 'rgba32float';
  /** Adapter identity from the init ladder — surfaced in diagnostics for Tier B evidence. */
  private adapterSummary = '';
  private adapterAttemptLabel: string | null = null;
  private adapterIdentity: AdapterIdentity = UNKNOWN_ADAPTER_IDENTITY;
  private unregisterCompileService: (() => void) | null = null;
  private formatCapabilities = DEFAULT_FORMAT_CAPABILITIES;
  /** Capability tier 2 of the live device (#1512): feature level, granted features, limits tiers. */
  private tier2: DeviceTier2 = CORE_TIER2;
  private releasingDevice = false;
  private detachUncapturedErrors: (() => void) | null = null;
  /** Set by simulateDeviceLoss(): the next 'destroyed' of this device counts as a loss. */
  private simulatedLossDevice: GPUDevice | null = null;
  private fatalErrorHandler: ((message: string, info?: DeviceLossInfo) => void) | null = null;
  private lastDeviceLoss: DeviceLossInfo | null = null;

  readonly gpuChores = new GpuChoresHost();
  /** Opt-in @group(1) sim ring — armed only when a group-1 pipeline compiles. */
  readonly simRing = new SimRing();

  private frameState?: WebGPUFrameState;
  private warmup: ShaderWarmupQueue | null = null;
  /** Scratch resources for opt-in graph nodes running below full size. */
  private readonly islands = new NodeScaleIslands();
  /**
   * Layer compositor for parallel groups with blend / mask outputs (#1512). Its GPU side is
   * the lazy `compositor` chunk: null until the first group that composites has loaded it.
   */
  private compositor: SlotCompositor | null = null;
  private compositorLoad: Promise<void> | null = null;
  private compositorLoadError: string | null = null;
  /** Demoted opt-in graph nodes: `${slot}:${nodeId}` → scale (< 1). */
  private readonly nodeScales = new Map<string, number>();
  /** The canvas this renderer presents to (an OffscreenCanvas in the render worker). */
  private presentCanvas: HTMLCanvasElement | OffscreenCanvas | null = null;
  /** Pending "give me the next presented frame" requests (recording / capture). */
  private frameGrabs: Array<{ timestampUs: number; resolve: (frame: VideoFrame | null) => void }> = [];
  /** WebCodecs VideoFrame ingest (element path as fallback). */
  private readonly videoIngest = new VideoIngest(videoFrameIngestDisabledByUrl());

  /**
   * `thread` says which thread this renderer runs on, for the device registry.
   * Only the host knows (the render worker entry passes 'worker'); the page default is 'main'.
   */
  constructor(private config: RendererConfig, private readonly options: WebGPURendererOptions = {}) {
    this.pipeline.shaderManager.setBoundIdsProvider(() => this.boundShaderIds());
  }

  getSupportsDeepWorkgroup(): boolean { return this.supportsDeepWorkgroup; }
  getSupportsSubgroups(): boolean { return this.supportsSubgroups; }
  getColorFormat(): InternalColorFormat { return this.colorFormat; }
  getFormatCapabilities(): DeviceFormatCapabilities { return this.formatCapabilities; }
  getDeviceTier2(): DeviceTier2 { return { ...this.tier2, limitsTiers: [...this.tier2.limitsTiers] }; }
  getHistoryLayers(): number { return this.resources.historyLayers; }
  getWorkingSizeCap(): number { return this.workingSizeCap; }

  /** `canvas` is an OffscreenCanvas when this renderer runs inside the render worker. */
  async init(canvas: HTMLCanvasElement | OffscreenCanvas, webGpuHandoff?: WebGpuProbeHandoff): Promise<boolean> {
    if (this.initialized) return true;

    let handoff = webGpuHandoff;
    for (let attempt = 0; attempt < 2; attempt++) {
      // A previous attempt's teardown (OOM retry) set this; the new device must report loss.
      this.releasingDevice = false;
      const outcome = await initializeWebGPUDevice(
        canvas,
        this.config.width,
        this.config.height,
        handoff,
      );
      if (!outcome.ok) return false;

      this.device = outcome.device;
      this.presentCanvas = canvas;
      instrumentDevice(outcome.device);
      this.context = outcome.context;
      this.canvasFormat = outcome.canvasFormat;
      this.preferredCanvasFormat = outcome.preferredCanvasFormat ?? outcome.canvasFormat;
      this.storagePresentSupported = outcome.storagePresent ?? false;
      this.canvasCopySrcSupported = outcome.canvasCopySrc ?? false;
      this.canvasCopySrcActive = false;
      this.canvasColorOptIns = outcome.canvasColorOptIns ?? {};
      this.canvasColorRequested =
        !!outcome.canvasColorOptIns?.displayP3 || outcome.canvasColorFallback === 'unsupported-p3';
      this.canvasColorFallback = outcome.canvasColorFallback;
      this.canvasW = outcome.canvasW;
      this.canvasH = outcome.canvasH;
      this.supportsSubgroups = outcome.supportsSubgroups;
      this.supportsDeepWorkgroup = outcome.supportsDeepWorkgroup;
      this.formatCapabilities = outcome.formatCapabilities;
      this.adapterSummary = outcome.adapterSummary ?? '';
      this.adapterAttemptLabel = outcome.adapterAttemptLabel ?? null;
      this.adapterIdentity = outcome.adapterIdentity ?? UNKNOWN_ADAPTER_IDENTITY;
      this.tier2 = outcome.tier2 ?? CORE_TIER2;
      this.pipeline.shaderManager.setShaderF16(this.tier2.shaderF16);

      const device = outcome.device;
      attachDeviceLostHandler(device, outcome.context, (details) => {
        if (this.releasingDevice || this.device !== device) return;
        // Only a loss while rendering is a runtime stop; init failures report through init().
        const wasRendering = this.initialized;
        this.initialized = false;
        if (this.frameState) this.frameRenderer.stopRenderLoop(this.frameState);
        this.warmup?.stop();
        this.warmup = null;
        this.videoIngest.detach();
        this.resolveFrameGrabs(null);
        this.timestampRuntime.hasRealGpuTimings = false;
        this.timestampRuntime.readbackPending = false;
        this.gpuChores.detach('device lost');
        const info: DeviceLossInfo = { kind: 'device-lost', ...details, at: Date.now() };
        this.lastDeviceLoss = info;
        clearRendererDevice('device lost', this);
        if (wasRendering) this.fatalErrorHandler?.(`GPU device lost (${info.reason})`, info);
      }, {
        isSimulated: () => this.simulatedLossDevice === device,
      });

      outcome.detachUncapturedLog?.();
      this.bindOutOfMemoryHandler(device);
      this.updateScaledDimensions();
      const resourcesResult = await this.setupGpuResources(outcome.hasF32Filterable, this.colorFormat);
      if (resourcesResult !== 'ok') {
        if (resourcesResult === 'lost' && attempt === 0) {
          persistHistoryOomCap();
          this.workingSizeCap = HISTORY_SAFE_WORKING_SIZE;
          // The next requestDevice must not race the old device's release (backendLifecycle).
          await this.teardownGpuHandles(true);
          handoff = undefined;
          continue;
        }
        // Release the device so a failed init does not keep it (and its listeners) alive.
        await this.teardownGpuHandles(true);
        return false;
      }

      this.gpuChores.attach(outcome.device, 'no GPUDevice adopted', this.colorFormat);
      // The device this renderer actually ended up with (after any OOM retry), not the handoff.
      publishRendererDevice(outcome.device, { supportsSubgroups: this.supportsSubgroups, thread: this.options.thread ?? 'main', owner: this });
      // Dev tools (ShaderScanner) compile against this renderer's layout, not a bare module check.
      this.unregisterCompileService?.();
      this.unregisterCompileService = registerShaderCompileService({
        supportsSubgroups: this.supportsSubgroups,
        compile: (id, code) => this.compileCheck(id, code),
      });

      this.frameState = createFrameState(createRendererFrameHost(this.createFrameContext()));
      this.initialized = true;
      this.startTime = performance.now() / 1000;
      this.lastFPSTime = this.startTime;
      this.frameRenderer.startRenderLoop(this.frameState);

      console.log(
        `✅ TypeScript WebGPU renderer initialized (${this.canvasW}×${this.canvasH}` +
        `, work ${this.scaledW}²×hist${this.resources.historyLayers}` +
        `${outcome.hasF32Filterable ? ', float32-filterable' : ''}` +
        `${this.supportsSubgroups ? ', subgroups' : ''}` +
        `${this.supportsDeepWorkgroup ? ', deep-workgroup' : ''})` +
        (outcome.adapterAttemptLabel ? ` [${outcome.adapterAttemptLabel}]` : ''),
      );
      return true;
    }
    return false;
  }

  private bindOutOfMemoryHandler(device: GPUDevice): void {
    const onOom = () => {
      persistHistoryOomCap();
      this.workingSizeCap = HISTORY_SAFE_WORKING_SIZE;
      if (this.scaledW > HISTORY_SAFE_WORKING_SIZE) {
        console.warn('[WebGPU] GPUOutOfMemoryError — capping working size at 1024, not retrying 2048');
        this.updateScaledDimensions();
        if (this.device && this.initialized && this.scaledW <= HISTORY_SAFE_WORKING_SIZE) {
          this.resources.recreateScaleTextures(
            this.device, this.canvasW, this.canvasH, this.scaledW, this.scaledH,
            this.colorFormat, this.resources.historyLayers,
          );
          this.rebuildComputeBindGroup();
        }
      }
    };
    this.detachUncapturedErrors?.();
    this.detachUncapturedErrors = attachUncapturedErrorRouter(device, { onOom });
  }

  private rebuildComputeBindGroup(): void {
    if (!this.device) return;
    this.computeBindGroup = createComputeBindGroup(
      this.device,
      this.pipeline.bindGroupLayout,
      this.resources.getTextureSet(),
      this.resources.getBufferSet(),
      this.resources.getSamplerSet(),
    );
    this.blitReadTex = this.resources.blitReadTex;
    this.lastBlitReadTex = null;
  }

  private async setupGpuResources(
    hasF32Filt: boolean,
    colorFormat: InternalColorFormat,
  ): Promise<'ok' | 'lost' | 'oom'> {
    const d = this.device!;
    this.colorFormat = colorFormat;
    this.pipeline.setupComputeLayout(d, hasF32Filt, colorFormat);

    this.updateScaledDimensions();
    const requested = Math.max(this.scaledW, this.scaledH);
    let bootRungs = rungsForRequest(requested, this.workingSizeCap);
    if (bootRungs.length === 0) {
      const size = Math.max(1, Math.min(requested, this.workingSizeCap));
      bootRungs = [
        { size, layers: HISTORY_DEPTH },
        { size, layers: 4 },
        { size, layers: 1 },
      ];
    }
    let allocated: Awaited<ReturnType<typeof allocateWorkingPool>> | null = null;
    for (const rung of bootRungs) {
      const result = await allocateWorkingPool(
        d, this.canvasW, this.canvasH, rung.size, rung.layers, colorFormat,
      );
      if (result.deviceLost) {
        console.error('[WebGPU] working pool: device lost during OOM — will requestDevice at 1024');
        return 'lost';
      }
      if (result.ok && result.set) {
        allocated = result;
        console.log(`[WebGPU] working pool OK ${rung.size}²×hist${rung.layers} (${colorFormat})`);
        break;
      }
      console.warn(
        `[WebGPU] working pool OOM at ${rung.size}²×${rung.layers} — dropping (do not retry 2048)`,
      );
    }
    if (!allocated?.set) {
      console.error('[WebGPU] working pool failed at 1024');
      return 'oom';
    }

    this.scaledW = allocated.workingSize;
    this.scaledH = allocated.workingSize;
    this.resources.colorFormat = colorFormat;
    this.resources.applyTextureSet(allocated.set);
    this.resources.ensureSamplersAndBuffers(d);

    const gate = {
      maxBufferSize: d.limits?.maxBufferSize ?? 0,
      adapterGpuType: this.formatCapabilities.adapterGpuType,
      adapterSummary: this.adapterSummary,
      adapterIdentity: this.adapterIdentity,
      isFallbackAdapter:
        this.adapterIdentity.isFallbackAdapter
        || (this.adapterAttemptLabel ?? '').includes('forceFallback'),
    };
    if (allowsFullWorkingSize(gate)) {
      const upgraded = await this.tryUpgradeToFullWorkingSize(d, colorFormat, allocated.layers);
      if (upgraded === 'lost' || upgraded === 'oom') return upgraded;
    }

    this.rebuildComputeBindGroup();
    this.pipeline.setupBlitPipelines(d, this.canvasFormat, this.blitReadTex, colorFormat);
    this.lastBlitReadTex = this.blitReadTex;
    this.lastBlitScaledW = this.scaledW;
    this.lastBlitScaledH = this.scaledH;

    const timing = setupTimestampQueries(d);
    this.timestampRuntime = timing;
    this.supportsTimestampQuery = timing.supportsTimestampQuery;
    this.gpuTimings = timing.gpuTimings;
    return 'ok';
  }

  private async tryUpgradeToFullWorkingSize(
    device: GPUDevice,
    colorFormat: InternalColorFormat,
    bootLayers: number,
  ): Promise<'ok' | 'lost' | 'oom' | 'kept'> {
    const full = HISTORY_FULL_WORKING_SIZE;
    console.log(`[WebGPU] attempting ${full} working-pool upgrade (fat discrete adapter)`);
    this.resources.destroyWorkingTextures();
    const up = await allocateWorkingPool(
      device, this.canvasW, this.canvasH, full, bootLayers, colorFormat,
    );
    if (up.ok && up.set) {
      this.scaledW = full;
      this.scaledH = full;
      this.workingSizeCap = full;
      this.resources.applyTextureSet(up.set);
      console.log(`[WebGPU] working pool upgraded to ${full}²×hist${bootLayers}`);
      return 'ok';
    }
    persistHistoryOomCap();
    this.workingSizeCap = HISTORY_SAFE_WORKING_SIZE;
    console.warn('[WebGPU] 2048 upgrade OOM — staying at 1024, not retrying 2048');
    if (up.deviceLost) return 'lost';
    const restore = await allocateWorkingPool(
      device, this.canvasW, this.canvasH, HISTORY_SAFE_WORKING_SIZE, bootLayers, colorFormat,
    );
    if (restore.deviceLost) return 'lost';
    // Only an actual device loss forces a new device; a failed restore on a live device is plain OOM.
    if (!restore.ok || !restore.set) return 'oom';
    this.scaledW = HISTORY_SAFE_WORKING_SIZE;
    this.scaledH = HISTORY_SAFE_WORKING_SIZE;
    this.resources.applyTextureSet(restore.set);
    return 'kept';
  }

  private getMediaContext(): WebGPUMediaInputContext {
    return {
      device: this.device,
      sourceTex: this.resources.sourceTex,
      readTex: this.resources.readTex,
      canvasW: this.canvasW,
      canvasH: this.canvasH,
      colorFormat: this.colorFormat,
      filterSampler: this.resources.filterSampler,
      supportsExternalTexture: this.pipeline.supportsExternalTexture,
      videoCopyPipeline: this.pipeline.videoCopyPipeline,
      videoCopyBindGroupLayout: this.pipeline.videoCopyBindGroupLayout,
    };
  }

  /** Boot probe saw the swapchain accept RENDER_ATTACHMENT | COPY_SRC. */
  supportsCanvasCopySrc(): boolean {
    return this.canvasCopySrcSupported;
  }

  /**
   * Reconfigure the swapchain with (or without) COPY_SRC for GPU-encode capture,
   * keeping the applied color opt-ins. Returns false when the probe refused it.
   */
  setCanvasCopySrc(enabled: boolean): boolean {
    if (!this.device || !this.context) return false;
    if (enabled && !this.canvasCopySrcSupported) return false;
    if (this.canvasCopySrcActive === enabled) return true;
    try {
      this.context.configure(buildCanvasConfigureOptions(
        this.device, this.preferredCanvasFormat,
        { ...this.canvasColorOptIns, copySrc: enabled, storagePresent: this.storagePresentConfigured() },
      ));
      this.canvasCopySrcActive = enabled;
      return true;
    } catch (e) {
      console.warn('[WebGPU] canvas COPY_SRC reconfigure failed:', e);
      if (enabled) this.canvasCopySrcSupported = false;
      return false;
    }
  }

  /**
   * Live Display P3 toggle (Render quality → Display P3). Re-negotiates on the
   * existing device/context (no second device), preserving the COPY_SRC bit.
   * `isHdr` is evaluated by the page (a worker cannot see the media query).
   * Deferred, with nothing changed, while a GPU-encode capture holds COPY_SRC so
   * one recording never mixes color spaces.
   */
  async setDisplayP3(enabled: boolean, isHdr: boolean): Promise<DisplayP3Result> {
    const requested: CanvasColorOptIns = { displayP3: enabled, extendedToneMapping: enabled && isHdr };
    const current = (): DisplayP3Result => ({
      requested,
      applied: this.canvasColorOptIns,
      colorSpace: this.canvasColorOptIns.displayP3 ? 'display-p3' : 'srgb',
      toneMapping: this.canvasColorOptIns.extendedToneMapping ? 'extended' : 'standard',
      format: this.canvasFormat,
      ...(this.canvasColorFallback ? { reason: this.canvasColorFallback } : {}),
    });
    if (!this.device || !this.context) return { ...current(), deferred: true };
    if (this.canvasCopySrcActive) return { ...current(), deferred: true };
    const result = await negotiateCanvasColor(
      this.device, this.context, this.preferredCanvasFormat, requested,
      { copySrc: this.canvasCopySrcActive, storagePresent: this.storagePresentSupported },
    );
    this.canvasColorOptIns = result.applied;
    this.canvasColorRequested = enabled;
    this.canvasColorFallback = result.reason;
    const format = result.format ?? this.preferredCanvasFormat;
    if (format !== this.canvasFormat) {
      // HDR on / off swaps the swapchain format: the present pipelines follow it.
      this.canvasFormat = format;
      if (this.blitReadTex) this.pipeline.setupBlitPipelines(this.device, format, this.blitReadTex, this.colorFormat);
    }
    updateWebGpuProbeColor(result, this.storagePresentConfigured());
    return result;
  }

  getCanvasColorState(): CanvasColorState {
    return {
      requestedDisplayP3: this.canvasColorRequested,
      colorSpace: this.canvasColorOptIns.displayP3 ? 'display-p3' : 'srgb',
      toneMapping: this.canvasColorOptIns.extendedToneMapping ? 'extended' : 'standard',
      copySrc: this.canvasCopySrcActive,
      format: this.canvasFormat,
      storagePresent: this.storagePresentConfigured(),
      ...(this.canvasColorFallback ? { fallbackReason: this.canvasColorFallback } : {}),
    };
  }

  /** Probe summary: attempt, adapter identity, limits, features, formats; '' before init. */
  getAdapterSummary(): string {
    return this.adapterSummary;
  }

  /** Which rung of ADAPTER_ATTEMPT_LADDER produced the device, if any. */
  getAdapterAttemptLabel(): string | null {
    return this.adapterAttemptLabel;
  }

  /** Last Tier C graph run (truncated steps + validation errors). */
  getLastGraphReport() {
    return graphRunner.lastReport;
  }

  getGpuChoresBreadcrumbs() {
    return this.gpuChores.getBreadcrumbs();
  }

  encodePreFxChores(encoder: GPUCommandEncoder): void {
    this.gpuChores.setPhysicsPinned(this.hasPhysicsPinnedSlot());
    this.gpuChores.encodePreFx(
      encoder,
      this.resources.readTex,
      this.scaledW,
      this.scaledH,
      this.resources.writeTex,
      (label) => profilePass(this.timestampRuntime, { kind: 'chores', label }),
    );
  }

  setSourceAutoExposure(enabled: boolean): void {
    this.gpuChores.setSourceNormalizeEnabled(enabled);
  }

  /**
   * Cue crossfade: dissolve over `durationMs` from the picture last presented into whatever
   * the next frames render (the blit lives in webgpu/presentHold.ts). Call it with the
   * shader-stack change it covers. False when the picture cuts instead: duration 0,
   * nothing presented yet, or the hold could not be created.
   */
  startCrossfade(durationMs: number): boolean {
    if (!this.frameState || !this.initialized) return false;
    return this.frameRenderer.startCrossfade(this.frameState, durationMs);
  }

  async captureChoresThumbnailPng(outSize: number): Promise<string | null> {
    // The texture the last frame presented. resources.blitReadTex is always
    // readTex, which holds the *input* for a single chained slot (output → writeTex).
    const src = this.blitReadTex ?? this.resources.readTex;
    if (!src) return null;
    return this.gpuChores.captureDownsampledPng(src, this.scaledW, this.scaledH, outSize);
  }

  private hasPhysicsPinnedSlot(): boolean {
    return this.slots.some(
      (slot) => slot.enabled && !!slot.shaderId && inferRequiresRgba32Float({ id: slot.shaderId }),
    );
  }

  encodePostFxChores(encoder: GPUCommandEncoder): void {
    this.gpuChores.encodeReadback(encoder);
    // After the present: the swapchain texture holds this frame's picture.
    this.encodeTexelProbe(encoder);
  }

  afterFrameSubmitChores(): void {
    this.gpuChores.afterSubmit();
  }

  /** Submits / bind groups created per frame (instrumented device counters). */
  getFrameStats(): FrameStats {
    return this.frameRenderer.getFrameStats();
  }

  getGPUTimings(): GPUTimings {
    return buildGPUTimings(
      this.gpuTimings,
      this.supportsTimestampQuery,
      this.timestampRuntime.hasRealGpuTimings,
      this.timestampRuntime.passTimings,
    );
  }

  /** Smoothed per-pass GPU ms (empty until timestamps resolve). */
  getPassTimings(): PassTiming[] {
    const timing = this.timestampRuntime;
    return timing.hasRealGpuTimings ? timing.passTimings.map((p) => ({ ...p })) : [];
  }

  /** Timestamp source + query usage, for diagnostics. */
  getTimingInfo(): { source: 'gpu-timestamp' | 'wall-clock'; periodNs: number; profiledPasses: number; overflow: number } {
    const timing = this.timestampRuntime;
    return {
      source: this.supportsTimestampQuery && timing.hasRealGpuTimings ? 'gpu-timestamp' : 'wall-clock',
      periodNs: timing.timestampPeriodNs,
      profiledPasses: timing.passTimings.reduce((n, p) => n + p.iterations, 0),
      overflow: timing.lastOverflow,
    };
  }

  applyTestRenderState(state: {
    time?: number; mouseX?: number; mouseY?: number;
    bass?: number; mid?: number; treble?: number;
  }): void {
    if (state.time !== undefined) this.currentTime = state.time;
    if (state.mouseX !== undefined) this.mouseX = state.mouseX;
    if (state.mouseY !== undefined) this.mouseYShader = state.mouseY;
    if (state.bass !== undefined) updateAudioData(this.audioDepth, state.bass, state.mid ?? 0, state.treble ?? 0);
    this.frameRenderer.renderFrame(this.frameState!);
  }

  /**
   * Bench only (#1080): render `frames` frames back to back with the rAF loop
   * stopped, then time to onSubmittedWorkDone(). Vsync cannot cap the result.
   */
  async benchmarkUncapped(frames: number): Promise<UncappedBenchResult | null> {
    const state = this.frameState;
    const device = this.device;
    if (!device || !state?.initialized || frames <= 0) return null;
    this.frameRenderer.stopRenderLoop(state);
    try {
      await device.queue.onSubmittedWorkDone();
      const t0 = performance.now();
      for (let i = 0; i < frames; i++) {
        this.currentTime += 1 / 60;
        this.frameRenderer.renderFrame(state);
      }
      await device.queue.onSubmittedWorkDone();
      const wallMs = performance.now() - t0;
      return { frames, wallMs, msPerFrame: wallMs / frames };
    } finally {
      // Teardown during the run owns the loop from here.
      if (this.frameState === state && state.initialized) this.frameRenderer.startRenderLoop(state);
    }
  }

  async loadShader(id: string, url: string): Promise<boolean> {
    const ok = await this.pipeline.shaderManager.loadShader(
      this.device, this.pipeline.pipelineLayout, id, url,
    );
    if (ok && this.device && this.pipeline.shaderManager.usesSimRing(id)) {
      const armed = await armSimRingFor(
        this.device, this.pipeline, this.simRing, id, resolveSimRingRequest(id), resolveSimHashRequest(id),
      );
      if (!armed) {
        console.warn(`[WebGPU] "${id}" declares @group(1) but the sim ring could not be armed`);
        return false;
      }
    }
    return ok;
  }

  /** Re-arm sim-ring seeding when a slot switches to a group-1 shader. */
  private rearmSimRingFor(id: string | null): void {
    if (!id || !this.simRing.allocated) return;
    const graph = resolveGraphForShader(id);
    if (this.pipeline.shaderManager.usesSimRing(id) || (graph && graphUsesSimRing(graph))) {
      this.simRing.resetFrame();
    }
  }

  /** Requested scale for an opt-in node (frame-plan hook). */
  nodeScale(slot: number, nodeId: string): number {
    return this.nodeScales.get(nodeScaleKey(slot, nodeId)) ?? 1;
  }

  /** Island resources while any node is demoted; frees scratch otherwise. */
  getIslands(): FrameIslands | null {
    if (this.nodeScales.size === 0 || !this.device) {
      if (this.islands.allocatedScales().length > 0) this.islands.releaseLevels();
      return null;
    }
    this.islands.attach({
      device: this.device,
      colorFormat: this.colorFormat,
      bindGroupLayout: this.pipeline.bindGroupLayout,
      textures: this.resources.getTextureSet(),
      buffers: this.resources.getBufferSet(),
      samplers: this.resources.getSamplerSet(),
      scaledW: this.scaledW,
      scaledH: this.scaledH,
    });
    return this.islands;
  }

  /**
   * The compositor while an enabled parallel slot blends or masks (frame-plan hook);
   * frees its layer textures otherwise. Null also when its allocation failed.
   */
  getCompositor(): FrameCompositor | null {
    const wanted = this.slots.some(
      (slot) => slot.enabled && !!slot.shaderId && slot.mode === 'parallel' && outputComposites(slot.output),
    );
    if (!wanted || !this.device) {
      this.compositor?.releaseTextures();
      return null;
    }
    const compositor = this.compositor;
    if (!compositor) {
      this.loadCompositor();
      return null; // last-one-wins until the chunk is in
    }
    compositor.attach({
      device: this.device,
      colorFormat: this.colorFormat,
      scaledW: this.scaledW,
      scaledH: this.scaledH,
      depthTex: this.resources.depthRead,
    });
    return compositor.available ? compositor : null;
  }

  /** Fetch the compositor chunk once. A failed load keeps parallel groups on last-one-wins. */
  private loadCompositor(): void {
    this.compositorLoad ??= import(/* webpackChunkName: "compositor" */ './webgpu/slotCompositor').then(
      ({ SlotCompositor }) => {
        this.compositor = new SlotCompositor();
      },
      (e: unknown) => {
        this.compositorLoadError = `compositor chunk failed to load: ${e instanceof Error ? e.message : String(e)}`;
        console.warn(`[WebGPU] ${this.compositorLoadError}; parallel groups stay last-one-wins`);
      },
    );
  }

  /** Layer / mask memory, pass count and unresolved-mask warnings, for diagnostics. */
  getCompositorStats(): CompositorStats {
    if (this.compositor) return this.compositor.stats();
    return { ...IDLE_COMPOSITOR_STATS, warnings: [], error: this.compositorLoadError };
  }

  /** The swapchain carries STORAGE_BINDING and is bgra8unorm: the compute present runs. */
  private storagePresentConfigured(): boolean {
    return this.storagePresentSupported && !isHdrCanvas(this.canvasColorOptIns) && this.canvasFormat === 'bgra8unorm';
  }

  /** HDR present on the rgba16float canvas, the compute present on a bgra8unorm one, else null (frame-plan hook). */
  getPresentVariant(): PresentVariant | null {
    const device = this.device;
    if (!device) return null;
    if (isHdrCanvas(this.canvasColorOptIns) && this.canvasFormat === 'rgba16float') {
      return this.hdrPresent.get(device, this.pipeline.blitBindGroupLayout, this.canvasFormat);
    }
    return this.storagePresentConfigured() ? this.storagePresent.variant : null;
  }

  /** Paper white / peak of the HDR present (nits). Kept across HDR on / off. */
  setHdrPresent(settings: Partial<HdrPresentSettings>): HdrPresentSettings {
    return this.hdrPresent.setSettings(settings);
  }

  getHdrPresent(): HdrPresentSettings {
    return this.hdrPresent.getSettings();
  }

  /** Compute presents encoded so far (0 when the render-pass blit presents). */
  getStoragePresentCount(): number {
    return this.storagePresent.presents;
  }

  /**
   * Test hook (?testMode=1, page thread): the next presented frame's texels at normalized
   * `points`, as floats (RGBA). rgba16float canvases keep values above 1.0, which is how
   * the HDR present is checked without an HDR display. Needs setCanvasCopySrc(true).
   */
  readPresentedTexels(points: Array<[number, number]>): Promise<number[][] | null> {
    if (!this.initialized || !this.canvasCopySrcActive || this.texelProbe || points.length === 0) {
      return Promise.resolve(null);
    }
    return new Promise((resolve) => {
      this.texelProbe = { points, resolve };
    });
  }

  private encodeTexelProbe(encoder: GPUCommandEncoder): void {
    const probe = this.texelProbe;
    const device = this.device;
    if (!probe || !device || !this.context) return;
    this.texelProbe = null;
    let texture: GPUTexture;
    try {
      texture = this.context.getCurrentTexture();
    } catch {
      probe.resolve(null);
      return;
    }
    const buffer = device.createBuffer({
      label: 'presentedTexels',
      size: 256 * probe.points.length,
      usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ,
    });
    probe.points.forEach(([u, v], i) => {
      const x = Math.min(texture.width - 1, Math.max(0, Math.floor(u * texture.width)));
      const y = Math.min(texture.height - 1, Math.max(0, Math.floor(v * texture.height)));
      encoder.copyTextureToBuffer(
        { texture, origin: [x, y, 0] },
        { buffer, offset: i * 256, bytesPerRow: 256 },
        [1, 1, 1],
      );
    });
    this.texelReadback = { buffer, format: texture.format, count: probe.points.length, resolve: probe.resolve };
  }

  private resolveTexelReadback(): void {
    const readback = this.texelReadback;
    if (!readback) return;
    this.texelReadback = null;
    void readback.buffer.mapAsync(GPUMapMode.READ).then(() => {
      const bytes = new Uint8Array(readback.buffer.getMappedRange().slice(0));
      readback.buffer.unmap();
      readback.buffer.destroy();
      readback.resolve(Array.from({ length: readback.count }, (_, i) => decodeTexel(bytes, i * 256, readback.format)));
    }, () => {
      readback.buffer.destroy();
      readback.resolve(null);
    });
  }

  /** Opt-in graph nodes of the bound slots, with their floor and current scale. */
  getScalableNodes(): Array<{ slot: number; nodeId: string; minScale: number; scale: number }> {
    const nodes: Array<{ slot: number; nodeId: string; minScale: number; scale: number }> = [];
    this.slots.forEach((slot, index) => {
      if (!slot.enabled || !slot.shaderId) return;
      const graph = resolveGraphForShader(slot.shaderId);
      for (const node of graph?.nodes ?? []) {
        if (!node.scalable || node.dispatch === 'simState') continue;
        nodes.push({
          slot: index,
          nodeId: node.id,
          minScale: node.minScale ?? 0.5,
          scale: this.nodeScale(index, node.id),
        });
      }
    });
    return nodes;
  }

  /**
   * Register (or, with `null`, drop) a runtime Tier C graph under `id` (Graph Lab
   * draft; see runtimeGraphs.ts). Takes effect on the next frame's slot plan; the
   * sim-ring request takes effect when a group-1 entry next compiles (loadShader).
   */
  setRuntimeGraph(id: string, graph: MultipassGraphDef | null, simRing: RuntimeSimRingRequest | null = null): void {
    setRuntimeGraphOverlay(id, graph, simRing);
  }

  /**
   * Run one opt-in graph node below the working size (#1314). Ignored for
   * nodes that are not `scalable`; snapped to 0.25 steps above minScale;
   * 1 restores full size. Returns the scale that will be used.
   */
  setNodeScale(slot: number, nodeId: string, scale: number): number {
    const node = this.getScalableNodes().find((n) => n.slot === slot && n.nodeId === nodeId);
    if (!node) return 1;
    const snapped = snapNodeScale(scale, node.minScale);
    const key = nodeScaleKey(slot, nodeId);
    if (snapped >= 1) this.nodeScales.delete(key);
    else this.nodeScales.set(key, snapped);
    return snapped;
  }

  getNodeScales(): Record<string, number> {
    return Object.fromEntries(this.nodeScales);
  }

  private clearNodeScales(slot: number): void {
    for (const key of Array.from(this.nodeScales.keys())) {
      if (key.startsWith(`${slot}:`)) this.nodeScales.delete(key);
    }
  }

  setActiveShader(id: string): void {
    if (this.slots[0]?.shaderId !== id) this.rearmSimRingFor(id);
    for (let i = 0; i < PHYSICAL_SLOT_LIMIT; i++) this.clearNodeScales(i);
    this.slots[0] = {
      shaderId: id, enabled: true, mode: 'chained', params: this.slotZoomParams[0], output: this.slotOutputs[0],
    };
    for (let i = 1; i < PHYSICAL_SLOT_LIMIT; i++) {
      this.slots[i] = {
        shaderId: null, enabled: false, mode: 'chained', params: this.slotZoomParams[i], output: this.slotOutputs[i],
      };
    }
  }

  setSlotShader(index: number, id: string): void {
    if (!checkPhysicalSlotIndex('WebGPURenderer', index)) return;
    const mode = this.slots[index]?.mode ?? 'chained';
    if (this.slots[index]?.shaderId !== id) {
      this.rearmSimRingFor(id);
      this.clearNodeScales(index);
    }
    this.slots[index] = {
      shaderId: id, enabled: !!id, mode, params: this.slotZoomParams[index], output: this.slotOutputs[index],
    };
  }

  setSlotEnabled(index: number, enabled: boolean): void {
    if (index < 0 || index >= PHYSICAL_SLOT_LIMIT) return;
    const slot = this.slots[index];
    if (slot) slot.enabled = enabled;
  }

  setSlotMode(index: number, mode: SlotMode): void {
    if (index < 0 || index >= PHYSICAL_SLOT_LIMIT) return;
    const slot = this.slots[index];
    if (slot) slot.mode = mode;
  }

  getSlotMode(index: number): SlotMode | null {
    if (index < 0 || index >= PHYSICAL_SLOT_LIMIT) return null;
    return this.slots[index]?.mode ?? null;
  }

  getSlotState(index: number): { shaderId: string | null; enabled: boolean; mode: SlotMode; output: SlotOutput } | null {
    if (index < 0 || index >= PHYSICAL_SLOT_LIMIT) return null;
    const slot = this.slots[index];
    if (!slot) return null;
    return { shaderId: slot.shaderId, enabled: slot.enabled, mode: slot.mode, output: normalizeSlotOutput(slot.output) };
  }

  /**
   * Merge `patch` into slot `index`'s compositor output (blend mode, opacity, mask…).
   * Takes effect on the next frame; only parallel slots composite. Returns the result.
   */
  setSlotOutput(index: number, patch: Partial<SlotOutput>): SlotOutput | null {
    const target = this.slotOutputs[index];
    if (!checkPhysicalSlotIndex('WebGPURenderer', index) || !target) return null;
    // In place: the slot objects hold this output by reference, like their params.
    Object.assign(target, patchSlotOutput(target, patch));
    return { ...target };
  }

  getSlotOutput(index: number): SlotOutput | null {
    const output = this.slotOutputs[index];
    return output ? { ...output } : null;
  }

  addRipple(x: number, y: number): void {
    if (this.ripples.length >= MAX_RIPPLES) this.ripples.shift();
    this.ripples.push({ x, y, startTime: this.currentTime });
  }

  clearRipples(): void { this.ripples = []; }
  getFPS(): number { return this.fps; }
  getAudioData() { return getAudioData(this.audioDepth); }

  getVideoStatus() {
    const v = this.mediaState.video;
    if (!v) return null;
    return {
      hasVideo: true, playing: !v.paused, readyState: v.readyState,
      currentTime: v.currentTime, videoWidth: v.videoWidth, videoHeight: v.videoHeight,
      ...this.getVideoIngestStats(),
    };
  }

  isShaderCached(id: string): boolean { return this.pipeline.shaderManager.hasPipeline(id); }

  /**
   * Compile pipelines the user is likely to pick next (gallery viewport) in
   * idle time, so selecting one hits the cache. Compiles only: no slot binding
   * and no sim-ring allocation (that happens on a real load).
   */
  warmShaders(entries: WarmupEntry[]): void {
    if (!this.device || !this.initialized) return;
    if (!this.warmup) {
      this.warmup = new ShaderWarmupQueue({
        load: (e) =>
          this.pipeline.shaderManager.loadShader(this.device, this.pipeline.pipelineLayout, e.id, e.url),
        isCached: (id) => this.pipeline.shaderManager.hasPipeline(id),
        boundIds: () => this.boundShaderIds(),
        evict: (id) => this.pipeline.shaderManager.evict(id),
        // Graph roots pull in several entries + maybe a sim ring: load those for real only.
        canWarm: (id) => !resolveGraphForShader(id),
      });
    }
    this.warmup.request(entries);
  }

  private boundShaderIds(): Set<string> {
    const ids = new Set<string>();
    for (const slot of this.slots) {
      if (!slot.shaderId) continue;
      for (const step of resolveMultipassChain(slot.shaderId)) ids.add(step);
      for (const entry of getGraphEntryIds(slot.shaderId)) ids.add(entry);
    }
    return ids;
  }
  getPipelineCacheStats() { return this.pipeline.shaderManager.getCacheStats(); }
  async preloadShader(id: string, url: string): Promise<boolean> { return this.loadShader(id, url); }

  getWorkgroupConfig() {
    return {
      size2D: [WG_SIZE_X, WG_SIZE_Y] as [number, number],
      size1D: WG_SIZE_1D,
      invocationsPerGroup: WG_SIZE_X * WG_SIZE_Y,
      dispatch2D: {
        x: Math.ceil(this.canvasW / WG_SIZE_X),
        y: Math.ceil(this.canvasH / WG_SIZE_Y),
      },
    };
  }

  setResolutionScale(scale: number): void {
    const snapped = Math.round(Math.max(0.25, Math.min(1.0, scale)) * 8) / 8;
    if (this.resolutionScale === snapped) return;
    this.resolutionScale = snapped;
    this.updateScaledDimensions();
    if (this.device && this.initialized) {
      this.resources.recreateScaleTextures(
        this.device, this.canvasW, this.canvasH, this.scaledW, this.scaledH, this.colorFormat,
      );
      this.rebuildComputeBindGroup();
      // recreateScaleTextures destroys sourceTex/readTex. Re-upload the last
      // image/video frame so image-effect shaders don't go blank black after
      // adaptive quality changes scale. Generative mode intentionally stays clear.
      if (this.inputSource !== 'generative') {
        restoreSourceFromOffscreen(this.getMediaContext(), this.mediaState);
      }
    }
  }

  setColorFormat(format: InternalColorFormat): void {
    if (this.colorFormat === format) return;
    this.colorFormat = format;
    this.gpuChores.setColorFormat(format);
    if (!this.device || !this.initialized) return;

    this.pipeline.setColorFormat(this.device, format);
    this.resources.recreateScaleTextures(
      this.device, this.canvasW, this.canvasH, this.scaledW, this.scaledH, format,
    );
    this.rebuildComputeBindGroup();
    if (this.inputSource !== 'generative') {
      restoreSourceFromOffscreen(this.getMediaContext(), this.mediaState);
    }
  }

  getResolutionScale() {
    const fullPixels = this.canvasW * this.canvasH;
    const scaledPixels = this.scaledW * this.scaledH;
    return {
      scale: this.resolutionScale,
      full: { w: this.canvasW, h: this.canvasH },
      scaled: { w: this.scaledW, h: this.scaledH },
      pixelReduction: `${Math.round((1 - scaledPixels / fullPixels) * 100)}%`,
    };
  }

  setAdaptiveQuality(enabled: boolean, targetFPS = 60): void {
    this.adaptiveQuality = enabled;
    this.targetFPS = targetFPS;
  }

  private updateScaledDimensions(): void {
    const dims = computeScaledDimensions(this.canvasW, this.canvasH, this.resolutionScale);
    const cap = this.workingSizeCap;
    this.scaledW = Math.min(dims.scaledW, cap);
    this.scaledH = Math.min(dims.scaledH, cap);
  }

  /**
   * The frame loop's view of this renderer (#1395): explicit accessors instead of
   * casting `this`, so the compiler checks every field the frame code reads or writes.
   */
  private createFrameContext(): FrameContext {
    // eslint-disable-next-line @typescript-eslint/no-this-alias
    const r = this;
    return {
      get resources() { return r.resources; },
      get pipeline() { return r.pipeline; },
      get simRing() { return r.simRing; },
      get computeBindGroup() { return r.computeBindGroup; },
      get audioDepth() { return r.audioDepth; },
      get mediaVideo() { return r.mediaVideo; },
      get device() { return r.device; },
      set device(v) { r.device = v; },
      get context() { return r.context; },
      set context(v) { r.context = v; },
      get initialized() { return r.initialized; },
      set initialized(v) { r.initialized = v; },
      get startTime() { return r.startTime; },
      set startTime(v) { r.startTime = v; },
      get currentTime() { return r.currentTime; },
      set currentTime(v) { r.currentTime = v; },
      get animationId() { return r.animationId; },
      set animationId(v) { r.animationId = v; },
      get blitReadTex() { return r.blitReadTex; },
      set blitReadTex(v) { r.blitReadTex = v; },
      get canvasW() { return r.canvasW; },
      set canvasW(v) { r.canvasW = v; },
      get canvasH() { return r.canvasH; },
      set canvasH(v) { r.canvasH = v; },
      get scaledW() { return r.scaledW; },
      set scaledW(v) { r.scaledW = v; },
      get scaledH() { return r.scaledH; },
      set scaledH(v) { r.scaledH = v; },
      get resolutionScale() { return r.resolutionScale; },
      set resolutionScale(v) { r.resolutionScale = v; },
      get slots() { return r.slots; },
      set slots(v) { r.slots = v; },
      get ripples() { return r.ripples; },
      set ripples(v) { r.ripples = v; },
      get mouseX() { return r.mouseX; },
      set mouseX(v) { r.mouseX = v; },
      get mouseYShader() { return r.mouseYShader; },
      set mouseYShader(v) { r.mouseYShader = v; },
      get mouseDown() { return r.mouseDown; },
      set mouseDown(v) { r.mouseDown = v; },
      get zoomParams() { return r.zoomParams; },
      set zoomParams(v) { r.zoomParams = v; },
      get inputSource() { return r.inputSource; },
      set inputSource(v) { r.inputSource = v; },
      get frameCount() { return r.frameCount; },
      set frameCount(v) { r.frameCount = v; },
      get lastFPSTime() { return r.lastFPSTime; },
      set lastFPSTime(v) { r.lastFPSTime = v; },
      get fps() { return r.fps; },
      set fps(v) { r.fps = v; },
      get adaptiveQuality() { return r.adaptiveQuality; },
      set adaptiveQuality(v) { r.adaptiveQuality = v; },
      get targetFPS() { return r.targetFPS; },
      set targetFPS(v) { r.targetFPS = v; },
      get lastBlitReadTex() { return r.lastBlitReadTex; },
      set lastBlitReadTex(v) { r.lastBlitReadTex = v; },
      get lastBlitScaledW() { return r.lastBlitScaledW; },
      set lastBlitScaledW(v) { r.lastBlitScaledW = v; },
      get lastBlitScaledH() { return r.lastBlitScaledH; },
      set lastBlitScaledH(v) { r.lastBlitScaledH = v; },
      get supportsTimestampQuery() { return r.supportsTimestampQuery; },
      set supportsTimestampQuery(v) { r.supportsTimestampQuery = v; },
      get gpuTimings() { return r.gpuTimings; },
      set gpuTimings(v) { r.gpuTimings = v; },
      get timestampRuntime() { return r.timestampRuntime; },
      set timestampRuntime(v) { r.timestampRuntime = v; },
      get maxPassesPerFrame() { return r.maxPassesPerFrame; },
      set maxPassesPerFrame(v) { r.maxPassesPerFrame = v; },
      get framePassBudget() { return r.framePassBudget; },
      set framePassBudget(v) { r.framePassBudget = v; },
      encodeVideoFrame: r.encodeVideoFrame.bind(r),
      adaptQualityIfNeeded: r.adaptQualityIfNeeded.bind(r),
      nodeScale: r.nodeScale.bind(r),
      getIslands: r.getIslands.bind(r),
      getCompositor: r.getCompositor.bind(r),
      getPresentVariant: r.getPresentVariant.bind(r),
      encodePreFxChores: r.encodePreFxChores.bind(r),
      encodePostFxChores: r.encodePostFxChores.bind(r),
      afterFrameSubmitChores: r.afterFrameSubmitChores.bind(r),
      afterFrameSubmit: r.afterFrameSubmit.bind(r),
      beforeFrame: r.beforeFrame.bind(r),
    };
  }

  private adaptQualityIfNeeded(): void {
    if (!this.adaptiveQuality) return;
    const ratio = this.fps / this.targetFPS;
    if (ratio < 0.7 && this.resolutionScale > 0.25) {
      this.setResolutionScale(this.resolutionScale - 0.125);
    } else if (ratio > 0.95 && this.resolutionScale < 1.0) {
      this.setResolutionScale(this.resolutionScale + 0.0625);
    }
  }

  /** Idempotent: WebGPUCanvas calls this every rAF with the same element. */
  setVideo(video: HTMLVideoElement | undefined): void {
    const next = video ?? null;
    if (this.mediaState.video === next) return;
    this.videoIngest.detach();
    this.mediaState.video = next;
  }

  get mediaVideo(): HTMLVideoElement | null {
    return this.mediaState.video;
  }

  /** Stand-alone upload with its own submit (input rebind); the frame loop uses encodeVideoFrame. */
  updateVideoFrame(): void {
    mediaUpdateVideoFrame(this.getMediaContext(), this.mediaState);
  }

  encodeVideoFrame(encoder: GPUCommandEncoder): boolean {
    return this.videoIngest.encode(encoder, {
      device: this.device,
      media: this.mediaState,
      context: () => this.getMediaContext(),
      timestamps: () => profilePass(this.timestampRuntime, { kind: 'video', label: 'videoCopyPass' }),
    });
  }

  private beforeFrameHook: (() => void) | null = null;

  /** Run `hook` at the start of every frame (the render worker drains its input ring). */
  setBeforeFrame(hook: (() => void) | null): void {
    this.beforeFrameHook = hook;
  }

  beforeFrame(): void {
    this.beforeFrameHook?.();
  }

  /** The input the next frame will use — diagnostics / tests prove input reached this thread. */
  getInputEcho(): { mouse: [number, number]; mouseDown: boolean; audio: [number, number, number]; slot0: number[] } {
    const audio = getAudioData(this.audioDepth);
    return {
      mouse: [this.mouseX, this.mouseYShader],
      mouseDown: this.mouseDown,
      audio: [audio.bass, audio.mid, audio.treble],
      slot0: [...(this.slotZoomParams[0] ?? [])],
    };
  }

  /** Frame-loop hook after queue.submit: release the frame's VideoFrame, serve frame grabs. */
  afterFrameSubmit(): void {
    this.videoIngest.afterSubmit();
    this.resolveTexelReadback();
    if (this.frameGrabs.length > 0) this.resolveFrameGrabs();
  }

  /**
   * A VideoFrame of the next presented frame. Taken in the same task as the
   * submit, which is when the canvas still holds it (worker included; no
   * COPY_SRC needed). Resolves null when no frame will come (teardown).
   */
  grabPresentedFrame(timestampUs: number): Promise<VideoFrame | null> {
    if (!this.initialized || !this.presentCanvas || typeof VideoFrame === 'undefined') {
      return Promise.resolve(null);
    }
    return new Promise((resolve) => this.frameGrabs.push({ timestampUs, resolve }));
  }

  private resolveFrameGrabs(canvas: HTMLCanvasElement | OffscreenCanvas | null = this.presentCanvas): void {
    for (const grab of this.frameGrabs.splice(0)) {
      if (!canvas) {
        grab.resolve(null);
        continue;
      }
      try {
        grab.resolve(new VideoFrame(canvas, { timestamp: grab.timestampUs, alpha: 'discard' }));
      } catch (e) {
        console.warn('[WebGPU] frame grab failed:', e);
        grab.resolve(null);
      }
    }
  }

  /** WGSL compile check on this renderer's device (ShaderScanner in worker mode). */
  async compileCheck(id: string, code: string): Promise<Array<{ type: GPUCompilationMessageType; lineNum: number; linePos: number; message: string }>> {
    if (!this.device) throw new Error('No GPUDevice');
    // As loadShader compiles it: storage formats rewritten to the active tier, then checked
    // against the catalog layout, so "compiles but does not fit the bind group" fails here too.
    // @group(1) sim-ring shaders need the two-group layout; those get the module check only.
    const compiled = rewriteWgslStorageFormats(applyF16Variant(code, this.tier2.shaderF16), this.colorFormat);
    const layout = declaresBindGroup1(code) ? undefined : this.pipeline.pipelineLayout;
    return compileCheckWgsl(this.device, id, compiled, { layout });
  }

  /** Render-worker video: frames arrive as transfers (null when the source stops). */
  setTransferredVideo(source: TransferredVideoFrames | null): void {
    this.videoIngest.setExternalSource(source);
  }

  getVideoIngestStats(): VideoIngestStats {
    return this.videoIngest.stats(!!this.mediaState.video);
  }

  async loadImage(url: string): Promise<string> {
    // Getter, not a snapshot: textures can be recreated while the image decodes.
    const result = await mediaLoadImage(() => this.getMediaContext(), this.mediaState, url);
    this.gpuChores.ingestOffscreen(this.mediaState.offscreen, this.mediaState.offCtx);
    return result;
  }

  updateAudioData(bass: number, mid: number, treble: number): void {
    updateAudioData(this.audioDepth, bass, mid, treble);
  }

  updateAudioFrequencyBins(bins: Float32Array): void {
    updateAudioFrequencyBins(this.audioDepth, bins);
  }

  updateDepthMap(data: Float32Array, width: number, height: number): void {
    if (!this.device) return;
    updateDepthMap(this.device, this.resources.depthRead, data, width, height, this.canvasW, this.canvasH);
  }

  /** Canvas-normalized mouse Y (0 = top, 1 = bottom) — matches WASM + WGSL_BUILTINS mouse_uv. */
  updateMouse(x: number, y: number): void {
    this.mouseX = x;
    this.mouseYShader = y;
  }

  setParam(name: string, value: number): void {
    switch (name) {
      case 'mouseDown': this.mouseDown = value > 0; break;
      case 'zoomParam1': this.updateSlotParams({ zoomParam1: value }, 0); break;
      case 'zoomParam2': this.updateSlotParams({ zoomParam2: value }, 0); break;
      case 'zoomParam3': this.updateSlotParams({ zoomParam3: value }, 0); break;
      case 'zoomParam4': this.updateSlotParams({ zoomParam4: value }, 0); break;
    }
  }

  setSlotParams(slotIndex: number, p1: number, p2: number, p3: number, p4: number): void {
    this.updateSlotParams({ zoomParam1: p1, zoomParam2: p2, zoomParam3: p3, zoomParam4: p4 }, slotIndex);
  }

  updateSlotParams(
    params: { zoomParam1?: number; zoomParam2?: number; zoomParam3?: number; zoomParam4?: number },
    slotIndex = 0,
  ): void {
    const target = this.slotZoomParams[slotIndex];
    if (!target) return;
    if (params.zoomParam1 !== undefined) target[0] = params.zoomParam1;
    if (params.zoomParam2 !== undefined) target[1] = params.zoomParam2;
    if (params.zoomParam3 !== undefined) target[2] = params.zoomParam3;
    if (params.zoomParam4 !== undefined) target[3] = params.zoomParam4;
    // Global uniform default (legacy single-shader path) tracks slot 0.
    if (slotIndex === 0) this.zoomParams = [...target];
  }

  setInputSource(source: 'image' | 'video' | 'webcam' | 'generative' | 'live'): void {
    this.inputSource = source;
    if (source === 'generative') {
      clearSourceTexture(this.getMediaContext());
    } else if (source === 'image') {
      // Leaving generative: restore last uploaded image if still in offscreen.
      restoreSourceFromOffscreen(this.getMediaContext(), this.mediaState);
    }
  }

  getInputSource() { return this.inputSource; }

  getCpuInputBitmap(): HTMLCanvasElement | HTMLImageElement | HTMLVideoElement | null {
    if (this.inputSource === 'generative') return null;
    if (
      (this.inputSource === 'video' || this.inputSource === 'webcam' || this.inputSource === 'live')
      && this.mediaState.video
    ) {
      return this.mediaState.video;
    }
    const off = this.mediaState.offscreen;
    // Only a DOM canvas can be handed to main-thread consumers (the worker's is offscreen).
    if (off && typeof HTMLCanvasElement !== 'undefined' && off instanceof HTMLCanvasElement
      && off.width > 0 && off.height > 0) {
      return off;
    }
    return this.mediaState.video;
  }

  /**
   * Upload an image decoded elsewhere (the render worker receives the main
   * thread's decode as a transferred ImageBitmap). Letterboxed like loadImage.
   */
  async loadImageBitmap(bitmap: ImageBitmap): Promise<void> {
    await ingestDecodedImage(() => this.getMediaContext(), this.mediaState, bitmap, bitmap.width, bitmap.height);
    this.gpuChores.ingestOffscreen(this.mediaState.offscreen, this.mediaState.offCtx);
  }

  loadImageFromElement(
    element: HTMLCanvasElement | HTMLImageElement,
  ): { width: number; height: number } | null {
    const w = element instanceof HTMLImageElement
      ? (element.naturalWidth || element.width)
      : element.width;
    const h = element instanceof HTMLImageElement
      ? (element.naturalHeight || element.height)
      : element.height;
    if (!w || !h) return null;
    const dstW = this.canvasW || w;
    const dstH = this.canvasH || h;
    if (!ensureOffscreen(this.mediaState, dstW, dstH) || !this.mediaState.offscreen) return null;
    if (!this.mediaState.offCtx) return null;
    this.mediaState.offCtx.fillStyle = 'black';
    this.mediaState.offCtx.fillRect(0, 0, dstW, dstH);
    this.mediaState.offCtx.drawImage(element, 0, 0, dstW, dstH);
    releaseStill(this.mediaState);
    const ctx = this.getMediaContext();
    if (!copyExternalToSource(ctx, this.mediaState.offscreen, dstW, dstH)) {
      const imageData = this.mediaState.offCtx.getImageData(0, 0, dstW, dstH);
      uploadRGBA8(ctx, imageData.data, dstW, dstH);
    }
    return { width: dstW, height: dstH };
  }

  setMaxPassesPerFrame(cap: number): void {
    this.maxPassesPerFrame = cap;
    if (this.frameState) {
      this.frameState.maxPassesPerFrame = cap;
    }
  }

  /**
   * One per-frame pass budget across linear chains and Tier C graphs: chains
   * are charged first (they cannot be truncated), graphs share the rest, each
   * still within maxPassesPerFrame. Non-finite or < 1 → per-graph caps only.
   */
  setFramePassBudget(budget: number): void {
    this.framePassBudget = Number.isFinite(budget) && budget >= 1 ? Math.floor(budget) : Number.POSITIVE_INFINITY;
  }

  /** Notified once per device when a runtime GPUDevice loss stops rendering. */
  setFatalErrorHandler(handler: ((message: string, info?: DeviceLossInfo) => void) | null): void {
    this.fatalErrorHandler = handler;
  }

  /** The live device (null until init succeeds and after a loss / teardown). */
  getGpuDevice(): GPUDevice | null {
    return this.initialized ? this.device : null;
  }

  getLastDeviceLoss(): DeviceLossInfo | null {
    return this.lastDeviceLoss;
  }

  /**
   * Test hook (?testMode=1): destroy the live device so it really is dead, but route its
   * `lost` through the device-loss path instead of the silent intentional-destroy path.
   */
  simulateDeviceLoss(): boolean {
    const device = this.device;
    if (!device || !this.initialized) return false;
    this.simulatedLossDevice = device;
    try {
      device.destroy();
    } catch {
      /* already destroyed */
    }
    return true;
  }

  /** Resolves once `device.lost` settles, so a remount can re-probe without racing it. */
  destroy(): Promise<void> {
    return this.teardownGpuHandles(true) ?? Promise.resolve();
  }

  async releaseExclusiveGpu(): Promise<void> {
    await this.teardownGpuHandles(true);
  }

  private teardownGpuHandles(awaitLost: boolean): Promise<void> | void {
    this.unregisterCompileService?.();
    this.unregisterCompileService = null;
    if (this.frameState) this.frameRenderer.stopRenderLoop(this.frameState);
    this.warmup?.stop();
    this.warmup = null;
    this.islands.destroy();
    this.compositor?.destroy();
    this.hdrPresent.release();
    this.storagePresent.release();
    this.texelProbe?.resolve(null);
    this.texelProbe = null;
    this.texelReadback?.resolve(null);
    this.texelReadback = null;
    this.frameRenderer.releasePresentHold();
    this.nodeScales.clear();
    this.videoIngest.detach();
    this.resolveFrameGrabs(null);
    this.initialized = false;
    this.gpuChores.destroy();
    this.simRing.destroy();
    destroyTimestampQueries(this.timestampRuntime);
    this.supportsTimestampQuery = false;
    this.pipeline.clear();
    // Buffers and samplers belong to the device being released; the OOM retry
    // (and any re-init) must allocate them again on the next device.
    this.resources.resetForDevice();
    try {
      this.context?.unconfigure();
    } catch {
      /* ignore */
    }
    this.detachUncapturedErrors?.();
    this.detachUncapturedErrors = null;
    clearRendererDevice('renderer released', this);
    const device = this.device;
    this.device = null;
    this.context = null;
    if (!device) return awaitLost ? Promise.resolve() : undefined;
    this.releasingDevice = true;
    const lost = device.lost;
    try {
      device.destroy();
    } catch {
      /* already destroyed */
    }
    if (!awaitLost) return undefined;
    return lost.then(() => undefined).catch(() => undefined);
  }
}

function halfToFloat(h: number): number {
  const sign = h & 0x8000 ? -1 : 1;
  const exp = (h >> 10) & 0x1f;
  const mant = h & 0x3ff;
  if (exp === 0) return sign * mant * 2 ** -24;
  if (exp === 31) return mant ? Number.NaN : sign * Number.POSITIVE_INFINITY;
  return sign * (1 + mant / 1024) * 2 ** (exp - 15);
}

/** One texel of a copyTextureToBuffer row as RGBA floats (rgba16float / bgra8unorm / rgba8unorm). */
function decodeTexel(bytes: Uint8Array, offset: number, format: GPUTextureFormat): number[] {
  if (format === 'rgba16float') {
    const view = new DataView(bytes.buffer, bytes.byteOffset + offset, 8);
    return [0, 2, 4, 6].map((o) => halfToFloat(view.getUint16(o, true)));
  }
  const px = Array.from(bytes.subarray(offset, offset + 4), (b) => b / 255);
  return format === 'bgra8unorm' ? [px[2] ?? 0, px[1] ?? 0, px[0] ?? 0, px[3] ?? 0] : px;
}
