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

const COMPOSITOR_SLOT_KEYS = ['b', 'o', 'm', 'f', 'k'];

/**
 * v1 → v2 (#1512): the envelope is unchanged and every v1 slot is a `replace` slot, so
 * the step only bumps the version. A v1 slot never had compositor keys (its validator
 * rejected them); any that appear anyway are dropped rather than trusted.
 *
 * `stripCompositorKeys: false` is for v0 input lifted through v1: a bare SharedChain or
 * VJ-set export from this build carries the keys legitimately (chain URLs, `.vjset.json`),
 * and the v2 validator sanitizes them like any other v2 chain.
 */
export function migrateV1ToV2(v1: ProjectFileV1, stripCompositorKeys = true): ProjectFile {
  const chain = stripCompositorKeys && isRecord(v1.chain) && Array.isArray(v1.chain.slots)
    ? {
        ...v1.chain,
        slots: v1.chain.slots.map((slot) => {
          if (!isRecord(slot)) return slot;
          const copy: Record<string, unknown> = { ...slot };
          for (const key of COMPOSITOR_SLOT_KEYS) delete copy[key];
          return copy as unknown as typeof slot;
        }),
      }
    : v1.chain;
  return { ...v1, chain, schemaVersion: PROJECT_FILE_SCHEMA_VERSION };
}

/**
 * Migrate one version at a time toward the current project format.
 *
 * v0 is the pair of pre-project portable formats: a bare SharedChain or a bare
 * VjSetExportPayload. v1 (#1393) becomes v2 (#1512). Current v2 input is returned
 * unchanged and is validated by the caller after migration.
 */
export function migrateProjectFile(
  raw: unknown,
  now: () => Date = () => new Date(),
): ProjectMigrationResult {
  if (!isRecord(raw)) return { project: null, reason: 'Project data must be an object' };

  if ('schemaVersion' in raw) {
    if (raw.schemaVersion === 1) return { project: migrateV1ToV2(raw as unknown as ProjectFileV1) };
    if (raw.schemaVersion !== PROJECT_FILE_SCHEMA_VERSION) {
      return { project: null, reason: `Unsupported project schema version: ${String(raw.schemaVersion)}` };
    }
    return { project: raw as unknown as ProjectFile };
  }

  // v0 SharedChain: the chain's own `v` remains untouched inside the envelope.
  if (typeof raw.v === 'number' && Array.isArray(raw.slots)) {
    return { project: migrateV1ToV2(makeV1(raw as unknown as SharedChain, now().toISOString()), false) };
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
    return { project: migrateV1ToV2(project, false) };
  }

  return { project: null, reason: 'Unrecognized project file or legacy export format' };
}
