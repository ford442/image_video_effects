import type { GpuChoresBreadcrumbs } from '../gpuChores';
import type { WebGpuProbeSerializable } from './webgpuBootProbe';
import { WASMDiagnostics } from './WASMRenderer';
import type { RendererType } from './backendLifecycle';
import type { GraphRunReport } from './GraphRunner';
import type { FrameStats } from './webgpu/deviceCounters';
import type { PassTiming } from './passTimings';

export interface RendererMetrics {
  fps: number;
  frameTime: number;
  agentCount: number;
  isWASM: boolean;
}

export interface RendererDiagnostics {
  rendererType: RendererType;
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
  };
}
