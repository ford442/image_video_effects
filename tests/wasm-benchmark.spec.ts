/**
 * WASM vs WebGPU benchmark suite using getGPUTimings() + FPS metrics.
 *
 * Outputs JSON summary to stdout for CI artifacts / local comparison.
 *
 * Run locally:
 *   npm run build && WASM_GPU_TESTS=1 npm run test:wasm:bench
 */

import { test, expect } from '@playwright/test';
import { BENCHMARK_MATRIX } from './fixtures/parityMatrix';
import {
  startStaticServer,
  stopStaticServer,
  buildAppUrl,
  waitForTestApi,
  loadShaderOnSlot,
  applyTestState,
  hasGpuForTests,
} from './helpers/rendererHarness';

interface BenchResult {
  shaderId: string;
  backend: string;
  avgFps: number;
  avgTotalMs: number;
  gpuTimingsAvailable: boolean;
  p95TotalMs: number;
}

test.beforeAll(async () => {
  await startStaticServer();
}, 60000);

test.afterAll(async () => {
  await stopStaticServer();
});

async function benchBackend(
  page: import('@playwright/test').Page,
  backend: 'wasm' | 'webgpu',
  shader: (typeof BENCHMARK_MATRIX)[number]
): Promise<BenchResult | null> {
  await page.goto(buildAppUrl(backend), { waitUntil: 'networkidle' });
  await waitForTestApi(page);

  const active = await page.evaluate(() => (window as any).__pixelocity__?.getRendererType?.());
  if (active !== backend) return null;

  await loadShaderOnSlot(page, shader);
  if (shader.testState) {
    await applyTestState(page, shader.testState);
  }
  await page.waitForTimeout(2000);

  const report = await page.evaluate(async (frameCount) => {
    return (window as any).__pixelocity__?.runBenchmark(frameCount);
  }, 60);

  const totals = (report?.samples ?? [])
    .map((s: { gpu: { totalTime: number } }) => s.gpu.totalTime)
    .filter((t: number) => t > 0)
    .sort((a: number, b: number) => a - b);
  const p95 = totals.length ? totals[Math.floor(totals.length * 0.95)] ?? 0 : 0;

  return {
    shaderId: shader.id,
    backend,
    avgFps: report?.avgFps ?? 0,
    avgTotalMs: report?.avgTotalMs ?? 0,
    gpuTimingsAvailable: report?.gpuTimingsAvailable ?? false,
    p95TotalMs: p95,
  };
}

test('WASM vs WebGPU benchmark matrix', async ({ page, browser }) => {
  test.skip(!hasGpuForTests(), 'Set WASM_GPU_TESTS=1 with WebGPU hardware');

  const allResults: BenchResult[] = [];

  for (const shader of BENCHMARK_MATRIX) {
    const wasmPage = page;
    const tsPage = await browser.newPage();

    const wasmBench = await benchBackend(wasmPage, 'wasm', shader);
    const tsBench = await benchBackend(tsPage, 'webgpu', shader);
    await tsPage.close();

    if (!wasmBench || !tsBench) {
      test.skip(true, 'One or both GPU backends unavailable');
    }

    allResults.push(wasmBench!, tsBench!);

    // WASM should stay within 3× TS wall-clock (generous — different timing sources)
    if (wasmBench!.avgTotalMs > 0 && tsBench!.avgTotalMs > 0) {
      expect(wasmBench!.avgTotalMs).toBeLessThan(tsBench!.avgTotalMs * 3 + 5);
    }

    expect(wasmBench!.avgFps).toBeGreaterThan(0);
    expect(tsBench!.avgFps).toBeGreaterThan(0);
  }

  console.log('\n=== WASM Benchmark Report ===');
  console.log(JSON.stringify(allResults, null, 2));
  console.log('Note: WASM getGPUTimings().available is false (CPU wall-clock only).');
  console.log('=============================\n');
});

test('WASM getGPUTimings API surface', async ({ page }) => {
  await page.goto(buildAppUrl('wasm'), { waitUntil: 'networkidle' });
  await waitForTestApi(page);

  const timings = await page.evaluate(() => (window as any).__pixelocity__?.getGPUTimings?.());
  expect(timings).toBeDefined();
  expect(typeof timings.parallelTime).toBe('number');
  expect(typeof timings.chainedTime).toBe('number');
  expect(typeof timings.totalTime).toBe('number');
  expect(typeof timings.available).toBe('boolean');
});
