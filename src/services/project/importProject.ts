import { MAX_SHARED_SLOTS, type SharedChainSlot } from '../layerChainShare';
import { migrateProjectFile } from './migrate';
import type {
  ProjectApplyPlan,
  ProjectFile,
  ProjectParseResult,
  ProjectSource,
} from './types';
import { validateProjectFile } from './validate';
import { PROJECT_FILE_SCHEMA_VERSION } from './types';

export interface ProjectImportEnvironment {
  knownShaderIds: ReadonlySet<string>;
  /** Runtime/catalog availability check. URL fetching is deliberately not performed here. */
  isMediaRefAvailable?: (source: ProjectSource) => boolean;
}

/** Parse, migrate, and validate the whole document without touching live state. */
export function parseProjectFile(serialized: string): ProjectParseResult {
  if (!serialized.trim()) return { ok: false, errors: ['Project file is empty'] };
  let raw: unknown;
  try {
    raw = JSON.parse(serialized);
  } catch {
    return { ok: false, errors: ['Project file is not valid JSON'] };
  }

  const migrated = migrateProjectFile(raw);
  if (!migrated.project) return { ok: false, errors: [migrated.reason] };
  const validated = validateProjectFile(migrated.project);
  if (!validated.ok) return validated;
  const migrationReason = migrated.migratedFrom === 0
    ? `Imported legacy export as project schema v${PROJECT_FILE_SCHEMA_VERSION}`
    : migrated.migratedFrom !== undefined
      ? `Upgraded project schema v${migrated.migratedFrom} to v${PROJECT_FILE_SCHEMA_VERSION}`
      : undefined;
  return {
    ok: true,
    project: validated.project,
    ...(migrationReason ? { migrationReason } : {}),
  };
}

function sourcePlan(
  source: ProjectSource,
  env: ProjectImportEnvironment,
  warnings: string[],
): ProjectSource {
  if (source.kind === 'generative') {
    const id = source.generativeShaderId;
    if (id && (env.knownShaderIds.size === 0 || env.knownShaderIds.has(id))) return source;
    warnings.push(`Generative source "${id ?? ''}" is unavailable; relink the source.`);
    return { kind: 'none' };
  }

  if (source.kind === 'image' || source.kind === 'video' || source.kind === 'stream') {
    if (source.ref && (!env.isMediaRefAvailable || env.isMediaRefAvailable(source))) return source;
    warnings.push(`${source.kind} source "${source.ref ?? ''}" is unavailable; relink the source.`);
    return { kind: 'none' };
  }

  return source;
}

/**
 * Produce a complete, inert apply plan. Unknown catalog entries are converted
 * to explicit empty slots so applying the plan cannot retain stale live slots.
 */
export function createProjectApplyPlan(
  project: ProjectFile,
  env: ProjectImportEnvironment,
): ProjectApplyPlan {
  const warnings: string[] = [];
  const slots: SharedChainSlot[] = Array.from({ length: MAX_SHARED_SLOTS }, (_, index) => {
    const slot = project.chain.slots[index] ?? { shaderId: null };
    if (!slot.shaderId || env.knownShaderIds.size === 0 || env.knownShaderIds.has(slot.shaderId)) {
      return { ...slot, ...(slot.params ? { params: { ...slot.params } } : {}) };
    }
    warnings.push(`Unknown shader "${slot.shaderId}" in slot ${index + 1}; imported as an empty slot.`);
    return { shaderId: null };
  });

  return {
    chain: { v: project.chain.v, slots },
    activeSlot: project.activeSlot,
    source: sourcePlan(project.source, env, warnings),
    render: { ...project.render },
    ...(project.audio
      ? { audio: { ...(project.audio.mappings ? { mappings: [...project.audio.mappings] } : {}) } }
      : {}),
    ...(project.timeline ? { timeline: project.timeline } : {}),
    warnings,
  };
}
