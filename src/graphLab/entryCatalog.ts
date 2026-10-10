/**
 * entryCatalog.ts
 *
 * Which WGSL files can a graph node point at? A node's `entry` is the file stem
 * under public/shaders/ (`wave-step` → shaders/wave-step.wgsl), which is NOT
 * the catalog id: graph secondaries (wave-step, wave-inject, …) are excluded
 * from the catalog lists, and 51 catalog shaders have a stem that differs from
 * their id. So the picker is built from three places:
 *   - catalog entries (stem of their `url`),
 *   - entries already used by registered graphs,
 *   - passes of Tier B linear chains.
 */

import { GRAPH_REGISTRY, MULTIPASS_REGISTRY } from '../renderer/multipassRegistry';

export type EntrySource = 'catalog' | 'graph-entry' | 'chain-pass';

export interface EntryOption {
  /** WGSL file stem — the value stored in `node.entry`. */
  entry: string;
  /** Human label: the catalog name, or the stem for secondaries. */
  label: string;
  source: EntrySource;
  /** Catalog shader id when this stem belongs to a catalog shader. */
  catalogId?: string;
  category?: string;
}

export interface EntryCatalog {
  options: EntryOption[];
  /** Every selectable entry stem (feed to `diagnoseGraph({ knownEntries })`). */
  knownEntries: Set<string>;
  /** Ids of catalog shaders: a graph entry with one of these ids is hidden from the lists on regeneration. */
  catalogIds: Set<string>;
  byEntry: Map<string, EntryOption>;
}

export interface CatalogShader {
  id: string;
  name: string;
  url: string;
  category?: string;
}

/** `shaders/kinetic_tiles.wgsl`, `https://host/p/x.wgsl?v=2` → `kinetic_tiles`, `x`. */
export function entryStem(url: string): string {
  const path = url.split(/[?#]/)[0];
  const file = path.slice(path.lastIndexOf('/') + 1);
  return file.replace(/\.wgsl$/i, '');
}

export function buildEntryCatalog(
  shaders: readonly CatalogShader[],
  registries: {
    graphs?: Record<string, { nodes: ReadonlyArray<{ entry: string }> }>;
    chains?: Record<string, { nextShader: string | null }>;
  } = { graphs: GRAPH_REGISTRY, chains: MULTIPASS_REGISTRY },
): EntryCatalog {
  const byEntry = new Map<string, EntryOption>();
  const catalogIds = new Set<string>();

  for (const shader of shaders) {
    catalogIds.add(shader.id);
    const stem = entryStem(shader.url);
    if (!stem || byEntry.has(stem)) continue;
    byEntry.set(stem, {
      entry: stem,
      label: shader.name || shader.id,
      source: 'catalog',
      catalogId: shader.id,
      category: shader.category,
    });
  }

  const addSecondary = (entry: string | null | undefined, source: EntrySource) => {
    if (!entry || byEntry.has(entry)) return;
    byEntry.set(entry, { entry, label: entry, source });
  };

  for (const graph of Object.values(registries.graphs ?? {})) {
    for (const node of graph.nodes) addSecondary(node.entry, 'graph-entry');
  }
  for (const [id, info] of Object.entries(registries.chains ?? {})) {
    addSecondary(id, 'chain-pass');
    addSecondary(info.nextShader, 'chain-pass');
  }

  const options = Array.from(byEntry.values()).sort((a, b) => a.entry.localeCompare(b.entry));
  return { options, knownEntries: new Set(byEntry.keys()), catalogIds, byEntry };
}

/**
 * Token-AND search over stem + label, stems that start with the query first.
 * An empty query returns the first `limit` options.
 */
export function searchEntries(catalog: EntryCatalog, query: string, limit = 50): EntryOption[] {
  const tokens = query.toLowerCase().split(/\s+/).filter(Boolean);
  if (tokens.length === 0) return catalog.options.slice(0, limit);
  const hits: Array<{ option: EntryOption; rank: number }> = [];
  for (const option of catalog.options) {
    const haystack = `${option.entry} ${option.label}`.toLowerCase();
    if (!tokens.every((t) => haystack.includes(t))) continue;
    hits.push({ option, rank: option.entry.toLowerCase().startsWith(tokens[0]) ? 0 : 1 });
  }
  hits.sort((a, b) => a.rank - b.rank || a.option.entry.localeCompare(b.option.entry));
  return hits.slice(0, limit).map((h) => h.option);
}
