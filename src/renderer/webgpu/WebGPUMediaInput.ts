/**
 * WebGPUMediaInput.ts
 *
 * Image and video upload paths for the TypeScript WebGPU renderer.
 */

import { reportError } from '../ErrorHandling';
import type { InternalColorFormat } from '../../config/formatPolicy';
import { packRgbaUploadData } from '../../config/formatPolicy';

export interface WebGPUMediaInputContext {
  device: GPUDevice | null;
  sourceTex: GPUTexture;
  readTex: GPUTexture;
  canvasW: number;
  canvasH: number;
  colorFormat: InternalColorFormat;
  filterSampler: GPUSampler;
  supportsExternalTexture: boolean;
  videoCopyPipeline: GPURenderPipeline | null;
  videoCopyBindGroupLayout: GPUBindGroupLayout | null;
}

export interface WebGPUMediaInputState {
  video: HTMLVideoElement | null;
  offscreen: ScratchCanvas | null;
  offCtx: ScratchContext2D | null;
  /**
   * Letterboxed still uploaded via copyExternalImageToTexture. Kept so texture
   * recreation re-copies the same (unconverted) pixels instead of the 2D offscreen.
   */
  still: StillPlacement | null;
}

export interface StillPlacement {
  bitmap: ImageBitmap;
  x: number;
  y: number;
  /** Canvas size the placement was computed for. */
  canvasW: number;
  canvasH: number;
}

/** A 2D scratch canvas: DOM canvas on the main thread, OffscreenCanvas in the render worker. */
export type ScratchCanvas = HTMLCanvasElement | OffscreenCanvas;
export type ScratchContext2D = CanvasRenderingContext2D | OffscreenCanvasRenderingContext2D;

export function createScratchCanvas(width: number, height: number): ScratchCanvas {
  if (typeof document !== 'undefined') {
    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    return canvas;
  }
  return new OffscreenCanvas(width, height);
}

/** (Re)size state.offscreen to w×h with a read-friendly 2D context. */
export function ensureOffscreen(state: WebGPUMediaInputState, width: number, height: number): ScratchContext2D | null {
  if (!state.offscreen || state.offscreen.width !== width || state.offscreen.height !== height) {
    state.offscreen = createScratchCanvas(width, height);
    state.offCtx = state.offscreen.getContext('2d', { willReadFrequently: true }) as ScratchContext2D | null;
  }
  return state.offCtx;
}

export function createMediaInputState(): WebGPUMediaInputState {
  return {
    video: null,
    offscreen: null,
    offCtx: null,
    still: null,
  };
}

export function releaseStill(state: WebGPUMediaInputState): void {
  state.still?.bitmap.close?.();
  state.still = null;
}

type CopyExternalSource = ImageBitmap | HTMLCanvasElement | OffscreenCanvas;

function hasCopyExternalImage(ctx: WebGPUMediaInputContext): ctx is WebGPUMediaInputContext & { device: GPUDevice } {
  return !!ctx.device && typeof ctx.device.queue.copyExternalImageToTexture === 'function';
}

function textureSize(tex: GPUTexture, fallbackW: number, fallbackH: number): [number, number] {
  const t = tex as GPUTexture & { width?: number; height?: number };
  return [t.width ?? fallbackW, t.height ?? fallbackH];
}

/**
 * GPU still upload: copy an external image straight into sourceTex (and readTex
 * when unscaled) at `origin`, skipping getImageData + CPU float conversion.
 * The browser converts unorm8 → the tier float format. Returns false when the
 * API is missing or the copy throws (tainted source, unsupported format), so
 * callers keep the 2D fallback. `clearFirst` blacks out the letterbox bars.
 */
