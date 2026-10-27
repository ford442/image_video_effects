import { useCallback } from 'react';
import type { RenderQualityMode } from '../config/performancePolicy';
import type { InputSource, RenderMode, ShaderEntry, SlotMode, SlotParams } from '../renderer/types';
import type { SlotLayer } from '../renderer/layerState';
import type { HdrToneMapSettings } from '../services/hdrOutput';
import type { VideoRecord } from '../syncTypes';
import type { ImageRecord } from '../types/aiVj';
import type { ControlBinding } from '../services/controlBindings';
import { buildSharedChain, type SharedChain } from '../services/layerChainShare';
import {
  buildVjSetExport,
  type VjSetExportPayload,
  type VjTimeline,
} from '../services/vjSetExport';
import {
  buildProjectFile,
  createProjectApplyPlan,
  parseProjectFile,
  serializeProjectFile,
  type ProjectApplyPlan,
  type ProjectSource,
} from '../services/project';

export interface UseProjectFileOptions {
  modes: RenderMode[];
  slotParams: SlotParams[];
  /** Per-slot chained/parallel + compositing (#1512, project schema v2). */
  slotModes?: SlotMode[];
  slotLayers?: SlotLayer[];
  /** HDR canvas tonemap (render.hdr). */
  hdrToneMap?: HdrToneMapSettings;
  setHdrToneMap?: (settings: HdrToneMapSettings) => void;
  activeSlot: number;
  inputSource: InputSource;
  currentImageUrl?: string;
  imageManifest: ImageRecord[];
  selectedVideo: string;
  videoList: VideoRecord[];
  liveStreamUrl?: string;
  activeGenerativeShader?: string;
  renderQualityMode: RenderQualityMode;
  bindings: ControlBinding[];
  timeline: VjTimeline | null;
  recorderState: 'idle' | 'recording' | 'playing';
  availableModes: ShaderEntry[];
  applySharedChain: (chain: SharedChain) => void;
  setActiveSlot: (index: number) => void;
  setInputSource: (source: InputSource) => void;
  setSelectedVideo: (video: string) => void;
  setActiveGenerativeShader?: (id: string) => void;
  startWebcam?: () => void;
  loadImage: (url: string) => Promise<void>;
  loadStream?: (url: string) => void;
  setRenderQuality?: (mode: RenderQualityMode) => void;
  setBindings: (bindings: ControlBinding[]) => void;
  setTimeline: (timeline: VjTimeline | null) => void;
}

export interface ProjectImportOutcome {
  ok: boolean;
  errors: string[];
  warnings: string[];
}

export interface UseProjectFileReturn {
  exportProject: () => { contents: string; filename: string };
  importProject: (serialized: string) => Promise<ProjectImportOutcome>;
}

function captureSource(options: UseProjectFileOptions): ProjectSource {
  switch (options.inputSource) {
    case 'image':
      return options.currentImageUrl
        ? { kind: 'image', ref: options.currentImageUrl }
        : { kind: 'none' };
    case 'video':
      return options.selectedVideo
        ? { kind: 'video', ref: options.selectedVideo }
        : { kind: 'none' };
    case 'webcam':
      return { kind: 'webcam' };
    case 'generative':
      return options.activeGenerativeShader
        ? { kind: 'generative', generativeShaderId: options.activeGenerativeShader }
        : { kind: 'none' };
    case 'live':
      return options.liveStreamUrl
        ? { kind: 'stream', ref: options.liveStreamUrl }
        : { kind: 'none' };
  }
}

function makeFilename(createdAt: string): string {
  return `pixelocity-project-${createdAt.slice(0, 10)}.pixelocity.json`;
}

async function applyPlan(plan: ProjectApplyPlan, options: UseProjectFileOptions): Promise<string[]> {
  const warnings = [...plan.warnings];

  // The plan is complete before this first setter runs. Reuse share-chain
  // expansion/application so projects cannot drift into a third stack model.
  options.applySharedChain(plan.chain);
  options.setActiveSlot(plan.activeSlot);
  if (plan.render.quality) options.setRenderQuality?.(plan.render.quality);
  if (plan.render.hdr) options.setHdrToneMap?.(plan.render.hdr);
  if (plan.audio?.mappings) options.setBindings(plan.audio.mappings);
  if (plan.timeline?.timeline) options.setTimeline(plan.timeline.timeline);

  try {
    switch (plan.source.kind) {
      case 'image':
        if (plan.source.ref) {
          await options.loadImage(plan.source.ref);
          options.setInputSource('image');
        }
        break;
      case 'video':
        if (plan.source.ref) {
          options.setSelectedVideo(plan.source.ref);
          options.setInputSource('video');
        }
        break;
      case 'webcam':
        options.startWebcam?.();
        break;
      case 'generative':
        if (plan.source.generativeShaderId) {
          options.setActiveGenerativeShader?.(plan.source.generativeShaderId);
          options.setInputSource('generative');
        }
        break;
      case 'stream':
        if (plan.source.ref && options.loadStream) {
          options.loadStream(plan.source.ref);
          options.setInputSource('live');
        }
        break;
      case 'none':
        break;
    }
  } catch {
    warnings.push('The saved media could not be loaded; relink the source.');
  }
  return warnings;
}

export function useProjectFile(options: UseProjectFileOptions): UseProjectFileReturn {
  const exportProject = useCallback(() => {
    const chain = buildSharedChain(options.modes, options.slotParams, {
      slotModes: options.slotModes,
      layers: options.slotLayers,
    });
    let timeline: VjSetExportPayload | undefined;
    if (options.timeline && options.recorderState !== 'recording') {
      timeline = buildVjSetExport('Project recording', chain, {
        bindings: options.bindings,
        timeline: options.timeline,
      });
    }
    const project = buildProjectFile({
      chain,
      activeSlot: options.activeSlot,
      source: captureSource(options),
      quality: options.renderQualityMode,
      hdr: options.hdrToneMap,
      audioMappings: options.bindings,
      timeline,
    });
    return {
      contents: serializeProjectFile(project),
      filename: makeFilename(project.createdAt),
    };
  }, [options]);

  const importProject = useCallback(async (serialized: string): Promise<ProjectImportOutcome> => {
    const parsed = parseProjectFile(serialized);
    if (!parsed.ok) return { ok: false, errors: parsed.errors, warnings: [] };

    const imageRefs = new Set(options.imageManifest.map(image => image.url));
    if (options.currentImageUrl) imageRefs.add(options.currentImageUrl);
    const videoRefs = new Set<string>();
    options.videoList.forEach(video => {
      videoRefs.add(video.url);
      if (video.id) videoRefs.add(video.id);
    });
    if (options.selectedVideo) videoRefs.add(options.selectedVideo);

    const plan = createProjectApplyPlan(parsed.project, {
      knownShaderIds: new Set(options.availableModes.map(mode => mode.id)),
      isMediaRefAvailable: source => {
        if (!source.ref) return false;
        if (source.kind === 'image') return imageRefs.has(source.ref);
        if (source.kind === 'video') return videoRefs.has(source.ref);
        if (source.kind === 'stream') return !!options.loadStream;
        return true;
      },
    });
    const warnings = await applyPlan(plan, options);
    if (parsed.migrationReason) warnings.unshift(parsed.migrationReason);
    return { ok: true, errors: [], warnings };
  }, [options]);

  return { exportProject, importProject };
}
