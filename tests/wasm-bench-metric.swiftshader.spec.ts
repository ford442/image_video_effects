/**
 * #1080 bench metric plumbing on a real (software) WebGPU device.
 *
 * Runs in the `swiftshader` Playwright project against `build/`. SwiftShader
 * says nothing about speed; this only proves that the pieces the bench now
 * relies on work end to end:
 *   - the bench server is cross-origin isolated and shaders still load,
 *   - runUncappedBenchmark() returns ms/frame on TS (worker + main) and WASM,
 *   - the TS backend reports 'gpu-timestamp' once a readback has decoded.
 *
 * The WASM leg does not load a shader: app shader loads through the sync
 * ccall are broken on this build (see wasm-measurement.swiftshader.spec.ts).
 * Its frames still encode, submit and present, but with no compute pass its
 * timestamps never resolve. That spec covers the C++ timestamps on a
 * standalone module.
 */
import { expect, test, type Page } from '@playwright/test';
import { PARITY_MATRIX } from './fixtures/parityMatrix';
import { loadShaderOnSlot, startStaticServer, stopStaticServer, waitForTestApi } from './helpers/rendererHarness';

const PORT = 3464;
// SwiftShader renders a few frames per second at the default working size.
const UNCAPPED_FRAMES = 6;
const PLASMA = PARITY_MATRIX.find((s) => s.id === 'plasma')!;

test.beforeAll(async () => {
  await startStaticServer(PORT, { isolated: true });
});

test.afterAll(async () => {
  await stopStaticServer();
});

const appUrl = (renderer: 'webgpu' | 'main' | 'wasm') =>
  `http://localhost:${PORT}/?renderer=${renderer}&testMode=1`;

async function waitForGpuTimestamps(page: Page): Promise<void> {
  await expect
    .poll(() => page.evaluate(() => (window as any).__pixelocity__.getGPUTimings()?.timingSource), {
      timeout: 60_000,
      intervals: [500],
    })
    .toBe('gpu-timestamp');
}

async function thumbnailActiveRatio(page: Page): Promise<number> {
  return page.evaluate(async () => {
    const b64: string | null = await (window as any).__pixelocity__.captureThumbnailPng(64);
    if (!b64) return 0;
    const img = new Image();
    img.src = `data:image/png;base64,${b64}`;
    await img.decode();
    const c = document.createElement('canvas');
    c.width = img.naturalWidth;
    c.height = img.naturalHeight;
    const ctx = c.getContext('2d')!;
    ctx.drawImage(img, 0, 0);
    const { data } = ctx.getImageData(0, 0, c.width, c.height);
    let active = 0;
    for (let i = 0; i < data.length; i += 4) if (data[i] + data[i + 1] + data[i + 2] > 38) active++;
    return active / (c.width * c.height);
  });
}

async function runUncapped(page: Page) {
  return page.evaluate(
    (frames) => (window as any).__pixelocity__.runUncappedBenchmark(frames, 1),
    UNCAPPED_FRAMES,
  );
}

test.describe('#1080 bench metric on SwiftShader WebGPU', () => {
  test.setTimeout(180_000);

  for (const renderer of ['webgpu', 'main'] as const) {
    test(`TS (${renderer === 'webgpu' ? 'worker' : 'main thread'}): isolated, uncapped ms, GPU timestamps`, async ({ page }) => {
      await page.goto(appUrl(renderer), { waitUntil: 'load' });
      await waitForTestApi(page, 60_000);
      expect(await page.evaluate(() => self.crossOriginIsolated)).toBe(true);
      expect(await loadShaderOnSlot(page, PLASMA)).toBe(true);

      const thread = renderer === 'webgpu' ? 'worker' : 'main';
      expect(await page.evaluate(() => (window as any).__pixelocity__.getRenderThread())).toBe(thread);

      const uncapped = await runUncapped(page);
      expect(uncapped).toEqual(expect.objectContaining({ frames: UNCAPPED_FRAMES, renderThread: thread }));
      expect(uncapped.msPerFrame).toBeGreaterThan(0);
      expect(uncapped.wallMs).toBeCloseTo(uncapped.msPerFrame * UNCAPPED_FRAMES, 5);

      await waitForGpuTimestamps(page);

      // The rAF loop is back after the uncapped run and the shader still draws. Read
      // back through the renderer: a 2D drawImage of a SwiftShader WebGPU canvas is blank.
      expect(await thumbnailActiveRatio(page)).toBeGreaterThan(0);
    });
  }

  test('WASM: isolated, uncapped ms via requestWorkDoneMark', async ({ page }) => {
    await page.goto(appUrl('wasm'), { waitUntil: 'load' });
    await page.waitForFunction(
      () => (window as any).webgpuProbe?.backend === 'wasm' && (window as any).__pixelocity__?.renderer != null,
      null,
      { timeout: 60_000 },
    );
    expect(await page.evaluate(() => self.crossOriginIsolated)).toBe(true);
    expect(await page.evaluate(() => (window as any).__pixelocity__.getRendererType())).toBe('wasm');

    const uncapped = await runUncapped(page);
    expect(uncapped).toEqual(expect.objectContaining({ frames: UNCAPPED_FRAMES, rendererType: 'wasm' }));
    expect(uncapped.msPerFrame).toBeGreaterThan(0);
    // The loop restarted: frames keep coming after the uncapped run.
    await expect
      .poll(() => page.evaluate(() => (window as any).__pixelocity__.renderer.getMetrics().fps), { timeout: 30_000 })
      .toBeGreaterThan(0);
  });
});
