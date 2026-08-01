/**
 * Format-tier bench: ultra vs balanced vs battery across five workload shapes.
 *
 * Records colorFormat, estimated texture MiB, FPS and timestamp honesty
 * (`hasRealGpuTimings`) per tier, and writes a markdown + JSON report.
 *
 *   npm run build && WASM_GPU_TESTS=1 npx playwright test tests/format-tier-bench.spec.ts
 *
 * Cloud/headless VMs cannot observe a WebGPU adapter — without a GPU this writes a stub
 * report and skips, so it is safe to leave in CI. Real numbers must come from the
 * GPU_REQUIRED workflow (.github/workflows/gpu-required.yml) on a human runner.
 */

import { test, expect } from '@playwright/test';
import { FORMAT_TIER_MATRIX, TIER_SWEEP, type SweptTier } from './fixtures/formatTierMatrix';
import {
  startStaticServer,
  stopStaticServer,
  buildAppUrl,
  waitForTestApi,
  applyTestState,
  isStrictGpuMode,
  collectAdapterSummary,
  buildFormatTierReport,
  writeFormatTierReport,
  renderFormatTierMarkdown,
  type TierMeasurement,
} from './helpers/rendererHarness';

const BENCH_FRAMES = 90;
const WARMUP_MS = 2500;

test.beforeAll(async () => {
  await startStaticServer();
}, 60000);

test.afterAll(async () => {
  await stopStaticServer();
});

test.describe('format tier bench', () => {
  test('sweeps ultra/balanced/battery across the workload matrix', async ({ page }) => {
    test.setTimeout(15 * 60 * 1000);

    const consoleWarnings: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'warning' || msg.type() === 'error') {
        consoleWarnings.push(msg.text());
      }
    });

    await page.goto(buildAppUrl('webgpu'), { waitUntil: 'networkidle' });
    await waitForTestApi(page);

    const backend = await page.evaluate(() => (window as any).__pixelocity__?.getRendererType?.());
    if (backend !== 'webgpu') {
      const stub = buildFormatTierReport([], {
        gpuObserved: false,
        note: `No WebGPU backend in this environment (active backend: ${backend ?? 'none'}). `
          + 'Run the GPU_REQUIRED workflow on a machine with a real adapter.',
      });
      writeFormatTierReport(stub);
      // eslint-disable-next-line no-console
      console.log('[format-tier-bench] No WebGPU adapter — wrote stub report.');
      test.skip(!isStrictGpuMode(), 'WebGPU adapter unavailable (set WASM_GPU_TESTS=1 to fail instead)');
      expect(backend, 'strict GPU mode requires a WebGPU backend').toBe('webgpu');
      return;
    }

    const adapterSummary = await collectAdapterSummary(page, 'webgpu');
    const userAgent = await page.evaluate(() => navigator.userAgent);
    const measurements: TierMeasurement[] = [];

    for (const workload of FORMAT_TIER_MATRIX) {
      for (const tier of TIER_SWEEP as readonly SweptTier[]) {
        const before = consoleWarnings.length;

        // Fresh page per (workload, tier): tier switches destroy textures and clear
        // the pipeline cache, and we do not want a previous case's FP32 pin leaking in.
        await page.goto(buildAppUrl('webgpu'), { waitUntil: 'networkidle' });
        await waitForTestApi(page);

        await page.evaluate((mode) => {
          (window as any).__pixelocity__?.setRenderQuality(mode);
        }, tier);

        const loaded = await page.evaluate(async (shaders) => {
          const api = (window as any).__pixelocity__;
          const out: Array<{ id: string; slot: number; ok: boolean }> = [];
          for (const s of shaders) {
            const ok = await api.loadShader(s.id, s.url, s.meta);
            if (ok) api.setSlotShader(s.slot ?? 0, s.id);
            out.push({ id: s.id, slot: s.slot ?? 0, ok: !!ok });
          }
          return out;
        }, workload.shaders);

        for (const s of workload.shaders) {
          if (s.testState) await applyTestState(page, s.testState);
        }
        await page.waitForTimeout(WARMUP_MS);

        const bench = await page.evaluate(
          async (frames) => (window as any).__pixelocity__?.runBenchmark(frames),
          BENCH_FRAMES,
        );

        const warnings = consoleWarnings.slice(before);
        measurements.push({
          workload: workload.key,
          kind: workload.kind,
          tier,
          expectsFp32Pin: workload.expectsFp32Pin,
          shadersLoaded: loaded.filter((l) => l.ok).length,
          shadersRequested: workload.shaders.length,
          avgFps: bench?.avgFps ?? 0,
          avgTotalMs: bench?.avgTotalMs ?? 0,
          colorFormat: bench?.colorFormat ?? 'unknown',
          requestedColorFormat: bench?.requestedColorFormat ?? 'unknown',
          fp32Pinned: !!bench?.fp32Pinned,
          fp32PinnedBy: bench?.fp32PinnedBy ?? [],
          estimatedTextureMiB: bench?.estimatedTextureMiB ?? 0,
          internalWidth: bench?.internalWidth ?? 0,
          internalHeight: bench?.internalHeight ?? 0,
          scale: bench?.scale ?? 0,
          maxPassesPerFrame: bench?.maxPassesPerFrame ?? 0,
          hasRealGpuTimings: !!bench?.hasRealGpuTimings,
          timingSource: bench?.timingSource ?? 'wall-clock',
          passCapWarnings: warnings.filter((w) => w.includes('Pass cap')),
          formatRewriteWarnings: warnings.filter((w) => w.includes('not rewritten')),
        });
      }
    }

    const report = buildFormatTierReport(measurements, {
      gpuObserved: true,
      adapterSummary,
      userAgent,
    });
    writeFormatTierReport(report);
    // eslint-disable-next-line no-console
    console.log(renderFormatTierMarkdown(report));

    // Acceptance guard: no silent FP16 path for FP32-required workloads.
    for (const m of measurements.filter((x) => x.expectsFp32Pin)) {
      expect(
        m.colorFormat,
        `${m.workload} @ ${m.tier} must keep rgba32float storage (FP32 precision guard)`,
      ).toBe('rgba32float');
    }
  });
});
