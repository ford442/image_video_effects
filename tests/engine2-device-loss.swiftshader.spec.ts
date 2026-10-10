/**
 * GPUDevice-loss recovery on a real (software) WebGPU device.
 *
 * `__pixelocity__.simulateDeviceLoss()` destroys the live device (so it really is
 * dead) but routes its `lost` through the runtime loss path. RendererManager then
 * rebuilds the TS WebGPU backend — on the page, or on a new render worker with a
 * fresh canvas — and replays the session. `simulateWorkerCrash()` raises an uncaught
 * error in the render worker, which recovers the same way (#1395). Pixels are read back through the
 * renderer (`captureThumbnailPng`) because compositor screenshots stay blank.
 *
 * Needs a production build: `SKIP_WASM_BUILD=1 npm run build && npm run test:engine2`.
 */
import { expect, test, type Page } from '@playwright/test';
import sharp from 'sharp';
import {
  installGpuUncapturedErrorHook,
  readGpuUncapturedErrors,
  startStaticServer,
  stopStaticServer,
} from './helpers/rendererHarness';

const PORT = 3464;
const STILL = './thumbnails/acoustic-string-theory.png';
const STACK = ['rgb-split-glitch', 'kaleidoscope'];

type Mode = 'main' | 'worker';
const MODES: Mode[] = ['main', 'worker'];

test.beforeAll(async () => {
  await startStaticServer(PORT, { isolated: process.env.PX_ISOLATED === '1' });
});

test.afterAll(async () => {
  await stopStaticServer();
});

/** Main-thread only (init scripts do not run in workers): every requestAdapter returns null while set. */
async function installAdapterKillSwitch(page: Page): Promise<void> {
  await page.addInitScript(() => {
    const gpu = (navigator as any).gpu;
    if (!gpu) return;
    const real = gpu.requestAdapter.bind(gpu);
    gpu.requestAdapter = (opts?: unknown) => ((window as any).__pxFailAdapter ? Promise.resolve(null) : real(opts));
  });
}

async function boot(page: Page, mode: Mode): Promise<void> {
  await installGpuUncapturedErrorHook(page);
  await page.goto(`http://localhost:${PORT}/?renderer=${mode}&testMode=1`, { waitUntil: 'load' });
  await page.waitForFunction(
    () => (window as any).webgpuProbe != null && (window as any).__pixelocity__?.renderer != null,
    null,
    { timeout: 60_000 },
  );
  const probe = await page.evaluate(() => (window as any).webgpuProbe);
  expect(probe.ok, `boot probe failed: ${probe.failedStage} ${probe.lastError}`).toBe(true);
}

/** A still image under a two-slot stack: a blank readback means the image or stack was not replayed. */
async function loadSession(page: Page): Promise<void> {
  const loaded = await page.evaluate(
    async ({ ids, still }) => {
      const api = (window as any).__pixelocity__;
      api.overrideSlotCap(ids.length);
      api.setInputSource('image');
      await api.loadImage(still);
      const ok: boolean[] = [];
      for (let i = 0; i < ids.length; i++) {
        ok.push(await api.loadShader(ids[i], `./shaders/${ids[i]}.wgsl`));
        api.setSlotShader(i, ids[i]);
      }
      api.setTestRenderState({ time: 1.5, mouseX: 0.5, mouseY: 0.5 });
      return ok;
    },
    { ids: STACK, still: STILL },
  );
  expect(loaded.every(Boolean)).toBe(true);
}

async function framesRendered(page: Page): Promise<number> {
  return page.evaluate(
    () => (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.frameStats?.framesRendered ?? 0,
  );
}

async function waitForFramesAbove(page: Page, n: number): Promise<void> {
  await page.waitForFunction(
    (min) => ((window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.frameStats?.framesRendered ?? 0) > min,
    n,
    { timeout: 90_000, polling: 250 },
  );
}

async function waitForRecovery(page: Page, state: 'idle' | 'failed', attempts: number) {
  await page.waitForFunction(
    ({ state, attempts }) => {
      const s = (window as any).__pixelocity__.getDeviceRecoveryStatus();
      return s.state === state && s.attempts === attempts;
    },
    { state, attempts },
    { timeout: 90_000, polling: 250 },
  );
  return page.evaluate(() => (window as any).__pixelocity__.getDeviceRecoveryStatus());
}

async function slotShaders(page: Page): Promise<Array<string | null>> {
  return page.evaluate(
    (n) => Array.from({ length: n }, (_, i) => (window as any).__pixelocity__.getSlotState(i)?.shaderId ?? null),
    STACK.length,
  );
}

async function thumbnailStats(page: Page, size = 64, attempts = 4) {
  let best = { max: 0, stdev: 0 };
  for (let i = 0; i < attempts; i++) {
    const png: string | null = await page.evaluate((s) => (window as any).__pixelocity__.captureThumbnailPng(s), size);
    expect(png, 'captureThumbnailPng returned null').toBeTruthy();
    const b64 = png!.includes(',') ? png!.split(',')[1] : png!;
    const stats = await sharp(Buffer.from(b64, 'base64')).stats();
    const max = Math.max(...stats.channels.slice(0, 3).map((c) => c.max));
    const stdev = Math.max(...stats.channels.slice(0, 3).map((c) => c.stdev));
    if (max > best.max) best = { max, stdev };
    if (best.max > 64 && best.stdev > 5) break;
    await page.waitForTimeout(500);
  }
  return best;
}

/** Page + current render worker: exactly one GPUDevice once the old one's `lost` settled. */
async function expectOneLiveDevice(page: Page): Promise<void> {
  await page.waitForFunction(
    () => (window as any).__pixelocity__.renderer.getDiagnostics()?.liveGpuDevices === 1,
    null,
    { timeout: 10_000, polling: 250 },
  ).catch(() => undefined);
  const live = await page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics()?.liveGpuDevices);
  expect(live, 'live GPUDevices after recovery').toBe(1);
}

async function gpuErrors(page: Page, mode: Mode): Promise<string[]> {
  if (mode === 'main') return (await readGpuUncapturedErrors(page)).map((e) => e.message);
  return page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.gpuErrors ?? []);
}

