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
  GraphNodeDef,
  GraphRole,
  graphUsesSimRing,
  MAX_REPEAT,
  MultipassGraphDef,
  NODE_SCALE_LEVELS,
  SIM_BUFFER_ROLES,
  TEXTURE_ROLES,
} from '../renderer/multipassGraph';

/** Roles the editor lets a user toggle: the ones with defined runtime behaviour. */
export const EDITABLE_READ_ROLES = ['read', 'dataA', 'dataB', 'dataC'] as const;
export const EDITABLE_WRITE_ROLES = ['color', 'dataA', 'dataB'] as const;

export type RoleSide = 'reads' | 'writes';

export const DEFAULT_MAX_PASSES = 8;
export const DEFAULT_CATEGORY = 'simulation';
const DEFAULT_ID = 'my-graph';

export interface GraphDraft {
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
}

export function newDraft(overrides: Partial<Pick<GraphDraft, 'id' | 'name' | 'category'>> = {}): GraphDraft {
  return {
    id: DEFAULT_ID,
    name: 'My Graph',
    category: DEFAULT_CATEGORY,
    envelope: {},
    multipassExtra: {},
    graph: { maxPassesPerFrame: DEFAULT_MAX_PASSES, nodes: [] },
    ...overrides,
  };
}

/** Sim-ring graphs need the group-1 ring armed from a definition: view-only in v1. */
export function isSimRingDraft(draft: GraphDraft): boolean {
  return graphUsesSimRing(draft.graph) || draft.envelope.simRing !== undefined;
}

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

/**
 * Append (or insert at `index`) a node for `entry`. The first color writer gets
 * `color`; later nodes default to a simulation step (dataC → dataA).
 */
export function addNode(draft: GraphDraft, entry: string, index = draft.graph.nodes.length): GraphDraft {
  const nodes = draft.graph.nodes.slice();
  const hasColorWriter = nodes.some((n) => (n.writes ?? []).includes('color'));
  const node: GraphNodeDef = {
    id: uniqueNodeId(nodes, entry),
    entry,
    reads: ['dataC'],
    writes: hasColorWriter ? ['dataA'] : ['color', 'dataA'],
  };
  const at = clampInt(index, 0, nodes.length, nodes.length);
  nodes.splice(at, 0, node);
  return withGraph(draft, nodes);
}

export function removeNodeAt(draft: GraphDraft, index: number): GraphDraft {
  if (index < 0 || index >= draft.graph.nodes.length) return draft;
  return withGraph(draft, draft.graph.nodes.filter((_, i) => i !== index));
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
  return withGraph(draft, nodes);
}

export function moveNode(draft: GraphDraft, from: number, to: number): GraphDraft {
  const nodes = draft.graph.nodes.slice();
  if (from < 0 || from >= nodes.length) return draft;
  const target = clampInt(to, 0, nodes.length - 1, from);
  if (target === from) return draft;
  const [moved] = nodes.splice(from, 1);
  nodes.splice(target, 0, moved);
  return withGraph(draft, nodes);
}

export function setNodeEntry(draft: GraphDraft, index: number, entry: string): GraphDraft {
  const node = draft.graph.nodes[index];
  return node ? replaceNode(draft, index, { ...node, entry }) : draft;
}

export function setNodeId(draft: GraphDraft, index: number, id: string): GraphDraft {
  const node = draft.graph.nodes[index];
  return node ? replaceNode(draft, index, { ...node, id }) : draft;
}

/** Toggle one editable role. Roles outside the editable set are left exactly as they are. */
export function toggleRole(draft: GraphDraft, index: number, side: RoleSide, role: GraphRole): GraphDraft {
  const node = draft.graph.nodes[index];
  const editable: readonly string[] = side === 'reads' ? EDITABLE_READ_ROLES : EDITABLE_WRITE_ROLES;
  if (!node || !editable.includes(role)) return draft;
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

export function setMaxPasses(draft: GraphDraft, maxPassesPerFrame: number): GraphDraft {
  return withGraph(draft, draft.graph.nodes.slice(), clampInt(maxPassesPerFrame, 1, 4096, DEFAULT_MAX_PASSES));
}

export function setMeta(draft: GraphDraft, meta: Partial<Pick<GraphDraft, 'id' | 'name' | 'category'>>): GraphDraft {
  return { ...draft, ...meta };
}

// ── Import ──────────────────────────────────────────────────────────────────

export type DraftImport = { ok: true; draft: GraphDraft } | { ok: false; error: string };

const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);

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
      id: draftId,
      name: typeof name === 'string' && name ? name : draftId,
      category: DEFAULT_CATEGORY,
      envelope: cloneJson(envelope),
      multipassExtra: cloneJson(multipassExtra),
      sourceId: typeof id === 'string' ? id : undefined,
      graph,
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
    id: shaderId,
    name: entry?.name ?? shaderId,
    category: entry?.category && entry.category !== 'shader' ? entry.category : DEFAULT_CATEGORY,
    envelope,
    multipassExtra: {},
    sourceId: shaderId,
    graph: cloneJson(graph),
  };
}

/** A starting copy of an existing draft under a new id (the Lab's "fork"). */
export function forkDraft(draft: GraphDraft, id: string, name: string): GraphDraft {
  return { ...draft, id, name, sourceId: undefined, graph: cloneJson(draft.graph) };
}
