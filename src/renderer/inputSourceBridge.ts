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
};

export function setInputSource(renderer: Renderer | null, source: InputSource): void {
  (renderer as RendererWithInput | null)?.setInputSource?.(source);
}

export function getInputSource(renderer: Renderer | null): InputSource | null {
  return (renderer as RendererWithInput | null)?.getInputSource?.() ?? null;
}

export function setVideo(renderer: Renderer | null, video: HTMLVideoElement): void {
  renderer?.setVideo(video);
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
