/**
 * The two present variants of capability tier 2 (#1512 Part A) on a software WebGPU device.
 *
 * HDR present: with extended tone mapping negotiated the canvas becomes an rgba16float
 * display-p3 swapchain and the present keeps values above 1.0 (paper white / peak roll-off
 * instead of a clamp). Without an HDR display the proof is numeric: the presented texels
 * are read back as floats (`readPresentedTexels`, page thread) and must exceed 1.0.
 *
 * Storage present: with bgra8unorm-storage and a bgra8unorm canvas (`?canvas_format=` forces
 * it where the preferred format is rgba8unorm) the present is one compute pass writing the
 * swapchain. It must produce the same texels as the render-pass blit (`?storage_present=0`).
 *
 * Needs a production build: `SKIP_WASM_BUILD=1 npm run build && npm run test:engine2 -- -g "present"`.
 */
import { expect, test, type Page } from '@playwright/test';
import { readFileSync } from 'fs';
import { resolve } from 'path';
import { startStaticServer, stopStaticServer } from './helpers/rendererHarness';
import { hdrShoulder } from '../src/renderer/webgpu/presentVariants';

const PORT = 3475;
const fixture = (dir: string, name: string) =>
  `data:text/plain;base64,${Buffer.from(readFileSync(resolve(__dirname, 'fixtures', dir, `${name}.wgsl`))).toString('base64')}`;

test.beforeAll(async () => {
  await startStaticServer(PORT);
});

test.afterAll(async () => {
  await stopStaticServer();
});

async function boot(page: Page, query: string): Promise<any> {
  await page.goto(`http://localhost:${PORT}/?testMode=1&${query}`, { waitUntil: 'load' });
  await page.waitForFunction(
    () => (window as any).webgpuProbe != null && (window as any).__pixelocity__?.renderer != null,
    null,
    { timeout: 60_000 },
  );
  const probe = await page.evaluate(() => (window as any).webgpuProbe);
  expect(probe.ok, `boot probe failed: ${probe.failedStage} ${probe.lastError}`).toBe(true);
  await page
    .waitForFunction(() => !!(window as any).__pixelocity__.getSlotState?.(0)?.shaderId, null, { timeout: 60_000 })
    .catch(() => undefined);
  return probe;
}

async function show(page: Page, id: string, url: string): Promise<void> {
  const ok = await page.evaluate(async ({ shaderId, shaderUrl }) => {
    const api = (window as any).__pixelocity__;
    api.overrideSlotCap(6);
    api.setRenderScale(0.25);
    api.setInputSource('generative');
    const loaded = await api.loadShader(shaderId, shaderUrl);
    for (let i = 1; i < 6; i++) api.setSlotShader(i, '');
    api.setSlotShader(0, shaderId);
    return loaded;
  }, { shaderId: id, shaderUrl: url });
  expect(ok).toBe(true);
  await page.waitForTimeout(800);
}

/** Texels of a frame presented after now (the first read may still be in flight). */
async function texels(page: Page, points: Array<[number, number]>): Promise<number[][]> {
  await page.evaluate(() => (window as any).__pixelocity__.renderer.setCanvasCopySrc(true));
  let last: number[][] | null = null;
  for (let i = 0; i < 3; i++) {
    last = await page.evaluate((p) => (window as any).__pixelocity__.readPresentedTexels(p), points);
  }
  expect(last, 'presented texels').toBeTruthy();
  return last!;
}

const encode = (linear: number) => Math.pow(linear, 1 / 2.2);

