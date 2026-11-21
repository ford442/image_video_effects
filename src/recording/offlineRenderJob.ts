/**
 * offlineRenderJob.ts — render a recorded VJ set to a file, frame by frame (#1401).
 * Part of the lazy "gpu-encode" chunk (re-exported by gpuEncoder.ts).
 *
 * For each output frame n (time t = start + n / fps):
 *   TimelinePlayer.stateAt(t)  → shaders per slot, params, source
 *   OfflineAudioAnalyser.at(n) → bass / mid / treble + 128 bins (if a soundtrack was given)
 *   OfflineVideoSource.frameAt → the source video frame at t (if the source is a video)
 *   renderer.renderFrameAt(t)  → the presented VideoFrame (stepped clock, no rAF)
 *   OfflineEncodeSession       → encoder → mp4 / webm muxer → file or Blob
 *
 * Nothing waits on rAF or timers, so a hidden tab or a GPU slower than real time only
 * changes how long the job takes. The frame count is exactly round(duration × fps) and
 * frame n is stamped n / fps: no drops, no duplicates.
 */

import {
  frameTimestampUs,
  type FrameInputSnapshot,
  type OfflineRenderInfo,
  type OfflineRenderOptions,
} from '../renderer/offlineRender';
import type { InputSource } from '../renderer/types';
import { OfflineAudioAnalyser, type DecodedAudio } from '../services/offlineAudio';
import { sourceMediaTimeSec, TimelinePlayer, type PlayerState } from '../services/timelinePlayer';
import { GPU_PARAM_KEYS, type TimelineSource, type VjTimeline } from '../services/vjSetExport';
import type { RecorderSnapshot } from '../services/vjSetRecorder';
import { OfflineEncodeSession, type OfflineEncoderDeps } from './offlineEncoder';
import {
  frameCountFor,
  type OfflineCodecCandidate,
  type OfflineCodecChoice,
  type OfflineContainer,
  type OfflineQuality,
} from './offlineExportPlan';
import { openOfflineVideoSource, type OfflineVideoSource } from './offlineVideoSource';

const SLOT_COUNT = 6;

/** What the job needs from the app (RendererManager + the shader catalog + React state). */
export interface OfflineRenderHost {
  beginOfflineRender(options: OfflineRenderOptions): Promise<OfflineRenderInfo>;
  renderFrameAt(timeSec: number, input: FrameInputSnapshot): Promise<VideoFrame | null>;
  endOfflineRender(): Promise<void>;
  /** Compile `id` from the catalog; false when unknown or it failed. */
  loadShader(id: string): Promise<boolean>;
  /** '' clears the slot. */
  setSlotShader(index: number, id: string): void;
  setInputSource(source: InputSource): void;
  /**
   * The generative source (Generative input mode): a shader id, or null to turn it off.
   * Optional: a host without a generator stage renders the recorded slots only.
   */
  setGenerator?(id: string | null): Promise<unknown> | void;
  loadImage(url: string): Promise<unknown>;
  /** Re-send the live still at the current render size. */
  reloadInputStill(): Promise<boolean>;
  /** Put the live stack, source and media back (after endOfflineRender). */
  restoreLive(): Promise<void>;
}

export interface OfflineRenderJobOptions {
  timeline: VjTimeline;
  /** State before the set's first events (the live stack and source at job start). */
  base?: RecorderSnapshot;
  width: number;
  height: number;
  fps: number;
  resolutionScale?: number;
  /** Render [startMs, startMs + durationMs) of the timeline (defaults: the whole set). */
  startMs?: number;
  durationMs?: number;
  container: OfflineContainer;
  codec: OfflineCodecChoice;
  quality: OfflineQuality;
  bitrate?: number;
  /** Stream the file here (File System Access); otherwise the result carries a Blob. */
  stream?: FileSystemWritableFileStream | null;
  /** Decoded soundtrack for audio-reactive shaders (video only: it is not muxed). */
  audio?: DecodedAudio | null;
  signal?: AbortSignal;
  onProgress?: (progress: OfflineRenderProgress) => void;
}

