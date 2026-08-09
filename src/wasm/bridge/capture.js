// src/wasm/bridge/capture.js
// Frame capture, screenshots, and image/video upload.

import { state, wasmRef } from './state.js';

/**
 * Capture the current rendered frame as RGBA8 pixel data.
 *
 * The capture is asynchronous (GPU readback via CopyTextureToBuffer + mapAsync).
 * This function polls requestAnimationFrame until the GPU has finished, then
 * converts the RGBA32Float frame data to RGBA8 and resolves the Promise.
 *
 * @returns {Promise<ImageData>} Resolves with an ImageData containing the frame pixels.
 */
export function captureFrame() {
  return new Promise((resolve, reject) => {
    if (!state.initialized || !wasmRef.module) {
      reject(new Error('[WASM] Renderer not initialized'));
      return;
    }

    wasmRef.module.ccall('beginFrameCapture', null, [], []);

    const pollState = () => {
      if (!wasmRef.module) {
        reject(new Error('[WASM] Module invalidated during capture'));
        return;
      }

      const captureState = wasmRef.module.ccall('getFrameCaptureState', 'number', [], []);

      if (captureState === 3) { // Complete
        const width = wasmRef.module.ccall('getCanvasWidth', 'number', [], []);
        const height = wasmRef.module.ccall('getCanvasHeight', 'number', [], []);
        const numPixels = width * height;
        const floatByteLength = numPixels * 4 * 4;

        const floatPtr = wasmRef.module.ccall('readCapturedFrame', 'number', [], []);

        if (!floatPtr) {
          wasmRef.module.ccall('endFrameCapture', null, [], []);
          reject(new Error('[WASM] readCapturedFrame returned null pointer'));
          return;
        }

        const floatBuffer = wasmRef.module.HEAPF32.subarray(
          floatPtr / 4,
          (floatPtr + floatByteLength) / 4
        );

        const rgba8 = new Uint8ClampedArray(numPixels * 4);
        for (let i = 0; i < numPixels * 4; i++) {
          rgba8[i] = Math.min(255, Math.max(0, Math.round(floatBuffer[i] * 255)));
        }

        wasmRef.module.ccall('endFrameCapture', null, [], []);

        const imageData = new ImageData(rgba8, width, height);
        resolve(imageData);

      } else if (captureState === 4) { // Error
        wasmRef.module.ccall('endFrameCapture', null, [], []);
        reject(new Error('[WASM] GPU frame capture failed on C++ side'));
      } else { // 0=Idle, 1=Copying, 2=Mapping
        requestAnimationFrame(pollState);
      }
    };

    requestAnimationFrame(pollState);
  });
}

/**
 * Capture the current frame and return it as a data URL PNG string.
 * @returns {Promise<string>}
 */
export async function captureFrameDataUrl() {
  const imgData = await captureFrame();
  const offscreen = document.createElement('canvas');
  offscreen.width = imgData.width;
  offscreen.height = imgData.height;
  const ctx = offscreen.getContext('2d');
  if (!ctx) throw new Error('[WASM] Failed to create 2D context for data URL');
  ctx.putImageData(imgData, 0, 0);
  return offscreen.toDataURL('image/png');
}

/**
 * Take a screenshot of the current frame and trigger browser file download.
 * @param {string} [filename='pixelocity-shader.png'] - Download filename
 * @returns {Promise<void>}
 */
export async function takeScreenshot(filename = 'pixelocity-shader.png') {
  const dataUrl = await captureFrameDataUrl();
  const a = document.createElement('a');
  a.href = dataUrl;
  a.download = filename;
  a.click();
}

/**
 * Upload raw RGBA8 image pixel data to C++ texture
 * @param {ImageData|HTMLImageElement|Uint8Array} image - Image data, element, or byte array
 * @param {number} [width] - Width in pixels (required if image is Uint8Array)
 * @param {number} [height] - Height in pixels (required if image is Uint8Array)
 */
export function uploadImageData(image, width, height) {
  if (!state.initialized || !wasmRef.module) return;

  let imgWidth, imgHeight, pixels;
  if (typeof ImageData !== 'undefined' && image instanceof ImageData) {
    imgWidth = image.width;
    imgHeight = image.height;
    pixels = image.data;
  } else if (image instanceof Uint8Array) {
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
  wasmRef.module.HEAPU8.set(pixels, ptr);

  try {
    wasmRef.module.ccall(
      'loadImageData',
      null,
      ['number', 'number', 'number', 'number'],
      [ptr, imgWidth, imgHeight, numBytes]
    );
  } finally {
    wasmRef.module._free(ptr);
  }
}

/**
 * Upload a frame from an HTMLVideoElement or VideoFrame
 * @param {HTMLVideoElement} video - Video element
 */
export function uploadVideoFrame(video) {
  if (!state.initialized || !wasmRef.module) return;
  if (!video || video.readyState < 2) return;

  const width = video.videoWidth;
  const height = video.videoHeight;
  if (!width || !height) return;

  const tempCanvas = document.createElement('canvas');
  tempCanvas.width = width;
  tempCanvas.height = height;
  const ctx = tempCanvas.getContext('2d');
  if (!ctx) return;

  ctx.drawImage(video, 0, 0, width, height);
  const imageData = ctx.getImageData(0, 0, width, height);

  const numBytes = width * height * 4;
  const ptr = wasmRef.module._malloc(numBytes);
  wasmRef.module.HEAPU8.set(imageData.data, ptr);

  wasmRef.module.ccall(
    'uploadVideoFrame',
    null,
    ['number', 'number', 'number', 'number'],
    [ptr, width, height, numBytes]
  );

  wasmRef.module._free(ptr);
}

/**
 * Resize the rendering canvas and rebuild swapchain textures
 * @param {number} width - New width
 * @param {number} height - New height
 */
export function resizeCanvas(width, height) {
  if (!state.initialized || !wasmRef.module) return;
  state.canvasWidth = width;
  state.canvasHeight = height;
  wasmRef.module.ccall(
    'resizeCanvas',
    null,
    ['number', 'number'],
    [width, height]
  );
}
