/**
 * graphDraft.ts
 *
 * The Graph Lab's editable document. The graph itself is the renderer's own
 * `MultipassGraphDef` (no second schema); a draft only adds what a shader
 * definition needs around it (id, name, folder, passthrough fields).
 *
 * Every edit is pure and returns a NEW draft with a NEW graph object. The
 * renderer memoises validation / expansion / pass caps per graph object
 * (multipassGraph.ts), so editing in place would keep serving a stale plan.
 */

import {
  GraphDispatchDomain,
  GraphNodeDef,
  GraphRole,
  graphUsesSimRing,
  MAX_REPEAT,
  MultipassGraphDef,
  NODE_SCALE_LEVELS,
  SIM_BUFFER_ROLES,
  TEXTURE_ROLES,
} from '../renderer/multipassGraph';
import type { RuntimeSimRingRequest } from '../renderer/runtimeGraphs';
import { SIM_RING_DEFAULT_STATE_COUNT, SIM_RING_OOM_LADDER } from '../renderer/webgpu/simRing';

/** Roles the editor lets a user toggle: the ones with defined runtime behaviour. */
export const EDITABLE_READ_ROLES = ['read', 'dataA', 'dataB', 'dataC'] as const;
export const EDITABLE_WRITE_ROLES = ['color', 'dataA', 'dataB'] as const;
/** Added while the draft uses the group-1 sim ring (bind_group1.json; simIndex is barrier-written only). */
export const SIM_READ_ROLES = ['simState', 'simIndex'] as const;
export const SIM_WRITE_ROLES = ['simState'] as const;

export type RoleSide = 'reads' | 'writes';

export const DEFAULT_MAX_PASSES = 8;
export const DEFAULT_CATEGORY = 'simulation';
const DEFAULT_ID = 'my-graph';

/** Draft document version. v1 (no layout) is upgraded on load by `upgradeDraft`. */
export const GRAPH_DRAFT_VERSION = 2;

export interface NodePosition {
  x: number;
  y: number;
}

export interface GraphDraft {
  version: typeof GRAPH_DRAFT_VERSION;
  /** Catalog id the definition is exported under. */
  id: string;
  name: string;
  /** `shader_definitions/<category>/` folder (the folder is the catalog category). */
  category: string;
  /**
   * Top-level definition fields other than id / name / multipass (description,
   * params, features, tags, requiresRgba32Float, url, simRing, …). Kept so
   * editing an existing graph shader round-trips.
   */
  envelope: Record<string, unknown>;
  /** `multipass` fields besides `graph` (Tier B pass / totalPasses / nextShader). */
  multipassExtra: Record<string, unknown>;
  /** Id of the shader this draft was started from, if any (export may replace it). */
  sourceId?: string;
  graph: MultipassGraphDef;
  /**
   * Canvas position per node id. Editor-only: never exported, never seen by the
   * renderer. Execution order stays the node array order, not the layout.
   */
  layout: Record<string, NodePosition>;
}

export function newDraft(overrides: Partial<Pick<GraphDraft, 'id' | 'name' | 'category'>> = {}): GraphDraft {
  return {
    version: GRAPH_DRAFT_VERSION,
    id: DEFAULT_ID,
    name: 'My Graph',
    category: DEFAULT_CATEGORY,
    envelope: {},
    multipassExtra: {},
    graph: { maxPassesPerFrame: DEFAULT_MAX_PASSES, nodes: [] },
    layout: {},
    ...overrides,
  };
}

/**
 * A stored draft of any version as a current one: v1 drafts (no `version`, no
 * `layout`) get an empty layout, which the canvas fills with `autoLayout`.
 * Null when the value is not a draft at all.
 */
export function upgradeDraft(raw: unknown): GraphDraft | null {
  if (!isRecord(raw) || typeof raw.id !== 'string' || !isRecord(raw.graph) || !Array.isArray(raw.graph.nodes)) return null;
  if (typeof raw.version === 'number' && raw.version > GRAPH_DRAFT_VERSION) return null;
  const layout: Record<string, NodePosition> = {};
  if (isRecord(raw.layout)) {
    for (const [id, p] of Object.entries(raw.layout)) {
      if (isRecord(p) && Number.isFinite(p.x) && Number.isFinite(p.y)) layout[id] = { x: p.x as number, y: p.y as number };
    }
  }
  return { ...newDraft(), ...(raw as Partial<GraphDraft>), version: GRAPH_DRAFT_VERSION, layout };
}

