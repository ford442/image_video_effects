/**
 * store.ts — page-side modulation state (#1513 Part A). Pure TS, no DOM.
 *
 * Holds the routes the UI edits (with each target's resolved min/max), the tempo, live
 * external controller values and which target the mod-matrix panel was opened for.
 * Every change is mirrored into this realm's ModulationRuntime (the ?renderer=main path)
 * and announced to subscribers — WorkerWebGPUBackend forwards it to the render worker.
 */

import { getModulationRuntime } from './runtime';
import type { ModTarget, ResolvedRoute, Route } from './types';
import { isRoute, toRoute } from './validate';

export interface ParamRange {
  min: number;
  max: number;
}

export interface ModulationSnapshot {
  routes: readonly ResolvedRoute[];
  bpm: number;
}

type Listener = (s: ModulationSnapshot) => void;
type ExternalListener = (values: Record<string, number>) => void;
type PanelListener = (target: ModTarget | null, open: boolean) => void;

const DEFAULT_RANGE: ParamRange = { min: 0, max: 1 };

let routes: ResolvedRoute[] = [];
let bpm = 120;
const listeners = new Set<Listener>();
const externalListeners = new Set<ExternalListener>();
const panelListeners = new Set<PanelListener>();
let panelOpen = false;
let panelTarget: ModTarget | null = null;
/** Range lookup for targets (slot, param) → shader-definition min/max. */
let rangeOf: (target: ModTarget) => ParamRange = () => DEFAULT_RANGE;

const snapshot = (): ModulationSnapshot => ({ routes, bpm });

function publish(): void {
  const rt = getModulationRuntime();
  rt.setRoutes(routes);
  rt.setBpm(bpm);
  const s = snapshot();
  for (const l of listeners) l(s);
}

function resolve(r: Route): ResolvedRoute {
  const range = r.target.param === 'opacity' ? DEFAULT_RANGE : rangeOf(r.target);
  return { ...toRoute(r), min: range.min, max: range.max };
}

export const modulationStore = {
  getSnapshot: snapshot,
  getRoutes(): Route[] {
    return routes.map(toRoute);
  },
  /** Replace every route (project import, panel edits). Invalid entries are dropped. */
  setRoutes(next: readonly Route[]): void {
    routes = next.filter(isRoute).map(resolve);
    publish();
  },
  upsertRoute(route: Route): void {
    if (!isRoute(route)) return;
    const resolved = resolve(route);
    const i = routes.findIndex((r) => r.id === route.id);
    routes = i < 0 ? [...routes, resolved] : routes.map((r, j) => (j === i ? resolved : r));
    publish();
  },
  removeRoute(id: string): void {
    routes = routes.filter((r) => r.id !== id);
    publish();
  },
  clear(): void {
    routes = [];
    publish();
  },
  /** Re-resolve ranges (call when a slot's shader changes). */
  setRangeResolver(fn: (target: ModTarget) => ParamRange): void {
    rangeOf = fn;
    routes = routes.map(resolve);
    publish();
  },
  setBpm(next: number): void {
    if (!Number.isFinite(next) || next <= 0) return;
    bpm = next;
    publish();
  },
  getBpm: () => bpm,
  /** External controller values (MIDI CC / OSC / keys), 0..1 by `${source}:${id}`. */
  setExternal(values: Record<string, number>): void {
    getModulationRuntime().setExternal(values);
    for (const l of externalListeners) l(values);
  },
  subscribe(listener: Listener): () => void {
    listeners.add(listener);
    return () => listeners.delete(listener);
  },
  subscribeExternal(listener: ExternalListener): () => void {
    externalListeners.add(listener);
    return () => externalListeners.delete(listener);
  },
  /** Open the mod-matrix panel, optionally pre-targeted at one slot param. */
  openPanel(target: ModTarget | null = null): void {
    panelOpen = true;
    panelTarget = target;
    for (const l of panelListeners) l(panelTarget, panelOpen);
  },
  closePanel(): void {
    panelOpen = false;
    for (const l of panelListeners) l(panelTarget, panelOpen);
  },
  getPanel: () => ({ open: panelOpen, target: panelTarget }),
  subscribePanel(listener: PanelListener): () => void {
    panelListeners.add(listener);
    return () => panelListeners.delete(listener);
  },
  /** Test hook. */
  reset(): void {
    routes = [];
    bpm = 120;
    panelOpen = false;
    panelTarget = null;
    rangeOf = () => DEFAULT_RANGE;
    listeners.clear();
    externalListeners.clear();
    panelListeners.clear();
  },
};