export function copyExternalToSource(
  ctx: WebGPUMediaInputContext,
  source: CopyExternalSource,
  srcW: number,
  srcH: number,
  origin: { x: number; y: number } = { x: 0, y: 0 },
  clearFirst = false,
): boolean {
  if (!hasCopyExternalImage(ctx)) return false;
  const targets = [ctx.sourceTex];
  const [readW, readH] = textureSize(ctx.readTex, ctx.canvasW, ctx.canvasH);
  if (readW === ctx.canvasW && readH === ctx.canvasH) targets.push(ctx.readTex);

  try {
    for (const texture of targets) {
      const [texW, texH] = textureSize(texture, ctx.canvasW, ctx.canvasH);
      const w = Math.min(srcW, texW - origin.x);
      const h = Math.min(srcH, texH - origin.y);
      if (w <= 0 || h <= 0) continue;
      if (clearFirst) clearTexture(ctx.device, texture);
      ctx.device.queue.copyExternalImageToTexture(
        { source, flipY: false },
        { texture, origin: [origin.x, origin.y], premultipliedAlpha: false },
        [w, h],
      );
    }
    return true;
  } catch (e) {
    console.warn('[WebGPU] copyExternalImageToTexture failed; using 2D upload:', e);
    return false;
  }
}

/** Fit `srcW×srcH` inside the canvas (letterbox), snapped to integer texels. */
export function letterboxRect(
  srcW: number,
  srcH: number,
  dstW: number,
  dstH: number,
): { x: number; y: number; w: number; h: number } {
  const srcAspect = srcW / srcH;
  const dstAspect = dstW / dstH;
  let w = dstW;
  let h = dstH;
  if (srcAspect > dstAspect) {
    h = dstW / srcAspect;
  } else {
    w = dstH * srcAspect;
  }
  const rw = Math.max(1, Math.min(dstW, Math.round(w)));
  const rh = Math.max(1, Math.min(dstH, Math.round(h)));
  return { x: Math.floor((dstW - rw) / 2), y: Math.floor((dstH - rh) / 2), w: rw, h: rh };
}

function copyStill(ctx: WebGPUMediaInputContext, still: StillPlacement): boolean {
  return copyExternalToSource(
    ctx,
    still.bitmap,
    still.bitmap.width,
    still.bitmap.height,
    { x: still.x, y: still.y },
    true,
  );
}

/** A context, or a getter re-read after every await (textures may be recreated meanwhile). */
export type MediaContextSource = WebGPUMediaInputContext | (() => WebGPUMediaInputContext);

function liveContext(source: MediaContextSource): WebGPUMediaInputContext {
  return typeof source === 'function' ? source() : source;
}

async function uploadStillBitmap(
  ctxSource: MediaContextSource,
  state: WebGPUMediaInputState,
  img: HTMLImageElement | ImageBitmap,
  rect: { x: number; y: number; w: number; h: number },
): Promise<boolean> {
  if (!hasCopyExternalImage(liveContext(ctxSource)) || typeof createImageBitmap !== 'function') return false;
  let bitmap: ImageBitmap;
  try {
    bitmap = await createImageBitmap(img, {
      colorSpaceConversion: 'none',
      premultiplyAlpha: 'none',
      resizeWidth: rect.w,
      resizeHeight: rect.h,
      resizeQuality: 'high',
    });
  } catch (e) {
    console.warn('[WebGPU] createImageBitmap failed; using 2D upload:', e);
    return false;
  }
  // Re-read after the decode await: a scale change may have recreated sourceTex.
  const ctx = liveContext(ctxSource);
  const still: StillPlacement = { bitmap, x: rect.x, y: rect.y, canvasW: ctx.canvasW, canvasH: ctx.canvasH };
  if (!copyStill(ctx, still)) {
    bitmap.close?.();
    return false;
  }
  releaseStill(state);
  state.still = still;
  return true;
}

function clearTexture(device: GPUDevice, texture: GPUTexture): void {
  const encoder = device.createCommandEncoder({ label: 'clearStillEncoder' });
  const pass = encoder.beginRenderPass({
    label: 'clearStillPass',
    colorAttachments: [
      {
        view: texture.createView(),
        loadOp: 'clear',
        storeOp: 'store',
        clearValue: { r: 0, g: 0, b: 0, a: 1 },
      },
    ],
  });
  pass.end();
  device.queue.submit([encoder.finish()]);
}

function rgba8ToFloat32(
  data: Uint8ClampedArray,
  srcW: number,
  srcH: number,
  dstW: number,
  dstH: number,
): { floats: Float32Array; cW: number; cH: number } {
  const cW = Math.min(srcW, dstW);
  const cH = Math.min(srcH, dstH);
  const floats = new Float32Array(cW * cH * 4);
  for (let y = 0; y < cH; y++) {
    for (let x = 0; x < cW; x++) {
      const si = (y * srcW + x) * 4;
      const di = (y * cW + x) * 4;
      floats[di] = data[si]! / 255;
      floats[di + 1] = data[si + 1]! / 255;
      floats[di + 2] = data[si + 2]! / 255;
      floats[di + 3] = data[si + 3]! / 255;
    }
  }
  return { floats, cW, cH };
}

