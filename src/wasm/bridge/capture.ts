import * as cpp from './_generated.js';
import { isBusy, runWhenIdle } from './call.js';
import { state, wasmRef, type EmscriptenModule } from './state.js';

/** C++ CaptureState (renderer.h): 0=idle, 1=pending, 2=ready, 3=error. */
const CAPTURE_IDLE = 0;
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
    const begun = wasmRef.module;
    if (!state.initialized || !begun) {
      reject(new Error('[WASM] Renderer not initialized'));
      return;
    }

    const pollState = () => {
      const mod = wasmRef.module;
      if (mod !== begun) {
        reject(new Error('[WASM] Module invalidated during capture'));
        return;
      }

      const captureState = cpp.getFrameCaptureState(mod);

      if (captureState === CAPTURE_READY) {
        const width = cpp.getCanvasWidth(mod);
        const height = cpp.getCanvasHeight(mod);
        const byteLength = width * height * 4;
        const ptr = byteLength > 0 ? mod._malloc(byteLength) : 0;
        let written = 0;
        let rgba8: Uint8ClampedArray | null = null;
        try {
          if (ptr) {
            written = cpp.readCapturedFrame(mod, ptr, byteLength);
            if (written === byteLength) {
              rgba8 = new Uint8ClampedArray(mod.HEAPU8.slice(ptr, ptr + byteLength).buffer);
            }
          }
        } finally {
          if (ptr) mod._free(ptr);
          cpp.endFrameCapture(mod);
        }
        if (!rgba8) {
          reject(new Error(`[WASM] readCapturedFrame wrote ${written} of ${byteLength} bytes (${width}x${height})`));
          return;
        }
        resolve(new ImageData(rgba8, width, height));
      } else if (captureState === CAPTURE_ERROR) {
        cpp.endFrameCapture(mod);
        reject(new Error('[WASM] GPU frame capture failed on C++ side'));
      } else if (captureState === CAPTURE_IDLE) {
        // A resize released the readback buffer and reset the capture.
        reject(new Error('[WASM] Frame capture cancelled (canvas resized)'));
      } else {
        requestAnimationFrame(pollState);
      }
    };

    // beginFrameCapture is `skip` mid-suspend (it copies writeTexture_, which a
    // suspended resize may have released), so begin once the module is idle.
    void runWhenIdle(begun, () => {
      if (wasmRef.module !== begun) {
        reject(new Error('[WASM] Module invalidated during capture'));
        return;
      }
      cpp.beginFrameCapture(begun);
      requestAnimationFrame(pollState);
    });
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

function uploadPixels(mod: EmscriptenModule, pixels: Uint8Array, width: number, height: number): void {
  const numBytes = width * height * 4;
  const ptr = mod._malloc(numBytes);
  try {
    mod.HEAPU8.set(pixels.subarray(0, numBytes), ptr);
    cpp.loadImageData(mod, ptr, width, height);
  } finally {
    mod._free(ptr);
  }
}

function rasterize(source: CanvasImageSource, width: number, height: number): Uint8ClampedArray | null {
  const tempCanvas = document.createElement('canvas');
  tempCanvas.width = width;
  tempCanvas.height = height;
  const ctx = tempCanvas.getContext('2d');
  if (!ctx) return null;
  ctx.drawImage(source, 0, 0);
  return ctx.getImageData(0, 0, width, height).data;
}

function copyExternal(
  mod: EmscriptenModule,
  source: HTMLImageElement | HTMLCanvasElement | ImageBitmap,
  width: number,
  height: number,
): boolean {
  mod.pixelocityPendingImage = source;
  try {
    return cpp.loadImageExternal(mod, width, height) === 1;
  } catch (err) {
    console.warn('[WASM] loadImageExternal failed:', err);
    return false;
  } finally {
    delete mod.pixelocityPendingImage;
  }
}

/**
 * GPU still ingest: C++ copies `source` straight into readTexture_ with
 * queue.copyExternalImageToTexture (top-left, clipped to the canvas, black
 * borders), the same geometry as the CPU uploadImageData path. Returns false
 * when the module or browser cannot do it; the caller then falls back to
 * uploadImageData. While a resize / shader compile is suspended the upload runs
 * after it (CPU fallback included) and this returns true.
 */
