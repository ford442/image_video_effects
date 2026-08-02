/**
 * WASM vs TS WebGPU pixel diff on frozen seeds — Tier B promotion evidence (gate 2).
 *
 * The parity spec compares mean luminance and coverage, which two structurally different
 * images can both satisfy. This captures N frames at pinned render state on both backends
 * and reports per-pixel deltas, so "parity" is a number a reviewer can argue with.
 *
 *   npm run build && WASM_GPU_TESTS=1 npx playwright test tests/wasm-pixel-diff.spec.ts
 *
 * Skips without a real adapter (cloud VMs) and writes a stub report — see
 * WASM_BACKEND_POLICY.md: a run with no adapter is not evidence.
 */

import { test, expect } from '@playwright/test';
import { PARITY_MATRIX } from './fixtures/parityMatrix';
import {
  startStaticServer,
  stopStaticServer,
  buildAppUrl,
  waitForTestApi,
  loadShaderOnSlot,
  applyTestState,
  isStrictGpuMode,
  collectAdapterSummary,
  captureFrame,
  diffFrames,
  buildPixelDiffReport,
  writePixelDiffReport,
  writeFrameArtifact,
  type PixelDiffResult,
} from './helpers/rendererHarness';

/** Frames captured per shader at a frozen time — deterministic, not a sequence. */
const FROZEN_TIMES = [1.0, 2.5, 4.0];
const SETTLE_MS = 1200;

/** Report-only thresholds: this spec documents parity, it does not gate merges yet. */
const REPORT_ONLY = true;

test.beforeAll(async () => {
  await startStaticServer();
}, 60000);

test.afterAll(async () => {
  await stopStaticServer();
});

test('pixel diff: WASM vs WebGPU on frozen seeds', async ({ page, browser }) => {
  test.setTimeout(10 * 60 * 1000);

  const wasmPage = page;
  const tsPage = await browser.newPage();

  await wasmPage.goto(buildAppUrl('wasm'), { waitUntil: 'networkidle' });
  await waitForTestApi(wasmPage);
  await tsPage.goto(buildAppUrl('webgpu'), { waitUntil: 'networkidle' });
  await waitForTestApi(tsPage);

  const wasmBackend = await wasmPage.evaluate(() => (window as any).__pixelocity__?.getRendererType?.());
  const tsBackend = await tsPage.evaluate(() => (window as any).__pixelocity__?.getRendererType?.());

  if (wasmBackend !== 'wasm' || tsBackend !== 'webgpu') {
    writePixelDiffReport(
      buildPixelDiffReport([], {
        gpuObserved: false,
        note: `Backends unavailable (wasm=${wasmBackend}, webgpu=${tsBackend}). `
          + 'Cloud/headless VMs cannot observe a WebGPU adapter — not promotion evidence.',
      }),
    );
    await tsPage.close();
    test.skip(!isStrictGpuMode(), 'Set WASM_GPU_TESTS=1 on a GPU machine');
    expect(`${wasmBackend}/${tsBackend}`, 'strict mode needs both backends').toBe('wasm/webgpu');
    return;
  }

  const wasmAdapterSummary = await collectAdapterSummary(wasmPage, 'wasm');
  const webgpuAdapterSummary = await collectAdapterSummary(tsPage, 'webgpu');
  const userAgent = await wasmPage.evaluate(() => navigator.userAgent);
  const diffs: PixelDiffResult[] = [];

  for (const shaderCase of PARITY_MATRIX) {
    await loadShaderOnSlot(wasmPage, shaderCase);
    await loadShaderOnSlot(tsPage, shaderCase);

    for (let i = 0; i < FROZEN_TIMES.length; i++) {
      const frozen = {
        ...(shaderCase.testState ?? { mouseX: 0.5, mouseY: 0.5 }),
        time: FROZEN_TIMES[i],
      };

      await applyTestState(wasmPage, frozen);
      await applyTestState(tsPage, frozen);
      await wasmPage.waitForTimeout(SETTLE_MS);
      await tsPage.waitForTimeout(SETTLE_MS);
      // Re-apply: feedback shaders advance their own state while settling.
      await applyTestState(wasmPage, frozen);
      await applyTestState(tsPage, frozen);

      const wasmFrame = await captureFrame(wasmPage);
      const tsFrame = await captureFrame(tsPage);
      if (!wasmFrame || !tsFrame) continue;

      const diff = diffFrames(shaderCase.id, i, wasmFrame, tsFrame);
      diffs.push(diff);

      writeFrameArtifact(wasmFrame, `test-results/pixel-diff/${shaderCase.id}-t${i}-wasm.png`);
      writeFrameArtifact(tsFrame, `test-results/pixel-diff/${shaderCase.id}-t${i}-webgpu.png`);

      // eslint-disable-next-line no-console
      console.log(
        `[pixel-diff:${shaderCase.id}#${i}] mean=${diff.meanAbsDelta.toFixed(4)} `
          + `max=${diff.maxAbsDelta.toFixed(4)} differing=${(diff.differingCellRatio * 100).toFixed(1)}%`,
      );
    }
  }

  await tsPage.close();

  writePixelDiffReport(
    buildPixelDiffReport(diffs, {
      gpuObserved: true,
      frames: FROZEN_TIMES.length,
      wasmAdapterSummary,
      webgpuAdapterSummary,
      userAgent,
    }),
  );

  // Evidence, not a gate: thresholds get set once a real GPU run says what "same" costs.
  expect(diffs.length, 'captured at least one frozen-seed comparison').toBeGreaterThan(0);
  if (!REPORT_ONLY) {
    for (const d of diffs) {
      expect(d.differingCellRatio).toBeLessThan(0.25);
    }
  }
});
