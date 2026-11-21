/**
 * useOfflineRender.ts — VJ Studio → Render (#1401): export a recorded set frame-accurately.
 *
 * Holds the render settings, the size estimate and the job's progress; the job itself
 * (TimelinePlayer → renderFrameAt → WebCodecs → mp4 / webm) lives in the lazy
 * "gpu-encode" chunk and is loaded on the first Render click.
 */

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { RendererManager } from '../renderer/RendererManager';
import type { InputSource, RenderMode, ShaderEntry, SlotParams } from '../renderer/types';
import { isGpuEncodeAvailable, loadGpuEncoder } from '../recording/gpuEncodeSupport';
import {
  CONTAINER_CODECS,
  estimateOfflineBytes,
  frameCountFor,
  offlineBitrate,
  resolvePresetSize,
  type OfflineCodecChoice,
  type OfflineContainer,
  type OfflineQuality,
  type ResolutionPreset,
} from '../recording/offlineExportPlan';
import type { OfflineRenderHost, OfflineRenderProgress } from '../recording/offlineRenderJob';
import { decodeAudioFile, type DecodedAudio } from '../services/offlineAudio';
import type { TimelineSource, VjTimeline } from '../services/vjSetExport';
import { takeSnapshot } from '../services/vjSetRecorder';
import { resolveShaderId } from '../utils/resolveShaderId';

export interface OfflineRenderSettings {
  preset: ResolutionPreset['id'];
  customWidth: number;
  customHeight: number;
  fps: number;
  container: OfflineContainer;
  codec: OfflineCodecChoice;
  quality: OfflineQuality;
}

export type OfflineRenderStatus = 'idle' | 'preparing' | 'rendering' | 'finalizing' | 'done' | 'cancelled' | 'error';

export interface OfflineRenderOutcome {
  fileName: string;
  frames: number;
  codec: string;
  /** Object URL of the in-memory file; null when it was streamed to disk. */
  downloadUrl: string | null;
  failedShaders: string[];
}

export interface UseOfflineRenderOptions {
  getRenderer?: () => RendererManager | null;
  timeline: VjTimeline | null;
  modes: RenderMode[];
  slotParams: SlotParams[];
  availableModes: ShaderEntry[];
  inputSource: InputSource;
  /** The generative source's shader id (used while inputSource is 'generative'). */
  activeGenerativeShader?: string;
  currentImageUrl?: string;
  /** The live source, the base state before the set's first source event. */
  getSource: () => TimelineSource | null;
  /** Live set playback must stop while a render owns the renderer. */
  onBeforeRender?: () => void;
  fileBaseName?: string;
}

export interface UseOfflineRenderReturn {
  settings: OfflineRenderSettings;
  updateSettings: (patch: Partial<OfflineRenderSettings>) => void;
  /** Codecs the chosen container can hold (auto first). */
  codecChoices: OfflineCodecChoice[];
  supported: boolean;
  unsupportedReason: string | null;
  maxDimension: number;
  output: { width: number; height: number };
  estimate: { frames: number; durationSec: number; bitrate: number; bytes: number };
  status: OfflineRenderStatus;
  progress: OfflineRenderProgress | null;
  error: string | null;
  outcome: OfflineRenderOutcome | null;
  audio: { name: string; durationSec: number } | null;
  loadAudio: (file: File) => Promise<void>;
  clearAudio: () => void;
  start: () => Promise<void>;
  cancel: () => void;
  busy: boolean;
}

const DEFAULT_SETTINGS: OfflineRenderSettings = {
  preset: '1080p',
  customWidth: 1920,
  customHeight: 1080,
  fps: 60,
  container: 'mp4',
  codec: 'auto',
  quality: 'high',
};

type SavePicker = (options: {
  suggestedName?: string;
  types?: Array<{ description: string; accept: Record<string, string[]> }>;
}) => Promise<{ createWritable(): Promise<FileSystemWritableFileStream> }>;

function slug(name: string): string {
  return name.trim().replace(/\s+/g, '-').replace(/[^a-z0-9._-]/gi, '').toLowerCase() || 'vj-set';
}