export interface OfflineRenderProgress {
  phase: 'preparing' | 'rendering' | 'finalizing';
  /** Frames finished. */
  frame: number;
  totalFrames: number;
  elapsedMs: number;
  /** Estimated time left (ms); null until a few frames are in. */
  etaMs: number | null;
  /** Frames rendered + encoded per second of wall time. */
  renderFps: number;
}

export interface OfflineRenderResult {
  blob: Blob | null;
  frames: number;
  durationSec: number;
  width: number;
  height: number;
  fps: number;
  codec: OfflineCodecCandidate;
  /** Shader ids that failed to compile (their slots rendered nothing). */
  failedShaders: string[];
}

export class OfflineRenderCancelled extends Error {
  constructor() {
    super('offline render cancelled');
    this.name = 'OfflineRenderCancelled';
  }
}

export interface OfflineRenderJobDeps {
  now?: () => number;
  encoder?: OfflineEncoderDeps;
  startEncoder?: typeof OfflineEncodeSession.start;
  openVideo?: (url: string) => Promise<OfflineVideoSource>;
  /** Sees every frame before it is encoded (tests, golden hashes); must not close it. */
  onFrame?: (frame: VideoFrame, index: number) => void | Promise<void>;
}

const sourceKey = (s: TimelineSource | null) => (s ? `${s.type}|${s.url ?? ''}|${s.shader ?? ''}` : '');

/** [slot, p1..p4] for every slot: missing params are the 0.5 defaults, as live. */
export function slotParamsFor(state: Pick<PlayerState, 'params'>): Array<[number, number, number, number, number]> {
  const out: Array<[number, number, number, number, number]> = [];
  for (let slot = 0; slot < SLOT_COUNT; slot++) {
    const p = state.params[slot] ?? {};
    const [a, b, c, d] = GPU_PARAM_KEYS.map((k) => p[k] ?? 0.5) as [number, number, number, number];
    out.push([slot, a, b, c, d]);
  }
  return out;
}

