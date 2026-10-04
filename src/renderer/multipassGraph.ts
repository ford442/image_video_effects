/**
 * multipassGraph.ts
 *
 * Graph builder + validator for Tier C multipass simulations.
 * JSON-aligned types; registry populated by buildMultipassRegistry.js.
 */

export type TextureRole = 'read' | 'color' | 'dataA' | 'dataB' | 'dataC';

export const TEXTURE_ROLES: readonly TextureRole[] = [
  'read', 'color', 'dataA', 'dataB', 'dataC',
] as const;

/**
 * Group-1 sim-ring buffer roles (src/contracts/bind_group1.json). `simState` is
 * the live agent buffer; `simIndex` is its read-only snapshot, refreshed by a
 * copyBufferToBuffer barrier — the buffer twin of dataA → dataC.
 */
export type SimBufferRole = 'simState' | 'simIndex';

export const SIM_BUFFER_ROLES: readonly SimBufferRole[] = ['simState', 'simIndex'] as const;

export type GraphRole = TextureRole | SimBufferRole;

/** `pixels` dispatches ceil(W/wg.x)×ceil(H/wg.y); `simState` dispatches ceil(stateCount/wg.x)×1. */
export type GraphDispatchDomain = 'pixels' | 'simState';

export const MAX_REPEAT = 64;

/** Allowed per-node resolution scales (#1314); 1 = full working size. */
export const NODE_SCALE_LEVELS = [0.25, 0.5, 0.75, 1] as const;

export interface GraphNodeDef {
  id: string;
  entry: string;
  reads: GraphRole[];
  writes: GraphRole[];
  repeat?: number;
  /** Dispatch domain; defaults to `pixels`. */
  dispatch?: GraphDispatchDomain;
  /**
   * Opt-in (#1314): this node may run below the working size. The renderer
   * resamples its inputs into scratch textures, patches `config.zw` to the
   * scaled size, and resamples declared writes back. Only for nodes whose
   * output tolerates resampling (fields, blurs, tensors), not per-pixel sims.
   */
  scalable?: boolean;
  /** Lowest scale adaptive demotion may pick (one of NODE_SCALE_LEVELS; default 0.5). */
  minScale?: number;
}

export interface MultipassGraphDef {
  maxPassesPerFrame: number;
  nodes: GraphNodeDef[];
}

export type CopyBarrier =
  | { from: 'dataA' | 'dataB'; to: 'dataC'; reason: string }
  | { from: 'simState'; to: 'simIndex'; reason: string };

export interface ExpandedDispatch {
  nodeId: string;
  entry: string;
  reads: GraphRole[];
  writes: GraphRole[];
  iteration: number;
  copiesBefore: CopyBarrier[];
  dispatch: GraphDispatchDomain;
  scalable?: boolean;
  minScale?: number;
}

export interface GraphShaderRecord {
  shaderId: string;
  graph: MultipassGraphDef;
}

function isTextureRole(v: string): v is TextureRole {
  return (TEXTURE_ROLES as readonly string[]).includes(v);
}

function isGraphRole(v: string): v is GraphRole {
  return isTextureRole(v) || (SIM_BUFFER_ROLES as readonly string[]).includes(v);
}

/** True when any node touches the group-1 sim ring or dispatches over simState. */
export function graphUsesSimRing(graph: MultipassGraphDef): boolean {
  return graph.nodes.some(
    (n) =>
      n.dispatch === 'simState' ||
      [...(n.reads ?? []), ...(n.writes ?? [])].some((r) =>
        (SIM_BUFFER_ROLES as readonly string[]).includes(r),
      ),
  );
}

/**
 * simIndex freshness. It is stale at frame start (simState persists across
 * frames and may have been written since the last snapshot), becomes fresh
 * after a copy, and goes stale again on every simState write.
 */
interface SimIndexState {
  fresh: boolean;
}

function simCopiesBeforeRead(reads: GraphRole[], sim: SimIndexState): CopyBarrier[] {
  if (!reads.includes('simIndex') || sim.fresh) return [];
  sim.fresh = true;
  return [{ from: 'simState', to: 'simIndex', reason: 'simState → simIndex snapshot' }];
}

function applySimWrites(writes: GraphRole[], sim: SimIndexState): void {
  if (writes.includes('simState')) sim.fresh = false;
}

/** Roles that hold simulation state across intra-frame handoff. */
const SIM_ROLES: TextureRole[] = ['dataA', 'dataB', 'dataC'];

function totalPassCount(graph: MultipassGraphDef): number {
  return graph.nodes.reduce((sum, n) => sum + (n.repeat ?? 1), 0);
}

/**
 * Track which sim role holds the freshest data after each expanded dispatch.
 * `dataC` is seeded from the previous frame before the graph runs.
 */
