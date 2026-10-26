import type { RenderQualityMode } from '../../config/performancePolicy';
import type { ControlBinding } from '../controlBindings';
import type { SharedChain } from '../layerChainShare';
import type { VjSetExportPayload } from '../vjSetExport';

/** v2 (#1512): chain slots may carry compositor output fields (b / o / m / f / k). */
export const PROJECT_FILE_SCHEMA_VERSION = 2 as const;
export const PROJECT_APP_NAME = 'pixelocity' as const;

export type ProjectSourceKind = 'image' | 'video' | 'webcam' | 'generative' | 'stream' | 'none';

export interface ProjectSource {
  kind: ProjectSourceKind;
  /** URL or catalog id only. Media bytes, blob URLs, and device identifiers are forbidden. */
  ref?: string;
  generativeShaderId?: string;
}

export interface ProjectRenderSettings {
  /** Reserved for a future independently-settable app scale. Current exports omit it. */
  renderScale?: number;
  quality?: RenderQualityMode;
}

export interface ProjectAudioSettings {
  mappings?: ControlBinding[];
}

/** The first project format (#1393): no compositor fields on chain slots. */
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

/** Current format: v1 plus per-slot compositor output in the chain (layerChainShare.ts). */
export interface ProjectFileV2 extends Omit<ProjectFileV1, 'schemaVersion'> {
  schemaVersion: typeof PROJECT_FILE_SCHEMA_VERSION;
}

export type ProjectFile = ProjectFileV2;

export interface ProjectBuildState {
  chain: SharedChain;
  activeSlot: number;
  source: ProjectSource;
  quality?: RenderQualityMode;
  audioMappings?: ControlBinding[];
  timeline?: VjSetExportPayload;
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
  warnings: string[];
}

export type ProjectValidationResult =
  | { ok: true; project: ProjectFile }
  | { ok: false; errors: string[] };

export type ProjectMigrationResult =
  | { project: ProjectFile; reason?: undefined }
  | { project: null; reason: string };

export type ProjectParseResult =
  | { ok: true; project: ProjectFile; migrationReason?: string }
  | { ok: false; errors: string[] };