// ── Layout ──────────────────────────────────────────────────────────────────

export const LAYOUT_COLUMN = 220;
export const LAYOUT_ROW = 110;

/**
 * Default position of node `index`: a left-to-right column per node in
 * execution order, rows zig-zagging so long chains stay readable.
 */
export function defaultNodePosition(index: number): NodePosition {
  return { x: LAYOUT_COLUMN * (index + 1), y: (index % 2) * LAYOUT_ROW };
}

/** Position of every node: stored, or the default for its index. */
export function resolvedLayout(draft: GraphDraft): NodePosition[] {
  return draft.graph.nodes.map((n, i) => draft.layout?.[n.id] ?? defaultNodePosition(i));
}

export function setNodePosition(draft: GraphDraft, nodeId: string, position: NodePosition): GraphDraft {
  if (!Number.isFinite(position.x) || !Number.isFinite(position.y)) return draft;
  const x = Math.round(position.x);
  const y = Math.round(position.y);
  const current = draft.layout?.[nodeId];
  if (current && current.x === x && current.y === y) return draft;
  return { ...draft, layout: { ...draft.layout, [nodeId]: { x, y } } };
}

/** Drop stored positions back to the default layout. */
export function resetLayout(draft: GraphDraft): GraphDraft {
  return Object.keys(draft.layout ?? {}).length === 0 ? draft : { ...draft, layout: {} };
}

/** True when the draft uses the group-1 sim ring (sim roles / simState dispatch, or a `simRing` request). */
export function isSimRingDraft(draft: GraphDraft): boolean {
  return graphUsesSimRing(draft.graph) || draft.envelope.simRing !== undefined;
}

/**
 * The ring size the draft asks for, as the renderer consumes a definition's
 * `simRing` field (only `stateCount`). Null when the draft does not use the ring;
 * a sim draft without an explicit count gets the contract default.
 */
export function simRingRequest(draft: GraphDraft): RuntimeSimRingRequest | null {
  if (!isSimRingDraft(draft)) return null;
  const raw = draft.envelope.simRing;
  const count = isRecord(raw) && typeof raw.stateCount === 'number' && raw.stateCount > 0 ? raw.stateCount : undefined;
  return { stateCount: count ?? SIM_RING_DEFAULT_STATE_COUNT };
}

/** Sizes the editor offers: the contract's OOM ladder (the ring allocates the largest rung that fits). */
export const SIM_STATE_COUNT_CHOICES: readonly number[] = SIM_RING_OOM_LADDER;

// ── Node ids ────────────────────────────────────────────────────────────────

function nodeIdBase(entry: string): string {
  const last = entry.split(/[-_]/).filter(Boolean).pop() ?? '';
  const slug = last.toLowerCase().replace(/[^a-z0-9]/g, '');
  return slug || 'node';
}

/** A node id not used by `nodes`, derived from the entry's last word. */
export function uniqueNodeId(nodes: readonly GraphNodeDef[], entry: string, ignoreIndex = -1): string {
  const taken = new Set(nodes.filter((_, i) => i !== ignoreIndex).map((n) => n.id));
  const base = nodeIdBase(entry);
  if (!taken.has(base)) return base;
  for (let n = 2; ; n++) {
    const candidate = `${base}-${n}`;
    if (!taken.has(candidate)) return candidate;
  }
}

// ── Internals ───────────────────────────────────────────────────────────────

const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);

function withGraph(draft: GraphDraft, nodes: GraphNodeDef[], maxPassesPerFrame = draft.graph.maxPassesPerFrame): GraphDraft {
  return { ...draft, graph: { maxPassesPerFrame, nodes } };
}

function replaceNode(draft: GraphDraft, index: number, node: GraphNodeDef): GraphDraft {
  if (index < 0 || index >= draft.graph.nodes.length) return draft;
  const nodes = draft.graph.nodes.slice();
  nodes[index] = node;
  return withGraph(draft, nodes);
}

const ROLE_ORDER: readonly GraphRole[] = [...TEXTURE_ROLES, ...SIM_BUFFER_ROLES];