function applyWrites(
  state: Map<TextureRole, TextureRole | 'frameSeed'>,
  writes: GraphRole[],
): void {
  const primary = writes.find((w): w is TextureRole => SIM_ROLES.includes(w as TextureRole));
  if (!primary) return;
  state.set(primary, primary);
  // Writing dataA or dataB invalidates stale dataC sample until copy.
  if (primary === 'dataA' || primary === 'dataB') {
    state.set('dataC', primary);
  }
}

function copiesNeededBeforeRead(
  reads: GraphRole[],
  state: Map<TextureRole, TextureRole | 'frameSeed'>,
): CopyBarrier[] {
  const copies: CopyBarrier[] = [];
  const needsSimRead = reads.some((r) => r === 'dataC' || r === 'dataA' || r === 'dataB');
  if (!needsSimRead) return copies;

  // Prefer an explicit storage role when the reader declares exactly one of
  // dataA/dataB. Lets a later sibling write (e.g. tear → dataB) keep living in
  // its own buffer while we still sample the earlier producer via dataC
  // (fabric-of-reality: positions in A, strain mask in B).
  const wantsA = reads.includes('dataA') && !reads.includes('dataB');
  const wantsB = reads.includes('dataB') && !reads.includes('dataA');
  if (wantsA && state.get('dataA') === 'dataA') {
    const cStale = state.get('dataC');
    if (cStale !== 'dataC') {
      copies.push({ from: 'dataA', to: 'dataC', reason: 'dataA → dataC (preferred read)' });
      state.set('dataC', 'dataC');
    }
    return copies;
  }
  if (wantsB && state.get('dataB') === 'dataB') {
    const cStale = state.get('dataC');
    if (cStale !== 'dataC') {
      copies.push({ from: 'dataB', to: 'dataC', reason: 'dataB → dataC (preferred read)' });
      state.set('dataC', 'dataC');
    }
    return copies;
  }

  const cStale = state.get('dataC');
  if (cStale === 'dataA') {
    copies.push({ from: 'dataA', to: 'dataC', reason: 'dataA → dataC handoff' });
    state.set('dataC', 'dataC');
  } else if (cStale === 'dataB') {
    copies.push({ from: 'dataB', to: 'dataC', reason: 'dataB → dataC handoff' });
    state.set('dataC', 'dataC');
  }
  return copies;
}

function alternateWrite(writes: GraphRole[], iteration: number): GraphRole[] {
  if (iteration === 0) return writes;
  const hasA = writes.includes('dataA');
  const hasB = writes.includes('dataB');
  if (!hasA || !hasB) return writes;
  if (iteration % 2 === 1) {
    return writes.map((w) => (w === 'dataA' ? 'dataB' : w === 'dataB' ? 'dataA' : w));
  }
  return writes;
}

