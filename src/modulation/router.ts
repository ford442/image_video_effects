/**
 * router.ts — evaluates routes into per-target overlay values (#1513 Part A).
 *
 * modulated = clamp(base + depth * curve(src) + offset, min, max)
 *
 * Several routes on one target sum their contributions before the clamp. The router never
 * owns base values: callers pass them in and get the overlay back.
 */

import { createSourceEvaluator, SourceEvaluator } from './sources';
import type { ModClock, ModCurve, ModInputs, ModTargetParam, ResolvedRoute } from './types';
import { MOD_TARGET_PARAMS } from './types';

const EXP_K = 4;
const EXP_NORM = Math.exp(EXP_K) - 1;

export function applyCurve(curve: ModCurve, x: number): number {
  switch (curve) {
    case 'linear': return x;
    case 'exp': return (Math.exp(EXP_K * x) - 1) / EXP_NORM;
    case 'smooth': return x * x * (3 - 2 * x);
  }
}

export function modulate(base: number, depth: number, curved: number, offset: number, min: number, max: number): number {
  const v = base + depth * curved + offset;
  const lo = Math.min(min, max);
  const hi = Math.max(min, max);
  return v < lo ? lo : v > hi ? hi : v;
}

export const PARAM_INDEX: Record<ModTargetParam, number> = { p1: 0, p2: 1, p3: 2, p4: 3, opacity: 4 };

interface LiveRoute {
  route: ResolvedRoute;
  source: SourceEvaluator;
}

/** Per-slot result of one evaluation: 5 values (p1..p4, opacity) and which are modulated. */
export interface SlotOverlay {
  values: Float64Array;
  /** Bit i set → MOD_TARGET_PARAMS[i] is modulated. */
  mask: number;
}

export class ModRouter {
  private live: LiveRoute[] = [];
  /** slot → [sum of depth*curve+offset per param, min, max]. */
  private readonly sums = new Map<number, { add: Float64Array; min: Float64Array; max: Float64Array; mask: number }>();
  private lastSources: number[] = [];

  setRoutes(routes: readonly ResolvedRoute[]): void {
    this.live = routes.map((route) => ({ route, source: createSourceEvaluator(route.source) }));
  }

  get routeCount(): number {
    return this.live.length;
  }

  /** Last sampled source value per route (UI meters, tests). */
  getLastSourceValues(): readonly number[] {
    return this.lastSources;
  }

  /** Sample every source once. Call once per frame. */
  step(clock: ModClock, inputs: ModInputs): void {
    this.sums.clear();
    this.lastSources = new Array(this.live.length);
    this.live.forEach(({ route, source }, i) => {
      const raw = source.sample(clock, inputs);
      this.lastSources[i] = raw;
      const idx = PARAM_INDEX[route.target.param];
      let s = this.sums.get(route.target.slot);
      if (!s) {
        s = { add: new Float64Array(5), min: new Float64Array(5), max: new Float64Array(5), mask: 0 };
        this.sums.set(route.target.slot, s);
      }
      s.add[idx] = (s.add[idx] ?? 0) + route.depth * applyCurve(route.curve, raw) + route.offset;
      // First route on a target sets its range (all routes on a target share the param's range).
      if (!(s.mask & (1 << idx))) {
        s.min[idx] = route.min;
        s.max[idx] = route.max;
      }
      s.mask |= 1 << idx;
    });
  }

  /** Slots touched by the last step(). */
  modulatedSlots(): IterableIterator<number> {
    return this.sums.keys();
  }

  /**
   * Overlay for `slot` on top of `base` (p1..p4, opacity). Returns null when nothing
   * targets the slot. Never mutates `base`.
   */
  overlay(slot: number, base: ArrayLike<number>): SlotOverlay | null {
    const s = this.sums.get(slot);
    if (!s) return null;
    const values = new Float64Array(5);
    for (let i = 0; i < MOD_TARGET_PARAMS.length; i++) {
      const b = base[i] ?? 0;
      values[i] = s.mask & (1 << i) ? modulate(b, 1, s.add[i] ?? 0, 0, s.min[i] ?? 0, s.max[i] ?? 1) : b;
    }
    return { values, mask: s.mask };
  }
}
