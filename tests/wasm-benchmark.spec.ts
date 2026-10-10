/**
 * WASM vs WebGPU benchmark suite — GPU timestamp ms, uncapped ms/frame, FPS.
 *
 * Writes JSON report for CI artifacts / Tier A promotion tracking
 * (docs/WASM_BENCH_REPORT.md). Served with COOP/COEP for ~5 µs timers.
 *
 *   npm run build && WASM_GPU_TESTS=1 [WASM_BENCH_DEV_FEATURES=1] npm run test:wasm:bench
 */

import { test, expect, type Page } from '@playwright/test';
import { BENCHMARK_MATRIX } from './fixtures/parityMatrix';
import {
  startStaticServer,
  stopStaticServer,
  buildAppUrl,
  waitForTestApi,
  loadShaderOnSlot,
  applyTestState,
  isStrictGpuMode,
  buildComparison,
  buildBenchmarkReport,
  buildStubBenchmarkReport,
  collectAdapterSummary,
  collectBenchEnvironment,
  assertGpuAdapter,
  assertRendererHealthy,
  writeBenchmarkReport,
  type BenchResult,
  type BenchComparison,
  PROMOTION_SPEEDUP_RATIO,
} from './helpers/rendererHarness';
import { buildGpuLaunchArgs, isBenchDevFeaturesEnabled } from '../src/utils/gpuLaunchArgs';

const BENCHMARK_SHADER_IDS = BENCHMARK_MATRIX.map((s) => s.id);
// TS reads timestamps back every 250 ms: 180 frames ≈ 12 GPU samples at 60 fps (#1080).
const BENCH_FRAMES = 180;
const WARMUP_FRAMES = 10;
const UNCAPPED_FRAMES = 120;

test.beforeAll(async () => {
  // Cross-origin isolated (#1080): performance.now() at ~5 µs instead of ~100 µs.
  await startStaticServer(undefined, { isolated: true });
}, 60000);

test.afterAll(async () => {
  await stopStaticServer();
});

async function benchBackend(
  page: Page,
  backend: 'wasm' | 'webgpu',
  shader: (typeof BENCHMARK_MATRIX)[number]
): Promise<{ result: BenchResult; timestampPeriodNs: number; crossOriginIsolated: boolean } | null> {
  await page.goto(buildAppUrl(backend), { waitUntil: 'networkidle' });
  await waitForTestApi(page);

  const active = await page.evaluate(() => (window as any).__pixelocity__?.getRendererType?.());
  if (active !== backend) {
    if (isStrictGpuMode()) throw new Error(`${shader.id}: expected ${backend} renderer, got ${active}`);
    return null;
  }

  // A failed load leaves an empty slot, and the leg would time a passthrough frame (#1080).
  if (!(await loadShaderOnSlot(page, shader))) {
    if (isStrictGpuMode()) throw new Error(`${shader.id}: shader failed to load on ${backend}`);
    return null;
  }
  if (shader.testState) {
    await applyTestState(page, shader.testState);
  }
  await page.waitForTimeout(2000);

  // The type alone survives a dead device (#1357 T8): check the backend's diagnostics too.
  const health = await assertRendererHealthy(page, backend);
  if (!health.ok) {
    console.warn(`[bench] ${shader.id}/${backend} unhealthy: ${health.reason}`);
    return null;
  }

  // A background tab gets throttled rAF (#1357 T3).
  await page.bringToFront();
  const report = await page.evaluate(
    async ({ frameCount, warmupFrames }) =>
      (window as any).__pixelocity__?.runBenchmark(frameCount, { warmupFrames }),
    { frameCount: BENCH_FRAMES, warmupFrames: WARMUP_FRAMES },
  );

  const lastGpu = report?.samples?.[report.samples.length - 1]?.gpu;

  // Vsync-free leg (#1080): N frames without rAF, timed to onSubmittedWorkDone.
  const uncapped = await page.evaluate(
    async ({ frameCount, warmupFrames }) =>
      (window as any).__pixelocity__?.runUncappedBenchmark?.(frameCount, warmupFrames) ?? null,
    { frameCount: UNCAPPED_FRAMES, warmupFrames: WARMUP_FRAMES },
  );
  if (!uncapped) console.warn(`[bench] ${shader.id}/${backend}: uncapped run unavailable`);
  const crossOriginIsolated = await page.evaluate(() => self.crossOriginIsolated === true);

  return {
    timestampPeriodNs: report?.timestampPeriodNs ?? 0,
    crossOriginIsolated,
    result: {
      shaderId: shader.id,
      backend,
      avgFps: report?.avgFps ?? 0,
      avgTotalMs: report?.avgTotalMs ?? 0,
      gpuTimingsAvailable: report?.gpuTimingsAvailable ?? false,
      timingSource: report?.timingSource ?? lastGpu?.timingSource ?? 'unavailable',
      // p95 over every sampled frame, not the 5-sample tail (#1357 T4).
      p95TotalMs: report?.totalMsStats?.p95 ?? 0,
      totalMsStats: report?.totalMsStats,
      fpsStats: report?.fpsStats,
      gpuReadbacks: report?.gpuReadbacks ?? 0,
      ...(uncapped?.msPerFrame > 0 ? { uncappedMsPerFrame: uncapped.msPerFrame } : {}),
      ...(report?.timingSource === 'gpu-timestamp' && report?.passTimings?.length
        ? { passTimings: report.passTimings }
        : {}),
    },
  };
}