test.describe('present variants on SwiftShader', () => {
  test.describe.configure({ timeout: 300_000 });

  test('HDR canvas: rgba16float display-p3, highlights above 1.0 reach the swapchain', async ({ page }) => {
    await boot(page, 'renderer=main');
    await show(page, 'hdr-highlight', fixture('present', 'hdr-highlight'));

    const on = await page.evaluate(() => (window as any).__pixelocity__.renderer.setDisplayP3(true, true));
    test.skip(on.toneMapping !== 'extended', `this browser rejected extended tone mapping (${on.reason})`);
    expect(on).toMatchObject({ colorSpace: 'display-p3', toneMapping: 'extended', format: 'rgba16float' });
    expect(await page.evaluate(() => (window as any).webgpuProbe.canvasFormat)).toBe('rgba16float');

    const peak = 1000 / 203;
    let [px] = await texels(page, [[0.5, 0.5]]);
    expect(px![0], 'red 3.0 stays above SDR white').toBeGreaterThan(1.2);
    expect(px![0]).toBeCloseTo(encode(hdrShoulder(3.0, peak)), 2);
    expect(px![1]).toBeCloseTo(encode(0.5), 2);

    // Paper white x2: the 0.5 green becomes SDR white.
    await page.evaluate(() => (window as any).__pixelocity__.setHdrPresent({ paperWhiteNits: 406 }));
    [px] = await texels(page, [[0.5, 0.5]]);
    expect(px![1]).toBeCloseTo(1, 2);

    // Off again (a live COPY_SRC capture defers colour changes, so end it first): back to
    // the preferred 8-bit canvas, where the highlight clamps.
    await page.evaluate(() => (window as any).__pixelocity__.renderer.setCanvasCopySrc(false));
    const off = await page.evaluate(() => (window as any).__pixelocity__.renderer.setDisplayP3(false, false));
    expect(off.deferred).toBeFalsy();
    expect(off.format).not.toBe('rgba16float');
    [px] = await texels(page, [[0.5, 0.5]]);
    expect(px![0]).toBeLessThanOrEqual(1);
    expect(px![0]).toBeGreaterThan(0.99);
  });

  test('storage present: one compute pass into a bgra8unorm swapchain, same texels as the blit', async ({ page }) => {
    const points: Array<[number, number]> = [[0.1, 0.1], [0.9, 0.2], [0.3, 0.8], [0.75, 0.95]];

    const blitProbe = await boot(page, 'renderer=main&canvas_format=bgra8unorm&storage_present=0');
    expect(blitProbe).toMatchObject({ canvasFormat: 'bgra8unorm', storagePresent: false });
    await show(page, 'golden-grad-a', fixture('compositor', 'golden-grad-a'));
    const viaBlit = await texels(page, points);

    const probe = await boot(page, 'renderer=main&canvas_format=bgra8unorm');
    test.skip(!probe.bgra8unormStorage, 'adapter without bgra8unorm-storage');
    expect(probe).toMatchObject({ canvasFormat: 'bgra8unorm', storagePresent: true });
    await show(page, 'golden-grad-a', fixture('compositor', 'golden-grad-a'));
    const viaStorage = await texels(page, points);
    const presents = await page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics().webgpu.canvas);
    expect(presents).toMatchObject({ format: 'bgra8unorm', storagePresent: true });

    viaStorage.forEach((texel, i) => {
      texel.slice(0, 3).forEach((v, c) => expect(Math.abs(v - viaBlit[i]![c]!), `point ${i} channel ${c}`).toBeLessThanOrEqual(1.5 / 255));
    });
    // And it is not a blank swapchain: the gradient varies across the points.
    expect(Math.abs(viaStorage[0]![0]! - viaStorage[1]![0]!)).toBeGreaterThan(0.1);
  });

  test('storage present in the render worker: the canvas keeps presenting', async ({ page }) => {
    const probe = await boot(page, 'renderer=worker&canvas_format=bgra8unorm');
    test.skip(!probe.bgra8unormStorage, 'adapter without bgra8unorm-storage');
    expect(probe).toMatchObject({ storagePresent: true, renderThread: 'worker' });
    await show(page, 'golden-grad-a', fixture('compositor', 'golden-grad-a'));
    const stats = await page.evaluate(async () => (window as any).__pixelocity__.captureCanvasStats());
    expect(stats.meanLuminance).toBeGreaterThan(0.2);
    expect(await page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.gpuErrors ?? [])).toEqual([]);
  });
});
