import { WASMDiagnostics } from './WASMRenderer';
import type { RendererType } from './backendLifecycle';
import type { RendererDiagnostics, RendererMetrics } from './rendererTypes';
import { resolveShaderBackend } from './slotOrchestration';
import { Renderer } from './Renderer';
import { WASMRenderer } from './WASMRenderer';

export function buildRendererDiagnostics(
  rendererType: RendererType,
  metrics: RendererMetrics,
  currentRenderer: Renderer | null,
  lastFailedWasmRenderer: WASMRenderer | null,
): RendererDiagnostics {
  const base: RendererDiagnostics = {
    rendererType,
    metrics,
    timestamp: new Date().toISOString(),
    webgpuProbe: typeof window !== 'undefined' ? window.webgpuProbe : undefined,
  };
  const active = currentRenderer as {
    getDiagnostics?: () => WASMDiagnostics;
    initialized?: boolean;
    getFPS?: () => number;
    getAdapterSummary?: () => string;
    getAdapterAttemptLabel?: () => string | null;
    getLastGraphReport?: () => import('./GraphRunner').GraphRunReport | null;
    getGpuChoresBreadcrumbs?: () => import('../gpuChores').GpuChoresBreadcrumbs;
    getFrameStats?: () => import('./webgpu/deviceCounters').FrameStats;
    getPassTimings?: () => import('./passTimings').PassTiming[];
    getTimingInfo?: () => NonNullable<RendererDiagnostics['webgpu']>['timing'];
    getNodeScales?: () => Record<string, number>;
    getVideoIngestStats?: () => import('./media/videoFramePump').VideoIngestStats;
    getGpuErrors?: () => string[];
    getInputEcho?: () => NonNullable<RendererDiagnostics['webgpu']>['input'];
    renderThread?: 'main' | 'worker';
    inputChannel?: 'sab' | 'postMessage';
  } | null;

  if (metrics.isWASM && active?.getDiagnostics) {
    return { ...base, wasm: active.getDiagnostics() };
  }
  if (resolveShaderBackend(currentRenderer) && !metrics.isWASM && active) {
    return {
      ...base,
      renderThread: active.renderThread ?? 'main',
      ...(active.inputChannel ? { inputChannel: active.inputChannel } : {}),
      crossOriginIsolated: typeof window !== 'undefined' && window.crossOriginIsolated === true,
      webgpu: {
        initialized: active.initialized ?? false,
        fps: active.getFPS?.() ?? 0,
        adapterInfo: active.getAdapterSummary?.() ?? '',
        adapterAttemptLabel: active.getAdapterAttemptLabel?.() ?? null,
        graph: active.getLastGraphReport?.() ?? null,
        gpuChores: active.getGpuChoresBreadcrumbs?.(),
        frameStats: active.getFrameStats?.(),
        passTimings: active.getPassTimings?.(),
        timing: active.getTimingInfo?.(),
        nodeScales: active.getNodeScales?.(),
        video: active.getVideoIngestStats?.(),
        ...(active.getGpuErrors ? { gpuErrors: active.getGpuErrors() } : {}),
        ...(active.getInputEcho ? { input: active.getInputEcho() } : {}),
      },
      ...(lastFailedWasmRenderer ? { wasm: lastFailedWasmRenderer.getDiagnostics() } : {}),
    };
  }
  if (lastFailedWasmRenderer) return { ...base, wasm: lastFailedWasmRenderer.getDiagnostics() };
  return base;
}
