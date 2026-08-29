import { state, wasmRef } from './state.js';

export function captureFrame(): Promise<ImageData> {
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

      const captureState = Number(wasmRef.module.ccall('getFrameCaptureState', 'number', [], []));

      if (captureState === 3) {
        const width = Number(wasmRef.module.ccall('getCanvasWidth', 'number', [], []));
        const height = Number(wasmRef.module.ccall('getCanvasHeight', 'number', [], []));
        const numPixels = width * height;
        const floatByteLength = numPixels * 4 * 4;

        const floatPtr = Number(wasmRef.module.ccall('readCapturedFrame', 'number', [], []));

        if (!floatPtr) {
          wasmRef.module.ccall('endFrameCapture', null, [], []);
          reject(new Error('[WASM] readCapturedFrame returned null pointer'));
          return;
        }

        const floatBuffer = wasmRef.module.HEAPF32.subarray(
          floatPtr / 4,
          (floatPtr + floatByteLength) / 4,
        );

        const rgba8 = new Uint8ClampedArray(numPixels * 4);
        for (let i = 0; i < numPixels * 4; i++) {
          rgba8[i] = Math.min(255, Math.max(0, Math.round(floatBuffer[i] * 255)));
        }

        wasmRef.module.ccall('endFrameCapture', null, [], []);
        resolve(new ImageData(rgba8, width, height));
      } else if (captureState === 4) {
        wasmRef.module.ccall('endFrameCapture', null, [], []);
        reject(new Error('[WASM] GPU frame capture failed on C++ side'));
      } else {
        requestAnimationFrame(pollState);
      }
    };

    requestAnimationFrame(pollState);
  });
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
  wasmRef.module.HEAPU8.set(imageData.data, ptr);

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
