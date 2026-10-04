import type { GpuChoresBreadcrumbs } from '../gpuChores';
import type { WebGpuProbeSerializable } from './webgpuBootProbe';
import { WASMDiagnostics } from './WASMRenderer';
import type { RendererType } from './backendLifecycle';
import type { GraphRunReport } from './GraphRunner';
import type { FrameStats } from './webgpu/deviceCounters';
import type { PassTiming } from './passTimings';
import type { VideoIngestStats } from './media/videoFramePump';

export interface RendererMetrics {
  fps: number;
  frameTime: number;
  agentCount: number;
  isWASM: boolean;
}

export interface RendererDiagnostics {
  rendererType: RendererType;
  /** TS WebGPU backend: rendering on the page or in the render worker (#1314). */
  renderThread?: 'main' | 'worker';
  /** Page ↔ render-worker input path: shared memory (isolated pages) or messages. */
  inputChannel?: 'sab' | 'postMessage';
  crossOriginIsolated?: boolean;
  metrics: RendererMetrics;
  timestamp: string;
  /** Last published boot-probe breadcrumb (also on window.webgpuProbe). */
  webgpuProbe?: WebGpuProbeSerializable;
  wasm?: WASMDiagnostics;
  webgpu?: {
    initialized: boolean;
    fps: number;
    adapterInfo: string;
    adapterAttemptLabel: string | null;
    graph?: GraphRunReport | null;
    gpuChores?: GpuChoresBreadcrumbs;
    /** Submits / bind groups per frame (#1314: steady state is one submit). */
    frameStats?: FrameStats;
    /** Smoothed per-pass GPU ms (#1314 WP-4); empty until timestamps resolve. */
    passTimings?: PassTiming[];
    timing?: { source: 'gpu-timestamp' | 'wall-clock'; periodNs: number; profiledPasses: number; overflow: number };
    /** Demoted opt-in graph nodes, `${slot}:${nodeId}` → scale. */
    nodeScales?: Record<string, number>;
    /** Video ingest path + counters (#1314 WP-2). */
    video?: VideoIngestStats;
    /** Uncaptured GPU errors in the render worker (page hooks cannot see that device). */
    gpuErrors?: string[];
    /** Input currently held by the renderer (worker mode; proves the input channel). */
    input?: { mouse: [number, number]; mouseDown: boolean; audio: [number, number, number]; slot0: number[] } | null;
  };
}
