import { expect, test } from '@playwright/test';
import sharp from 'sharp';
import { installGpuUncapturedErrorHook, readGpuUncapturedErrors, startStaticServer, stopStaticServer } from './helpers/rendererHarness';

const PORT = 3474;
const SHADERS = [
  { id: 'gen-neon-plasma-chrono-bloom', params: [0.5, 1, 0.7, 0] },
  { id: 'stellar-plasma', params: [0, 0.2, 0.3, 0.5] },
  { id: 'plasma-orb', params: [0.5, 0.4, 0.5, 0.6] },
  { id: 'liquid-volumetric-zoom', params: [1, 0.8, 0.5, 0.6] },
  { id: 'atmos_volumetric_fog', params: [0.3, 0.5, 0.5, 0.5] },
  { id: 'heat-haze', params: [0.5, 0.5, 0.5, 0.5] },
  { id: 'sim-volumetric-fake-em', params: [0.5, 0.5, 0.5, 0.5] },
];

test.beforeAll(async () => startStaticServer(PORT));
test.afterAll(async () => stopStaticServer());

test('upgraded shaders compile and produce nonuniform frames on WebGPU', async ({ page }) => {
  test.setTimeout(300_000);
  await installGpuUncapturedErrorHook(page);
  await page.goto(`http://localhost:${PORT}/?renderer=main&testMode=1`, { waitUntil: 'load' });
  await page.waitForFunction(() => (window as any).webgpuProbe && (window as any).__pixelocity__?.renderer, null, { timeout: 60_000 });
  expect(await page.evaluate(() => (window as any).webgpuProbe.ok)).toBe(true);
  await page.waitForFunction(() => (window as any).__pixelocity__.getSlotState(0)?.shaderId === 'liquid', null, { timeout: 60_000 });
  await page.evaluate(async () => {
    const api = (window as any).__pixelocity__;
    api.setRenderScale(0.25);
    api.setInputSource('image');
    await api.loadImage('./thumbnails/plasma.png');
    api.setTestRenderState({ time: 2.5, mouseX: 0.5, mouseY: 0.5 });
  });

  for (const shader of SHADERS) {
    const loaded = await page.evaluate(async ({ id, params }) => {
      const api = (window as any).__pixelocity__;
      const ok = await api.loadShader(id, `./shaders/${id}.wgsl`);
      api.setSlotShader(0, id);
      api.renderer.setSlotParams(0, ...params);
      return ok;
    }, shader);
    expect(loaded, `${shader.id} failed to load`).toBe(true);
    const frame = await page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.frameStats?.framesRendered ?? 0);
    await page.waitForFunction(
      (n) => ((window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.frameStats?.framesRendered ?? 0) >= n + 3,
      frame,
      { timeout: 90_000, polling: 250 },
    );
    const png = await page.evaluate(() => (window as any).__pixelocity__.captureThumbnailPng(64) as Promise<string | null>);
    if (!png) throw new Error(`${shader.id} produced no capture`);
    const stats = await sharp(Buffer.from(png.replace(/^data:image\/png;base64,/, ''), 'base64')).stats();
    expect(Math.max(...stats.channels.slice(0, 3).map((c) => c.max)), shader.id).toBeGreaterThan(10);
    expect(Math.max(...stats.channels.slice(0, 3).map((c) => c.stdev)), shader.id).toBeGreaterThan(1);
    expect(await readGpuUncapturedErrors(page), shader.id).toEqual([]);
  }
});