/** Upload pixels into sourceTex only (full-res). Frame loop copies/scales into readTex. */
export function uploadSourceRGBA8(
  ctx: WebGPUMediaInputContext,
  data: Uint8ClampedArray,
  srcW: number,
  srcH: number,
): void {
  if (!ctx.device) return;
  const { floats, cW, cH } = rgba8ToFloat32(data, srcW, srcH, ctx.canvasW, ctx.canvasH);
  const packed = packRgbaUploadData(floats, cW, cH, ctx.colorFormat);
  ctx.device.queue.writeTexture(
    { texture: ctx.sourceTex },
    packed.data,
    { bytesPerRow: packed.bytesPerRow, rowsPerImage: packed.rowsPerImage },
    [cW, cH],
  );
}

export function uploadRGBA8(
  ctx: WebGPUMediaInputContext,
  data: Uint8ClampedArray,
  srcW: number,
  srcH: number,
): void {
  if (!ctx.device) return;
  const { floats, cW, cH } = rgba8ToFloat32(data, srcW, srcH, ctx.canvasW, ctx.canvasH);
  const packed = packRgbaUploadData(floats, cW, cH, ctx.colorFormat);

  ctx.device.queue.writeTexture(
    { texture: ctx.sourceTex },
    packed.data,
    { bytesPerRow: packed.bytesPerRow, rowsPerImage: packed.rowsPerImage },
    [cW, cH],
  );
  // readTex may be resolution-scaled; only write when dimensions match canvas
  // (scale === 1). Otherwise the frame loop's scalePass/copy restores from sourceTex.
  const readW = (ctx.readTex as GPUTexture & { width?: number }).width ?? ctx.canvasW;
  const readH = (ctx.readTex as GPUTexture & { height?: number }).height ?? ctx.canvasH;
  if (readW === ctx.canvasW && readH === ctx.canvasH) {
    ctx.device.queue.writeTexture(
      { texture: ctx.readTex },
      packed.data,
      { bytesPerRow: packed.bytesPerRow, rowsPerImage: packed.rowsPerImage },
      [cW, cH],
    );
  }
}

/**
 * Re-upload the last letterboxed image/video frame from the CPU offscreen canvas
 * into sourceTex after GPU textures were recreated (e.g. adaptive resolution scale).
 * Without this, image-effect shaders go blank black after a scale change while
 * generative shaders keep working (they don't need source pixels).
 */
export function restoreSourceFromOffscreen(
  ctx: WebGPUMediaInputContext,
  state: WebGPUMediaInputState,
): boolean {
  if (!ctx.device) return false;
  const still = state.still;
  if (still && still.canvasW === ctx.canvasW && still.canvasH === ctx.canvasH && copyStill(ctx, still)) {
    return true;
  }
  if (!state.offscreen || !state.offCtx) return false;
  if (state.offscreen.width !== ctx.canvasW || state.offscreen.height !== ctx.canvasH) {
    return false;
  }
  try {
    const imageData = state.offCtx.getImageData(0, 0, ctx.canvasW, ctx.canvasH);
    uploadSourceRGBA8(ctx, imageData.data, ctx.canvasW, ctx.canvasH);
    return true;
  } catch (e) {
    console.warn('[WebGPU] Failed to restore source texture from offscreen:', e);
    return false;
  }
}

/** Encode a black clear of sourceTex into an existing encoder. */
export function encodeClearSource(ctx: WebGPUMediaInputContext, encoder: GPUCommandEncoder): void {
  const pass = encoder.beginRenderPass({
    label: 'clearSourcePass',
    colorAttachments: [
      {
        view: ctx.sourceTex.createView(),
        loadOp: 'clear',
        storeOp: 'store',
        clearValue: { r: 0, g: 0, b: 0, a: 1 },
      },
    ],
  });
  pass.end();
}

