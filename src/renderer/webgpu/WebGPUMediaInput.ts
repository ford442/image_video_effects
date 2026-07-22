/**
 * WebGPUMediaInput.ts
 *
 * Image and video upload paths for the TypeScript WebGPU renderer.
 */

import { reportError } from '../ErrorHandling';

export interface WebGPUMediaInputContext {
  device: GPUDevice | null;
  sourceTex: GPUTexture;
  readTex: GPUTexture;
  canvasW: number;
  canvasH: number;
  filterSampler: GPUSampler;
  supportsExternalTexture: boolean;
  videoCopyPipeline: GPURenderPipeline | null;
  videoCopyBindGroupLayout: GPUBindGroupLayout | null;
}

export interface WebGPUMediaInputState {
  video: HTMLVideoElement | null;
  offscreen: HTMLCanvasElement | null;
  offCtx: CanvasRenderingContext2D | null;
  videoExternalTexture: GPUExternalTexture | null;
}

export function createMediaInputState(): WebGPUMediaInputState {
  return {
    video: null,
    offscreen: null,
    offCtx: null,
    videoExternalTexture: null,
  };
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
      floats[di] = data[si] / 255;
      floats[di + 1] = data[si + 1] / 255;
      floats[di + 2] = data[si + 2] / 255;
      floats[di + 3] = data[si + 3] / 255;
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
  ctx.device.queue.writeTexture(
    { texture: ctx.sourceTex },
    floats,
    { bytesPerRow: cW * 16, rowsPerImage: cH },
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

  ctx.device.queue.writeTexture(
    { texture: ctx.sourceTex },
    floats,
    { bytesPerRow: cW * 16, rowsPerImage: cH },
    [cW, cH],
  );
  // readTex may be resolution-scaled; only write when dimensions match canvas
  // (scale === 1). Otherwise the frame loop's scalePass/copy restores from sourceTex.
  const readW = (ctx.readTex as GPUTexture & { width?: number }).width ?? ctx.canvasW;
  const readH = (ctx.readTex as GPUTexture & { height?: number }).height ?? ctx.canvasH;
  if (readW === ctx.canvasW && readH === ctx.canvasH) {
    ctx.device.queue.writeTexture(
      { texture: ctx.readTex },
      floats,
      { bytesPerRow: cW * 16, rowsPerImage: cH },
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
  if (!ctx.device || !state.offscreen || !state.offCtx) return false;
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

export function clearSourceTexture(ctx: WebGPUMediaInputContext): void {
  if (!ctx.device) return;

  const encoder = ctx.device.createCommandEncoder({ label: 'clearSourceEncoder' });
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
  ctx.device.queue.submit([encoder.finish()]);
}

export function updateVideoFrameZeroCopy(
  ctx: WebGPUMediaInputContext,
  state: WebGPUMediaInputState,
): void {
  if (
    !ctx.device ||
    !state.video ||
    !ctx.videoCopyPipeline ||
    !ctx.videoCopyBindGroupLayout
  ) {
    return;
  }

  state.videoExternalTexture = ctx.device.importExternalTexture({ source: state.video });

  const videoCopyBindGroup = ctx.device.createBindGroup({
    label: 'videoCopyBG',
    layout: ctx.videoCopyBindGroupLayout,
    entries: [
      { binding: 0, resource: state.videoExternalTexture },
      { binding: 1, resource: ctx.filterSampler },
    ],
  });

  const encoder = ctx.device.createCommandEncoder({ label: 'videoCopyEncoder' });
  const pass = encoder.beginRenderPass({
    label: 'videoCopyPass',
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

  ctx.device.queue.submit([encoder.finish()]);
  state.videoExternalTexture = null;
}

export function updateVideoFrameCanvasFallback(
  ctx: WebGPUMediaInputContext,
  state: WebGPUMediaInputState,
): void {
  if (!state.video) return;
  const dstW = ctx.canvasW;
  const dstH = ctx.canvasH;

  if (!state.offscreen || state.offscreen.width !== dstW || state.offscreen.height !== dstH) {
    state.offscreen = document.createElement('canvas');
    state.offscreen.width = dstW;
    state.offscreen.height = dstH;
    state.offCtx = state.offscreen.getContext('2d', { willReadFrequently: true });
  }
  if (!state.offCtx) return;

  state.offCtx.drawImage(state.video, 0, 0, dstW, dstH);
  uploadRGBA8(ctx, state.offCtx.getImageData(0, 0, dstW, dstH).data, dstW, dstH);
}

export function updateVideoFrame(
  ctx: WebGPUMediaInputContext,
  state: WebGPUMediaInputState,
): void {
  if (!state.video || state.video.readyState < 2) return;
  const vw = state.video.videoWidth;
  const vh = state.video.videoHeight;
  if (!vw || !vh) return;

  try {
    if (state.video.error) {
      const errorCode = state.video.error.code;
      const errorMessages: Record<number, string> = {
        1: 'Video loading aborted',
        2: 'Network error while loading video',
        3: 'Video decoding error (corrupt file?)',
        4: 'Video format not supported',
      };

      reportError({
        type: 'media-load',
        message: `Video error: ${errorMessages[errorCode] || 'Unknown video error'}`,
        recoverable: true,
      });

      clearSourceTexture(ctx);
      return;
    }

    if (ctx.supportsExternalTexture && ctx.device && ctx.videoCopyPipeline) {
      updateVideoFrameZeroCopy(ctx, state);
    } else {
      updateVideoFrameCanvasFallback(ctx, state);
    }
  } catch (e) {
    console.warn('[WebGPU] Video frame upload failed:', e);
    clearSourceTexture(ctx);
  }
}

export async function loadImage(
  ctx: WebGPUMediaInputContext,
  state: WebGPUMediaInputState,
  url: string,
): Promise<string> {
  try {
    const img = new Image();
    img.crossOrigin = 'anonymous';

    await new Promise<void>((resolve, reject) => {
      img.onload = () => resolve();
      img.onerror = () => reject(new Error(`Failed to load image: ${url}`));
      img.src = url;
    });

    const dstW = ctx.canvasW;
    const dstH = ctx.canvasH;
    const srcAspect = img.naturalWidth / img.naturalHeight;
    const dstAspect = dstW / dstH;
    let drawW = dstW;
    let drawH = dstH;
    let drawX = 0;
    let drawY = 0;
    if (srcAspect > dstAspect) {
      drawH = dstW / srcAspect;
      drawY = (dstH - drawH) / 2;
    } else {
      drawW = dstH * srcAspect;
      drawX = (dstW - drawW) / 2;
    }

    if (!state.offscreen || state.offscreen.width !== dstW || state.offscreen.height !== dstH) {
      state.offscreen = document.createElement('canvas');
      state.offscreen.width = dstW;
      state.offscreen.height = dstH;
      state.offCtx = state.offscreen.getContext('2d', { willReadFrequently: true });
    }
    if (!state.offCtx) return url;

    state.offCtx.fillStyle = 'black';
    state.offCtx.fillRect(0, 0, dstW, dstH);
    state.offCtx.drawImage(img, drawX, drawY, drawW, drawH);

    uploadRGBA8(ctx, state.offCtx.getImageData(0, 0, dstW, dstH).data, dstW, dstH);
    return url;
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';

    reportError({
      type: 'media-load',
      message: `Failed to load image "${url}": ${errorMessage}`,
      recoverable: true,
    });

    console.warn('[WebGPU] Image load failed:', error);

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
