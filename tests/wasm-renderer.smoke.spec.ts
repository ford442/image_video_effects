/**
 * WASM renderer Playwright smoke suite.
 *
 * Soft mode (default CI): verifies production build loads, test API works, no crash.
 * Strict mode (WASM_GPU_TESTS=1): requires real ?renderer=wasm backend, FPS health,
 * and exercises the full parity matrix (fluid, RD, audio, generative, interactive).
 *
 *   npm run build && WASM_GPU_TESTS=1 npm run test:wasm:smoke
 */

import { test, expect } from '@playwright/test';
import { PARITY_MATRIX } from './fixtures/parityMatrix';
import {
  startStaticServer,
  stopStaticServer,
  buildAppUrl,
  waitForTestApi,
  waitForWebGpuProbe,
  getActiveBackend,
  assertExpectedBackend,
  attachConsoleCollector,
  exerciseShaderOnWasm,
  captureCanvasStats,
  getRendererFps,
  isStrictGpuMode,
  MIN_WASM_FPS,
} from './helpers/rendererHarness';

test.beforeAll(async () => {
  await startStaticServer();
}, 60000);

test.afterAll(async () => {
  await stopStaticServer();
});

test('WebGPU boot probe completes on headless CI', async ({ page }) => {
  const { criticalErrors } = attachConsoleCollector(page);
  await page.goto(buildAppUrl('webgpu'), { waitUntil: 'networkidle' });
  await waitForWebGpuProbe(page);

  const probe = await page.evaluate(() => (window as { webgpuProbe?: { ok: boolean; attempts: unknown[] } }).webgpuProbe);
  expect(probe).toBeDefined();
  if (isStrictGpuMode()) {
    expect(probe?.ok).toBe(true);
  } else {
    expect(typeof probe?.ok).toBe('boolean');
    if (!probe?.ok) {
      expect(probe?.attempts?.length).toBeGreaterThan(0);
    }
  }

  const overlay = await page.getByTestId('webgpu-probe-failure').isVisible();
  if (!probe?.ok) {
    expect(overlay).toBe(true);
  }

  const filtered = criticalErrors.filter(
    (e) =>
      !e.includes('No GPU adapter found') &&
      !e.includes('Failed to obtain a WebGPU adapter') &&
      !e.includes('webgpu-unavailable')
  );
  expect(filtered).toEqual([]);
});

test('WASM renderer initializes (testMode API + diagnostics)', async ({ page }) => {
  const { criticalErrors } = attachConsoleCollector(page);
  await page.goto(buildAppUrl('wasm'), { waitUntil: 'networkidle' });
  await waitForTestApi(page);

  const active = await assertExpectedBackend(page, 'wasm');

  const diagnostics = await page.evaluate(() => {
    return (window as any).__pixelocity__?.renderer?.getDiagnostics?.();
  });

  expect(diagnostics).toBeDefined();

  if (!diagnostics?.wasm) {
    console.log('WASM renderer fell back (expected in CI)');
  } else {
    expect(diagnostics?.wasm?.fps).toBeGreaterThanOrEqual(0);
    expect(diagnostics?.wasm?.hasModule).toBe(true);
    if (active === 'wasm') {
      expect(diagnostics?.wasm?.initialized).toBe(true);
      expect(diagnostics?.rendererType).toBe('wasm');
    } else if (!isStrictGpuMode()) {
      console.log(`[smoke] WASM fell back to "${active}" — OK without WASM_GPU_TESTS=1`);
    }
  }

  const filtered = criticalErrors.filter(
    (e) =>
      !e.includes('No GPU adapter found') && !e.includes('Failed to obtain a WebGPU adapter') &&
      !e.includes('Failed to get WebGPU adapter') &&
      !e.includes('wasm-init') &&
      !e.includes('webgpu-unavailable')
  );
  expect(filtered).toEqual([]);
});

