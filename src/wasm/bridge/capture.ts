import { state, wasmRef } from './state.js';

/** C++ CaptureState (renderer.h): 0=idle, 1=pending, 2=ready, 3=error. */
const CAPTURE_READY = 2;
const CAPTURE_ERROR = 3;

let _captureInFlight: Promise<ImageData> | null = null;

/**
 * Read the current output (writeTexture_) back as RGBA8. C++ packs the
 * rgba16f/rgba32f texels into the caller's buffer (readCapturedFrame(ptr, maxBytes)).
 * One capture at a time: the C++ side owns a single mapped readback buffer, so a
 * caller that overlaps gets the in-flight promise instead of a second begin.
 */
export function captureFrame(): Promise<ImageData> {
  if (_captureInFlight) return _captureInFlight;
  const pending = new Promise<ImageData>((resolve, reject) => {
    if (!state.initialized || !wasmRef.module) {
      reject(new Error('[WASM] Renderer not initialized'));
      return;
    }

    wasmRef.module.ccall('beginFrameCapture', null, [], []);

    const pollState = () => {
      const mod = wasmRef.module;
      if (!mod) {
        reject(new Error('[WASM] Module invalidated during capture'));
        return;
      }

      const captureState = Number(mod.ccall('getFrameCaptureState', 'number', [], []));

      if (captureState === CAPTURE_READY) {
        const width = Number(mod.ccall('getCanvasWidth', 'number', [], []));
        const height = Number(mod.ccall('getCanvasHeight', 'number', [], []));
        const byteLength = width * height * 4;
        const ptr = byteLength > 0 ? mod._malloc(byteLength) : 0;
        let written = 0;
        let rgba8: Uint8ClampedArray | null = null;
        try {
          if (ptr) {
            written = Number(mod.ccall(
              'readCapturedFrame',
              'number',
              ['number', 'number'],
              [ptr, byteLength],
            ));
            if (written === byteLength) {
              rgba8 = new Uint8ClampedArray(mod.HEAPU8.slice(ptr, ptr + byteLength).buffer);
            }
          }
        } finally {
          if (ptr) mod._free(ptr);
          mod.ccall('endFrameCapture', null, [], []);
        }
        if (!rgba8) {
          reject(new Error(`[WASM] readCapturedFrame wrote ${written} of ${byteLength} bytes (${width}x${height})`));
          return;
        }
        resolve(new ImageData(rgba8, width, height));
      } else if (captureState === CAPTURE_ERROR) {
        mod.ccall('endFrameCapture', null, [], []);
        reject(new Error('[WASM] GPU frame capture failed on C++ side'));
      } else {
        requestAnimationFrame(pollState);
      }
    };

    requestAnimationFrame(pollState);
  });
  _captureInFlight = pending;
  const clear = () => {
    if (_captureInFlight === pending) _captureInFlight = null;
  };
  pending.then(clear, clear);
  return pending;
}

export async function captureFrameDataUrl(): Promise<string> {
  const imgData = await captureFrame();
  const offscreen = document.createElement('canvas');
  offscreen.width = imgData.width;
  offscreen.height = imgData.height;
  const ctx = offscreen.getContext('2d');
  if (!ctx) throw new Error('[WASM] Failed to create 2D context for data URL');
  ctx.putImageData(imgData, 0, 0);
  return offscreen.toDataURL('image/png');
}

export async function takeScreenshot(filename = 'pixelocity-shader.png'): Promise<void> {
  const dataUrl = await captureFrameDataUrl();
  const a = document.createElement('a');
  a.href = dataUrl;
  a.download = filename;
  a.click();
}

function asU8(pixels: Uint8Array | Uint8ClampedArray): Uint8Array {
  return pixels instanceof Uint8Array
    ? pixels
    : new Uint8Array(pixels.buffer, pixels.byteOffset, pixels.byteLength);
}

/**
 * GPU still ingest: C++ copies `source` straight into readTexture_ with
 * queue.copyExternalImageToTexture (top-left, clipped to the canvas, black
 * borders), the same geometry as the CPU uploadImageData path. Returns false
 * when the module or browser cannot do it; the caller then falls back to
 * uploadImageData.
 */
