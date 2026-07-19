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

export const MAX_REPEAT = 64;

export interface GraphNodeDef {
  id: string;
  entry: string;
  reads: TextureRole[];
  writes: TextureRole[];
  repeat?: number;
}

export interface MultipassGraphDef {
  maxPassesPerFrame: number;
  nodes: GraphNodeDef[];
}

export interface CopyBarrier {
  from: 'dataA' | 'dataB';
  to: 'dataC';
  reason: string;
}

export interface ExpandedDispatch {
  nodeId: string;
  entry: string;
  reads: TextureRole[];
  writes: TextureRole[];
  iteration: number;
  copiesBefore: CopyBarrier[];
}

export interface GraphShaderRecord {
  shaderId: string;
  graph: MultipassGraphDef;
}

function isTextureRole(v: string): v is TextureRole {
  return (TEXTURE_ROLES as readonly string[]).includes(v);
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
  writes: TextureRole[],
): void {
  const primary = writes.find((w) => SIM_ROLES.includes(w));
  if (!primary) return;
  state.set(primary, primary);
  // Writing dataA or dataB invalidates stale dataC sample until copy.
  if (primary === 'dataA' || primary === 'dataB') {
    state.set('dataC', primary);
  }
}

function copiesNeededBeforeRead(
  reads: TextureRole[],
  state: Map<TextureRole, TextureRole | 'frameSeed'>,
): CopyBarrier[] {
  const copies: CopyBarrier[] = [];
  const needsSimRead = reads.some((r) => r === 'dataC' || r === 'dataA' || r === 'dataB');
  if (!needsSimRead) return copies;

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

function alternateWrite(writes: TextureRole[], iteration: number): TextureRole[] {
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
      if (!isTextureRole(r)) errors.push(`node ${node.id}: invalid read role "${r}"`);
    }
    for (const w of node.writes ?? []) {
      if (!isTextureRole(w)) errors.push(`node ${node.id}: invalid write role "${w}"`);
    }
    if (!node.reads?.length && !node.writes?.length) {
      errors.push(`node ${node.id}: must declare reads or writes`);
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
        if (!SIM_ROLES.includes(role)) continue;
        const available = state.get(role);
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
          if (SIM_ROLES.includes(role) && state.get(role) === undefined && role !== 'dataC') {
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

  for (const node of graph.nodes) {
    const repeat = node.repeat ?? 1;
    for (let i = 0; i < repeat; i++) {
      const reads = [...(node.reads ?? [])];
      const writes = alternateWrite(node.writes ?? [], i);
      const copiesBefore = copiesNeededBeforeRead(reads, state);

      result.push({
        nodeId: node.id,
        entry: node.entry,
        reads,
        writes,
        iteration: i,
        copiesBefore,
      });

      applyWrites(state, writes);
    }
  }

  return result;
}

export function countGraphPasses(graph: MultipassGraphDef): number {
  return totalPassCount(graph);
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
