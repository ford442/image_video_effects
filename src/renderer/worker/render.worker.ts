/* eslint-disable no-restricted-globals */
/**
 * render.worker.ts — the render worker (#1314 WP-1).
 *
 * Owns the TS WebGPU renderer, its GPUDevice and the OffscreenCanvas
 * transferred from the main thread. All logic lives in renderWorkerHost.ts;
 * this file only wires the worker scope (fetch base, chunk path, messages).
 */

import { setRendererErrorHandler } from '../ErrorHandling';
import { createWorkerRenderer } from './workerRenderer';
import { getLiveDeviceCount, runWebGpuBootProbe, toWebGpuProbeBreadcrumb } from '../webgpuBootProbe';
import { createRenderWorkerHost } from './renderWorkerHost';
import type { RenderEvent, RenderToWorker, RenderWorkerCaps } from './protocol';

// The built worker lives in static/js/ (vite.config.ts worker output), two levels
// below the app root; under `vite dev` it is served from the root's /src/ tree.
// Lazy chunks resolve against the worker's own URL via import.meta.url, so only
// page-relative fetches need this base.
const APP_BASE = import.meta.env.DEV
  ? new URL('/', self.location.href).href
  : new URL('../../', self.location.href).href;

// Shader fetches use page-relative URLs (./shaders/x.wgsl); resolve them
// against the app root the main thread reports, not this script's folder.
let fetchBase = APP_BASE;
const nativeFetch = self.fetch.bind(self);
self.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
  if (typeof input === 'string' && !/^[a-z][a-z0-9+.-]*:/i.test(input)) {
    return nativeFetch(new URL(input, fetchBase).href, init);
  }
  return nativeFetch(input, init);
}) as typeof fetch;

function detectCaps(): RenderWorkerCaps {
  let offscreenWebgpu = false;
  try {
    offscreenWebgpu = typeof OffscreenCanvas !== 'undefined' && !!new OffscreenCanvas(1, 1).getContext('webgpu');
  } catch {
    offscreenWebgpu = false;
  }
  return {
    gpu: 'gpu' in navigator && !!navigator.gpu,
    offscreenWebgpu,
    raf: typeof requestAnimationFrame === 'function',
    videoFrame: typeof VideoFrame !== 'undefined',
    crossOriginIsolated: !!self.crossOriginIsolated,
    sharedArrayBuffer: typeof SharedArrayBuffer !== 'undefined',
  };
}

// tsconfig has the DOM lib only: describe the bits of the worker scope we use.
const scope = self as unknown as {
  postMessage(message: unknown, transfer: Transferable[]): void;
  addEventListener(type: 'message', listener: (event: MessageEvent<RenderToWorker>) => void): void;
};
const post = (event: RenderEvent, transfer: Transferable[] = []) => scope.postMessage(event, transfer);

/** Presented frame → PNG base64 via an OffscreenCanvas (screenshots, test harness). */
async function encodeFramePng(frame: VideoFrame): Promise<string | null> {
  const bitmap = await createImageBitmap(frame);
  const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
  // A Display P3 swapchain yields smpte432 frames; keep the 2D surface wide-gamut so the
  // PNG is not clamped to sRGB (fail-soft: browsers without 2D colorSpace use the default).
  const wide = (frame.colorSpace?.primaries as string | null | undefined) === 'smpte432';
  let ctx: OffscreenCanvasRenderingContext2D | null = null;
  if (wide) {
    try {
      ctx = canvas.getContext('2d', { colorSpace: 'display-p3' });
    } catch {
      ctx = null;
    }
  }
  ctx ??= canvas.getContext('2d');
  if (!ctx) return null;
  ctx.drawImage(bitmap, 0, 0);
  bitmap.close();
  const bytes = new Uint8Array(await (await canvas.convertToBlob({ type: 'image/png' })).arrayBuffer());
  let binary = '';
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(binary);
}

const host = createRenderWorkerHost({
  encodeFramePng,
  post,
  createRenderer: createWorkerRenderer,
  runProbe: (canvas, width, height, options) => runWebGpuBootProbe(canvas, width, height, options),
  liveDeviceCount: getLiveDeviceCount,
  crash: (message) => {
    // Uncaught on purpose: the page sees an `error` event on the Worker, as for a real crash.
    setTimeout(() => {
      throw new Error(message);
    }, 0);
  },
  toBreadcrumb: toWebGpuProbeBreadcrumb,
  setErrorSink: (sink) => setRendererErrorHandler(sink),
  setFetchBase: (url) => {
    fetchBase = url;
  },
});

scope.addEventListener('message', (event) => host.handle(event.data));
post({ type: 'hello', caps: detectCaps() });
