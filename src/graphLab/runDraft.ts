/**
 * runDraft.ts
 *
 * Runs a draft in the real renderer: the draft is registered as a runtime graph
 * (renderer/runtimeGraphs.ts) under one fixed id and bound to a slot, so it goes
 * through the same planner, pass budgets, truncation and color-writer rules as
 * any shipped graph — the Lab adds no execution path of its own.
 */

import type { GraphRunReport } from '../renderer/GraphRunner';
import type { MultipassGraphDef } from '../renderer/multipassGraph';
import type { PassTiming } from '../renderer/passTimings';
import type { RendererManager } from '../renderer/RendererManager';
import { GRAPH_LAB_RUNTIME_ID } from '../renderer/runtimeGraphs';
import { analyzeGraph } from './graphAnalysis';
import { GraphDraft, isSimRingDraft } from './graphDraft';

export type RunResult =
  | { ok: true; slot: number; entries: string[]; previousShaderId: string | null }
  | { ok: false; reason: 'invalid' | 'sim-ring' | 'empty' | 'backend' | 'load-failed'; message: string };

export interface LiveReading {
  /** The planner's report for the running draft; null until it has compiled a frame. */
  report: GraphRunReport | null;
  /** Smoothed GPU ms per node for the running draft (empty until timestamps resolve). */
  passTimings: PassTiming[];
}

const entryUrl = (entry: string) => `shaders/${entry}.wgsl`;

/** A fresh object per run: the renderer memoises plans per graph object. */
export function cloneGraph(graph: MultipassGraphDef): MultipassGraphDef {
  return {
    maxPassesPerFrame: graph.maxPassesPerFrame,
    nodes: graph.nodes.map((n) => ({ ...n, reads: [...(n.reads ?? [])], writes: [...(n.writes ?? [])] })),
  };
}

export async function runDraft(
  manager: RendererManager,
  slot: number,
  draft: GraphDraft,
  options: { knownEntries?: Set<string>; previousShaderId?: string | null } = {},
): Promise<RunResult> {
  if (draft.graph.nodes.length === 0) {
    return { ok: false, reason: 'empty', message: 'Add at least one node to run the graph.' };
  }
  if (isSimRingDraft(draft)) {
    return { ok: false, reason: 'sim-ring', message: 'Sim-ring graphs are view-only in the Lab (v1).' };
  }
  const analysis = analyzeGraph(draft.graph, options.knownEntries ? { knownEntries: options.knownEntries } : {});
  if (!analysis.valid) {
    return { ok: false, reason: 'invalid', message: analysis.errors[0]?.message ?? 'The graph has errors.' };
  }

  const previousShaderId =
    options.previousShaderId !== undefined
      ? options.previousShaderId
      : (manager.getSlotState(slot)?.shaderId ?? null);

  // Registered before loading: loadShader pulls every graph entry through hasGraph / getGraphEntryIds.
  const graph = cloneGraph(draft.graph);
  if (!manager.setRuntimeGraph(GRAPH_LAB_RUNTIME_ID, graph)) {
    return { ok: false, reason: 'backend', message: 'Graphs run on the TypeScript WebGPU renderer only.' };
  }

  const entries = Array.from(new Set(graph.nodes.map((n) => n.entry)));
  // The root id needs a compiled pipeline (the planner gates slots on it); the first entry's WGSL serves.
  if (!manager.isShaderCached(GRAPH_LAB_RUNTIME_ID)) {
    const ok = await manager.loadShader(GRAPH_LAB_RUNTIME_ID, entryUrl(entries[0]));
    if (!ok) return { ok: false, reason: 'load-failed', message: `Could not compile "${entries[0]}".` };
  }
  for (const entry of entries) {
    if (manager.isShaderCached(entry)) continue;
    const ok = await manager.loadShader(entry, entryUrl(entry));
    if (!ok) return { ok: false, reason: 'load-failed', message: `Could not compile "${entry}".` };
  }

  manager.setSlotShader(slot, GRAPH_LAB_RUNTIME_ID);
  return { ok: true, slot, entries, previousShaderId };
}

/**
 * Drop the draft and put the slot back the way it was — unless the slot no longer
 * shows the draft (the user picked another shader meanwhile), which is left alone.
 */
export function stopDraft(manager: RendererManager, slot: number, previousShaderId: string | null): void {
  if (manager.getSlotState(slot)?.shaderId === GRAPH_LAB_RUNTIME_ID) {
    manager.setSlotShader(slot, previousShaderId ?? '');
  }
  manager.setRuntimeGraph(GRAPH_LAB_RUNTIME_ID, null);
}

/** Live planner report and per-node GPU time for the running draft. */
export function readLive(manager: RendererManager): LiveReading {
  const report = manager.getDiagnostics().webgpu?.graph ?? null;
  const mine = report && report.shaderId === GRAPH_LAB_RUNTIME_ID ? report : null;
  const passTimings = manager
    .getPassTimings()
    .filter((t) => t.kind === 'compute' && t.shaderId === GRAPH_LAB_RUNTIME_ID);
  return { report: mine, passTimings };
}
