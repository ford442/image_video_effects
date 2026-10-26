/**
 * The compatibility rung (#1512 Part A) on a real, software, WebGPU device.
 *
 * `?feature_level=compatibility` starts the adapter ladder at the compat rung, and the
 * device is created without core-features-and-limits, so it validates exactly like one
 * on an Android GL ES / older Chromebook adapter (lower limits, view-dimension rules).
 * The catalog must still load: a plain image effect, a generative one, a history-ring
 * shader (binding 13 is a 2d-array, the compat view-dimension case), and a composited
 * parallel pair — with no uncaptured GPU errors, in both render threads.
 *
 * Needs a production build: `SKIP_WASM_BUILD=1 npm run build && npm run test:engine2 -- -g "compat"`.
 */
import { expect, test, type Page } from '@playwright/test';
import sharp from 'sharp';
import {
  installGpuUncapturedErrorHook,
  readGpuUncapturedErrors,
  startStaticServer,
  stopStaticServer,
} from './helpers/rendererHarness';

const PORT = 3473;
type Mode = 'main' | 'worker';

test.beforeAll(async () => {
  await startStaticServer(PORT);
});

test.afterAll(async () => {
  await stopStaticServer();
});

async function boot(page: Page, mode: Mode): Promise<void> {
  await installGpuUncapturedErrorHook(page);
  await page.goto(`http://localhost:${PORT}/?renderer=${mode}&testMode=1&feature_level=compatibility`, { waitUntil: 'load' });
  await page.waitForFunction(
    () => (window as any).webgpuProbe != null && (window as any).__pixelocity__?.renderer != null,
    null,
    { timeout: 60_000 },
  );
}

async function gpuErrors(page: Page, mode: Mode): Promise<string[]> {
  if (mode === 'main') return (await readGpuUncapturedErrors(page)).map((e) => e.message);
  return page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.gpuErrors ?? []);
}

/** A few reads: the frame after a shader change may still be the old one. */
async function rendersSomething(page: Page): Promise<boolean> {
  for (let i = 0; i < 6; i++) {
    await page.waitForTimeout(700);
    const png: string | null = await page.evaluate(() => (window as any).__pixelocity__.captureThumbnailPng(32));
    if (!png) continue;
    const stats = await sharp(Buffer.from(png.includes(',') ? png.split(',')[1]! : png, 'base64')).stats();
    const max = Math.max(...stats.channels.slice(0, 3).map((c) => c.max));
    if (max > 24) return true;
  }
  return false;
}

async function show(page: Page, shaderId: string, source: 'image' | 'generative'): Promise<boolean> {
  return page.evaluate(async ({ id, src }) => {
    const api = (window as any).__pixelocity__;
    api.overrideSlotCap(6);
    api.setRenderScale(0.25);
    api.setInputSource(src);
    const ok = await api.loadShader(id, `./shaders/${id}.wgsl`);
    for (let i = 1; i < 6; i++) api.setSlotShader(i, '');
    api.setSlotShader(0, id);
    return ok;
  }, { id: shaderId, src: source });
}

test.describe('compatibility rung on SwiftShader', () => {
  test.describe.configure({ timeout: 300_000 });

  for (const mode of ['worker', 'main'] as const) {
    test(`${mode}: a compat-only device loads the catalog`, async ({ page }) => {
      await boot(page, mode);
      const probe = await page.evaluate(() => (window as any).webgpuProbe);
      expect(probe.ok, `boot probe failed: ${probe.failedStage} ${probe.lastError}`).toBe(true);
      expect(probe).toMatchObject({ compat: true, featureLevel: 'compatibility', adapterAttemptLabel: 'Compatibility' });
      expect(probe.attempts.map((a: { label: string }) => a.label)).toEqual(['Compatibility']);
      // 256 invocations were requested above the compat default of 128.
      expect(probe.limitsTiers).toContain('base');
      // Compat devices prefer fp16 storage (formatPolicy).
      expect(await page.evaluate(() => (window as any).__pixelocity__.getPerformanceStatus().colorFormat)).toBe('rgba16float');

      // Let the app's own default slot-0 shader land before replacing it.
      await page
        .waitForFunction(() => !!(window as any).__pixelocity__.getSlotState?.(0)?.shaderId, null, { timeout: 60_000 })
        .catch(() => undefined);

      for (const [id, source] of [
        ['plasma', 'generative'],
        ['chrono-luma-slit-scan', 'generative'], // binds the 2d-array history ring
        ['gen-aurora-silk', 'generative'],
      ] as const) {
        expect(await show(page, id, source), `${id} compiles on a compat device`).toBe(true);
        expect(await rendersSomething(page), `${id} renders on a compat device`).toBe(true);
      }

      // The layer compositor on compat: a 2d-array layer texture + r8unorm masks.
      await page.evaluate(async () => {
        const api = (window as any).__pixelocity__;
        await api.loadShader('plasma', './shaders/plasma.wgsl');
        api.setSlotShader(0, 'gen-aurora-silk');
        api.setSlotShader(1, 'plasma');
        api.setSlotMode(0, 'parallel');
        api.setSlotMode(1, 'parallel');
        api.setSlotOutput(1, { mode: 'blend', blend: 'screen', opacity: 0.5, mask: 'luma', feather: 0.5 });
      });
      expect(await rendersSomething(page)).toBe(true);
      await expect
        .poll(() => page.evaluate(() => (window as any).__pixelocity__.getCompositorStats()), { timeout: 30_000 })
        .toMatchObject({ layers: 2, masks: 1, error: null });

      expect(await gpuErrors(page, mode)).toEqual([]);
    });
  }
});