export function clearSourceTexture(ctx: WebGPUMediaInputContext): void {
  if (!ctx.device) return;

  const encoder = ctx.device.createCommandEncoder({ label: 'clearSourceEncoder' });
  encodeClearSource(ctx, encoder);
  ctx.device.queue.submit([encoder.finish()]);
}

/**
 * Encode the external-texture video copy into `encoder`. The external texture
 * is only valid until the current task ends, so the caller must submit the
 * encoder in the same task (the frame loop does). Returns false when the
 * zero-copy pipeline is unavailable.
 */
export function encodeVideoCopy(
  ctx: WebGPUMediaInputContext,
  state: WebGPUMediaInputState,
  encoder: GPUCommandEncoder,
  timestamps?: () => GPURenderPassTimestampWrites | undefined,
): boolean {
  return state.video ? encodeExternalCopy(ctx, state.video, encoder, timestamps) : false;
}

/**
 * Encode an external-texture copy of `source` (the <video> element, or a
 * WebCodecs VideoFrame from the ingest pump) stretched over sourceTex. A
 * VideoFrame-backed external texture stays valid until the frame is closed,
 * so the caller closes it only after queue.submit. May throw if the
 * browser cannot import the source (the caller falls back).
 */
export function encodeExternalCopy(
  ctx: WebGPUMediaInputContext,
  source: HTMLVideoElement | VideoFrame,
  encoder: GPUCommandEncoder,
  timestamps?: () => GPURenderPassTimestampWrites | undefined,
): boolean {
  if (!ctx.device || !ctx.videoCopyPipeline || !ctx.videoCopyBindGroupLayout) {
    return false;
  }

  const external = ctx.device.importExternalTexture({ source });
  // External textures expire with the task, so this group cannot be cached.
  const videoCopyBindGroup = ctx.device.createBindGroup({
    label: 'videoCopyBG',
    layout: ctx.videoCopyBindGroupLayout,
    entries: [
      { binding: 0, resource: external },
      { binding: 1, resource: ctx.filterSampler },
    ],
  });

  const timestampWrites = timestamps?.();
  const pass = encoder.beginRenderPass({
    label: 'videoCopyPass',
    ...(timestampWrites ? { timestampWrites } : {}),
    colorAttachments: [
      {
        view: ctx.sourceTex.createView(),
        loadOp: 'clear',
        storeOp: 'store',
        clearValue: { r: 0, g: 0, b: 0, a: 1 },
      },
    ],
  });

  pass.setPipeline(ctx.videoCopyPipeline);
  pass.setBindGroup(0, videoCopyBindGroup);
  pass.draw(3);
  pass.end();
  return true;
}

/** Stand-alone zero-copy upload (own encoder + submit) for callers outside the frame loop. */
export function updateVideoFrameZeroCopy(
  ctx: WebGPUMediaInputContext,
  state: WebGPUMediaInputState,
): void {
  if (!ctx.device) return;
  const encoder = ctx.device.createCommandEncoder({ label: 'videoCopyEncoder' });
  if (encodeVideoCopy(ctx, state, encoder)) {
    ctx.device.queue.submit([encoder.finish()]);
  }
}

export function updateVideoFrameCanvasFallback(
  ctx: WebGPUMediaInputContext,
  state: WebGPUMediaInputState,
): void {
  if (!state.video) return;
  const dstW = ctx.canvasW;
  const dstH = ctx.canvasH;

  if (!ensureOffscreen(state, dstW, dstH) || !state.offCtx) return;

  state.offCtx.drawImage(state.video, 0, 0, dstW, dstH);
  uploadRGBA8(ctx, state.offCtx.getImageData(0, 0, dstW, dstH).data, dstW, dstH);
}

const VIDEO_ERROR_MESSAGES: Record<number, string> = {
  1: 'Video loading aborted',
  2: 'Network error while loading video',
  3: 'Video decoding error (corrupt file?)',
  4: 'Video format not supported',
};

/**
 * Encode this frame's video ingest into `encoder` (zero-copy path), or upload
 * through the 2D fallback via queue writes. Returns true when GPU commands were
 * encoded. Shared by the frame loop and the stand-alone updateVideoFrame.
 */
