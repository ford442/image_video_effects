/**
 * graphAnalysis.ts
 *
 * Everything the Lab shows about a draft, derived from the renderer's own
 * validator and planner (multipassGraph.ts) — no parallel implementation:
 *   - diagnostics  ← diagnoseGraph (the same checks the frame planner runs)
 *   - dependencies ← expandGraph (reads → producer, copy barriers)
 *   - cost / caps  ← capGraphDispatches under each quality policy
 *
 * Analysis expands a sanitized copy (repeat clamped to 1–64) so a broken import
 * with `repeat: 1e9` reports its error instead of freezing the tab. It uses the
 * non-memoized planner entry points, which are safe for a graph that is edited.
 */

import { resolveAutoPolicy, QUALITY_PRESETS } from '../config/performancePolicy';
import {
  capGraphDispatches,
  diagnoseGraph,
  expandGraph,
  GraphDiagnostic,
  GraphNodeDef,
  GraphRole,
  graphUsesSimRing,
  MAX_REPEAT,
  MultipassGraphDef,
} from '../renderer/multipassGraph';
import { framePassBudgetFor } from '../renderer/performanceStatus';

export interface DependencyRead {
  role: GraphRole;
  /** Where the data comes from: the source image, a node dispatch, a barrier copy, or the previous frame. */
  from: string;
}

export interface DependencyRow {
  /** Position in the expanded dispatch list. */
  index: number;
  nodeId: string;
  iteration: number;
  entry: string;
  reads: DependencyRead[];
  writes: GraphRole[];
  /** Copy barriers inserted before this dispatch, e.g. `dataA → dataC`. */
  barriers: string[];
}

export interface NodeCost {
  index: number;
  nodeId: string;
  entry: string;
  passes: number;
  /** Fraction of the graph's requested passes (0–1). */
  share: number;
  scalable: boolean;
  /** Copy barriers inserted across all of this node's dispatches. */
  barriers: number;
}

export interface CapPreview {
  id: string;
  label: string;
  /** Per-graph pass cap from the policy (the graph's own ceiling still applies). */
  policyCap: number;
  effectiveCap: number;
  /** Frame budget for a stack of `maxActiveSlots` graphs under this policy. */
  frameBudget: number;
  executed: number;
  truncated: number;
  /** null when the graph has no color writer to keep. */
  keepsColorWriter: boolean | null;
  /** The surviving dispatches, e.g. `step#1`, `render`. */
  dispatches: string[];
}

export interface GraphAnalysis {
  diagnostics: GraphDiagnostic[];
  errors: GraphDiagnostic[];
  warnings: GraphDiagnostic[];
  /** No error diagnostics: the planner would encode it. */
  valid: boolean;
  usesSimRing: boolean;
  requested: number;
  ceiling: number;
  rows: DependencyRow[];
  nodes: NodeCost[];
  barrierCount: number;
  caps: CapPreview[];
}

const POLICIES: ReadonlyArray<{ id: string; label: string; policy: { maxPassesPerFrame: number; maxActiveSlots: number } }> = [
  { id: 'battery', label: 'Battery', policy: QUALITY_PRESETS.battery },
  { id: 'balanced', label: 'Balanced', policy: QUALITY_PRESETS.balanced },
  { id: 'ultra', label: 'Ultra', policy: QUALITY_PRESETS.ultra },
  { id: 'auto-low', label: 'Auto · low-end GPU', policy: resolveAutoPolicy({ supportsDeepWorkgroup: false, isMobile: false }) },
  { id: 'auto-mobile', label: 'Auto · mobile', policy: resolveAutoPolicy({ supportsDeepWorkgroup: true, isMobile: true }) },
  { id: 'auto-desktop', label: 'Auto · desktop', policy: resolveAutoPolicy({ supportsDeepWorkgroup: true, isMobile: false }) },
];

function sanitize(graph: MultipassGraphDef): MultipassGraphDef {
  const nodes: GraphNodeDef[] = (graph.nodes ?? []).map((n) => {
    const repeat = Number.isFinite(n.repeat) ? Math.min(MAX_REPEAT, Math.max(1, Math.round(n.repeat as number))) : 1;
    return { ...n, reads: [...(n.reads ?? [])], writes: [...(n.writes ?? [])], repeat };
  });
  return { maxPassesPerFrame: graph.maxPassesPerFrame, nodes };
}

