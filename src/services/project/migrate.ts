import { parseVjSetExport } from '../vjSetExport';
import type { SharedChain } from '../layerChainShare';
import {
  PROJECT_APP_NAME,
  PROJECT_FILE_SCHEMA_VERSION,
  type ProjectFile,
  type ProjectFileV1,
  type ProjectMigrationResult,
} from './types';

const DEFAULT_APP_VERSION = process.env.REACT_APP_VERSION || '0.1.0';

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

function makeV1(chain: SharedChain, createdAt: string): ProjectFileV1 {
  return {
    schemaVersion: 1,
    app: { name: PROJECT_APP_NAME, version: DEFAULT_APP_VERSION },
    createdAt,
    chain,
    activeSlot: 0,
    source: { kind: 'none' },
    render: {},
  };
}

/**
 * v1 → v2 (#1512). v2 only adds optional fields (chain-slot compositor fields
 * b/o/m/k, render.hdr), and a v1 file cannot contain them, so the step is the
 * version bump: every v1 slot becomes a replace layer, which is what v1 rendered.
 */
export function migrateV1ToV2(project: ProjectFileV1): ProjectFile {
  return { ...project, schemaVersion: PROJECT_FILE_SCHEMA_VERSION };
}

/**
 * Migrate one version at a time toward the current project format.
 *
 * v0 is the pair of pre-project portable formats: a bare SharedChain or a bare
 * VjSetExportPayload, lifted into v1 and then stepped to v2. Current v2 input
 * is returned unchanged; the caller validates the result.
 */
export function migrateProjectFile(
  raw: unknown,
  now: () => Date = () => new Date(),
): ProjectMigrationResult {
  if (!isRecord(raw)) return { project: null, reason: 'Project data must be an object' };

  if ('schemaVersion' in raw) {
    if (raw.schemaVersion === PROJECT_FILE_SCHEMA_VERSION) return { project: raw as unknown as ProjectFile };
    if (raw.schemaVersion === 1) {
      return { project: migrateV1ToV2(raw as unknown as ProjectFileV1), migratedFrom: 1 };
    }
    return { project: null, reason: `Unsupported project schema version: ${String(raw.schemaVersion)}` };
  }

  // v0 SharedChain: the chain's own `v` remains untouched inside the envelope.
  if (typeof raw.v === 'number' && Array.isArray(raw.slots)) {
    return { project: migrateV1ToV2(makeV1(raw as unknown as SharedChain, now().toISOString())), migratedFrom: 0 };
  }

  // v0 VJ set export: preserve the entire payload for recorder playback while
  // promoting its chain and bindings to the project-level fields.
  if (raw.exportVersion === 1) {
    const parsed = parseVjSetExport(JSON.stringify(raw));
    if (!parsed) return { project: null, reason: 'Legacy VJ set payload is malformed' };
    const savedAt = Number.isFinite(parsed.savedAt) ? new Date(parsed.savedAt) : now();
    const project = makeV1(
      parsed.chain,
      Number.isFinite(savedAt.getTime()) ? savedAt.toISOString() : now().toISOString(),
    );
    if (parsed.bindings) project.audio = { mappings: parsed.bindings };
    project.timeline = parsed;
    return { project: migrateV1ToV2(project), migratedFrom: 0 };
  }

  return { project: null, reason: 'Unrecognized project file or legacy export format' };
}