export function encodeVideoFrame(
  ctx: WebGPUMediaInputContext,
  state: WebGPUMediaInputState,
  encoder: GPUCommandEncoder,
  timestamps?: () => GPURenderPassTimestampWrites | undefined,
): boolean {
  if (!state.video || state.video.readyState < 2) return false;
  if (state.still) releaseStill(state);
  const vw = state.video.videoWidth;
  const vh = state.video.videoHeight;
  if (!vw || !vh) return false;

  try {
    if (state.video.error) {
      const errorCode = state.video.error.code;
      reportError({
        type: 'media-load',
        message: `Video error: ${VIDEO_ERROR_MESSAGES[errorCode] || 'Unknown video error'}`,
        recoverable: true,
      });
      encodeClearSource(ctx, encoder);
      return true;
    }

    if (ctx.supportsExternalTexture && ctx.device && ctx.videoCopyPipeline) {
      return encodeVideoCopy(ctx, state, encoder, timestamps);
    }
    updateVideoFrameCanvasFallback(ctx, state);
    return false;
  } catch (e) {
    console.warn('[WebGPU] Video frame upload failed:', e);
    encodeClearSource(ctx, encoder);
    return true;
  }
}

/** Stand-alone video upload (own encoder + submit), e.g. on input rebind. */
export function updateVideoFrame(
  ctx: WebGPUMediaInputContext,
  state: WebGPUMediaInputState,
): void {
  if (!ctx.device) return;
  const encoder = ctx.device.createCommandEncoder({ label: 'videoIngestEncoder' });
  if (encodeVideoFrame(ctx, state, encoder)) {
    ctx.device.queue.submit([encoder.finish()]);
  }
}

/**
 * Letterbox an already-decoded image into sourceTex (GPU copy, 2D fallback)
 * and the CPU offscreen. Shared by URL loads and by the render worker, which
 * receives images as transferred ImageBitmaps decoded on the main thread.
 */
export async function ingestDecodedImage(
  ctxSource: MediaContextSource,
  state: WebGPUMediaInputState,
  img: HTMLImageElement | ImageBitmap,
  srcW: number,
  srcH: number,
): Promise<void> {
  let ctx = liveContext(ctxSource);
  const dstW = ctx.canvasW;
  const dstH = ctx.canvasH;
  const rect = letterboxRect(srcW, srcH, dstW, dstH);
  const offCtx = ensureOffscreen(state, dstW, dstH);
  if (!offCtx) return;

  offCtx.fillStyle = 'black';
  offCtx.fillRect(0, 0, dstW, dstH);
  // Offscreen stays populated for CPU consumers (chores ingest, getCpuInputBitmap);
  // drawImage alone is cheap — the readback + float convert is what the GPU path skips.
  offCtx.drawImage(img, rect.x, rect.y, rect.w, rect.h);

  if (!(await uploadStillBitmap(ctxSource, state, img, rect))) {
    releaseStill(state);
    ctx = liveContext(ctxSource);
    uploadRGBA8(ctx, offCtx.getImageData(0, 0, dstW, dstH).data, dstW, dstH);
  }
}

export async function loadImage(
  ctxSource: MediaContextSource,
  state: WebGPUMediaInputState,
  url: string,
): Promise<string> {
  let ctx = liveContext(ctxSource);
  try {
    const img = new Image();
    img.crossOrigin = 'anonymous';

    await new Promise<void>((resolve, reject) => {
      img.onload = () => resolve();
      img.onerror = () => reject(new Error(`Failed to load image: ${url}`));
      img.src = url;
    });

    await ingestDecodedImage(ctxSource, state, img, img.naturalWidth, img.naturalHeight);
    return url;
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';

    reportError({
      type: 'media-load',
      message: `Failed to load image "${url}": ${errorMessage}`,
      recoverable: true,
    });

    console.warn('[WebGPU] Image load failed:', error);

    releaseStill(state);
    ctx = liveContext(ctxSource);
    if (state.offscreen && state.offCtx) {
      const dstW = ctx.canvasW;
      const dstH = ctx.canvasH;
      state.offCtx.fillStyle = 'black';
      state.offCtx.fillRect(0, 0, dstW, dstH);
      uploadRGBA8(ctx, state.offCtx.getImageData(0, 0, dstW, dstH).data, dstW, dstH);
    }

    throw error;
  }
}
