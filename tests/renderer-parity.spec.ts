/**
 * WASM vs TypeScript WebGPU parity matrix.
 *
 * Compares statistical canvas output (luminance + coverage) for core effects.
 * Skips automatically when WebGPU is unavailable (headless CI without GPU).
 *
 * Run with GPU locally:
 *   npm run build && WASM_GPU_TESTS=1 npx playwright test tests/renderer-parity.spec.ts
 */

import { test, expect } from '@playwright/test';
import {
  PARITY_MATRIX,
  PARITY_THRESHOLDS,
  type ParityShaderCase,
} from './fixtures/parityMatrix';
import {
  startStaticServer,
  stopStaticServer,
  renderShaderCase,
  hasGpuForTests,
} from './helpers/rendererHarness';

test.beforeAll(async () => {
  await startStaticServer();
}, 60000);

test.afterAll(async () => {
  await stopStaticServer();
});

for (const shaderCase of PARITY_MATRIX) {
  test(`parity: ${shaderCase.category} / ${shaderCase.id}`, async ({ page, browser }) => {
    test.skip(!hasGpuForTests(), 'Set WASM_GPU_TESTS=1 locally with a WebGPU-capable browser');

    const wasmPage = page;
    const tsPage = await browser.newPage();

    const wasmResult = await renderShaderCase(wasmPage, 'wasm', shaderCase);
    const tsResult = await renderShaderCase(tsPage, 'webgpu', shaderCase);

    await tsPage.close();

    if (wasmResult.backend !== 'wasm' || tsResult.backend !== 'webgpu') {
      test.skip(true, `GPU backends unavailable (wasm=${wasmResult.backend}, webgpu=${tsResult.backend})`);
    }

    expect(wasmResult.criticalErrors, 'WASM critical errors').toEqual([]);
    expect(tsResult.criticalErrors, 'WebGPU critical errors').toEqual([]);

    const minActive =
      shaderCase.minActivePixelRatio ?? PARITY_THRESHOLDS.defaultMinActivePixelRatio;
    expect(wasmResult.stats.activePixelRatio).toBeGreaterThan(minActive);
    expect(tsResult.stats.activePixelRatio).toBeGreaterThan(minActive);

    const maxDelta =
      shaderCase.maxLuminanceDelta ?? PARITY_THRESHOLDS.defaultMaxLuminanceDelta;
    const lumDelta = Math.abs(wasmResult.stats.meanLuminance - tsResult.stats.meanLuminance);

    console.log(
      `[parity:${shaderCase.id}] wasm lum=${wasmResult.stats.meanLuminance.toFixed(3)} ` +
        `webgpu lum=${tsResult.stats.meanLuminance.toFixed(3)} delta=${lumDelta.toFixed(3)}`
    );

    expect(lumDelta).toBeLessThanOrEqual(maxDelta);
  });
}

test.describe('WASM canvas snapshots', () => {
  for (const shaderCase of PARITY_MATRIX.slice(0, 2)) {
    test(`snapshot wasm: ${shaderCase.id}`, async ({ page }) => {
      test.skip(!hasGpuForTests(), 'Set WASM_GPU_TESTS=1 for snapshot tests');

      const result = await renderShaderCase(page, 'wasm', shaderCase);
      if (result.backend !== 'wasm') {
        test.skip(true, 'WASM backend unavailable');
      }

      const canvas = page.locator('canvas').first();
      await expect(canvas).toHaveScreenshot(`wasm-${shaderCase.id}.png`, {
        maxDiffPixelRatio: 0.25,
      });
    });
  }
});
