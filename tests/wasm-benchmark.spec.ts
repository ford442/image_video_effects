/**
 * WASM vs WebGPU benchmark suite — FPS + getGPUTimings() wall-clock metrics.
 *
 * Writes JSON report for CI artifacts / Tier A promotion tracking.
 *
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
  isStrictGpuMode,
  computeSpeedupRatio,
  buildBenchmarkReport,
  writeBenchmarkReport,
  type BenchResult,
  type BenchComparison,
  PROMOTION_SPEEDUP_RATIO,
} from './helpers/rendererHarness';

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

  const lastGpu = report?.samples?.[report.samples.length - 1]?.gpu;

  return {
    shaderId: shader.id,
    backend,
    avgFps: report?.avgFps ?? 0,
    avgTotalMs: report?.avgTotalMs ?? 0,
    gpuTimingsAvailable: report?.gpuTimingsAvailable ?? false,
    timingSource: lastGpu?.timingSource ?? 'unavailable',
    p95TotalMs: p95,
  };
}

test('WASM vs WebGPU benchmark matrix', async ({ page, browser }) => {
  if (!isStrictGpuMode()) {
    test.skip(true, 'Set WASM_GPU_TESTS=1 with WebGPU hardware for benchmarks');
  }

  const allResults: BenchResult[] = [];
  const comparisons: BenchComparison[] = [];
  let gpuObserved = false;

  for (const shader of BENCHMARK_MATRIX) {
    const wasmPage = page;
    const tsPage = await browser.newPage();

    const wasmBench = await benchBackend(wasmPage, 'wasm', shader);
    const tsBench = await benchBackend(tsPage, 'webgpu', shader);
    await tsPage.close();

    if (!wasmBench || !tsBench) {
      console.warn(
        `[bench] Skipping ${shader.id}: wasm=${wasmBench ? 'ok' : 'missing'} webgpu=${tsBench ? 'ok' : 'missing'}`
      );
      continue;
    }

    gpuObserved = true;
    allResults.push(wasmBench, tsBench);

    const speedupRatio = computeSpeedupRatio(wasmBench, tsBench);
    const meetsPromotionGate = speedupRatio >= PROMOTION_SPEEDUP_RATIO;

    comparisons.push({
      shaderId: shader.id,
      wasmFps: wasmBench.avgFps,
      webgpuFps: tsBench.avgFps,
      wasmAvgTotalMs: wasmBench.avgTotalMs,
      webgpuAvgTotalMs: tsBench.avgTotalMs,
      speedupRatio,
      meetsPromotionGate,
    });

    expect(wasmBench.avgFps).toBeGreaterThan(0);
    expect(tsBench.avgFps).toBeGreaterThan(0);

    // Generous wall-clock guard (different timing sources)
    if (wasmBench.avgTotalMs > 0 && tsBench.avgTotalMs > 0) {
      expect(wasmBench.avgTotalMs).toBeLessThan(tsBench.avgTotalMs * 3 + 5);
    }
  }

  const report = buildBenchmarkReport(allResults, comparisons);
  report.gpuBackendObserved = gpuObserved;
  writeBenchmarkReport(report);

  console.log('\n=== WASM Benchmark Report ===');
  console.log(JSON.stringify(report, null, 2));
  console.log(
    `Promotion gate (≥${PROMOTION_SPEEDUP_RATIO}× on ≥${report.promotionMinShaders} shaders): ` +
      `${report.promotionGateMet ? 'MET' : 'NOT MET'} ` +
      `(${comparisons.filter((c) => c.meetsPromotionGate).length}/${comparisons.length} shaders)`
  );
  console.log('Note: WASM getGPUTimings().available is false — timingSource is wall-clock.');
  console.log('=============================\n');

  if (!gpuObserved) {
    test.skip(true, 'WebGPU adapter unavailable — run locally or on a GPU runner with WASM_GPU_TESTS=1');
  }
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
  expect(['gpu-timestamp', 'wall-clock', 'unavailable']).toContain(timings.timingSource);
});
