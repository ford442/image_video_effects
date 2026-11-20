/**
 * offlineHarness.ts — `?testMode=1` hooks for the offline render path (#1401).
 * Loaded lazily by useTestHarness, so none of this is in the page bundle's hot path.
 *
 *   renderOfflineFrames: a single shader on a deterministic input, stepped frames 0..N,
 *     returning SHA-256 + PNG of the requested frames (tests/golden-frames.swiftshader.spec.ts).
 *   exportOfflineClip: the full VJ Studio → Render job (TimelinePlayer → renderFrameAt →
 *     WebCodecs → mp4 / webm) on a synthetic set; returns the file for ffprobe.
 */

import type { RendererManager } from '../renderer/RendererManager';
import { loadGpuEncoder } from '../recording/gpuEncodeSupport';
import type { OfflineCodecChoice, OfflineContainer } from '../recording/offlineExportPlan';
import type { VjTimeline } from '../services/vjSetExport';

export interface OfflineFramesRequest {
  shaderId: string;
  url: string;
  size?: number;
  fps?: number;
  /** Frame indices to capture (every frame up to the largest is rendered). */
  frames: number[];
  /** 'pattern' = a fixed procedural still uploaded as the image source. */
  source?: 'pattern' | 'generative';
  params?: [number, number, number, number];
  mouse?: [number, number];
  audio?: [number, number, number];
}

export interface OfflineFrameCapture {
  frame: number;
  /** SHA-256 (hex) of the RGBA8 pixels. */
  sha256: string;
  /** PNG, base64 without the data: prefix. */
  png: string;
}

/** A fixed RGBA pattern (gradients, rings, a checker), exact bytes every run. */
export function patternDataUrl(size: number): string {
  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('no 2D context for the test pattern');
  const img = ctx.createImageData(size, size);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const u = x / size;
      const v = y / size;
      const dx = u - 0.5;
      const dy = v - 0.5;
      const ring = Math.cos(Math.sqrt(dx * dx + dy * dy) * 40) * 0.5 + 0.5;
      const checker = ((x >> 4) + (y >> 4)) & 1;
      const o = (y * size + x) * 4;
      img.data[o] = Math.round(255 * u);
      img.data[o + 1] = Math.round(255 * (ring * 0.7 + checker * 0.3));
      img.data[o + 2] = Math.round(255 * v);
      img.data[o + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
  return canvas.toDataURL('image/png');
}

function toHex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer), (b) => b.toString(16).padStart(2, '0')).join('');
}

async function blobToBase64(blob: Blob): Promise<string> {
  const bytes = new Uint8Array(await blob.arrayBuffer());
  let binary = '';
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(binary);
}

async function readFrame(frame: VideoFrame): Promise<{ sha256: string; png: string }> {
  const canvas = new OffscreenCanvas(frame.displayWidth, frame.displayHeight);
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  if (!ctx) throw new Error('no 2D context to read the frame');
  ctx.drawImage(frame, 0, 0);
  const { data } = ctx.getImageData(0, 0, canvas.width, canvas.height);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return { sha256: toHex(digest), png: await blobToBase64(await canvas.convertToBlob({ type: 'image/png' })) };
}

export async function renderOfflineFrames(manager: RendererManager, req: OfflineFramesRequest): Promise<OfflineFrameCapture[]> {
  const size = req.size ?? 256;
  const fps = req.fps ?? 30;
  const params = req.params ?? [0.5, 0.5, 0.5, 0.5];
  if (!(await manager.loadShader(req.shaderId, req.url))) throw new Error(`shader "${req.shaderId}" failed to load`);
  await manager.beginOfflineRender({ width: size, height: size, fps, resolutionScale: 1 });
  const job = manager.offlineJobControls();
  try {
    for (let i = 1; i < 6; i++) job.setSlotShader(i, '');
    job.setSlotShader(0, req.shaderId);
    if (req.source === 'generative') {
      job.setInputSource('generative');
    } else {
      job.setInputSource('image');
      await job.loadImage(patternDataUrl(size));
    }
    const wanted = new Set(req.frames);
    const last = Math.max(0, ...req.frames);
    const out: OfflineFrameCapture[] = [];
    for (let n = 0; n <= last; n++) {
      const frame = await manager.renderFrameAt(n / fps, {
        slotParams: [[0, ...params]],
        ...(req.mouse ? { mouse: req.mouse } : {}),
        ...(req.audio ? { audio: req.audio } : {}),
      });
      if (!frame) throw new Error(`no frame ${n} for "${req.shaderId}"`);
      try {
        if (wanted.has(n)) out.push({ frame: n, ...(await readFrame(frame)) });
      } finally {
        frame.close();
      }
    }
    return out;
  } finally {
    await manager.endOfflineRender();
  }
}

export interface OfflineClipRequest {
  /** id → url of every shader the timeline uses. */
  shaders: Record<string, string>;
  timeline: VjTimeline;
  width: number;
  height: number;
  fps: number;
  container: OfflineContainer;
  codec?: OfflineCodecChoice;
}

export interface OfflineClipResult {
  frames: number;
  type: string;
  bytes: number;
  codec: string;
  muxCodec: string;
  base64: string;
  wallMs: number;
}

export async function exportOfflineClip(manager: RendererManager, req: OfflineClipRequest): Promise<OfflineClipResult> {
  const { runOfflineRender } = await loadGpuEncoder();
  const t0 = performance.now();
  const job = manager.offlineJobControls();
  const result = await runOfflineRender(
    {
      beginOfflineRender: (o) => manager.beginOfflineRender(o),
      renderFrameAt: (t, input) => manager.renderFrameAt(t, input),
      endOfflineRender: () => manager.endOfflineRender(),
      loadShader: async (id) => {
        const url = req.shaders[id];
        return url ? manager.loadShader(id, url) : false;
      },
      setSlotShader: (i, id) => job.setSlotShader(i, id),
      setInputSource: (s) => job.setInputSource(s),
      loadImage: (url) => job.loadImage(url),
      reloadInputStill: () => manager.reloadInputStill(),
      restoreLive: async () => {},
    },
    {
      timeline: req.timeline,
      base: { modes: ['none', 'none', 'none', 'none', 'none', 'none'], params: [], source: { type: 'generative' } },
      width: req.width,
      height: req.height,
      fps: req.fps,
      container: req.container,
      codec: req.codec ?? 'auto',
      quality: 'standard',
    },
  );
  if (!result.blob) throw new Error('expected an in-memory file');
  return {
    frames: result.frames,
    type: result.blob.type,
    bytes: result.blob.size,
    codec: result.codec.codec,
    muxCodec: result.codec.muxCodec,
    base64: await blobToBase64(result.blob),
    wallMs: performance.now() - t0,
  };
}
