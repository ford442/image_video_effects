import { WASMDiagnostics } from './WASMRenderer';
import type { RendererType } from './backendLifecycle';

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
  wasm?: WASMDiagnostics;
  webgpu?: {
    initialized: boolean;
    fps: number;
    adapterInfo: string;
    adapterAttemptLabel: string | null;
  };
}
