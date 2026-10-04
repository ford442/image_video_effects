/**
 * protocol.ts
 *
 * Typed message protocol between the main thread and the render worker
 * (#1314 WP-1). Same style as shaderSearchProtocol.ts: discriminated unions on
 * `type`. Requests that need an answer carry a `requestId`; the worker replies
 * with an `rpcResult`.
 *
 *   main → worker   RenderCommand (fire-and-forget) | RenderRpc (request/reply)
 *   worker → main   RenderEvent
 *
 * The *_TYPES lists and the handler tables in renderWorkerHost.ts /
 * WorkerWebGPUBackend.ts are checked against each other by
 * protocol.contract.test.ts and, at compile time, by the assertions below.
 */

import type { InternalColorFormat, DeviceFormatCapabilities } from '../../config/formatPolicy';
import type { GpuChoresBreadcrumbs } from '../../gpuChores';
import type { RendererError } from '../ErrorHandling';
import type { GraphRunReport } from '../GraphRunner';
import type { VideoIngestStats } from '../media/videoFramePump';
import type { PassTiming } from '../passTimings';
import type { GPUTimings, RendererConfig } from '../Renderer';
import type { InputSource } from '../types';
import type { FrameStats } from '../webgpu/deviceCounters';
import type { CanvasConfigureOptIns } from '../webgpu/device';
import type { SlotMode } from '../webgpu/webgpuConstants';
import type { WebGpuProbeSerializable } from '../webgpuBootProbe';

/** What the worker scope supports (sent once, before init). */
export interface RenderWorkerCaps {
  gpu: boolean;
  offscreenWebgpu: boolean;
  raf: boolean;
  videoFrame: boolean;
  crossOriginIsolated: boolean;
  sharedArrayBuffer: boolean;
}

export interface TestRenderState {
  time?: number;
  mouseX?: number;
  mouseY?: number;
  bass?: number;
  mid?: number;
  treble?: number;
}

/**
 * Per-frame input coalesced on the main thread: one message per main rAF
 * instead of one per pointermove / slider tick / audio frame.
 */
export interface FrameInput {
  mouse?: [number, number];
  mouseDown?: boolean;
  audio?: [number, number, number];
  bins?: Float32Array;
  /** [slotIndex, p1, p2, p3, p4] for every slot whose params changed. */
  slotParams?: Array<[number, number, number, number, number]>;
  /** Ripples added since the last flush (stamped with the worker's clock). */
  ripples?: Array<[number, number]>;
  clearRipples?: boolean;
  /** Main-thread pump counters, folded into the worker's video stats. */
  videoStats?: { missedFrames: number; droppedFrames: number };
}

export type RenderCommand =
  | { type: 'frameInput'; input: FrameInput }
  | { type: 'setActiveShader'; id: string }
  | { type: 'setSlotShader'; index: number; id: string }
  | { type: 'setSlotEnabled'; index: number; enabled: boolean }
  | { type: 'setSlotMode'; index: number; mode: SlotMode }
  | { type: 'setInputSource'; source: InputSource }
  | { type: 'updateDepthMap'; data: Float32Array; width: number; height: number }
  | { type: 'setVideoActive'; active: boolean }
  | { type: 'videoFrame'; frame: VideoFrame }
  | { type: 'setResolutionScale'; scale: number }
  | { type: 'setColorFormat'; format: InternalColorFormat }
  | { type: 'setMaxPassesPerFrame'; cap: number }
  | { type: 'setFramePassBudget'; budget: number }
  | { type: 'setNodeScale'; slot: number; nodeId: string; scale: number }
  | { type: 'setAdaptiveQuality'; enabled: boolean; targetFps: number }
  | { type: 'setSourceAutoExposure'; enabled: boolean }
  | { type: 'applyTestRenderState'; state: TestRenderState }
  | { type: 'setCanvasCopySrc'; enabled: boolean }
  | { type: 'warmShaders'; entries: Array<{ id: string; url: string }> };

export interface RenderInitInfo {
  ok: boolean;
  probe: WebGpuProbeSerializable;
  formatCapabilities?: DeviceFormatCapabilities;
  supportsDeepWorkgroup?: boolean;
  canvasCopySrc?: boolean;
  adapterSummary?: string;
  adapterAttemptLabel?: string | null;
  lastInitError?: string;
}