export function useOfflineRender(options: UseOfflineRenderOptions): UseOfflineRenderReturn {
  const [settings, setSettings] = useState<OfflineRenderSettings>(DEFAULT_SETTINGS);
  const [status, setStatus] = useState<OfflineRenderStatus>('idle');
  const [progress, setProgress] = useState<OfflineRenderProgress | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [outcome, setOutcome] = useState<OfflineRenderOutcome | null>(null);
  const [audio, setAudio] = useState<(DecodedAudio & { name: string }) | null>(null);
  const abortRef = useRef<AbortController | null>(null);
  const optsRef = useRef(options);
  optsRef.current = options;

  // Revoke the last in-memory file when it is replaced or the panel goes away.
  useEffect(() => () => {
    if (outcome?.downloadUrl) URL.revokeObjectURL(outcome.downloadUrl);
  }, [outcome]);
  useEffect(() => () => abortRef.current?.abort(), []);

  const renderer = options.getRenderer?.() ?? null;
  const supported = !!renderer?.supportsOfflineRender() && isGpuEncodeAvailable();
  const unsupportedReason = !isGpuEncodeAvailable()
    ? 'This browser has no WebCodecs VideoEncoder.'
    : !renderer?.supportsOfflineRender()
      ? 'Offline render needs the TypeScript WebGPU renderer (not ?renderer=wasm / js).'
      : null;
  const maxDimension = renderer?.getMaxTextureDimension2D() || 8192;
  const canvas = renderer?.getOutputSize() ?? { width: 1920, height: 1080 };
  const output = resolvePresetSize(
    settings.preset,
    canvas,
    { width: settings.customWidth, height: settings.customHeight },
    maxDimension,
  );

  const durationMs = options.timeline?.durationMs ?? 0;
  const estimate = useMemo(() => {
    const frames = frameCountFor(durationMs, settings.fps);
    const codec = settings.codec === 'auto' ? CONTAINER_CODECS[settings.container][0] ?? 'h264' : settings.codec;
    const bitrate = offlineBitrate(output.width, output.height, settings.fps, codec, settings.quality);
    const durationSec = frames / settings.fps;
    return { frames, durationSec, bitrate, bytes: estimateOfflineBytes(bitrate, durationSec) };
  }, [durationMs, settings.fps, settings.codec, settings.container, settings.quality, output.width, output.height]);

  const updateSettings = useCallback((patch: Partial<OfflineRenderSettings>) => {
    setSettings((prev) => {
      const next = { ...prev, ...patch };
      // A codec the new container cannot hold falls back to auto.
      if (next.codec !== 'auto' && !CONTAINER_CODECS[next.container].includes(next.codec)) next.codec = 'auto';
      return next;
    });
  }, []);

  const loadAudio = useCallback(async (file: File) => {
    setError(null);
    try {
      const decoded = await decodeAudioFile(await file.arrayBuffer());
      setAudio({ ...decoded, name: file.name });
    } catch (e) {
      setError(`Could not decode "${file.name}": ${e instanceof Error ? e.message : String(e)}`);
    }
  }, []);

  const cancel = useCallback(() => abortRef.current?.abort(), []);

  const start = useCallback(async () => {
    const o = optsRef.current;
    const manager = o.getRenderer?.() ?? null;
    const timeline = o.timeline;
    if (!manager || !timeline || abortRef.current) return;
    setError(null);
    setOutcome(null);
    const ext = settings.container;
    const fileName = `${slug(o.fileBaseName ?? 'vj-set')}-${output.width}x${output.height}-${settings.fps}fps.${ext}`;

    // The picker needs the click's user activation: ask before anything slow.
    let stream: FileSystemWritableFileStream | null = null;
    const picker = (window as Window & { showSaveFilePicker?: SavePicker }).showSaveFilePicker;
    if (typeof picker === 'function') {
      try {
        const handle = await picker({
          suggestedName: fileName,
          types: [{ description: ext === 'mp4' ? 'MP4 video' : 'WebM video', accept: { [ext === 'mp4' ? 'video/mp4' : 'video/webm']: [`.${ext}`] } }],
        });
        stream = await handle.createWritable();
      } catch (e) {
        if (e instanceof DOMException && e.name === 'AbortError') return; // the user closed the picker
        stream = null; // no permission / not allowed here: build the file in memory instead
      }
    }

    const controller = new AbortController();
    abortRef.current = controller;
    o.onBeforeRender?.();
    setStatus('preparing');
    setProgress(null);
    const resolveShader = (id: string) => o.availableModes.find((s) => s.id === resolveShaderId(id));
    const job = manager.offlineJobControls();
    const host: OfflineRenderHost = {
      beginOfflineRender: (opts) => manager.beginOfflineRender(opts),
      renderFrameAt: (t, input) => manager.renderFrameAt(t, input),
      endOfflineRender: () => manager.endOfflineRender(),
      loadShader: async (id) => {
        const entry = resolveShader(id);
        return entry ? manager.loadShader(entry.id, entry.url) : false;
      },
      setSlotShader: (i, id) => job.setSlotShader(i, id ? resolveShaderId(id) : ''),
      setInputSource: (source) => job.setInputSource(source),
      setGenerator: async (id) => {
        const entry = id ? resolveShader(id) : undefined;
        if (id && !entry) return;
        await job.setGenerator(entry ? entry.id : null, entry ? { url: entry.url } : undefined);
      },
      loadImage: (url) => job.loadImage(url),
      reloadInputStill: () => manager.reloadInputStill(),
      restoreLive: async () => {
        const live = optsRef.current;
        await manager.resyncShaderStack({
          modes: live.modes,
          slotParams: live.slotParams,
          resolveShader,
          inputSource: live.inputSource,
        });
        const liveGenerator = live.inputSource === 'generative'
          ? (live.activeGenerativeShader ? resolveShader(live.activeGenerativeShader) : undefined)
          : undefined;
        await manager.setGenerator(
          liveGenerator ? liveGenerator.id : null,
          liveGenerator ? { url: liveGenerator.url } : undefined,
        );
        if (live.inputSource === 'image' && live.currentImageUrl) await manager.loadImage(live.currentImageUrl);
        else await manager.reloadInputStill();
      },
    };

    let lastUi = 0;
    try {
      const mod = await loadGpuEncoder();
      const result = await mod.runOfflineRender(host, {
        timeline,
        base: takeSnapshot(o.modes, o.slotParams, o.getSource()),
        width: output.width,
        height: output.height,
        fps: settings.fps,
        container: settings.container,
        codec: settings.codec,
        quality: settings.quality,
        stream,
        audio: audio ?? null,
        signal: controller.signal,
        onProgress: (p) => {
          const t = performance.now();
          if (p.phase !== 'rendering' || t - lastUi > 100 || p.frame === p.totalFrames) {
            lastUi = t;
            setStatus(p.phase);
            setProgress(p);
          }
        },
      });
      let downloadUrl: string | null = null;
      if (result.blob) {
        downloadUrl = URL.createObjectURL(result.blob);
        const a = document.createElement('a');
        a.href = downloadUrl;
        a.download = fileName;
        a.click();
      }
      setOutcome({
        fileName,
        frames: result.frames,
        codec: `${result.codec.id.toUpperCase()} (${result.codec.codec})`,
        downloadUrl,
        failedShaders: result.failedShaders,
      });
      setStatus('done');
    } catch (e) {
      if (e instanceof Error && e.name === 'OfflineRenderCancelled') {
        setStatus('cancelled');
      } else {
        setError(e instanceof Error ? e.message : String(e));
        setStatus('error');
      }
    } finally {
      abortRef.current = null;
    }
  }, [settings, output.width, output.height, audio]);

  const busy = status === 'preparing' || status === 'rendering' || status === 'finalizing';
  return {
    settings,
    updateSettings,
    codecChoices: ['auto', ...CONTAINER_CODECS[settings.container]],
    supported,
    unsupportedReason,
    maxDimension,
    output,
    estimate,
    status,
    progress,
    error,
    outcome,
    audio: audio ? { name: audio.name, durationSec: audio.durationSec } : null,
    loadAudio,
    clearAudio: () => setAudio(null),
    start,
    cancel,
    busy,
  };
}