test.describe('device-loss recovery on SwiftShader WebGPU', () => {
  for (const mode of MODES) {
    test(`a lost device is rebuilt with the session and renders again [${mode}]`, async ({ page }) => {
      await boot(page, mode);
      await loadSession(page);
      await waitForFramesAbove(page, 3);
      const before = await slotShaders(page);
      expect(before).toEqual(STACK);
      const lit = await thumbnailStats(page);
      expect(lit.max, 'session renders before the loss').toBeGreaterThan(64);

      expect(await page.evaluate(() => (window as any).__pixelocity__.simulateDeviceLoss())).toBe(true);
      const status = await waitForRecovery(page, 'idle', 1);
      expect(status.lastLoss).toMatchObject({ kind: 'device-lost', reason: 'simulated' });

      const diag = await page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics());
      expect(diag.rendererType).toBe('webgpu');
      expect(diag.renderThread).toBe(mode);
      expect(diag.webgpuProbe?.ok).toBe(true);
      expect(diag.webgpu?.initialized).toBe(true);
      expect(await slotShaders(page)).toEqual(before);

      // The rebuilt backend counts frames from zero; it must keep producing them.
      const after = await framesRendered(page);
      await waitForFramesAbove(page, after + 2);
      const stats = await thumbnailStats(page);
      expect(stats.max, 'image + stack replayed after recovery').toBeGreaterThan(64);
      expect(stats.stdev).toBeGreaterThan(5);
      await expect(page.getByTestId('webgpu-device-lost')).toHaveCount(0);
      await expect(page.getByTestId('webgpu-probe-failure')).toHaveCount(0);
      expect(await gpuErrors(page, mode)).toEqual([]);
      // One device owner (#1395): the lost device is gone, only the rebuilt one is alive.
      await expectOneLiveDevice(page);
    });
  }

  test('a crashed render worker is replaced by a new one with the session [worker]', async ({ page }) => {
    await boot(page, 'worker');
    await loadSession(page);
    await waitForFramesAbove(page, 3);
    const generation = await page.evaluate(
      () => (window as any).__pixelocity__.renderer.getDiagnostics().deviceGeneration,
    );

    expect(await page.evaluate(() => (window as any).__pixelocity__.simulateWorkerCrash())).toBe(true);
    const status = await waitForRecovery(page, 'idle', 1);
    expect(status.lastLoss).toMatchObject({ kind: 'worker-died', reason: 'render worker crashed' });

    const diag = await page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics());
    expect(diag.renderThread).toBe('worker');
    expect(diag.webgpu?.initialized).toBe(true);
    // Cleared by the crash, published again by the new worker's backend.
    expect(diag.deviceGeneration).toBeGreaterThanOrEqual(generation + 2);
    expect(await slotShaders(page)).toEqual(STACK);
    const after = await framesRendered(page);
    await waitForFramesAbove(page, after + 2);
    expect((await thumbnailStats(page)).max, 'image + stack replayed on the new worker').toBeGreaterThan(64);
    expect(await gpuErrors(page, 'worker')).toEqual([]);
    await expectOneLiveDevice(page);
  });

  test('a failed recovery shows the diagnostic overlay with Retry, and Retry restores rendering [main]', async ({ page }) => {
    await installAdapterKillSwitch(page);
    await boot(page, 'main');
    await loadSession(page);
    await waitForFramesAbove(page, 3);

    await page.evaluate(() => {
      (window as any).__pxFailAdapter = true;
      (window as any).__pixelocity__.simulateDeviceLoss();
    });
    const failed = await waitForRecovery(page, 'failed', 1);
    expect(failed.lastError).toBeTruthy();
    const overlay = page.getByTestId('webgpu-device-lost');
    await expect(overlay).toBeVisible();
    await expect(overlay).toHaveAttribute('data-recovery-state', 'failed');
    expect(await page.evaluate(() => (window as any).webgpuProbe?.ok)).toBe(false);
    // No silent fallback to Canvas2D / WASM: the manager holds no backend at all.
    expect(await page.evaluate(() => {
      const m = (window as any).__pixelocity__.renderer;
      return { renderer: m.currentRenderer, type: m.currentType };
    })).toEqual({ renderer: null, type: null });

    await page.evaluate(() => { (window as any).__pxFailAdapter = false; });
    await page.getByTestId('webgpu-retry').click();
    await waitForRecovery(page, 'idle', 2);
    await expect(overlay).toHaveCount(0);
    expect(await slotShaders(page)).toEqual(STACK);
    const after = await framesRendered(page);
    await waitForFramesAbove(page, after + 2);
    expect((await thumbnailStats(page)).max).toBeGreaterThan(64);
  });
});