function sortRoles(roles: GraphRole[]): GraphRole[] {
  return roles.slice().sort((a, b) => ROLE_ORDER.indexOf(a) - ROLE_ORDER.indexOf(b));
}

function clampInt(value: number, min: number, max: number, fallback: number): number {
  if (!Number.isFinite(value)) return fallback;
  return Math.min(max, Math.max(min, Math.round(value)));
}

// ── Edits ───────────────────────────────────────────────────────────────────

/** Roles for a new node, typically inferred from its WGSL (portInference.ts). */
export interface NodeRoles {
  reads: readonly GraphRole[];
  writes: readonly GraphRole[];
  dispatch?: GraphDispatchDomain;
}

/**
 * Append (or insert at `index`) a node for `entry`. With `roles` (what the
 * entry's WGSL binds) the node gets those, minus `color` when another node
 * already writes it, and a sim role turns the sim ring on. Without, the first
 * color writer gets `color`; later nodes default to a simulation step
 * (dataC → dataA).
 */
export function addNode(draft: GraphDraft, entry: string, index = draft.graph.nodes.length, roles?: NodeRoles): GraphDraft {
  const nodes = draft.graph.nodes.slice();
  const hasColorWriter = nodes.some((n) => (n.writes ?? []).includes('color'));
  const node: GraphNodeDef = roles
    ? {
        id: uniqueNodeId(nodes, entry),
        entry,
        reads: sortRoles([...roles.reads]),
        writes: sortRoles(roles.writes.filter((r) => !(hasColorWriter && r === 'color'))),
        ...(roles.dispatch === 'simState' ? { dispatch: 'simState' as const } : {}),
      }
    : {
        id: uniqueNodeId(nodes, entry),
        entry,
        reads: ['dataC'],
        writes: hasColorWriter ? ['dataA'] : ['color', 'dataA'],
      };
  const at = clampInt(index, 0, nodes.length, nodes.length);
  nodes.splice(at, 0, node);
  const next = withGraph(draft, nodes);
  return graphUsesSimRing(next.graph) && draft.envelope.simRing === undefined ? setSimRing(next, true) : next;
}

export function removeNodeAt(draft: GraphDraft, index: number): GraphDraft {
  const node = draft.graph.nodes[index];
  if (!node) return draft;
  const next = withGraph(draft, draft.graph.nodes.filter((_, i) => i !== index));
  if (!draft.layout?.[node.id] || next.graph.nodes.some((n) => n.id === node.id)) return next;
  const { [node.id]: _gone, ...layout } = draft.layout;
  return { ...next, layout };
}

export function duplicateNodeAt(draft: GraphDraft, index: number): GraphDraft {
  const source = draft.graph.nodes[index];
  if (!source) return draft;
  const copy: GraphNodeDef = {
    ...source,
    id: uniqueNodeId(draft.graph.nodes, source.entry),
    reads: [...(source.reads ?? [])],
    writes: [...(source.writes ?? [])],
  };
  const nodes = draft.graph.nodes.slice();
  nodes.splice(index + 1, 0, copy);
  const next = withGraph(draft, nodes);
  const from = draft.layout?.[source.id];
  return from ? { ...next, layout: { ...draft.layout, [copy.id]: { x: from.x + 40, y: from.y + 40 } } } : next;
}

export function moveNode(draft: GraphDraft, from: number, to: number): GraphDraft {
  const nodes = draft.graph.nodes.slice();
  if (from < 0 || from >= nodes.length) return draft;
  const target = clampInt(to, 0, nodes.length - 1, from);
  if (target === from) return draft;
  const [moved] = nodes.splice(from, 1);
  if (!moved) return draft;
  nodes.splice(target, 0, moved);
  return withGraph(draft, nodes);
}

export function setNodeEntry(draft: GraphDraft, index: number, entry: string): GraphDraft {
  const node = draft.graph.nodes[index];
  return node ? replaceNode(draft, index, { ...node, entry }) : draft;
}

