/**
 * Cross-origin isolation + the render worker's SharedArrayBuffer input ring
 * (#1314 C3), on the SwiftShader software device. Served by
 * scripts/serve-isolated.mjs with the production COOP/COEP headers.
 */
import { expect, test, type Page } from '@playwright/test';
import { startStaticServer, stopStaticServer } from './helpers/rendererHarness';

const PORT = 3463;

test.beforeAll(async () => {
  await startStaticServer(PORT, { isolated: true });
});

test.afterAll(async () => {
  await stopStaticServer();
});

async function boot(page: Page): Promise<void> {
  await page.goto(`http://localhost:${PORT}/?renderer=worker&testMode=1`, { waitUntil: 'load' });
  await page.waitForFunction(
    () => (window as any).webgpuProbe != null && (window as any).__pixelocity__?.renderer != null,
    null,
    { timeout: 60_000 },
  );
}

test.describe('render worker under cross-origin isolation', () => {
  test('the page and the worker are isolated and input travels through shared memory', async ({ page }) => {
    await boot(page);
    const diag = await page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics());
    expect(await page.evaluate(() => window.crossOriginIsolated)).toBe(true);
    expect(diag.renderThread).toBe('worker');
    expect(diag.crossOriginIsolated).toBe(true);
    expect(diag.inputChannel).toBe('sab');

    // Mouse + slot params written into the ring show up in the worker's renderer.
    await page.evaluate(async () => {
      const api = (window as any).__pixelocity__;
      api.setInputSource('generative');
      await api.loadShader('plasma', './shaders/plasma.wgsl');
      api.setSlotShader(0, 'plasma');
      api.renderer.updateMouse(0.2, 0.8);
      api.renderer.updateSlotParams({ zoomParam1: 0.9, zoomParam3: 0.1 }, 0);
    });
    await page.waitForFunction(() => {
      const input = (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.input;
      return !!input && Math.abs(input.mouse[0] - 0.2) < 1e-6 && Math.abs(input.slot0[0] - 0.9) < 1e-6;
    }, null, { timeout: 60_000, polling: 250 });
    const input = await page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics().webgpu.input);
    expect(input.mouse.map((v: number) => Number(v.toFixed(3)))).toEqual([0.2, 0.8]);
    // Only the params written here (the app's own sync owns the others).
    expect(Number(input.slot0[0].toFixed(3))).toBe(0.9);
    expect(Number(input.slot0[2].toFixed(3))).toBe(0.1);
    expect(await page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics().webgpu.gpuErrors)).toEqual([]);
  });
});
