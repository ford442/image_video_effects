/**
 * Engine 2.0 (#1314) e2e on a real — software — WebGPU device.
 *
 * Runs in the `swiftshader` Playwright project (playwright.config.ts), which
 * launches Chromium with SwiftShader-over-Vulkan so GPU-less hosts get an
 * adapter. Compositor screenshots of a WebGPU canvas stay blank there, so pixel
 * checks read back through the renderer (`captureThumbnailPng`).
 *
 * Needs a production build: `SKIP_WASM_BUILD=1 npm run build && npm run test:engine2`.
 */
import { expect, test, type Page } from '@playwright/test';
import sharp from 'sharp';
import {
  buildAppUrl,
  installGpuUncapturedErrorHook,
  readGpuUncapturedErrors,
  startStaticServer,
  stopStaticServer,
} from './helpers/rendererHarness';

const PORT = 3462;

const STACK = [
  'plasma',
  'cyber-ripples',
  'rgb-split-glitch',
  'kaleidoscope',
  'anisotropic-kuwahara', // Tier C graph (3 nodes)
  'gen-lichen-reaction-diffusion',
];

type Api = Record<string, (...args: any[]) => any> & { renderer: any };

test.beforeAll(async () => {
  await startStaticServer(PORT);
});

test.afterAll(async () => {
  await stopStaticServer();
});

async function boot(page: Page, params: Record<string, string> = {}): Promise<void> {
  await installGpuUncapturedErrorHook(page);
  await page.goto(buildAppUrl('webgpu', params, PORT), { waitUntil: 'load' });
  await page.waitForFunction(
    () => {
      const w = window as any;
      return w.webgpuProbe != null && w.__pixelocity__?.renderer != null;
    },
    null,
    { timeout: 60_000 },
  );
  const probe = await page.evaluate(() => (window as any).webgpuProbe);
  expect(probe.ok, `boot probe failed: ${probe.failedStage} ${probe.lastError}`).toBe(true);
}

async function loadStack(page: Page, ids: string[], input: 'generative' | 'image' = 'generative') {
  return page.evaluate(
    async ({ ids, input }) => {
      const api = (window as any).__pixelocity__ as Api;
      api.overrideSlotCap(ids.length);
      api.setInputSource(input);
      const loaded: Record<string, boolean> = {};
      for (let i = 0; i < ids.length; i++) {
        loaded[ids[i]] = await api.loadShader(ids[i], `./shaders/${ids[i]}.wgsl`);
        api.setSlotShader(i, ids[i]);
      }
      api.setTestRenderState({ time: 2.5, mouseX: 0.5, mouseY: 0.5 });
      return loaded;
    },
    { ids, input },
  );
}

async function waitFrames(page: Page, n: number): Promise<void> {
  await page.evaluate((count) => (window as any).__pixelocity__.waitFrames(count), n);
}

async function frameStats(page: Page) {
  return page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.frameStats);
}

async function thumbnailStats(page: Page, size = 64) {
  const png: string | null = await page.evaluate(
    (s) => (window as any).__pixelocity__.captureThumbnailPng(s),
    size,
  );
  expect(png, 'captureThumbnailPng returned null').toBeTruthy();
  const b64 = png!.includes(',') ? png!.split(',')[1] : png!;
  const stats = await sharp(Buffer.from(b64, 'base64')).stats();
  return {
    max: Math.max(...stats.channels.slice(0, 3).map((c) => c.max)),
    stdev: Math.max(...stats.channels.slice(0, 3).map((c) => c.stdev)),
  };
}

test.describe('engine2 on SwiftShader WebGPU', () => {
  test('boots the TS backend on a software adapter', async ({ page }) => {
    await boot(page);
    const summary = await page.evaluate(() => (window as any).webgpuProbe.adapterSummary as string);
    expect(summary).toContain('features=');
    expect(await page.evaluate(() => (window as any).__pixelocity__.getRendererType())).toBe('webgpu');
  });

  test('a 6-slot stack with a Tier C graph submits once per frame, no bind-group churn, no GPU errors', async ({ page }) => {
    await boot(page);
    const loaded = await loadStack(page, STACK);
    for (const id of STACK) expect(loaded[id], `${id} failed to load`).toBe(true);

    await waitFrames(page, 4);
    const stats = await frameStats(page);
    expect(stats.framesRendered).toBeGreaterThan(2);
    expect(stats.submitsLastFrame).toBe(1);
    expect(stats.bindGroupsLastFrame).toBe(0);

    const slots = await page.evaluate(
      (n) => Array.from({ length: n }, (_, i) => (window as any).__pixelocity__.getSlotState(i)?.shaderId),
      STACK.length,
    );
    expect(slots).toEqual(STACK);
    expect(await readGpuUncapturedErrors(page)).toEqual([]);
  });

  test('thumbnail capture reads the presented output of a single-slot stack', async ({ page }) => {
    await boot(page);
    const loaded = await loadStack(page, ['plasma']);
    expect(loaded.plasma).toBe(true);
    await waitFrames(page, 3);

    const thumb = await thumbnailStats(page);
    // Generative input is cleared to black, so reading readTex (the pre-fix
    // behaviour for a single chained slot) yields max 0. Plasma draws bright orbs.
    expect(thumb.max).toBeGreaterThan(64);
    expect(thumb.stdev).toBeGreaterThan(1);
    expect(await readGpuUncapturedErrors(page)).toEqual([]);
  });

  test('gallery warm-up compiles pipelines ahead of selection without binding them', async ({ page }) => {
    await boot(page);
    const result = await page.evaluate(async () => {
      const api = (window as any).__pixelocity__;
      const ids = ['kaleidoscope', 'cyber-ripples'];
      api.renderer.warmShaders(ids.map((id) => ({ id, url: `./shaders/${id}.wgsl` })));
      const deadline = performance.now() + 60_000;
      while (performance.now() < deadline && !ids.every((id) => api.renderer.isShaderCached(id))) {
        await new Promise((r) => setTimeout(r, 250));
      }
      return {
        cached: ids.map((id) => api.renderer.isShaderCached(id)),
        slot0: api.getSlotState(0)?.shaderId ?? null,
      };
    });
    expect(result.cached).toEqual([true, true]);
    expect(result.slot0).toBeNull();
    expect(await readGpuUncapturedErrors(page)).toEqual([]);
  });
});