export function uploadImageSource(
  source: HTMLImageElement | HTMLCanvasElement | ImageBitmap,
  width: number,
  height: number,
): boolean {
  const mod = wasmRef.module;
  if (!state.initialized || !mod || !width || !height) return false;
  if (!isBusy(mod)) return copyExternal(mod, source, width, height);
  void runWhenIdle(mod, () => {
    if (wasmRef.module !== mod || copyExternal(mod, source, width, height)) return;
    const pixels = rasterize(source, width, height);
    if (pixels) uploadPixels(mod, asU8(pixels), width, height);
  });
  return true;
}

export function uploadImageData(
  image: ImageData | HTMLImageElement | Uint8Array | Uint8ClampedArray,
  width?: number,
  height?: number,
): void {
  const mod = wasmRef.module;
  if (!state.initialized || !mod) return;

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
    pixels = rasterize(image, imgWidth, imgHeight);
  } else {
    return;
  }

  if (!imgWidth || !imgHeight || !pixels || pixels.length === 0) return;

  // loadImageData is `skip` mid-suspend; a still is sent once, so defer it
  // (on a copy: the caller may reuse its buffer) instead of losing it.
  if (isBusy(mod)) {
    const copy = asU8(pixels).slice(0, imgWidth * imgHeight * 4);
    const w = imgWidth;
    const h = imgHeight;
    void runWhenIdle(mod, () => {
      if (wasmRef.module === mod) uploadPixels(mod, copy, w, h);
    });
    return;
  }
  uploadPixels(mod, asU8(pixels), imgWidth, imgHeight);
}

/**
 * GPU video ingest: the same copyExternalImageToTexture hand-off as stills, so a
 * frame never round-trips through getImageData or a CPU u8→float conversion.
 * False when the module or browser cannot do it (caller falls back to
 * uploadVideoFrame) or while a resize / compile is suspended (frame dropped).
 */
export function uploadVideoSource(
  source: HTMLVideoElement | VideoFrame | HTMLCanvasElement | ImageBitmap,
  width: number,
  height: number,
): boolean {
  const mod = wasmRef.module;
  if (!state.initialized || !mod || !width || !height || isBusy(mod)) return false;
  mod.pixelocityPendingImage = source;
  try {
    return cpp.uploadVideoExternal(mod, width, height) === 1;
  } catch (err) {
    console.warn('[WASM] uploadVideoExternal failed:', err);
    return false;
  } finally {
    delete mod.pixelocityPendingImage;
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
    sendVideoFrame(wasmRef.module, asU8(videoOrPixels), width, height);
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
  sendVideoFrame(wasmRef.module, asU8(ctx.getImageData(0, 0, w, h).data), w, h);
}

/** Per frame: `skip` mid-suspend, the next frame replaces a dropped one. */
function sendVideoFrame(mod: EmscriptenModule, pixels: Uint8Array, width: number, height: number): void {
  if (isBusy(mod)) return;
  const numBytes = width * height * 4;
  const ptr = mod._malloc(numBytes);
  try {
    mod.HEAPU8.set(pixels.subarray(0, numBytes), ptr);
    cpp.uploadVideoFrame(mod, ptr, width, height);
  } finally {
    mod._free(ptr);
  }
}

/**
 * Async export: RecreateTextures can suspend in TryCreateHistoryTexture.
 * Frames are skipped until it returns. Resolves false when C++ could not
 * rebuild the textures (rendering pauses until a resize succeeds) or the
 * module went away.
 */
export async function resizeCanvas(width: number, height: number): Promise<boolean> {
  const mod = wasmRef.module;
  if (!state.initialized || !mod) return false;
  state.canvasWidth = width;
  state.canvasHeight = height;
  try {
    const ok = (await cpp.resizeCanvas(mod, width, height)) === 1;
    if (!ok) console.error(`[WASM] resizeCanvas(${width}, ${height}): textures could not be rebuilt; rendering paused`);
    return ok && wasmRef.module === mod;
  } catch (err) {
    console.error('[WASM] resizeCanvas failed:', err);
    return false;
  }
}