function dispatchLabel(nodeId: string, iteration: number, repeat: number): string {
  return repeat > 1 ? `${nodeId}#${iteration + 1}` : nodeId;
}

function buildRows(graph: MultipassGraphDef): DependencyRow[] {
  const repeats = new Map<string, number>();
  for (const n of graph.nodes) repeats.set(n.id, (repeats.get(n.id) ?? 0) + (n.repeat ?? 1));

  const lastWriter = new Map<GraphRole, string>();
  let dataCSource = 'previous frame';
  return expandGraph(graph).map((d, index) => {
    const label = dispatchLabel(d.nodeId, d.iteration, repeats.get(d.nodeId) ?? 1);
    for (const copy of d.copiesBefore) {
      if (copy.to === 'dataC') dataCSource = `${copy.from} → dataC (${lastWriter.get(copy.from) ?? 'previous frame'})`;
    }
    const reads = d.reads.map((role): DependencyRead => {
      if (role === 'read') return { role, from: 'source image' };
      if (role === 'color') return { role, from: 'display target' };
      if (role === 'dataC') return { role, from: dataCSource };
      if (role === 'simState' || role === 'simIndex') return { role, from: 'sim ring' };
      return { role, from: lastWriter.get(role) ?? 'nothing produces it' };
    });
    for (const role of d.writes) lastWriter.set(role, label);
    return {
      index,
      nodeId: d.nodeId,
      iteration: d.iteration,
      entry: d.entry,
      reads,
      writes: [...d.writes],
      barriers: d.copiesBefore.map((c) => `${c.from} → ${c.to}`),
    };
  });
}

function buildCaps(graph: MultipassGraphDef, requested: number): CapPreview[] {
  const hasColorWriter = graph.nodes.some((n) => (n.writes ?? []).includes('color'));
  const repeats = new Map<string, number>();
  for (const n of graph.nodes) repeats.set(n.id, (repeats.get(n.id) ?? 0) + (n.repeat ?? 1));

  return POLICIES.map(({ id, label, policy }) => {
    const survivors = capGraphDispatches(graph, policy.maxPassesPerFrame);
    return {
      id,
      label,
      policyCap: policy.maxPassesPerFrame,
      effectiveCap: Math.max(1, Math.min(graph.maxPassesPerFrame || policy.maxPassesPerFrame, policy.maxPassesPerFrame)),
      frameBudget: framePassBudgetFor(policy),
      executed: survivors.length,
      truncated: Math.max(0, requested - survivors.length),
      keepsColorWriter: hasColorWriter ? survivors.some((d) => d.writes.includes('color')) : null,
      dispatches: survivors.map((d) => dispatchLabel(d.nodeId, d.iteration, repeats.get(d.nodeId) ?? 1)),
    };
  });
}

export function analyzeGraph(
  graph: MultipassGraphDef,
  options: { knownEntries?: Set<string> } = {},
): GraphAnalysis {
  const diagnostics = diagnoseGraph(graph, options.knownEntries ? { knownEntries: options.knownEntries } : undefined);
  const errors = diagnostics.filter((d) => d.severity === 'error');
  const warnings = diagnostics.filter((d) => d.severity === 'warning');
  const safe = sanitize(graph);
  const requested = safe.nodes.reduce((sum, n) => sum + (n.repeat ?? 1), 0);

  const rows = safe.nodes.length > 0 ? buildRows(safe) : [];
  const barrierByNode = new Map<string, number>();
  for (const row of rows) barrierByNode.set(row.nodeId, (barrierByNode.get(row.nodeId) ?? 0) + row.barriers.length);

  const nodes: NodeCost[] = safe.nodes.map((n, index) => ({
    index,
    nodeId: n.id,
    entry: n.entry,
    passes: n.repeat ?? 1,
    share: requested > 0 ? (n.repeat ?? 1) / requested : 0,
    scalable: !!n.scalable,
    barriers: barrierByNode.get(n.id) ?? 0,
  }));

  return {
    diagnostics,
    errors,
    warnings,
    valid: errors.length === 0,
    usesSimRing: graphUsesSimRing(graph),
    requested,
    ceiling: graph.maxPassesPerFrame,
    rows,
    nodes,
    barrierCount: rows.reduce((sum, r) => sum + r.barriers.length, 0),
    // An invalid graph is never encoded, so there is nothing to preview.
    caps: errors.length === 0 && safe.nodes.length > 0 ? buildCaps(safe, requested) : [],
  };
}