export async function runOfflineRender(
  host: OfflineRenderHost,
  options: OfflineRenderJobOptions,
  deps: OfflineRenderJobDeps = {},
): Promise<OfflineRenderResult> {
  const now = deps.now ?? (() => performance.now());
  const { fps, signal } = options;
  const startMs = Math.max(0, options.startMs ?? 0);
  const durationMs = Math.max(0, options.durationMs ?? options.timeline.durationMs - startMs);
  const totalFrames = frameCountFor(durationMs, fps);
  const t0 = now();
  const progress = (phase: OfflineRenderProgress['phase'], frame: number) => {
    const elapsedMs = now() - t0;
    const renderFps = frame > 0 && elapsedMs > 0 ? (frame * 1000) / elapsedMs : 0;
    options.onProgress?.({
      phase,
      frame,
      totalFrames,
      elapsedMs,
      etaMs: frame >= 3 && renderFps > 0 ? ((totalFrames - frame) / renderFps) * 1000 : null,
      renderFps,
    });
  };
  const throwIfCancelled = () => {
    if (signal?.aborted) throw new OfflineRenderCancelled();
  };

  throwIfCancelled();
  progress('preparing', 0);
  const start = deps.startEncoder ?? OfflineEncodeSession.start;
  const session = await start({
    width: options.width,
    height: options.height,
    fps,
    container: options.container,
    codec: options.codec,
    quality: options.quality,
    bitrate: options.bitrate,
    stream: options.stream ?? null,
  }, deps.encoder);
  if (!session) {
    throw new Error(`no ${options.container.toUpperCase()} encoder for ${options.codec} at ${options.width}×${options.height} @ ${fps} fps on this browser`);
  }

  const player = new TimelinePlayer(options.timeline, { base: options.base });
  const analyser = options.audio ? new OfflineAudioAnalyser(options.audio, fps, undefined, startMs / 1000) : null;
  const openVideo = deps.openVideo ?? openOfflineVideoSource;
  const failedShaders = new Set<string>();
  const loaded = new Set<string>();
  const appliedModes: Array<string | undefined> = new Array(SLOT_COUNT).fill(undefined);
  let appliedSource = '\u0000';
  let video: OfflineVideoSource | null = null;
  let began = false;
  let finished = false;

  const ensureShader = async (id: string): Promise<boolean> => {
    if (loaded.has(id)) return true;
    if (failedShaders.has(id)) return false;
    const ok = await host.loadShader(id);
    (ok ? loaded : failedShaders).add(id);
    return ok;
  };

  const applySource = async (state: PlayerState) => {
    const key = sourceKey(state.source);
    if (key === appliedSource) return;
    appliedSource = key;
    video?.close();
    video = null;
    const source = state.source;
    if (!source) return;
    if (source.type === 'image' && source.url) {
      await host.setGenerator?.(null);
      host.setInputSource('image');
      await host.loadImage(source.url);
    } else if (source.type === 'video' && source.url) {
      await host.setGenerator?.(null);
      host.setInputSource('video');
      video = await openVideo(source.url);
    } else if (source.type === 'generative') {
      host.setInputSource('generative');
      // The generator is the source the recorded slots process; without a shader id it is off.
      await host.setGenerator?.(source.shader ?? null);
    }
    // Webcam / stream / an unsaved local file: the live still stays (re-sent at job start).
  };

  const applyShaders = async (state: PlayerState) => {
    for (let slot = 0; slot < SLOT_COUNT; slot++) {
      const mode = state.modes[slot];
      if (mode === undefined || mode === appliedModes[slot]) continue;
      appliedModes[slot] = mode;
      const id = !mode || mode === 'none' ? '' : mode;
      if (id && !(await ensureShader(id))) {
        host.setSlotShader(slot, '');
        continue;
      }
      host.setSlotShader(slot, id);
    }
  };

  try {
    await host.beginOfflineRender({
      width: options.width,
      height: options.height,
      fps,
      ...(options.resolutionScale !== undefined ? { resolutionScale: options.resolutionScale } : {}),
    });
    began = true;
    // Compile everything up front: no frame waits on a pipeline mid-render.
    for (const id of player.shaderIds()) {
      throwIfCancelled();
      await ensureShader(id);
    }
    await host.reloadInputStill();

    for (let n = 0; n < totalFrames; n++) {
      throwIfCancelled();
      const tMs = startMs + (n * 1000) / fps;
      const timeSec = tMs / 1000;
      const state = player.stateAt(tMs);
      await applySource(state);
      await applyShaders(state);
      const audio = analyser?.at(n);
      const timestampUs = frameTimestampUs(Math.round(timeSec * fps), fps);
      const activeVideo = video as OfflineVideoSource | null;
      const videoFrame = activeVideo ? await activeVideo.frameAt(sourceMediaTimeSec(state, tMs), timestampUs) : null;
      const input: FrameInputSnapshot = {
        slotParams: slotParamsFor(state),
        ...(audio ? { audio: [audio.bass, audio.mid, audio.treble], bins: audio.bins } : {}),
        ...(videoFrame ? { videoFrame } : {}),
      };
      const frame = await host.renderFrameAt(timeSec, input);
      if (!frame) throw new Error(`the renderer produced no picture for frame ${n} (device lost?)`);
      try {
        await deps.onFrame?.(frame, n);
      } catch (e) {
        frame.close();
        throw e;
      }
      await session.encode(frame, n);
      progress('rendering', n + 1);
    }

    progress('finalizing', totalFrames);
    const blob = await session.finish();
    if (options.stream) await options.stream.close();
    finished = true;
    return {
      blob,
      frames: totalFrames,
      durationSec: totalFrames / fps,
      width: options.width,
      height: options.height,
      fps,
      codec: session.candidate,
      failedShaders: [...failedShaders],
    };
  } catch (e) {
    session.abort();
    if (options.stream && !finished) {
      try {
        await options.stream.abort();
      } catch {
        // already closed
      }
    }
    throw e;
  } finally {
    (video as OfflineVideoSource | null)?.close();
    if (began) {
      try {
        await host.endOfflineRender();
      } finally {
        await host.restoreLive();
      }
    }
  }
}
