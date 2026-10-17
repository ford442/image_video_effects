/**
 * WASM renderer Playwright smoke suite.
 *
 * Soft mode (default CI): verifies production build loads, test API works, no crash.
 * Strict mode (WASM_GPU_TESTS=1): requires real ?renderer=wasm backend, FPS health,
 * and exercises the full parity matrix (fluid, RD, audio, generative, interactive).
 * Debug mode (WASM_DEBUG=1): every page loads the ASSERTIONS=2 debug artifact
 * (?wasm_debug=1) and any Emscripten assertion fails the spec (#1400).
 *
 *   npm run build && WASM_GPU_TESTS=1 npm run test:wasm:e2e
 *   npm run wasm:build:debug && npm run build && npm run test:wasm:debug   # SwiftShader
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
  isWasmDebugMode,
  EMSCRIPTEN_ASSERTION_PATTERN,
  MIN_WASM_FPS,
  installGpuUncapturedErrorHook,
  readGpuUncapturedErrors,
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
  // A software adapter (SwiftShader) lands in the 1-slot quality tier; this spec
  // is about the WASM multi-slot path, not the tier cap.
  await page.evaluate((n) => (window as any).__pixelocity__?.overrideSlotCap?.(n), stack.length);

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

const TINY_PNG =
  'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

test('?renderer=wasm boot fails the spec on GPUValidationError (skip without adapter)', async ({
  page,
}) => {
  const { criticalErrors } = attachConsoleCollector(page);
  await installGpuUncapturedErrorHook(page);
  await page.goto(buildAppUrl('wasm'), { waitUntil: 'networkidle' });
  await waitForWebGpuProbe(page);

  const probeOk = await page.evaluate(
    () => (window as { webgpuProbe?: { ok?: boolean } }).webgpuProbe?.ok === true,
  );
  if (!probeOk) {
    test.skip(true, 'No GPU adapter (WebGPU boot probe failed)');
    return;
  }

  await waitForTestApi(page);
  await page.waitForTimeout(1500);

  const gpuErrors = await readGpuUncapturedErrors(page);
  const validation = gpuErrors.filter(
    (e) =>
      e.type === 'GPUValidationError' ||
      /GPUValidationError|Dispatch workgroup count/i.test(e.message),
  );
  expect(validation, JSON.stringify(gpuErrors)).toEqual([]);

  const consoleValidation = criticalErrors.filter((e) =>
    /GPUValidationError|Dispatch workgroup count|uncapturederror/i.test(e),
  );
  expect(consoleValidation).toEqual([]);
});

test('JS→WASM switch rebinds input so the photo is not empty (skip without adapter)', async ({
  page,
}) => {
  await installGpuUncapturedErrorHook(page);
  await page.goto(buildAppUrl('webgpu'), { waitUntil: 'networkidle' });
  await waitForWebGpuProbe(page);

  const probeOk = await page.evaluate(
    () => (window as { webgpuProbe?: { ok?: boolean } }).webgpuProbe?.ok === true,
  );
  if (!probeOk) {
    test.skip(true, 'No GPU adapter (WebGPU boot probe failed)');
    return;
  }

  await waitForTestApi(page);

  const loaded = await page.evaluate(async (url) => {
    const api = (window as { __pixelocity__?: { loadImage?: (u: string) => Promise<unknown> } })
      .__pixelocity__;
    if (!api?.loadImage) return false;
    await api.loadImage(url);
    return true;
  }, TINY_PNG);
  if (!loaded) {
    test.skip(true, 'Test API loadImage unavailable');
    return;
  }

  const switched = await page.evaluate(async () => {
    const manager = (
      window as {
        __pixelocity__?: { renderer?: { switchRenderer?: (t: string) => Promise<boolean> } };
      }
    ).__pixelocity__?.renderer;
    if (!manager?.switchRenderer) return false;
    return manager.switchRenderer('wasm');
  });
  if (!switched) {
    if (isStrictGpuMode()) {
      throw new Error('switchRenderer(wasm) failed under WASM_GPU_TESTS=1');
    }
    test.skip(true, 'WASM backend unavailable after JS→WASM switch');
    return;
  }

  const after = await page.evaluate(() => {
    const manager = (
      window as {
        __pixelocity__?: {
          getRendererType?: () => string;
          renderer?: { getInputSource?: () => string | null };
        };
      }
    ).__pixelocity__;
    return {
      type: manager?.getRendererType?.() ?? null,
      input: manager?.renderer?.getInputSource?.() ?? null,
    };
  });
  expect(after.type).toBe('wasm');
  expect(after.input).toBeTruthy();
  expect(after.input).not.toBe('generative');

  const gpuErrors = await readGpuUncapturedErrors(page);
  expect(gpuErrors.filter((e) => e.type === 'GPUValidationError')).toEqual([]);
});

test('WASM debug profile: every async export runs with zero Emscripten assertions', async ({ page }) => {
  test.skip(!isWasmDebugMode(), 'Debug profile only (WASM_DEBUG=1 after npm run wasm:build:debug)');
  const assertions: string[] = [];
  page.on('console', (m) => { if (process.env.PW_ECHO) console.log(`[browser:${m.type()}] ${m.text()}`); });
  page.on('console', (msg) => {
    if (EMSCRIPTEN_ASSERTION_PATTERN.test(msg.text())) assertions.push(msg.text());
  });
  page.on('pageerror', (err) => {
    if (EMSCRIPTEN_ASSERTION_PATTERN.test(err.message)) assertions.push(err.message);
  });
  const loadedArtifacts: string[] = [];
  page.on('response', (res) => {
    if (/pixelocity_wasm[^/]*\.wasm$/.test(res.url())) loadedArtifacts.push(res.url());
  });

  await page.goto(buildAppUrl('wasm'), { waitUntil: 'networkidle' });
  await waitForTestApi(page);
  const active = await getActiveBackend(page);
  if (active !== 'wasm') {
    if (isStrictGpuMode()) expect(active).toBe('wasm');
    test.skip(true, `WASM backend unavailable (active=${active})`);
    return;
  }
  expect(loadedArtifacts.some((u) => u.endsWith('pixelocity_wasm.debug.wasm'))).toBe(true);

  // initWasmRenderer already ran. Now loadShader, reloadShader, resizeCanvas (via
  // the render scale), setColorFormat (via the quality preset: ultra is
  // rgba32float, battery rgba16float) and a capture, while frames keep calling Render().
  const [first, second] = [PARITY_MATRIX[0]!, PARITY_MATRIX[3]!];
  const result = await page.evaluate(
    async ({ a, b }) => {
      const api = (window as any).__pixelocity__;
      api.setInputSource('generative');
      const loadedA = await api.loadShader(a.id, a.url);
      api.setSlotShader(0, a.id);
      const loadedB = await api.loadShader(b.id, b.url);
      api.setSlotShader(1, b.id);
      api.setRenderScale(0.5);
      await api.waitFrames(5);
      api.setRenderScale(1);
      const reloaded = await api.reloadShader(a.id, a.url);
      await api.waitFrames(10);
      api.setRenderQuality('ultra');
      await api.waitFrames(5);
      api.setRenderQuality('battery');
      await api.waitFrames(5);
      const png = await api.captureThumbnailPng(64);
      return { loadedA, loadedB, reloaded, captured: typeof png === 'string' && png.length > 0 };
    },
    { a: first, b: second },
  );
  console.log(`[debug-profile] ${JSON.stringify(result)}`);
  expect(result.loadedA).toBe(true);
  expect(result.loadedB).toBe(true);
  expect(result.reloaded).toBe(true);
  expect(assertions).toEqual([]);
});
