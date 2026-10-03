/**
 * backendFailure.ts — post-init backend death (#1311 WP-A item 4).
 * A WASM render loop that stops after repeated errors must stop being advertised and reach the
 * existing failure overlay. No fallback renderer: the app policy is "WebGPU required".
 */
import type { Renderer } from './Renderer';
import type { RendererError } from './ErrorHandling';
import type { RendererType } from './backendLifecycle';
import type { WASMRenderer } from './WASMRenderer';

export class BackendFailureWatch {
  private listener?: (error: RendererError) => void;

  setListener(listener: (error: RendererError) => void): void {
    this.listener = listener;
  }

  /** Arm `renderer` so a stopped loop calls `onFail` (only while it is still current), then the listener. */
  watch(renderer: Renderer, type: RendererType | null, isCurrent: () => boolean, onFail: () => void): void {
    if (type !== 'wasm') return;
    (renderer as WASMRenderer).onRenderLoopStopped = (error) => {
      if (!isCurrent()) return;
      onFail();
      this.listener?.(error);
    };
  }
}