export function uploadImageSource(
  source: HTMLImageElement | HTMLCanvasElement | ImageBitmap,
  width: number,
  height: number,
): boolean {
  const mod = wasmRef.module;
  if (!state.initialized || !mod || !width || !height) return false;
  mod.pixelocityPendingImage = source;
  try {
    return Number(mod.ccall(
      'loadImageExternal',
      'number',
      ['number', 'number'],
      [width, height],
    )) === 1;
  } catch (err) {
    console.warn('[WASM] loadImageExternal failed:', err);
    return false;
  } finally {
    delete mod.pixelocityPendingImage;
  }
}

export function uploadImageData(
  image: ImageData | HTMLImageElement | Uint8Array | Uint8ClampedArray,
  width?: number,
  height?: number,
): void {
  if (!state.initialized || !wasmRef.module) return;

  let imgWidth = 0;
  let imgHeight = 0;
  let pixels: Uint8Array | Uint8ClampedArray | null = null;

  if (typeof ImageData !== 'undefined' && image instanceof ImageData) {
    imgWidth = image.width;
    imgHeight = image.height;
    pixels = image.data;
  } else if (image instanceof Uint8Array || image instanceof Uint8ClampedArray) {
    if (!width || !height || image.length === 0) return;
    imgWidth = width;
    imgHeight = height;
    pixels = image;
  } else if (typeof HTMLImageElement !== 'undefined' && image instanceof HTMLImageElement) {
    imgWidth = image.naturalWidth || image.width;
    imgHeight = image.naturalHeight || image.height;
    const tempCanvas = document.createElement('canvas');
    tempCanvas.width = imgWidth;
    tempCanvas.height = imgHeight;
    const ctx = tempCanvas.getContext('2d');
    if (!ctx) return;
    ctx.drawImage(image, 0, 0);
    pixels = ctx.getImageData(0, 0, imgWidth, imgHeight).data;
  } else {
    return;
  }

  if (!imgWidth || !imgHeight || !pixels || pixels.length === 0) return;

  const numBytes = imgWidth * imgHeight * 4;
  const ptr = wasmRef.module._malloc(numBytes);
  wasmRef.module.HEAPU8.set(asU8(pixels).subarray(0, numBytes), ptr);

  try {
    wasmRef.module.ccall(
      'loadImageData',
      null,
      ['number', 'number', 'number'],
      [ptr, imgWidth, imgHeight],
    );
  } finally {
    wasmRef.module._free(ptr);
  }
}

export function uploadVideoFrame(
  videoOrPixels: HTMLVideoElement | Uint8Array | Uint8ClampedArray,
  width?: number,
  height?: number,
): void {
  if (!state.initialized || !wasmRef.module) return;

  if (videoOrPixels instanceof Uint8Array || videoOrPixels instanceof Uint8ClampedArray) {
    if (!width || !height || videoOrPixels.length === 0) return;
    const numBytes = width * height * 4;
    const ptr = wasmRef.module._malloc(numBytes);
    wasmRef.module.HEAPU8.set(asU8(videoOrPixels).subarray(0, numBytes), ptr);
    wasmRef.module.ccall(
      'uploadVideoFrame',
      null,
      ['number', 'number', 'number'],
      [ptr, width, height],
    );
    wasmRef.module._free(ptr);
    return;
  }

  const video = videoOrPixels;
  if (!video || video.readyState < 2) return;

  const w = video.videoWidth;
  const h = video.videoHeight;
  if (!w || !h) return;

  const tempCanvas = document.createElement('canvas');
  tempCanvas.width = w;
  tempCanvas.height = h;
  const ctx = tempCanvas.getContext('2d');
  if (!ctx) return;

  ctx.drawImage(video, 0, 0, w, h);
  const imageData = ctx.getImageData(0, 0, w, h);
  const numBytes = w * h * 4;
  const ptr = wasmRef.module._malloc(numBytes);
  wasmRef.module.HEAPU8.set(asU8(imageData.data).subarray(0, numBytes), ptr);

  wasmRef.module.ccall(
    'uploadVideoFrame',
    null,
    ['number', 'number', 'number'],
    [ptr, w, h],
  );
  wasmRef.module._free(ptr);
}

export function resizeCanvas(width: number, height: number): void {
  if (!state.initialized || !wasmRef.module) return;
  state.canvasWidth = width;
  state.canvasHeight = height;
  wasmRef.module.ccall('resizeCanvas', null, ['number', 'number'], [width, height]);
}
