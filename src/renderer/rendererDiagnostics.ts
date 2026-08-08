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
  };
  const active = currentRenderer as {
    getDiagnostics?: () => WASMDiagnostics;
    initialized?: boolean;
    getFPS?: () => number;
    getAdapterSummary?: () => string;
    getAdapterAttemptLabel?: () => string | null;
  } | null;

  if (metrics.isWASM && active?.getDiagnostics) {
    return { ...base, wasm: active.getDiagnostics() };
  }
  if (resolveShaderBackend(currentRenderer) && !metrics.isWASM && active) {
    return {
      ...base,
      webgpu: {
        initialized: active.initialized ?? false,
        fps: active.getFPS?.() ?? 0,
        adapterInfo: active.getAdapterSummary?.() ?? '',
        adapterAttemptLabel: active.getAdapterAttemptLabel?.() ?? null,
      },
      ...(lastFailedWasmRenderer ? { wasm: lastFailedWasmRenderer.getDiagnostics() } : {}),
    };
  }
  if (lastFailedWasmRenderer) return { ...base, wasm: lastFailedWasmRenderer.getDiagnostics() };
  return base;
}
