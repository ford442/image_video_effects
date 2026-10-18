/**
 * Renders one shader through the live production renderer and captures a
 * thumbnail, matching scripts/generate-shader-thumbnails.js (--engine=app):
 * same input-source rule, fixture image, time uniform, warmup and size.
 */
import type { RendererManager } from '../../renderer/RendererManager';
import type { ShaderEntry } from '../../renderer/types';
import { MULTIPASS_REGISTRY } from '../../renderer/multipassRegistry';
import { classifyFrame, formatFrameStats, statsFromPngBase64, FrameErrorReason, FrameStats } from './frameCheck';

/** Only standalone generators render without the input image (as in the app). */
export const THUMB_GENERATIVE_CATEGORIES = new Set(['generative']);
/** Procedural 512² scene, see scripts/make-thumbnail-fixture.py. */
export const THUMB_FIXTURE_URL = './fixtures/thumbnail-scene.png';

export interface CaptureOptions {
  size: number;
  frames: number;
  simFrames: number;
  time: number;
}

export const DEFAULT_CAPTURE_OPTIONS: CaptureOptions = { size: 256, frames: 60, simFrames: 120, time: 1.5 };

/** What the scanner's host (AppOverlays) provides so captures go through normal app state. */
export interface ThumbnailHost {
  getRenderer(): RendererManager | null;
  /** Same path as picking a shader in the UI (loads WGSL, applies default params). */
  loadIntoSlot(index: number, shaderId: string): Promise<void>;
  clearSlot(index: number): Promise<void>;
  /** Saves slot shaders / input source / image; resolves to a function that restores them. */
  beginSession(): Promise<() => Promise<void>>;
}

export type CaptureFailureReason = FrameErrorReason | 'load_failed' | 'capture_failed' | 'gpu_unavailable';

export type CaptureResult =
  | { ok: true; pngB64: string; stats: FrameStats; paramsSnapshot: number[] }
  | { ok: false; reason: CaptureFailureReason; detail: string; stats?: FrameStats };

export function defaultParamsSnapshot(shader: ShaderEntry): number[] {
  const out = [0.5, 0.5, 0.5, 0.5];
  const slot: Record<string, number> = { x: 0, y: 1, z: 2, w: 3 };
  for (const p of shader.params ?? []) {
    const axis = /^zoom_params\.([xyzw])$/.exec((p as { mapping?: string }).mapping ?? '')?.[1];
    const idx = axis ? slot[axis] : undefined;
    if (idx !== undefined && typeof p.default === 'number') out[idx] = p.default;
  }
  return out;
}

function warmupFrames(shader: ShaderEntry, opts: CaptureOptions): number {
  const isSim = String(shader.category) === 'simulation' || shader.id in MULTIPASS_REGISTRY;
  return isSim ? Math.max(opts.frames, opts.simFrames) : opts.frames;
}

function waitFrames(n: number): Promise<void> {
  return new Promise(resolve => {
    let count = 0;
    const tick = () => {
      count += 1;
      if (count >= n) resolve();
      else requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  });
}

async function canvasFallbackPng(size: number): Promise<string | null> {
  const canvas = document.querySelector('canvas');
  if (!canvas) return null;
  const tmp = document.createElement('canvas');
  tmp.width = size;
  tmp.height = size;
  const ctx = tmp.getContext('2d');
  if (!ctx) return null;
  ctx.drawImage(canvas, 0, 0, size, size);
  return tmp.toDataURL('image/png').replace(/^data:image\/png;base64,/, '');
}

export interface CaptureSessionState {
  inputSource: 'image' | 'generative' | null;
}

export async function captureShaderThumbnail(
  host: ThumbnailHost,
  shader: ShaderEntry,
  opts: CaptureOptions,
  session: CaptureSessionState,
): Promise<CaptureResult> {
  const manager = host.getRenderer();
  if (!manager || manager.getActiveRendererType() !== 'webgpu') {
    return { ok: false, reason: 'gpu_unavailable', detail: 'TypeScript WebGPU renderer (Tier A) must be active' };
  }

  const source = THUMB_GENERATIVE_CATEGORIES.has(String(shader.category)) ? 'generative' : 'image';
  if (session.inputSource !== source) {
    manager.setInputSource(source);
    if (source === 'image') await manager.loadImage(THUMB_FIXTURE_URL);
    session.inputSource = source;
  }

  await host.loadIntoSlot(0, shader.id);
  // loadShader is cached after the slot load; this tells us whether it actually succeeded.
  const loaded = await manager.loadShader(shader.id, shader.url);
  if (!loaded) return { ok: false, reason: 'load_failed', detail: `loadShader failed for ${shader.id}` };

  manager.applyTestRenderState({ time: opts.time, mouseX: 0.5, mouseY: 0.5 });
  await waitFrames(warmupFrames(shader, opts));

  const pngB64 = (await manager.captureThumbnailPng(opts.size)) ?? (await canvasFallbackPng(opts.size));
  if (!pngB64) return { ok: false, reason: 'capture_failed', detail: 'captureThumbnailPng returned null' };

  const stats = await statsFromPngBase64(pngB64);
  const frameError = classifyFrame(stats);
  if (frameError) return { ok: false, reason: frameError, detail: formatFrameStats(stats), stats };

  return { ok: true, pngB64, stats, paramsSnapshot: defaultParamsSnapshot(shader) };
}
