/**
 * WASM canvas/encode parity on a REAL GPU (#1080 hardware handoff).
 *
 * 1. The committed artifact is 6-slot: setSlotShader(5, …) reads back on
 *    ?renderer=wasm (slot_limits.json maxPhysicalSlots).
 * 2. A 2 s ?renderer=wasm clip goes through WebCodecs (COPY_SRC canvas when the
 *    C++ probe is green, else the captureFrame() readback), not the Canvas2D
 *    putImageData → MediaRecorder pump, and is a real WebM.
 *
 * Headless / cloud VMs have no WebGPU adapter: the spec writes a stub report
 * with gpuObserved: false and skips unless WASM_GPU_TESTS=1 (strict).
 *
 *   npm run build && WASM_GPU_TESTS=1 npx playwright test tests/wasm-encode-parity.gpu.spec.ts --project=chromium
 */

import fs from 'fs';
import path from 'path';
import { test, expect, Page } from '@playwright/test';
import {
  startStaticServer,
  stopStaticServer,
  buildAppUrl,
  waitForTestApi,
  getActiveBackend,
  isStrictGpuMode,
  collectAdapterSummary,
} from './helpers/rendererHarness';
import { PARITY_MATRIX } from './fixtures/parityMatrix';

const CLIP_MS = 2000;
const REPORT = path.join('test-results', 'wasm-encode-parity-report.json');
const report: Record<string, unknown> = {};

function writeReport(): void {
  fs.mkdirSync(path.dirname(REPORT), { recursive: true });
  fs.writeFileSync(REPORT, JSON.stringify({ generatedAt: new Date().toISOString(), ...report }, null, 2));
}

/** Returns false (after recording why) when this machine can't produce evidence. */
async function requireWasmGpu(page: Page, needVideoEncoder: boolean): Promise<boolean> {
  await page.goto(buildAppUrl('wasm'), { waitUntil: 'networkidle' });
  await waitForTestApi(page);
  const backend = await getActiveBackend(page);
  const hasVideoEncoder = await page.evaluate(() => typeof VideoEncoder !== 'undefined');
  // The ASYNCIFY init ccall can report "ready" before C++ has a device; the WASM
  // breadcrumb is only published once C++ Initialize() really finished.
  const cppReady = backend === 'wasm' && await page
    .waitForFunction(() => {
      const probe = (window as any).webgpuProbe;
      return probe?.backend === 'wasm' && probe.ok === true;
    }, undefined, { timeout: 20000 })
    .then(() => true, () => false);
  if (cppReady && (!needVideoEncoder || hasVideoEncoder)) return true;
  report.gpuObserved = false;
  report.note = `backend=${backend} cppReady=${cppReady} VideoEncoder=${hasVideoEncoder}. No WebGPU adapter here — not evidence.`;
  writeReport();
  test.skip(!isStrictGpuMode(), 'Set WASM_GPU_TESTS=1 on a GPU machine');
  expect(backend, 'strict mode needs the WASM backend').toBe('wasm');
  expect(cppReady, 'strict mode needs C++ Initialize() to finish (real adapter)').toBe(true);
  expect(hasVideoEncoder || !needVideoEncoder, 'strict mode needs WebCodecs VideoEncoder').toBe(true);
  return false;
}

test.beforeAll(async () => {
  await startStaticServer();
}, 60000);

test.afterAll(async () => {
  writeReport();
  await stopStaticServer();
});

test('committed WASM artifact round-trips all 6 physical slots', async ({ page }) => {
  test.setTimeout(60000);
  if (!(await requireWasmGpu(page, false))) return;

  const shader = PARITY_MATRIX[0];
  const slots = await page.evaluate(async (s) => {
    const api = (window as any).__pixelocity__;
    const ok = await api.loadShader(s.id, s.url);
    // Bypass the manager's quality cap (maxActiveSlots 1-3): this checks the
    // physical ceiling compiled into the artifact, not the performance policy.
    const wasm = api.renderer.currentRenderer;
    const accepted = wasm.setSlotShader(5, s.id);
    const state = wasm.getSlotState(5);
    const diag = api.renderer.getDiagnostics()?.wasm;
    return {
      loaded: ok,
      accepted,
      slot5: state?.shaderId ?? null,
      dropped: wasm.getDroppedSlots(),
      maxShaderSlots: diag?.maxShaderSlots ?? null,
    };
  }, shader);

  report.gpuObserved = true;
  report.slots = slots;
  expect(slots.loaded, `${shader.id} compiled on WASM`).toBe(true);
  expect(slots.maxShaderSlots, 'artifact MAX_SHADER_SLOTS').toBe(6);
  expect(slots.accepted, 'setSlotShader(5) accepted').toBe(true);
  expect(slots.slot5, 'slot 5 reads back').toBe(shader.id);
  expect(slots.dropped).toEqual([]);
});

test('WASM records a 2s WebM through WebCodecs (no Canvas2D pump)', async ({ page }) => {
  test.setTimeout(90000);
  if (!(await requireWasmGpu(page, true))) return;

  await page.waitForTimeout(1000);
  const clip = await page.evaluate(async (durationMs) => {
    const counts = { putImageData: 0, getContext2d: 0, mediaRecorder: 0, videoEncoder: 0 };
    const ctxProto = CanvasRenderingContext2D.prototype;
    const origPut = ctxProto.putImageData;
    ctxProto.putImageData = function (this: CanvasRenderingContext2D, ...args: unknown[]) {
      counts.putImageData++;
      return (origPut as (...a: unknown[]) => void).apply(this, args);
    } as typeof ctxProto.putImageData;
    const canvasProto = HTMLCanvasElement.prototype;
    const origGetContext = canvasProto.getContext;
    canvasProto.getContext = function (this: HTMLCanvasElement, type: string, ...rest: unknown[]) {
      if (type === '2d') counts.getContext2d++;
      return (origGetContext as (...a: unknown[]) => unknown).call(this, type, ...rest);
    } as typeof canvasProto.getContext;
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
        getContext2dCalls: counts.getContext2d,
        mediaRecorderCount: counts.mediaRecorder,
        videoEncoderCount: counts.videoEncoder,
        canvasCopySrc: manager.getDiagnostics()?.wasm?.canvasCopySrc ?? null,
        probeCanvasCopySrc: (window as any).webgpuProbe?.canvasCopySrc ?? null,
      };
    } finally {
      ctxProto.putImageData = origPut;
      canvasProto.getContext = origGetContext;
      window.MediaRecorder = OrigMR;
      window.VideoEncoder = OrigVE;
    }
  }, CLIP_MS);

  report.gpuObserved = true;
  report.adapterSummary = await collectAdapterSummary(page, 'wasm');
  report.userAgent = await page.evaluate(() => navigator.userAgent);
  report.frameSource = clip.canvasCopySrc ? 'canvas (C++ COPY_SRC)' : 'readback (beginFrameCapture)';
  report.clip = clip;

  expect(clip.videoEncoderCount, 'WebCodecs VideoEncoder used').toBeGreaterThan(0);
  expect(clip.mediaRecorderCount, 'no MediaRecorder fallback').toBe(0);
  expect(clip.getContext2dCalls, 'no Canvas2D context in the happy path').toBe(0);
  expect(clip.putImageDataCalls, 'no Canvas2D putImageData pump').toBe(0);
  expect(clip.canvasCopySrc, 'breadcrumb matches the C++ probe').toBe(clip.probeCanvasCopySrc);
  expect(clip.type).toBe('video/webm');
  expect(clip.ebml, 'WebM EBML header').toBe(true);
  expect(clip.bytes).toBeGreaterThan(1024);
});
