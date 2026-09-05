/**
 * inputSourceBridge.ts
 *
 * Pure seams for image/video/webcam/depth input handoff to the active renderer backend.
 */

import { Renderer } from './Renderer';
import { InputSource } from './types';

type RendererWithInput = Renderer & {
  setInputSource?: (source: InputSource) => void;
  getInputSource?: () => InputSource;
  setImageList?: (urls: string[]) => void;
  updateDepthMap?: (data: Float32Array, width: number, height: number) => void;
  loadImage?: (url: string) => Promise<string>;
  loadImageFromURL?: (url: string) => Promise<void>;
  getAvailableModes?: () => import('./types').ShaderEntry[];
  getVideo?: () => HTMLVideoElement | null;
  mediaVideo?: HTMLVideoElement | null;
  video?: HTMLVideoElement | null;
};

const LIVE_VIDEO_SOURCES: InputSource[] = ['video', 'webcam', 'live'];

/** Duck-typed video element — TS WebGPU keeps it on mediaState, WASM/JS on `video`. */
export function readRendererVideo(renderer: Renderer | null): HTMLVideoElement | null {
  const r = renderer as RendererWithInput | null;
  if (!r) return null;
  return r.getVideo?.() ?? r.mediaVideo ?? r.video ?? null;
}

export function setInputSource(renderer: Renderer | null, source: InputSource): void {
  (renderer as RendererWithInput | null)?.setInputSource?.(source);
}

export function getInputSource(renderer: Renderer | null): InputSource | null {
  return (renderer as RendererWithInput | null)?.getInputSource?.() ?? null;
}

export function setVideo(renderer: Renderer | null, video: HTMLVideoElement): void {
  renderer?.setVideo(video);
}

export interface MediaRebindResult {
  uploaded: boolean;
  width: number;
  height: number;
  source: InputSource | 'none';
}

/**
 * After an exclusive WebGPU device switch the previous textures are gone.
 * `setInputSource` only sets a mode flag — this re-uploads pixels (#1206).
 */
export async function rebindMediaAfterBackendSwitch(
  renderer: Renderer | null,
  options: {
    inputSource?: InputSource | null;
    imageUrl?: string | null;
  },
): Promise<MediaRebindResult> {
  const source = options.inputSource ?? getInputSource(renderer) ?? 'image';
  const empty: MediaRebindResult = { uploaded: false, width: 0, height: 0, source };

  if (!renderer) {
    console.warn('[RendererManager] Input rebind skipped: no renderer');
    return empty;
  }

  setInputSource(renderer, source);

  if (source === 'generative') {
    console.log('[RendererManager] Input rebind skipped (source=generative)');
    return empty;
  }

  if (LIVE_VIDEO_SOURCES.includes(source)) {
    const video = readRendererVideo(renderer);
    if (video) renderer.setVideo(video);
    renderer.updateVideoFrame();
    const w = video?.videoWidth ?? 0;
    const h = video?.videoHeight ?? 0;
    const uploaded = !!(video && w > 0 && h > 0);
    console.log(
      `[RendererManager] Input rebind upload ran: ${w}×${h} source=${source}` +
        (uploaded ? '' : ' (no video frame yet)'),
    );
    return { uploaded, width: w, height: h, source };
  }

  const url = options.imageUrl;
  if (!url) {
    return empty;
  }

  await loadImage(renderer, url);
  console.log(`[RendererManager] Input rebind upload ran for image source=${source} url=${url}`);
  return { uploaded: true, width: 0, height: 0, source };
}

export function updateVideoFrame(renderer: Renderer | null): void {
  renderer?.updateVideoFrame();
}

export function setImageList(renderer: Renderer | null, urls: string[]): void {
  const r = renderer as RendererWithInput | null;
  r?.setImageList?.(urls);
}

export function updateDepthMap(
  renderer: Renderer | null,
  data: Float32Array,
  width: number,
  height: number,
): void {
  const r = renderer as RendererWithInput | null;
  r?.updateDepthMap?.(data, width, height);
}

/** Duck-typed image load — prefers loadImage, falls back to loadImageFromURL (#887). */
export async function loadImage(renderer: Renderer | null, url: string): Promise<string> {
  const r = renderer as RendererWithInput | null;
  if (!r) return url;
  if (r.loadImage) {
    return r.loadImage(url);
  }
  if (r.loadImageFromURL) {
    await r.loadImageFromURL(url);
    return url;
  }
  return url;
}

export function getAvailableModes(renderer: Renderer | null): import('./types').ShaderEntry[] {
  const r = renderer as RendererWithInput | null;
  return r?.getAvailableModes?.() ?? [];
}