export function setNodeId(draft: GraphDraft, index: number, id: string): GraphDraft {
  const node = draft.graph.nodes[index];
  if (!node) return draft;
  const next = replaceNode(draft, index, { ...node, id });
  // The position follows the node, unless another node still answers to the old id.
  const position = draft.layout?.[node.id];
  if (!position || draft.layout[id]) return next;
  const { [node.id]: _old, ...rest } = draft.layout;
  const shared = draft.graph.nodes.some((n, i) => i !== index && n.id === node.id);
  return { ...next, layout: shared ? { ...draft.layout, [id]: position } : { ...rest, [id]: position } };
}

/** Roles the editor offers on one side: the texture roles, plus the sim roles while the ring is on. */
export function editableRoles(draft: GraphDraft, side: RoleSide): readonly GraphRole[] {
  const sim = isSimRingDraft(draft);
  if (side === 'reads') return sim ? [...EDITABLE_READ_ROLES, ...SIM_READ_ROLES] : EDITABLE_READ_ROLES;
  return sim ? [...EDITABLE_WRITE_ROLES, ...SIM_WRITE_ROLES] : EDITABLE_WRITE_ROLES;
}

/** Toggle one editable role. Roles outside the editable set are left exactly as they are. */
export function toggleRole(draft: GraphDraft, index: number, side: RoleSide, role: GraphRole): GraphDraft {
  const node = draft.graph.nodes[index];
  if (!node || !editableRoles(draft, side).includes(role)) return draft;
  const current = node[side] ?? [];
  const next = current.includes(role) ? current.filter((r) => r !== role) : sortRoles([...current, role]);
  return replaceNode(draft, index, { ...node, [side]: next });
}

/** Repeat is a whole number in 1–64; anything else is clamped, never stored. */
export function setRepeat(draft: GraphDraft, index: number, repeat: number): GraphDraft {
  const node = draft.graph.nodes[index];
  if (!node) return draft;
  const value = clampInt(repeat, 1, MAX_REPEAT, 1);
  const { repeat: _old, ...rest } = node;
  return replaceNode(draft, index, value === 1 ? rest : { ...rest, repeat: value });
}

/** Opt a node in or out of per-node resolution scaling. */
export function setScalable(draft: GraphDraft, index: number, scalable: boolean, minScale?: number): GraphDraft {
  const node = draft.graph.nodes[index];
  if (!node) return draft;
  const { scalable: _s, minScale: _m, ...rest } = node;
  if (!scalable) return replaceNode(draft, index, rest);
  const levels = NODE_SCALE_LEVELS as readonly number[];
  // An invalid request keeps whatever floor the node already had.
  const keep = minScale !== undefined && levels.includes(minScale) ? minScale : node.minScale;
  const next: GraphNodeDef = { ...rest, scalable: true };
  if (keep !== undefined && levels.includes(keep) && keep < 1) next.minScale = keep;
  return replaceNode(draft, index, next);
}

/**
 * Dispatch domain of one node. `simState` needs the ring (the toggle turns it on
 * first) and cannot be scalable, so switching to it drops `scalable` / `minScale`.
 */
export function setNodeDispatch(draft: GraphDraft, index: number, domain: GraphDispatchDomain): GraphDraft {
  const node = draft.graph.nodes[index];
  if (!node) return draft;
  const { dispatch: _d, ...rest } = node;
  if (domain === 'pixels') return replaceNode(draft, index, rest);
  if (!isSimRingDraft(draft)) return draft;
  const { scalable: _s, minScale: _m, ...unscaled } = rest;
  return replaceNode(draft, index, { ...unscaled, dispatch: 'simState' });
}

/**
 * Turn the group-1 sim ring on (with a `simRing.stateCount` request) or off.
 * Off is refused while any node still uses a sim role or a simState dispatch:
 * the graph would keep needing the ring. Other `simRing` fields (agent, packing)
 * are kept while it stays on.
 */
export function setSimRing(draft: GraphDraft, enabled: boolean, stateCount?: number): GraphDraft {
  const { simRing: current, ...rest } = draft.envelope;
  if (!enabled) {
    if (graphUsesSimRing(draft.graph) || current === undefined) return draft;
    return { ...draft, envelope: rest };
  }
  const base = isRecord(current) ? current : {};
  const fallback = typeof base.stateCount === 'number' ? base.stateCount : SIM_RING_DEFAULT_STATE_COUNT;
  const count = stateCount !== undefined && SIM_STATE_COUNT_CHOICES.includes(stateCount) ? stateCount : fallback;
  return { ...draft, envelope: { ...rest, simRing: { ...base, stateCount: count } } };
}