export function validateGraph(
  graph: MultipassGraphDef,
  options?: { knownEntries?: Set<string> },
): string[] {
  const errors: string[] = [];

  if (!graph.maxPassesPerFrame || graph.maxPassesPerFrame < 1) {
    errors.push('graph.maxPassesPerFrame must be >= 1');
  }
  if (!graph.nodes || graph.nodes.length === 0) {
    errors.push('graph must have at least one node');
    return errors;
  }

  const passCount = totalPassCount(graph);
  if (graph.maxPassesPerFrame && passCount > graph.maxPassesPerFrame) {
    errors.push(
      `graph exceeds maxPassesPerFrame: ${passCount} > ${graph.maxPassesPerFrame}`,
    );
  }

  for (const node of graph.nodes) {
    if (!node.id) errors.push('node.id is required');
    if (!node.entry) errors.push(`node ${node.id}: entry is required`);
    if (options?.knownEntries && node.entry && !options.knownEntries.has(node.entry)) {
      errors.push(`node ${node.id}: unknown entry "${node.entry}"`);
    }
    const repeat = node.repeat ?? 1;
    if (repeat < 1 || repeat > MAX_REPEAT) {
      errors.push(`node ${node.id}: repeat must be 1–${MAX_REPEAT}`);
    }
    for (const r of node.reads ?? []) {
      if (!isGraphRole(r)) errors.push(`node ${node.id}: invalid read role "${r}"`);
    }
    for (const w of node.writes ?? []) {
      if (!isGraphRole(w)) errors.push(`node ${node.id}: invalid write role "${w}"`);
      if (w === 'simIndex') {
        errors.push(`node ${node.id}: simIndex is read-only (written only by the simState → simIndex barrier)`);
      }
    }
    if (node.dispatch !== undefined && node.dispatch !== 'pixels' && node.dispatch !== 'simState') {
      errors.push(`node ${node.id}: invalid dispatch "${node.dispatch}" (pixels | simState)`);
    }
    if (!node.reads?.length && !node.writes?.length) {
      errors.push(`node ${node.id}: must declare reads or writes`);
    }
    if (node.minScale !== undefined && !(NODE_SCALE_LEVELS as readonly number[]).includes(node.minScale)) {
      errors.push(`node ${node.id}: minScale must be one of ${NODE_SCALE_LEVELS.join(', ')}`);
    }
    if (node.scalable && node.dispatch === 'simState') {
      errors.push(`node ${node.id}: simState dispatches cannot be scalable`);
    }
  }

  // Dependency / cycle check via simulated expansion
  const state = new Map<TextureRole, TextureRole | 'frameSeed'>();
  state.set('dataC', 'frameSeed');

  for (const node of graph.nodes) {
    const repeat = node.repeat ?? 1;
    for (let i = 0; i < repeat; i++) {
      const writes = alternateWrite(node.writes ?? [], i);
      const reads = node.reads ?? [];

      for (const role of reads) {
        if (!SIM_ROLES.includes(role as TextureRole)) continue;
        const available = state.get(role as TextureRole);
        if (role === 'dataC' && available === 'frameSeed') continue;
        if (role === 'dataC' && (available === 'dataA' || available === 'dataB')) continue;
        if (available === role || available === 'frameSeed') continue;
        if (role === 'dataA' && state.get('dataC') === 'dataA') continue;
        if (role === 'dataB' && state.get('dataC') === 'dataB') continue;
        if (available === undefined) {
          errors.push(
            `node ${node.id} iter ${i}: reads "${role}" before any producer in this frame`,
          );
        }
      }

      const copies = copiesNeededBeforeRead(reads, new Map(state));
      if (copies.length === 0) {
        for (const role of reads) {
          if (
            SIM_ROLES.includes(role as TextureRole) &&
            state.get(role as TextureRole) === undefined &&
            role !== 'dataC'
          ) {
            const viaC = state.get('dataC');
            if (viaC !== role && viaC !== 'dataA' && viaC !== 'dataB' && viaC !== 'frameSeed') {
              errors.push(`node ${node.id} iter ${i}: cannot satisfy read "${role}"`);
            }
          }
        }
      }

      copiesNeededBeforeRead(reads, state);
      applyWrites(state, writes);
    }
  }

  return errors;
}

/** Flatten repeat nodes and compute copy barriers between dispatches. */
export function expandGraph(graph: MultipassGraphDef): ExpandedDispatch[] {
  const result: ExpandedDispatch[] = [];
  const state = new Map<TextureRole, TextureRole | 'frameSeed'>();
  state.set('dataC', 'frameSeed');
  const sim: SimIndexState = { fresh: false };

  for (const node of graph.nodes) {
    const repeat = node.repeat ?? 1;
    for (let i = 0; i < repeat; i++) {
      const reads = [...(node.reads ?? [])];
      const writes = alternateWrite(node.writes ?? [], i);
      const copiesBefore = [
        ...copiesNeededBeforeRead(reads, state),
        ...simCopiesBeforeRead(reads, sim),
      ];

      result.push({
        nodeId: node.id,
        entry: node.entry,
        reads,
        writes,
        iteration: i,
        copiesBefore,
        dispatch: node.dispatch ?? 'pixels',
        ...(node.scalable ? { scalable: true, minScale: node.minScale ?? 0.5 } : {}),
      });

      applyWrites(state, writes);
      applySimWrites(writes, sim);
    }
  }

  return result;
}

export function countGraphPasses(graph: MultipassGraphDef): number {
  return totalPassCount(graph);
}

function lastColorWriterIndex(nodes: GraphNodeDef[]): number {
  for (let i = nodes.length - 1; i >= 0; i--) {
    if ((nodes[i].writes ?? []).includes('color')) return i;
  }
  return -1;
}

/**
 * Shrink a graph to fit `cap` dispatches without dropping the display pass.
 * 1. Reduce `repeat` on earlier iterative nodes first.
 * 2. Drop non-color nodes nearest the color writer.
 * 3. Only then reduce the color node's own repeat.
 * Graphs with no color writer fall back to a prefix slice of the expanded list.
 */
