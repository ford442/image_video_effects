/**
 * inputSourceBridge.ts
 *
 * Pure seams for image/video/webcam/depth input handoff to the active renderer backend.
 */

import { Renderer } from './Renderer';
import { InputSource } from './types';

export type CpuInputElement = HTMLCanvasElement | HTMLImageElement | HTMLVideoElement;

type RendererWithInput = Renderer & {
  setInputSource?: (source: InputSource) => void;
  getInputSource?: () => InputSource;
  setImageList?: (urls: string[]) => void;
  updateDepthMap?: (data: Float32Array, width: number, height: number) => void;
  loadImage?: (url: string) => Promise<string>;
  loadImageFromURL?: (url: string) => Promise<void>;
  loadImageFromElement?: (
    element: HTMLCanvasElement | HTMLImageElement,
  ) => Promise<{ width: number; height: number } | null> | { width: number; height: number } | null;
  getCpuInputBitmap?: () => CpuInputElement | null;
  getAvailableModes?: () => import('./types').ShaderEntry[];
  getVideo?: () => HTMLVideoElement | null;
  mediaVideo?: HTMLVideoElement | null;
  video?: HTMLVideoElement | null;
};

const LIVE_VIDEO_SOURCES: InputSource[] = ['video', 'webcam', 'live'];

const WASM_CANVAS_ID = /^pixelocity-wasm-canvas-\d+$/;

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

export function readCpuInputBitmap(renderer: Renderer | null): CpuInputElement | null {
  const r = renderer as RendererWithInput | null;
  if (!r) return null;
  if (typeof r.getCpuInputBitmap === 'function') {
    return r.getCpuInputBitmap();
  }
  return readRendererVideo(r);
}

export function readPresentCanvasId(fallbackCanvas?: HTMLCanvasElement | null): string {
  if (typeof document !== 'undefined') {
    const tagged = document.querySelector<HTMLCanvasElement>('[id^="pixelocity-wasm-canvas-"]');
    if (tagged?.id && WASM_CANVAS_ID.test(tagged.id)) return tagged.id;
  }
  if (fallbackCanvas?.id && WASM_CANVAS_ID.test(fallbackCanvas.id)) return fallbackCanvas.id;
  return fallbackCanvas?.id ?? '';
}

function elementSize(element: CpuInputElement): { width: number; height: number } {
  if (element instanceof HTMLVideoElement) {
    return { width: element.videoWidth, height: element.videoHeight };
  }
  if (element instanceof HTMLImageElement) {
    return { width: element.naturalWidth || element.width, height: element.naturalHeight || element.height };
  }
  return { width: element.width, height: element.height };
}

function logInputUpload(result: MediaRebindResult, canvasId: string): void {
  const id = canvasId ? `#${canvasId}` : '(none)';
  const line =
    `[WASM] Input upload ran: ${result.width}×${result.height} uploaded=${result.uploaded} canvas=${id}`;
  if (result.uploaded) {
    console.log(line);
  } else {
    console.warn(line);
  }
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
    bitmap?: CpuInputElement | null;
    presentCanvas?: HTMLCanvasElement | null;
    logUpload?: boolean;
  },
): Promise<MediaRebindResult> {
  const source = options.inputSource ?? getInputSource(renderer) ?? 'image';
  const empty: MediaRebindResult = { uploaded: false, width: 0, height: 0, source };
  const canvasId = readPresentCanvasId(options.presentCanvas);
  const shouldLog = options.logUpload !== false;

  if (!renderer) {
    console.warn('[RendererManager] Input rebind skipped: no renderer');
    if (shouldLog) logInputUpload(empty, canvasId);
    return empty;
  }

  setInputSource(renderer, source);

  if (source === 'generative') {
    console.log('[RendererManager] Input rebind skipped (source=generative)');
    return empty;
  }

  try {
    if (LIVE_VIDEO_SOURCES.includes(source)) {
      const video = (options.bitmap instanceof HTMLVideoElement)
        ? options.bitmap
        : readRendererVideo(renderer);
      if (video) renderer.setVideo(video);
      renderer.updateVideoFrame();
      const w = video?.videoWidth ?? 0;
      const h = video?.videoHeight ?? 0;
      const uploaded = !!(video && w > 0 && h > 0);
      const result: MediaRebindResult = { uploaded, width: w, height: h, source };
      if (shouldLog) logInputUpload(result, canvasId);
      return result;
    }

    const bitmap = options.bitmap && !(options.bitmap instanceof HTMLVideoElement)
      ? options.bitmap
      : null;
    const target = renderer as RendererWithInput;

    if (bitmap && typeof target.loadImageFromElement === 'function') {
      const size = await target.loadImageFromElement(bitmap);
      const fallback = elementSize(bitmap);
      const width = size?.width ?? fallback.width;
      const height = size?.height ?? fallback.height;
      if (size && width > 0 && height > 0) {
        const result: MediaRebindResult = { uploaded: true, width, height, source };
        if (shouldLog) logInputUpload(result, canvasId);
        return result;
      }
    }

    const url = options.imageUrl;
    if (!url) {
      if (shouldLog) logInputUpload(empty, canvasId);
      return empty;
    }

    await loadImage(renderer, url);
    const after = readCpuInputBitmap(renderer);
    const dim = after && !(after instanceof HTMLVideoElement) ? elementSize(after) : { width: 0, height: 0 };
    const result: MediaRebindResult = {
      uploaded: true,
      width: dim.width,
      height: dim.height,
      source,
    };
    if (shouldLog) logInputUpload(result, canvasId);
    return result;
  } catch (err) {
    console.warn('[RendererManager] Input rebind failed after backend switch:', err);
    if (shouldLog) logInputUpload(empty, canvasId);
    return empty;
  }
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