test('WASM canvas has non-zero dimensions', async ({ page }) => {
  await page.goto(buildAppUrl('wasm'), { waitUntil: 'networkidle' });
  await waitForTestApi(page);


  let probeOk = false;
  try {
    probeOk = await page.evaluate(() => (window as any).webgpuProbe?.ok ?? false);
  } catch {}

  if (!probeOk && !isStrictGpuMode()) {
    test.skip(true, 'No WebGPU adapter (soft mode)');
    return;
  }

  const stats = await captureCanvasStats(page);
  expect(stats.width).toBeGreaterThan(0);
  expect(stats.height).toBeGreaterThan(0);
});

for (const shaderCase of PARITY_MATRIX) {
  test(`WASM smoke: ${shaderCase.category} / ${shaderCase.id}`, async ({ page }) => {
    const { criticalErrors } = attachConsoleCollector(page);
    await page.goto(buildAppUrl('wasm'), { waitUntil: 'networkidle' });
    await waitForTestApi(page);

    const active = await assertExpectedBackend(page, 'wasm');
    if (active !== 'wasm') {
      if (isStrictGpuMode()) {
        expect(active).toBe('wasm');
      }
      test.skip(true, 'WASM backend unavailable');
      return;
    }

    const { loaded, fps, stats, criticalErrors: exerciseErrors } = await exerciseShaderOnWasm(
      page,
      shaderCase
    );
    if (!loaded) {
      if (isStrictGpuMode()) {
        throw new Error(`loadShader failed for ${shaderCase.id}`);
      }
      test.skip(true, `WASM loadShader soft-failed for ${shaderCase.id} (no GPU)`);
      return;
    }

    expect([...criticalErrors, ...exerciseErrors]).toEqual([]);
    expect(stats.width).toBeGreaterThan(0);
    expect(stats.height).toBeGreaterThan(0);

    if (isStrictGpuMode()) {
      expect(stats.activePixelRatio).toBeGreaterThan(0.01);
      expect(fps).toBeGreaterThanOrEqual(MIN_WASM_FPS);
    }

    const slotState = await page.evaluate((idx) => {
      return (window as any).__pixelocity__?.getSlotState?.(idx);
    }, shaderCase.slot ?? 0);

    if (slotState) {
      expect(slotState.shaderId).toBe(shaderCase.id);
      expect(slotState.enabled).toBe(true);
    }

    console.log(
      `[smoke:${shaderCase.id}] fps=${fps.toFixed(1)} active=${(stats.activePixelRatio * 100).toFixed(1)}%`
    );
  });
}

test('WASM multi-slot stack (fluid + generative)', async ({ page }) => {
  await page.goto(buildAppUrl('wasm'), { waitUntil: 'networkidle' });
  await waitForTestApi(page);

  const active = await getActiveBackend(page);
  if (active !== 'wasm') {
    if (isStrictGpuMode()) expect(active).toBe('wasm');
    test.skip(true, 'WASM backend unavailable');
    return;
  }

  const stack = [
    { ...PARITY_MATRIX[0], slot: 0 },
    { ...PARITY_MATRIX[3], slot: 1 },
  ];

  for (const shader of stack) {
    const loaded = await page.evaluate(
      async (s) => {
        const api = (window as any).__pixelocity__;
        api.setInputSource('generative');
        const ok = await api.loadShader(s.id, s.url);
        if (!ok) return false;
        api.setSlotShader(s.slot ?? 0, s.id);
        return true;
      },
      shader
    );
    if (!loaded) {
      if (isStrictGpuMode()) {
        throw new Error(`loadShader failed: ${shader.id}`);
      }
      test.skip(true, `WASM loadShader soft-failed for ${shader.id} (no GPU)`);
      return;
    }
    await page.waitForTimeout(400);
  }

  await page.waitForTimeout(3000);

  const fps = await getRendererFps(page);
  const stats = await captureCanvasStats(page);

  if (isStrictGpuMode()) {
    expect(fps).toBeGreaterThanOrEqual(MIN_WASM_FPS);
    expect(stats.activePixelRatio).toBeGreaterThan(0.01);
  }

  const slot0 = await page.evaluate(() => (window as any).__pixelocity__?.getSlotState?.(0));
  const slot1 = await page.evaluate(() => (window as any).__pixelocity__?.getSlotState?.(1));
  expect(slot0?.enabled).toBe(true);
  expect(slot1?.enabled).toBe(true);
});
