/**
 * graphExport.ts
 *
 * Draft → shader-definition JSON, in the format the repo already consumes:
 * `shader_definitions/<category>/<id>.json` with `multipass.graph`
 * (docs/MULTIPASS_GRAPH.md). `scripts/buildMultipassRegistry.js` copies that
 * graph verbatim into GRAPH_REGISTRY, so nothing here is hand-translated.
 *
 * Export refuses a draft the planner would refuse: any error diagnostic, or an
 * id that cannot be a catalog id.
 */

import { GRAPH_REGISTRY } from '../renderer/multipassRegistry';
import { GRAPH_LAB_RUNTIME_ID } from '../renderer/runtimeGraphs';
import { analyzeGraph } from './graphAnalysis';
import { entryStem, EntryCatalog } from './entryCatalog';
import { GraphDraft } from './graphDraft';

/** The `shader_definitions/` folders; the folder is the catalog category. */
export const EXPORT_CATEGORIES = [
  'advanced-hybrid',
  'artistic',
  'distortion',
  'generative',
  'geometric',
  'hybrid',
  'image',
  'interactive-mouse',
  'lighting-effects',
  'liquid-effects',
  'post-processing',
  'retro-glitch',
  'simulation',
  'visual-effects',
] as const;

const ID_PATTERN = /^[a-z0-9][a-z0-9-]*$/;

export interface ExportNote {
  code: 'replaces-existing' | 'hides-catalog-entry' | 'drift-baseline' | 'sim-ring-untouched' | 'no-params';
  message: string;
}

export interface ExportContext {
  /** Entry catalog (for the hidden-from-lists warning). Omit while the catalog is loading. */
  entries?: EntryCatalog | null;
  /**
   * Catalog ids that already exist (a clash is an error unless the draft replaces
   * its own source). Defaults to the entry catalog's ids.
   */
  existingIds?: ReadonlySet<string>;
}

export type ExportResult =
  | {
      ok: true;
      definition: Record<string, unknown>;
      json: string;
      /** Where the file belongs in the repo. */
      path: string;
      notes: ExportNote[];
    }
  | { ok: false; errors: string[]; notes: ExportNote[] };

const RESERVED_ENVELOPE = new Set(['id', 'name', 'url', 'multipass']);

function usesSimTextures(draft: GraphDraft): boolean {
  return draft.graph.nodes.some((n) =>
    [...(n.reads ?? []), ...(n.writes ?? [])].some((r) => r === 'dataA' || r === 'dataB' || r === 'dataC'),
  );
}

/** Root WGSL of the definition: the draft's own url when it still names a node entry, else the first entry. */
function rootUrl(draft: GraphDraft): string {
  const entries = draft.graph.nodes.map((n) => n.entry);
  const kept = typeof draft.envelope.url === 'string' ? draft.envelope.url : null;
  if (kept && entries.includes(entryStem(kept))) return kept;
  return `shaders/${entries[0]}.wgsl`;
}

export function exportGraphDefinition(draft: GraphDraft, context: ExportContext = {}): ExportResult {
  const errors: string[] = [];
  const notes: ExportNote[] = [];
  const known = context.entries?.knownEntries;
  const analysis = analyzeGraph(draft.graph, known ? { knownEntries: known } : {});

  for (const d of analysis.errors) errors.push(d.message);

  if (!ID_PATTERN.test(draft.id)) {
    errors.push('id must be lowercase letters, digits and hyphens, starting with a letter or digit');
  } else if (draft.id === GRAPH_LAB_RUNTIME_ID) {
    errors.push(`id "${GRAPH_LAB_RUNTIME_ID}" is reserved for the running draft`);
  } else {
    const existing = context.existingIds ?? context.entries?.catalogIds;
    const exists = !!existing?.has(draft.id) || draft.id in GRAPH_REGISTRY;
    if (exists && draft.id !== draft.sourceId) {
      errors.push(`id "${draft.id}" already exists in the catalog; pick another or start from it to replace it`);
    } else if (exists) {
      notes.push({
        code: 'replaces-existing',
        message: `This replaces shader_definitions entry "${draft.id}" when you overwrite its file.`,
      });
    }
  }
  if (!draft.name.trim()) errors.push('name is required');
  if (!(EXPORT_CATEGORIES as readonly string[]).includes(draft.category)) {
    errors.push(`category must be one of the shader_definitions folders: ${EXPORT_CATEGORIES.join(', ')}`);
  }

  if (errors.length > 0 || draft.graph.nodes.length === 0) {
    return { ok: false, errors, notes };
  }

  // Entries that are catalog shaders drop out of the lists once used as graph entries.
  const hidden = new Set<string>();
  const secondaries = new Set(draft.graph.nodes.map((n) => n.entry).filter((e) => e !== draft.id));
  for (const entry of secondaries) {
    if (context.entries?.catalogIds.has(entry)) hidden.add(entry);
  }
  for (const entry of Array.from(hidden).sort()) {
    notes.push({
      code: 'hides-catalog-entry',
      message: `"${entry}" is a catalog shader. Used as a graph entry it becomes a secondary and drops out of the shader lists (scripts/generate_shader_lists.js).`,
    });
  }
  if (secondaries.size > 0) {
    notes.push({
      code: 'drift-baseline',
      message:
        'New graph entries without their own definition appear in the catalog drift audit: run python3 scripts/audit_catalog_consistency.py --ensure-lists --write-baseline.',
    });
  }
  if (analysis.usesSimRing || draft.envelope.simRing !== undefined) {
    notes.push({
      code: 'sim-ring-untouched',
      message: 'Sim-ring fields are exported exactly as imported; the Lab cannot edit or run them in v1.',
    });
  }
  if (draft.envelope.params === undefined) {
    notes.push({
      code: 'no-params',
      message: 'No params are exported, so the four zoom_params sliders are not listed; add them by hand if the entries use them.',
    });
  }

  const envelope = Object.fromEntries(Object.entries(draft.envelope).filter(([key]) => !RESERVED_ENVELOPE.has(key)));
  // Defaults only for a graph started from scratch. An imported or forked definition is exported
  // exactly as it came (adding `requiresRgba32Float` would change how a shipped shader is allocated).
  const fresh = Object.keys(envelope).length === 0;
  const definition: Record<string, unknown> = {
    id: draft.id,
    name: draft.name.trim(),
    url: rootUrl(draft),
    ...(fresh
      ? {
          description: 'Tier C graph authored in the Graph Lab.',
          ...(usesSimTextures(draft) ? { requiresRgba32Float: true } : {}),
          features: ['simulation', 'multi-pass', 'graph-runner'],
          tags: ['simulation', 'graph'],
        }
      : {}),
    ...envelope,
    multipass: { ...draft.multipassExtra, graph: draft.graph },
  };

  return {
    ok: true,
    definition,
    json: `${JSON.stringify(definition, null, 2)}\n`,
    path: `shader_definitions/${draft.category}/${draft.id}.json`,
    notes,
  };
}