export function setMaxPasses(draft: GraphDraft, maxPassesPerFrame: number): GraphDraft {
  return withGraph(draft, draft.graph.nodes.slice(), clampInt(maxPassesPerFrame, 1, 4096, DEFAULT_MAX_PASSES));
}

export function setMeta(draft: GraphDraft, meta: Partial<Pick<GraphDraft, 'id' | 'name' | 'category'>>): GraphDraft {
  return { ...draft, ...meta };
}

// ── Import ──────────────────────────────────────────────────────────────────

export type DraftImport = { ok: true; draft: GraphDraft } | { ok: false; error: string };

function cloneJson<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function parseGraph(raw: unknown): MultipassGraphDef | null {
  if (!isRecord(raw) || !Array.isArray(raw.nodes) || !raw.nodes.every(isRecord)) return null;
  return cloneJson(raw) as unknown as MultipassGraphDef;
}

/**
 * Accepts a shader definition (object, or the one-element array some files use)
 * with `multipass.graph`, or a bare `{ maxPassesPerFrame, nodes }` graph.
 */
export function draftFromDefinition(input: unknown): DraftImport {
  const def = Array.isArray(input) ? input[0] : input;
  if (!isRecord(def)) return { ok: false, error: 'Expected a JSON object (a shader definition or a graph).' };

  const bare = parseGraph(def);
  if (bare) return { ok: true, draft: { ...newDraft(), graph: bare } };

  const multipass = def.multipass;
  const graph = isRecord(multipass) ? parseGraph(multipass.graph) : null;
  if (!isRecord(multipass) || !graph) {
    return { ok: false, error: 'No multipass.graph with a nodes array found in that JSON.' };
  }

  const { id, name, multipass: _mp, ...envelope } = def;
  const { graph: _g, ...multipassExtra } = multipass;
  const draftId = typeof id === 'string' && id ? id : DEFAULT_ID;
  return {
    ok: true,
    draft: {
      version: GRAPH_DRAFT_VERSION,
      id: draftId,
      name: typeof name === 'string' && name ? name : draftId,
      category: DEFAULT_CATEGORY,
      envelope: cloneJson(envelope),
      multipassExtra: cloneJson(multipassExtra),
      sourceId: typeof id === 'string' ? id : undefined,
      graph,
      layout: {},
    },
  };
}

/** What a registry template needs from a catalog entry (a subset of ShaderEntry). */
export interface TemplateEntry {
  id: string;
  name?: string;
  url?: string;
  category?: string;
  description?: string;
  tags?: string[];
  params?: unknown[];
  features?: string[];
  requiresRgba32Float?: boolean;
}

/** Start from a registered graph (e.g. `wave-tank`), copying its catalog fields when known. */
export function draftFromRegistryGraph(
  shaderId: string,
  graph: MultipassGraphDef,
  entry?: TemplateEntry,
): GraphDraft {
  const envelope: Record<string, unknown> = {};
  if (entry?.url) envelope.url = entry.url;
  if (entry?.description) envelope.description = entry.description;
  if (entry?.params?.length) envelope.params = cloneJson(entry.params);
  if (entry?.requiresRgba32Float !== undefined) envelope.requiresRgba32Float = entry.requiresRgba32Float;
  if (entry?.features?.length) envelope.features = [...entry.features];
  if (entry?.tags?.length) envelope.tags = [...entry.tags];
  return {
    version: GRAPH_DRAFT_VERSION,
    id: shaderId,
    name: entry?.name ?? shaderId,
    category: entry?.category && entry.category !== 'shader' ? entry.category : DEFAULT_CATEGORY,
    envelope,
    multipassExtra: {},
    sourceId: shaderId,
    graph: cloneJson(graph),
    layout: {},
  };
}

/** A starting copy of an existing draft under a new id (the Lab's "fork"). */
export function forkDraft(draft: GraphDraft, id: string, name: string): GraphDraft {
  return { ...draft, id, name, sourceId: undefined, graph: cloneJson(draft.graph), layout: cloneJson(draft.layout ?? {}) };
}