test('WASM vs WebGPU benchmark matrix', async ({ page, browser }) => {
  test.setTimeout(180000);

  const spoofedUserAgent = await page.evaluate(() => navigator.userAgent);
  const strict = isStrictGpuMode();
  const environment = collectBenchEnvironment(
    browser.version(),
    buildGpuLaunchArgs(process.platform, strict, isBenchDevFeaturesEnabled()),
    strict ? 'chromium' : 'chromium-headless-shell',
  );

  if (!strict) {
    writeBenchmarkReport(
      buildStubBenchmarkReport(BENCHMARK_SHADER_IDS, { spoofedUserAgent, environment, warmupFrames: WARMUP_FRAMES })
    );
    test.skip(true, 'Set WASM_GPU_TESTS=1 with WebGPU hardware for benchmarks');
  }

  // No adapter (or SwiftShader) under WASM_GPU_TESTS=1 is a failure, not a skip (#1357 T7).
  await page.goto(buildAppUrl('webgpu'), { waitUntil: 'domcontentloaded' });
  await assertGpuAdapter(page);

  const allResults: BenchResult[] = [];
  const comparisons: BenchComparison[] = [];
  let completed = false;

  // Written in finally so a mid-run failure keeps the shaders done so far (#1357 T6).
  try {
    for (const shader of BENCHMARK_MATRIX) {
      const wasmPage = page;
      const wasmBench = await benchBackend(wasmPage, 'wasm', shader);
      if (wasmBench && !environment.adapters.wasm) {
        environment.adapters.wasm = await collectAdapterSummary(wasmPage, 'wasm');
        environment.crossOriginIsolated = { ...environment.crossOriginIsolated, wasm: wasmBench.crossOriginIsolated };
      }
      // Stop the WASM render loop so it cannot compete with the TS leg (#1357 T3).
      await wasmPage.goto('about:blank');

      const tsPage = await browser.newPage();
      let tsBench: Awaited<ReturnType<typeof benchBackend>> = null;
      try {
        tsBench = await benchBackend(tsPage, 'webgpu', shader);
        // Read the summary before the page closes (#1357 T2).
        if (tsBench && !environment.adapters.webgpu) {
          environment.adapters.webgpu = await collectAdapterSummary(tsPage, 'webgpu');
          environment.timestampPeriodNs = tsBench.timestampPeriodNs;
          environment.crossOriginIsolated = { ...environment.crossOriginIsolated, webgpu: tsBench.crossOriginIsolated };
        }
      } finally {
        await tsPage.close();
      }

      if (!wasmBench || !tsBench) {
        const msg = `${shader.id}: wasm=${wasmBench ? 'ok' : 'missing'} webgpu=${tsBench ? 'ok' : 'missing'}`;
        throw new Error(`[bench] ${msg}`);
      }

      // Without isolation the timers fall back to ~100 µs and the run is not the one documented.
      if (!wasmBench.crossOriginIsolated || !tsBench.crossOriginIsolated) {
        throw new Error(`[bench] ${shader.id}: page is not cross-origin isolated (COOP/COEP missing)`);
      }

      allResults.push(wasmBench.result, tsBench.result);
      comparisons.push(buildComparison(wasmBench.result, tsBench.result));

      expect(wasmBench.result.avgFps).toBeGreaterThan(0);
      expect(tsBench.result.avgFps).toBeGreaterThan(0);

      // Generous wall-clock guard (different timing sources)
      if (wasmBench.result.avgTotalMs > 0 && tsBench.result.avgTotalMs > 0) {
        expect(wasmBench.result.avgTotalMs).toBeLessThan(tsBench.result.avgTotalMs * 3 + 5);
      }
    }
    completed = true;
  } finally {
    const report = buildBenchmarkReport(allResults, comparisons, {
      benchmarkShaderIds: BENCHMARK_SHADER_IDS,
      environment,
      warmupFrames: WARMUP_FRAMES,
      spoofedUserAgent,
      gpuBackendObserved: allResults.length > 0,
      completed,
    });
    writeBenchmarkReport(report);

    const likeForLike = comparisons.filter((c) => c.likeForLike).length;
    console.log('\n=== WASM Benchmark Report ===');
    console.log(JSON.stringify(report, null, 2));
    console.log(
      `Promotion gate (≥${PROMOTION_SPEEDUP_RATIO}× on ≥${report.promotionMinShaders} shaders): ` +
        `${report.promotionGateMet ? 'MET' : 'NOT MET'} ` +
        `(${comparisons.filter((c) => c.meetsPromotionGate).length}/${comparisons.length} shaders)`
    );
    const byMetric = comparisons.map((c) => `${c.shaderId}=${c.speedupMetric}`).join(', ');
    console.log(`Speedup metric per shader (gpu-ms > uncapped-ms > fps): ${byMetric || 'none'}`);
    console.log(
      `Like-for-like on ${likeForLike}/${comparisons.length} shaders (mixed rows never meet the gate).`
    );
    if (!completed) console.log('Run did not complete — report holds partial results.');
    console.log('=============================\n');
  }
});