export type RenderRpc =
  | {
      type: 'init';
      requestId: number;
      canvas: OffscreenCanvas;
      config: RendererConfig;
      colorOptIns: Pick<CanvasConfigureOptIns, 'displayP3' | 'extendedToneMapping'>;
      /** Absolute app root; relative fetches in the worker resolve against it. */
      appBaseUrl: string;
    }
  | { type: 'loadShader'; requestId: number; id: string; url: string }
  | { type: 'loadImageBitmap'; requestId: number; bitmap: ImageBitmap }
  | { type: 'captureThumbnail'; requestId: number; size: number }
  | { type: 'dispose'; requestId: number };

/** Results by RPC type. */
export interface RenderRpcResults {
  init: RenderInitInfo;
  loadShader: boolean;
  loadImageBitmap: true;
  captureThumbnail: string | null;
  dispose: true;
}

/** Everything the main thread's synchronous getters need, refreshed ~4×/s. */
export interface RenderSnapshot {
  initialized: boolean;
  fps: number;
  gpuTimings: GPUTimings;
  passTimings: PassTiming[];
  timing: { source: 'gpu-timestamp' | 'wall-clock'; periodNs: number; profiledPasses: number; overflow: number };
  frameStats: FrameStats;
  video: VideoIngestStats;
  nodeScales: Record<string, number>;
  scalableNodes: Array<{ slot: number; nodeId: string; minScale: number; scale: number }>;
  slots: Array<{ shaderId: string | null; enabled: boolean; mode: SlotMode } | null>;
  graphReport: GraphRunReport | null;
  chores: GpuChoresBreadcrumbs;
  cachedShaderIds: string[];
  colorFormat: InternalColorFormat;
  historyLayers: number;
  workingSizeCap: number;
  resolution: { scale: number; full: { w: number; h: number }; scaled: { w: number; h: number }; pixelReduction: string };
  /** Most recent uncaptured GPU errors in the worker (newest last). */
  gpuErrors: string[];
}

export type RenderEvent =
  | { type: 'hello'; caps: RenderWorkerCaps }
  | { type: 'snapshot'; snapshot: RenderSnapshot }
  | { type: 'error'; error: RendererError }
  | { type: 'rpcResult'; requestId: number; ok: true; value: unknown }
  | { type: 'rpcResult'; requestId: number; ok: false; error: string };

export type RenderToWorker = RenderCommand | RenderRpc;

export const RENDER_COMMAND_TYPES = [
  'frameInput',
  'setActiveShader',
  'setSlotShader',
  'setSlotEnabled',
  'setSlotMode',
  'setInputSource',
  'updateDepthMap',
  'setVideoActive',
  'videoFrame',
  'setResolutionScale',
  'setColorFormat',
  'setMaxPassesPerFrame',
  'setFramePassBudget',
  'setNodeScale',
  'setAdaptiveQuality',
  'setSourceAutoExposure',
  'applyTestRenderState',
  'setCanvasCopySrc',
  'warmShaders',
] as const;

export const RENDER_RPC_TYPES = ['init', 'loadShader', 'loadImageBitmap', 'captureThumbnail', 'dispose'] as const;

export const RENDER_EVENT_TYPES = ['hello', 'snapshot', 'error', 'rpcResult'] as const;

// Compile-time exhaustiveness: every union member is listed, and nothing else.
type Exact<A, B> = [A] extends [B] ? ([B] extends [A] ? true : never) : never;
export const PROTOCOL_LISTS_ARE_EXHAUSTIVE: [
  Exact<RenderCommand['type'], (typeof RENDER_COMMAND_TYPES)[number]>,
  Exact<RenderRpc['type'], (typeof RENDER_RPC_TYPES)[number]>,
  Exact<RenderEvent['type'], (typeof RENDER_EVENT_TYPES)[number]>,
  Exact<RenderRpc['type'], keyof RenderRpcResults>,
] = [true, true, true, true];

/** Payloads that can be moved instead of copied. */
export function transferablesOf(message: RenderToWorker | RenderEvent): Transferable[] {
  switch (message.type) {
    case 'init':
      return [message.canvas];
    case 'videoFrame':
      return [message.frame as unknown as Transferable];
    case 'loadImageBitmap':
      return [message.bitmap];
    case 'updateDepthMap':
      return [message.data.buffer];
    case 'frameInput':
      return message.input.bins ? [message.input.bins.buffer] : [];
    default:
      return [];
  }
}
