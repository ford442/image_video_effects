/**
 * WASM Recording 2.0 — one 2-second WebM from ?renderer=wasm through WebCodecs.
 *
 * Needs a real WebGPU adapter; headless/cloud VMs write a stub report with
 * gpuObserved: false and skip (not evidence). #1080-adjacent, not a close
 * condition for the code landing.
 *
 *   npm run build && WASM_GPU_TESTS=1 npx playwright test tests/wasm-recording.gpu.spec.ts --project=chromium
 */

import fs from 'fs';
import path from 'path';
import { test, expect } from '@playwright/test';
import {
  startStaticServer,
  stopStaticServer,
  buildAppUrl,
  waitForTestApi,
  getActiveBackend,
  isStrictGpuMode,
  collectAdapterSummary,
} from './helpers/rendererHarness';

const CLIP_MS = 2000;
const REPORT = path.join('test-results', 'wasm-recording-report.json');

interface ClipResult {
  bytes: number;
  type: string;
  ebml: boolean;
  putImageDataCalls: number;
  mediaRecorderCount: number;
  videoEncoderCount: number;
  canvasCopySrc: boolean | null;
}

function writeReport(report: Record<string, unknown>): void {
  fs.mkdirSync(path.dirname(REPORT), { recursive: true });
  fs.writeFileSync(REPORT, JSON.stringify({ generatedAt: new Date().toISOString(), ...report }, null, 2));
}

test.beforeAll(async () => {
  await startStaticServer();
}, 60000);

test.afterAll(async () => {
  await stopStaticServer();
});

test('WASM records a 2s WebM through WebCodecs (no Canvas2D pump)', async ({ page }) => {
  test.setTimeout(90000);
  await page.goto(buildAppUrl('wasm'), { waitUntil: 'networkidle' });
  await waitForTestApi(page);

  const backend = await getActiveBackend(page);
  const hasVideoEncoder = await page.evaluate(() => typeof VideoEncoder !== 'undefined');
  if (backend !== 'wasm' || !hasVideoEncoder) {
    writeReport({
      gpuObserved: false,
      note: `backend=${backend} VideoEncoder=${hasVideoEncoder}. Headless/cloud VMs have no WebGPU adapter — not evidence.`,
    });
    test.skip(!isStrictGpuMode(), 'Set WASM_GPU_TESTS=1 on a GPU machine');
    expect(backend, 'strict mode needs the WASM backend').toBe('wasm');
    expect(hasVideoEncoder, 'strict mode needs WebCodecs VideoEncoder').toBe(true);
    return;
  }

  await page.waitForTimeout(1000);
  const clip: ClipResult = await page.evaluate(async (durationMs) => {
    const counts = { putImageData: 0, mediaRecorder: 0, videoEncoder: 0 };
    const proto = CanvasRenderingContext2D.prototype;
    const origPut = proto.putImageData;
    proto.putImageData = function (this: CanvasRenderingContext2D, ...args: unknown[]) {
      counts.putImageData++;
      return (origPut as (...a: unknown[]) => void).apply(this, args);
    } as typeof proto.putImageData;
    const OrigMR = window.MediaRecorder;
    window.MediaRecorder = class extends OrigMR {
      constructor(...args: ConstructorParameters<typeof MediaRecorder>) {
        super(...args);
        counts.mediaRecorder++;
      }
    } as typeof MediaRecorder;
    const OrigVE = window.VideoEncoder;
    window.VideoEncoder = class extends OrigVE {
      constructor(...args: ConstructorParameters<typeof VideoEncoder>) {
        super(...args);
        counts.videoEncoder++;
      }
    } as typeof VideoEncoder;

    try {
      const manager = (window as any).__pixelocity__.renderer;
      const canvas = document.querySelector('[id^="pixelocity-wasm-canvas-"]') as HTMLCanvasElement;
      const blob: Blob = await manager.startRecording(canvas, { durationMs, frameRate: 30 });
      const head = new Uint8Array(await blob.slice(0, 4).arrayBuffer());
      return {
        bytes: blob.size,
        type: blob.type,
        ebml: head[0] === 0x1a && head[1] === 0x45 && head[2] === 0xdf && head[3] === 0xa3,
        putImageDataCalls: counts.putImageData,
        mediaRecorderCount: counts.mediaRecorder,
        videoEncoderCount: counts.videoEncoder,
        canvasCopySrc: manager.getDiagnostics()?.wasm?.canvasCopySrc ?? null,
      };
    } finally {
      proto.putImageData = origPut;
      window.MediaRecorder = OrigMR;
      window.VideoEncoder = OrigVE;
    }
  }, CLIP_MS);

  writeReport({
    gpuObserved: true,
    adapterSummary: await collectAdapterSummary(page, 'wasm'),
    userAgent: await page.evaluate(() => navigator.userAgent),
    frameSource: clip.canvasCopySrc ? 'canvas (C++ COPY_SRC)' : 'readback (beginFrameCapture)',
    clip,
  });

  expect(clip.videoEncoderCount, 'WebCodecs VideoEncoder used').toBeGreaterThan(0);
  expect(clip.mediaRecorderCount, 'no MediaRecorder fallback').toBe(0);
  expect(clip.putImageDataCalls, 'no Canvas2D putImageData pump').toBe(0);
  expect(clip.type).toBe('video/webm');
  expect(clip.ebml, 'WebM EBML header').toBe(true);
  expect(clip.bytes).toBeGreaterThan(1024);
});
