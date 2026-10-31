import { MAX_SHARED_SLOTS } from '../layerChainShare';
import { sanitizeBindings } from '../controlBindings';
import {
  PROJECT_APP_NAME,
  PROJECT_FILE_SCHEMA_VERSION,
  type ProjectBuildState,
  type ProjectFile,
  type ProjectSource,
} from './types';
import { isSafeProjectRef, validateProjectFile } from './validate';
import { toRoute } from '../../modulation/validate';

const DEFAULT_APP_VERSION = process.env.REACT_APP_VERSION || '0.1.0';

function safeSource(source: ProjectSource): ProjectSource {
  switch (source.kind) {
    case 'image':
    case 'video':
    case 'stream':
      return isSafeProjectRef(source.ref)
        ? { kind: source.kind, ref: source.ref.trim() }
        : { kind: 'none' };
    case 'generative':
      return typeof source.generativeShaderId === 'string'
        && source.generativeShaderId.trim().length > 0
        && source.generativeShaderId.length <= 128
        ? { kind: 'generative', generativeShaderId: source.generativeShaderId.trim() }
        : { kind: 'none' };
    case 'webcam':
      return { kind: 'webcam' };
    default:
      return { kind: 'none' };
  }
}

/** Build a current-version project by explicitly selecting portable session fields. */
export function buildProjectFile(state: ProjectBuildState): ProjectFile {
  const mappings = state.audioMappings ? sanitizeBindings(state.audioMappings) : [];
  return {
    schemaVersion: PROJECT_FILE_SCHEMA_VERSION,
    app: {
      name: PROJECT_APP_NAME,
      version: state.appVersion?.trim() || DEFAULT_APP_VERSION,
    },
    createdAt: state.createdAt ?? new Date().toISOString(),
    chain: state.chain,
    activeSlot: Math.max(0, Math.min(MAX_SHARED_SLOTS - 1, Math.floor(state.activeSlot))),
    source: safeSource(state.source),
    render: {
      ...(state.quality ? { quality: state.quality } : {}),
      ...(state.hdr ? { hdr: { paperWhiteNits: state.hdr.paperWhiteNits, peakNits: state.hdr.peakNits } } : {}),
    },
    ...(mappings.length > 0 ? { audio: { mappings } } : {}),
    ...(state.timeline ? { timeline: state.timeline } : {}),
    modulation: (state.modulation ?? []).map(toRoute),
  };
}

/** Serialize only a fully valid project file. */
export function serializeProjectFile(project: ProjectFile): string {
  const validated = validateProjectFile(project);
  if (!validated.ok) {
    throw new Error(`Cannot serialize invalid project file: ${validated.errors.join('; ')}`);
  }
  return JSON.stringify(validated.project, null, 2);
}