export function shrinkGraphToCap(graph: MultipassGraphDef, cap: number): MultipassGraphDef {
  const safeCap = Math.max(1, cap);
  const nodes: GraphNodeDef[] = graph.nodes.map((n) => ({
    ...n,
    reads: [...(n.reads ?? [])],
    writes: [...(n.writes ?? [])],
    repeat: n.repeat ?? 1,
  }));

  const passCount = () => nodes.reduce((sum, n) => sum + (n.repeat ?? 1), 0);

  if (lastColorWriterIndex(nodes) < 0) {
    // No display pass — keep the original node list; caller prefix-slices.
    return { maxPassesPerFrame: graph.maxPassesPerFrame, nodes: graph.nodes };
  }

  while (passCount() > safeCap) {
    let reduced = false;
    const colorIdx = lastColorWriterIndex(nodes);
    for (let i = 0; i < nodes.length; i++) {
      if (i === colorIdx) continue;
      const r = nodes[i].repeat ?? 1;
      if (r > 1) {
        nodes[i].repeat = r - 1;
        reduced = true;
        break;
      }
    }
    if (!reduced) break;
  }

  while (passCount() > safeCap && nodes.length > 1) {
    const colorIdx = lastColorWriterIndex(nodes);
    let drop = -1;
    for (let i = colorIdx - 1; i >= 0; i--) {
      drop = i;
      break;
    }
    if (drop < 0 && colorIdx < nodes.length - 1) {
      drop = nodes.length - 1;
    }
    if (drop < 0) break;
    nodes.splice(drop, 1);
  }

  while (passCount() > safeCap) {
    const colorIdx = lastColorWriterIndex(nodes);
    if (colorIdx < 0) break;
    const r = nodes[colorIdx].repeat ?? 1;
    if (r <= 1) break;
    nodes[colorIdx].repeat = r - 1;
  }

  return { maxPassesPerFrame: graph.maxPassesPerFrame, nodes };
}

/** Apply graph ceiling + quality pass budget, keeping the color write when possible. */
export function capGraphDispatches(
  graph: MultipassGraphDef,
  maxPassesPerFrame: number,
): ExpandedDispatch[] {
  const cap = Math.max(1, Math.min(graph.maxPassesPerFrame || maxPassesPerFrame, maxPassesPerFrame));
  const full = expandGraph(graph);
  if (full.length <= cap) return full;

  if (lastColorWriterIndex(graph.nodes) < 0) {
    return full.slice(0, cap);
  }

  const shrunk = shrinkGraphToCap(graph, cap);
  const expanded = expandGraph(shrunk);
  if (expanded.length <= cap) return expanded;
  return expanded.slice(Math.max(0, expanded.length - cap));
}

interface GraphPlanCache {
  errors: string[];
  requested: number;
  byCap: Map<number, ExpandedDispatch[]>;
}

/** Graph defs are static registry objects: validate / expand / cap once, not per frame. */
const graphPlans = new WeakMap<MultipassGraphDef, GraphPlanCache>();

function graphPlan(graph: MultipassGraphDef): GraphPlanCache {
  let plan = graphPlans.get(graph);
  if (!plan) {
    plan = { errors: validateGraph(graph), requested: countGraphPasses(graph), byCap: new Map() };
    graphPlans.set(graph, plan);
  }
  return plan;
}

/** validateGraph, memoized per graph def. */
export function graphPlanErrors(graph: MultipassGraphDef): string[] {
  return graphPlan(graph).errors;
}

/** countGraphPasses, memoized per graph def. */
export function graphRequestedPasses(graph: MultipassGraphDef): number {
  return graphPlan(graph).requested;
}

/** capGraphDispatches, memoized per (graph def, pass cap). Do not mutate the result. */
export function cappedDispatches(graph: MultipassGraphDef, maxPassesPerFrame: number): ExpandedDispatch[] {
  const plan = graphPlan(graph);
  let expanded = plan.byCap.get(maxPassesPerFrame);
  if (!expanded) {
    expanded = capGraphDispatches(graph, maxPassesPerFrame);
    plan.byCap.set(maxPassesPerFrame, expanded);
  }
  return expanded;
}

/** Demo / test fixture matching wave-tank graph shape. */
export function createWaveTankGraph(): MultipassGraphDef {
  return {
    maxPassesPerFrame: 8,
    nodes: [
      { id: 'step', entry: 'wave-step', reads: ['dataC'], writes: ['dataA'], repeat: 3 },
      { id: 'inject', entry: 'wave-inject', reads: ['dataA'], writes: ['dataB'] },
      { id: 'render', entry: 'wave-render', reads: ['dataB'], writes: ['color', 'dataA'] },
    ],
  };
}

/** @deprecated Use createWaveTankGraph — kept for existing tests during migration */
export function createRippleTankGraph(): MultipassGraphDef & { id: string } {
  return {
    id: 'quantum-foam-graph',
    maxPassesPerFrame: 8,
    nodes: [
      { id: 'integrate', entry: 'quantum-foam-pass1', reads: ['dataC'], writes: ['dataA'] },
      { id: 'composite', entry: 'quantum-foam-pass2', reads: ['dataA'], writes: ['dataB'] },
      { id: 'render', entry: 'quantum-foam-pass3', reads: ['dataB'], writes: ['color'] },
    ],
  };
}

// Re-export registry resolver — implemented in generated multipassRegistry.ts
export { resolveGraphForShader, GRAPH_REGISTRY } from './multipassRegistry';
