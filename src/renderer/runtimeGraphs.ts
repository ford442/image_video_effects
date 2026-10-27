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

/** A runtime graph's sim-ring request: the definition `simRing` field, as consumed. */
export interface RuntimeSimRingRequest {
  stateCount: number;
}

const overlay = new Map<string, MultipassGraphDef>();
const simRingOverlay = new Map<string, RuntimeSimRingRequest>();

/**
 * Register (or, with `null`, remove) a graph for `id`, with its optional sim-ring
 * request. The request only sizes the ring when a group-1 entry compiles
 * (WebGPURenderer.loadShader → SimRing.ensure); it never attaches group 1 itself.
 */
export function setRuntimeGraph(
  id: string,
  graph: MultipassGraphDef | null,
  simRing: RuntimeSimRingRequest | null = null,
): void {
  if (graph) overlay.set(id, graph);
  else overlay.delete(id);
  if (graph && simRing) simRingOverlay.set(id, { stateCount: simRing.stateCount });
  else simRingOverlay.delete(id);
}

export function getRuntimeGraph(id: string): MultipassGraphDef | null {
  return overlay.get(id) ?? null;
}

/**
 * Sim-ring element count a runtime graph requests for `shaderId` — the graph's
 * own id or one of its node entries. Undefined when no runtime graph claims it.
 */
export function getRuntimeSimRingRequest(shaderId: string): number | undefined {
  const direct = simRingOverlay.get(shaderId);
  if (direct) return direct.stateCount;
  for (const [ownerId, req] of Array.from(simRingOverlay)) {
    if (overlay.get(ownerId)?.nodes.some((n) => n.entry === shaderId)) return req.stateCount;
  }
  return undefined;
}

export function listRuntimeGraphIds(): string[] {
  return Array.from(overlay.keys());
}

/** Every registered runtime graph with its sim-ring request, for re-seeding a new backend. */
export function listRuntimeGraphs(): Array<{
  id: string;
  graph: MultipassGraphDef;
  simRing: RuntimeSimRingRequest | null;
}> {
  return Array.from(overlay, ([id, graph]) => ({ id, graph, simRing: simRingOverlay.get(id) ?? null }));
}

/** Test hook: drop every runtime graph. */
export function clearRuntimeGraphs(): void {
  overlay.clear();
  simRingOverlay.clear();
}
