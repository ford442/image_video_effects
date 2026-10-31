/**
 * runtime.ts — the modulation bus of one realm (#1513 Part A).
 *
 * One instance per JS realm: the render worker's (fed by the `setModulation` /
 * `setModulationExternal` commands) or the page's (fed by modulationStore when the
 * renderer runs on the main thread, ?renderer=main). frame.ts calls applyOverlay()
 * once per frame, so both render threads share this evaluator.
 *
 * The overlay swaps each modulated slot's `params` / `layer` for modulated copies for
 * the duration of the frame and restores the originals afterwards: base values (what the
 * UI set) are never written.
 */

import { ModRouter } from './router';
import type { ModClock, ResolvedRoute } from './types';
import { isResolvedRoute } from './validate';

export interface OverlaySlot<L extends { opacity: number } = { opacity: number }> {
  params?: number[];
  layer?: L;
}

export interface OverlayAudio {
  bass: number;
  mid: number;
  treble: number;
}

export class ModulationRuntime {
  private readonly router = new ModRouter();
  private bpmValue = 120;
  private readonly external = new Map<string, number>();
  private injectedClock: ModClock | null = null;
  private frameTime = 0;
  private readonly frameClock: ModClock = {
    now: () => this.frameTime,
    bpm: () => this.bpmValue,
  };

  setRoutes(routes: readonly ResolvedRoute[]): void {
    this.router.setRoutes(routes.filter(isResolvedRoute));
  }

  get routeCount(): number {
    return this.router.routeCount;
  }

  setBpm(bpm: number): void {
    if (Number.isFinite(bpm) && bpm > 0) this.bpmValue = bpm;
  }

  getBpm(): number {
    return this.bpmValue;
  }

  setExternal(values: Record<string, number>): void {
    for (const [k, v] of Object.entries(values)) if (Number.isFinite(v)) this.external.set(k, v);
  }

  /** Seam for #1401: a RenderClock replaces the frame-time clock. null restores it. */
  setClock(clock: ModClock | null): void {
    this.injectedClock = clock;
  }

  /**
   * Evaluate the bus for this frame and overlay it onto `slots` (indexed by physical slot).
   * Returns the function that restores the base values; call it after the frame is encoded.
   */
  applyOverlay<L extends { opacity: number }>(
    slots: Array<OverlaySlot<L>>,
    frameTimeSeconds: number,
    audio: OverlayAudio,
  ): () => void {
    if (this.router.routeCount === 0) return noop;
    this.frameTime = frameTimeSeconds;
    this.router.step(this.injectedClock ?? this.frameClock, {
      bass: audio.bass,
      mid: audio.mid,
      high: audio.treble,
      external: this.external,
    });
    const undo: Array<() => void> = [];
    for (const index of this.router.modulatedSlots()) {
      const slot = slots[index];
      if (!slot) continue;
      const params = slot.params;
      const layer = slot.layer;
      const base = [params?.[0] ?? 0.5, params?.[1] ?? 0.5, params?.[2] ?? 0.5, params?.[3] ?? 0.5, layer?.opacity ?? 1];
      const o = this.router.overlay(index, base);
      if (!o) continue;
      if (o.mask & 0b1111 && params) {
        const next = params.slice();
        for (let i = 0; i < 4; i++) if (o.mask & (1 << i)) next[i] = o.values[i] ?? next[i] ?? 0;
        slot.params = next;
        undo.push(() => { slot.params = params; });
      }
      if (o.mask & 0b10000 && layer) {
        slot.layer = { ...layer, opacity: o.values[4] ?? layer.opacity };
        undo.push(() => { slot.layer = layer; });
      }
    }
    return () => { for (const u of undo) u(); };
  }
}

const noop = () => {};

let realmRuntime: ModulationRuntime | null = null;

/** This realm's bus (created on first use). */
export function getModulationRuntime(): ModulationRuntime {
  realmRuntime ??= new ModulationRuntime();
  return realmRuntime;
}

/** Test hook. */
export function resetModulationRuntime(): void {
  realmRuntime = null;
}
