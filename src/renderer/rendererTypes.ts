import type { GpuChoresBreadcrumbs } from '../gpuChores';
import type { WebGpuProbeSerializable } from './webgpuBootProbe';
import { WASMDiagnostics } from './WASMRenderer';
import type { RendererType } from './backendLifecycle';
import type { GraphRunReport } from './GraphRunner';

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
  };
}
