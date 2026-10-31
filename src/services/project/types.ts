import type { RenderQualityMode } from '../../config/performancePolicy';
import type { ControlBinding } from '../controlBindings';
import type { SharedChain } from '../layerChainShare';
import type { VjSetExportPayload } from '../vjSetExport';
import type { Route } from '../../modulation/types';

/**
 * v3 (#1513): `modulation` routes. v2 (#1512): chain slots carry compositor fields
 * b/o/m/k; render.hdr. Older files migrate one step at a time (migrate.ts).
 */
export const PROJECT_FILE_SCHEMA_VERSION = 3 as const;
export const PROJECT_APP_NAME = 'pixelocity' as const;

export type ProjectSourceKind = 'image' | 'video' | 'webcam' | 'generative' | 'stream' | 'none';

export interface ProjectSource {
  kind: ProjectSourceKind;
  /** URL or catalog id only. Media bytes, blob URLs, and device identifiers are forbidden. */
  ref?: string;
  generativeShaderId?: string;
}

/** Final tonemap of the HDR (rgba16float, extended) canvas; ignored on SDR output. */
export interface ProjectHdrSettings {
  /** Nits the working-space 1.0 maps to. */
  paperWhiteNits: number;
  /** Highest nits the tonemap rolls off toward. */
  peakNits: number;
}

export interface ProjectRenderSettings {
  /** Reserved for a future independently-settable app scale. Current exports omit it. */
  renderScale?: number;
  quality?: RenderQualityMode;
  /** v2+. */
  hdr?: ProjectHdrSettings;
}

export interface ProjectAudioSettings {
  mappings?: ControlBinding[];
}

/** Schema v1 (2026-10, #1393): no compositor fields, no render.hdr. Read-only: migrated to v2. */
export interface ProjectFileV1 {
  schemaVersion: 1;
  app: {
    name: typeof PROJECT_APP_NAME;
    version: string;
  };
  createdAt: string;
  chain: SharedChain;
  activeSlot: number;
  source: ProjectSource;
  render: ProjectRenderSettings;
  audio?: ProjectAudioSettings;
  /** Existing VJ-set payload embedded intact; its own version remains authoritative. */
  timeline?: VjSetExportPayload;
}

/** Schema v2 (#1512): same envelope; chain slots may carry b/o/m/k and render may carry hdr. Migrated to v3. */
export interface ProjectFileV2 extends Omit<ProjectFileV1, 'schemaVersion'> {
  schemaVersion: 2;
}

/** Schema v3 (#1513): adds the modulation bus routes (empty when nothing is modulated). */
export interface ProjectFileV3 extends Omit<ProjectFileV2, 'schemaVersion'> {
  schemaVersion: typeof PROJECT_FILE_SCHEMA_VERSION;
  modulation: Route[];
}

export type ProjectFile = ProjectFileV3;

export interface ProjectBuildState {
  chain: SharedChain;
  activeSlot: number;
  source: ProjectSource;
  quality?: RenderQualityMode;
  hdr?: ProjectHdrSettings;
  audioMappings?: ControlBinding[];
  timeline?: VjSetExportPayload;
  /** Modulation routes (v3); absent → none. */
  modulation?: Route[];
  appVersion?: string;
  createdAt?: string;
}

export interface ProjectApplyPlan {
  chain: SharedChain;
  activeSlot: number;
  source: ProjectSource;
  render: ProjectRenderSettings;
  audio?: ProjectAudioSettings;
  timeline?: VjSetExportPayload;
  /** Routes whose target slot exists in the imported chain. */
  modulation: Route[];
  warnings: string[];
}

export type ProjectValidationResult =
  | { ok: true; project: ProjectFile }
  | { ok: false; errors: string[] };

export type ProjectMigrationResult =
  /** `migratedFrom`: the version the input had (0 = a legacy chain / VJ-set export) when it was not current. */
  | { project: ProjectFile; reason?: undefined; migratedFrom?: number }
  | { project: null; reason: string; migratedFrom?: undefined };

export type ProjectParseResult =
  | { ok: true; project: ProjectFile; migrationReason?: string }
  | { ok: false; errors: string[] };
