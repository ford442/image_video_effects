// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)

import * as cpp from "./_generated.js";
import { isBusy, isSuspended, runWhenIdle } from "./call.js";
import { state, wasmRef } from "./state.js";
const CAPTURE_READY = 2;
const CAPTURE_ERROR = 3;
let _captureInFlight = null;
function captureFrame() {
  if (_captureInFlight) return _captureInFlight;
  const pending = new Promise((resolve, reject) => {
    const module = wasmRef.module;
    if (!state.initialized || !module) {
      reject(new Error("[WASM] Renderer not initialized"));
      return;
    }
    const pollState = () => {
      const mod = wasmRef.module;
      if (!mod) {
        reject(new Error("[WASM] Module invalidated during capture"));
        return;
      }
      const captureState = cpp.getFrameCaptureState(mod);
      if (captureState === CAPTURE_READY) {
        const width = cpp.getCanvasWidth(mod);
        const height = cpp.getCanvasHeight(mod);
        const byteLength = width * height * 4;
        const ptr = byteLength > 0 ? mod._malloc(byteLength) : 0;
        let written = 0;
        let rgba8 = null;
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
        reject(new Error("[WASM] GPU frame capture failed on C++ side"));
      } else {
        requestAnimationFrame(pollState);
      }
    };
    runWhenIdle(module, () => {
      if (wasmRef.module !== module) throw new Error("[WASM] Module invalidated during capture");
      cpp.beginFrameCapture(module);
      requestAnimationFrame(pollState);
    }).catch(reject);
  });
  _captureInFlight = pending;
  const clear = () => {
    if (_captureInFlight === pending) _captureInFlight = null;
  };
  pending.then(clear, clear);
  return pending;
}
async function captureFrameDataUrl() {
  const imgData = await captureFrame();
  const offscreen = document.createElement("canvas");
  offscreen.width = imgData.width;
  offscreen.height = imgData.height;
  const ctx = offscreen.getContext("2d");
  if (!ctx) throw new Error("[WASM] Failed to create 2D context for data URL");
  ctx.putImageData(imgData, 0, 0);
  return offscreen.toDataURL("image/png");
}
async function takeScreenshot(filename = "pixelocity-shader.png") {
  const dataUrl = await captureFrameDataUrl();
  const a = document.createElement("a");
  a.href = dataUrl;
  a.download = filename;
  a.click();
}
function asU8(pixels) {
  return pixels instanceof Uint8Array ? pixels : new Uint8Array(pixels.buffer, pixels.byteOffset, pixels.byteLength);
}
function uploadImageSource(source, width, height) {
  const mod = wasmRef.module;
  if (!state.initialized || !mod || !width || !height) return false;
  if (isSuspended(mod)) return false;
  mod.pixelocityPendingImage = source;
  try {
    return cpp.loadImageExternal(mod, width, height) === 1;
  } catch (err) {
    console.warn("[WASM] loadImageExternal failed:", err);
    return false;
  } finally {
    delete mod.pixelocityPendingImage;
  }
}
function uploadImageData(image, width, height) {
  if (!state.initialized || !wasmRef.module) return;
  let imgWidth = 0;
  let imgHeight = 0;
  let pixels = null;
  if (typeof ImageData !== "undefined" && image instanceof ImageData) {
    imgWidth = image.width;
    imgHeight = image.height;
    pixels = image.data;
  } else if (image instanceof Uint8Array || image instanceof Uint8ClampedArray) {
    if (!width || !height || image.length === 0) return;
    imgWidth = width;
    imgHeight = height;
    pixels = image;
  } else if (typeof HTMLImageElement !== "undefined" && image instanceof HTMLImageElement) {
    imgWidth = image.naturalWidth || image.width;
    imgHeight = image.naturalHeight || image.height;
    const tempCanvas = document.createElement("canvas");
    tempCanvas.width = imgWidth;
    tempCanvas.height = imgHeight;
    const ctx = tempCanvas.getContext("2d");
    if (!ctx) return;
    ctx.drawImage(image, 0, 0);
    pixels = ctx.getImageData(0, 0, imgWidth, imgHeight).data;
  } else {
    return;
  }
  if (!imgWidth || !imgHeight || !pixels || pixels.length === 0) return;
  const numBytes = imgWidth * imgHeight * 4;
  const module = wasmRef.module;
  const busy = isBusy(module);
  const src = busy ? asU8(pixels).slice(0, numBytes) : asU8(pixels).subarray(0, numBytes);
  const w = imgWidth;
  const h = imgHeight;
  const upload = () => {
    if (!state.initialized || wasmRef.module !== module) return;
    const ptr = module._malloc(numBytes);
    module.HEAPU8.set(src, ptr);
    try {
      cpp.loadImageData(module, ptr, w, h);
    } finally {
      module._free(ptr);
    }
  };
  if (!busy) upload();
  else runWhenIdle(module, upload).catch((err) => console.error("[WASM] deferred image upload failed:", err));
}
function uploadVideoFrame(videoOrPixels, width, height) {
  if (!state.initialized || !wasmRef.module) return;
  if (isSuspended(wasmRef.module)) return;
  if (videoOrPixels instanceof Uint8Array || videoOrPixels instanceof Uint8ClampedArray) {
    if (!width || !height || videoOrPixels.length === 0) return;
    const numBytes2 = width * height * 4;
    const ptr2 = wasmRef.module._malloc(numBytes2);
    wasmRef.module.HEAPU8.set(asU8(videoOrPixels).subarray(0, numBytes2), ptr2);
    cpp.uploadVideoFrame(wasmRef.module, ptr2, width, height);
    wasmRef.module._free(ptr2);
    return;
  }
  const video = videoOrPixels;
  if (!video || video.readyState < 2) return;
  const w = video.videoWidth;
  const h = video.videoHeight;
  if (!w || !h) return;
  const tempCanvas = document.createElement("canvas");
  tempCanvas.width = w;
  tempCanvas.height = h;
  const ctx = tempCanvas.getContext("2d");
  if (!ctx) return;
  ctx.drawImage(video, 0, 0, w, h);
  const imageData = ctx.getImageData(0, 0, w, h);
  const numBytes = w * h * 4;
  const ptr = wasmRef.module._malloc(numBytes);
  wasmRef.module.HEAPU8.set(asU8(imageData.data).subarray(0, numBytes), ptr);
  cpp.uploadVideoFrame(wasmRef.module, ptr, w, h);
  wasmRef.module._free(ptr);
}
async function resizeCanvas(width, height) {
  if (!state.initialized || !wasmRef.module) return;
  state.canvasWidth = width;
  state.canvasHeight = height;
  await cpp.resizeCanvas(wasmRef.module, width, height);
}
export {
  captureFrame,
  captureFrameDataUrl,
  resizeCanvas,
  takeScreenshot,
  uploadImageData,
  uploadImageSource,
  uploadVideoFrame
};
