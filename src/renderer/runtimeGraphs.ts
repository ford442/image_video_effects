/**
 * runtimeGraphs.ts
 *
 * Runtime overlay on the build-time graph registry (multipassRegistry.ts is
 * generated, so this lives in a hand-written module it imports). The Graph Lab
 * (docs/GRAPH_LAB.md) registers an unsaved draft here; resolveGraphForShader /
 * hasGraph / getGraphEntryIds consult the overlay before the static table, so
 * the frame planner, shader loader and badges all see the draft unchanged.
 *
 * One overlay per JS realm: the render worker has its own copy, fed by the
 * `setRuntimeGraph` render command (worker/protocol.ts).
 *
 * Callers must pass a fresh graph object per edit. Validation, expansion and
 * pass caps are memoised per graph object (multipassGraph.ts), so mutating a
 * registered graph in place would keep serving the stale plan.
 */

import type { MultipassGraphDef } from './multipassGraph';

/** Shader id the Graph Lab runs its draft under (single running draft, stable slot binding). */
export const GRAPH_LAB_RUNTIME_ID = 'graphlab-draft';

const overlay = new Map<string, MultipassGraphDef>();

/** Register (or, with `null`, remove) a graph for `id`. */
export function setRuntimeGraph(id: string, graph: MultipassGraphDef | null): void {
  if (graph) overlay.set(id, graph);
  else overlay.delete(id);
}

export function getRuntimeGraph(id: string): MultipassGraphDef | null {
  return overlay.get(id) ?? null;
}

export function listRuntimeGraphIds(): string[] {
  return Array.from(overlay.keys());
}

/** Test hook: drop every runtime graph. */
export function clearRuntimeGraphs(): void {
  overlay.clear();
}