const FORMAT_TIER_SHADERS = BENCHMARK_MATRIX.filter((s) =>
  ['sim-fluid-feedback-coupled', 'gen-lichen-reaction-diffusion', 'plasma'].includes(s.id),
);

test('format tier FP16 vs FP32 (WebGPU)', async ({ page }) => {
  test.setTimeout(120000);
  if (!isStrictGpuMode()) {
    test.skip(true, 'Set WASM_GPU_TESTS=1 with WebGPU hardware for format tier benchmarks');
  }

  await page.goto(buildAppUrl('webgpu'), { waitUntil: 'networkidle' });
  await waitForTestApi(page);

  const tierResults: BenchResult[] = [];
  for (const shader of FORMAT_TIER_SHADERS) {
    await loadShaderOnSlot(page, shader);
    if (shader.testState) await applyTestState(page, shader.testState);
    await page.waitForTimeout(1000);

    for (const qualityMode of ['ultra', 'balanced'] as const) {
      const report = await page.evaluate(
        async ({ frameCount, mode }) =>
          (window as any).__pixelocity__?.runBenchmark(frameCount, { qualityMode: mode }),
        { frameCount: 45, mode: qualityMode },
      );
      tierResults.push({
        shaderId: shader.id,
        backend: 'webgpu',
        avgFps: report?.avgFps ?? 0,
        avgTotalMs: report?.avgTotalMs ?? 0,
        gpuTimingsAvailable: report?.gpuTimingsAvailable ?? false,
        p95TotalMs: 0,
        qualityMode,
        colorFormat: report?.colorFormat,
        estimatedTextureMiB: report?.estimatedTextureMiB,
      });
    }
  }

  expect(tierResults.length).toBeGreaterThan(0);
  const ultra = tierResults.find((r) => r.qualityMode === 'ultra');
  const balanced = tierResults.find((r) => r.qualityMode === 'balanced');
  expect(ultra?.colorFormat).toBe('rgba32float');
  expect(balanced?.colorFormat).toBe('rgba16float');
  if (ultra && balanced) {
    expect(balanced.estimatedTextureMiB ?? 0).toBeLessThan(ultra.estimatedTextureMiB ?? 0);
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
