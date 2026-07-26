// Frame capture, screenshots, and image/video upload.

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
    if (!state.initialized || !wasmModule) {
      reject(new Error('[WASM] Renderer not initialized'));
      return;
    }

    // Kick off the async GPU readback.
    wasmModule.ccall('beginFrameCapture', null, [], []);

    // Poll until the GPU map operation completes.
    function poll() {
      const captureState = wasmModule.ccall('getFrameCaptureState', 'number', [], []);

      if (captureState === 2) {
        // Ready — read the pixel data from the mapped buffer.
        const w = wasmModule.ccall('getCanvasWidth',  'number', [], []);
        const h = wasmModule.ccall('getCanvasHeight', 'number', [], []);
        const byteLen = w * h * 4;
        const ptr = wasmModule._malloc(byteLen);
        let written = 0;
        try {
          written = wasmModule.ccall(
            'readCapturedFrame',
            'number',
            ['number', 'number'],
            [ptr, byteLen]
          );
        } catch (e) {
          wasmModule._free(ptr);
          wasmModule.ccall('endFrameCapture', null, [], []);
          reject(e);
          return;
        }

        if (written > 0) {
          // Copy out of WASM heap before freeing.
          const raw = new Uint8ClampedArray(wasmModule.HEAPU8.buffer, ptr, written).slice();
          wasmModule._free(ptr);
          wasmModule.ccall('endFrameCapture', null, [], []);
          resolve(new ImageData(raw, w, h));
        } else {
          wasmModule._free(ptr);
          wasmModule.ccall('endFrameCapture', null, [], []);
          reject(new Error('[WASM] readCapturedFrame returned 0 bytes'));
        }
      } else if (captureState === 3) {
        // Error state.
        reject(new Error('[WASM] Frame capture failed (GPU error)'));
      } else {
        // Still pending — try again next frame.
        requestAnimationFrame(poll);
      }
    }

    poll();
  });
}

/**
 * Take a screenshot of the current frame and download it as a PNG file.
 * Uses OffscreenCanvas when available (Chrome/Firefox), falls back to a
 * regular canvas element for Safari compatibility.
 * @param {string} [filename='screenshot.png'] - Download filename.
 * @returns {Promise<void>}
 */
export async function takeScreenshot(filename = 'screenshot.png') {
  const imageData = await captureFrame();

  let blob;
  if (typeof OffscreenCanvas !== 'undefined') {
    // Fast path: OffscreenCanvas is available (Chrome, Edge, Firefox).
    const offscreen = new OffscreenCanvas(imageData.width, imageData.height);
    const ctx = offscreen.getContext('2d');
    ctx.putImageData(imageData, 0, 0);
    blob = await offscreen.convertToBlob({ type: 'image/png' });
  } else {
    // Fallback for Safari: use a regular <canvas> element.
    blob = await new Promise((resolve) => {
      const tmpCanvas  = document.createElement('canvas');
      tmpCanvas.width  = imageData.width;
      tmpCanvas.height = imageData.height;
      const ctx = tmpCanvas.getContext('2d');
      ctx.putImageData(imageData, 0, 0);
      tmpCanvas.toBlob((b) => resolve(b), 'image/png');
    });
  }

  const url = URL.createObjectURL(blob);
  const a   = document.createElement('a');
  a.href    = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

/**
 * Capture the current frame and return a PNG data URL (for export / sharing).
 * Async because it uses the GPU readback path.
 */
export async function captureFrameDataUrl() {
  const imageData = await captureFrame();
  let blob;
  if (typeof OffscreenCanvas !== 'undefined') {
    const offscreen = new OffscreenCanvas(imageData.width, imageData.height);
    const ctx = offscreen.getContext('2d');
    ctx.putImageData(imageData, 0, 0);
    blob = await offscreen.convertToBlob({ type: 'image/png' });
  } else {
    blob = await new Promise((resolve) => {
      const tmp = document.createElement('canvas');
      tmp.width = imageData.width;
      tmp.height = imageData.height;
      tmp.getContext('2d').putImageData(imageData, 0, 0);
      tmp.toBlob((b) => resolve(b), 'image/png');
    });
  }
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
}

/**
 * Upload RGBA pixel data as an image (one-time load).
 * @param {Uint8Array|Uint8ClampedArray} rgbaPixels - RGBA bytes (width * height * 4)
 * @param {number} width
 * @param {number} height
 */
export function uploadImageData(rgbaPixels, width, height) {
  if (!state.initialized || !wasmModule) return;
  if (!width || !height || !rgbaPixels?.length) return;

  const ptr = wasmModule._malloc(rgbaPixels.length);
  wasmModule.HEAPU8.set(rgbaPixels, ptr);
  try {
    wasmModule.ccall('loadImageData', null, ['number', 'number', 'number'], [ptr, width, height]);
  } finally {
    wasmModule._free(ptr);
  }
}

/**
 * Upload RGBA pixel data as a video frame (called every frame).
 * The C++ side uses a persistent staging buffer to avoid per-frame heap allocation.
 * @param {Uint8Array|Uint8ClampedArray} rgbaPixels - RGBA bytes (width * height * 4)
 * @param {number} width
 * @param {number} height
 */
export function uploadVideoFrame(rgbaPixels, width, height) {
  if (!state.initialized || !wasmModule) return;

  const ptr = wasmModule._malloc(rgbaPixels.length);
  wasmModule.HEAPU8.set(rgbaPixels, ptr);
  try {
    wasmModule.ccall('uploadVideoFrame', null, ['number', 'number', 'number'], [ptr, width, height]);
  } finally {
    wasmModule._free(ptr);
  }
}
