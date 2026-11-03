import { expect, test } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import sharp from 'sharp';
import { installGpuUncapturedErrorHook, readGpuUncapturedErrors, startStaticServer, stopStaticServer } from './helpers/rendererHarness';

const PORT = 3477;
const ID = 'gen-sentient-bismuth-hypercrystal';

test.beforeAll(async () => startStaticServer(PORT));
test.afterAll(async () => stopStaticServer());

test('sentient crystal renders its folded faces across growth and twist settings', async ({ page }) => {
  test.setTimeout(300_000);
  await installGpuUncapturedErrorHook(page);
  await page.goto(`http://localhost:${PORT}/?renderer=main&testMode=1`, { waitUntil: 'load' });
  await page.waitForFunction(() => (window as any).webgpuProbe && (window as any).__pixelocity__?.renderer, null, { timeout: 60_000 });
  expect(await page.evaluate(() => (window as any).webgpuProbe.ok)).toBe(true);
  await page.waitForFunction(() => (window as any).__pixelocity__.getSlotState(0)?.shaderId === 'liquid', null, { timeout: 60_000 });
  const black = await sharp({
    create: { width: 32, height: 32, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 1 } },
  }).png().toBuffer();
  const loaded = await page.evaluate(async ({ id, image }) => {
    const api = (window as any).__pixelocity__;
    api.setRenderScale(0.25);
    api.setInputSource('image');
    await api.loadImage(image);
    const ok = await api.loadShader(id, `./shaders/${id}.wgsl`);
    api.setSlotShader(0, id);
    return ok;
  }, { id: ID, image: `data:image/png;base64,${black.toString('base64')}` });
  expect(loaded).toBe(true);

  for (const params of [[1, 1, 0, 1], [0.1, 0, -2, 0.5], [5, 3, 2, 3]]) {
    await page.evaluate((p) => {
      const api = (window as any).__pixelocity__;
      api.renderer.setSlotParams(0, p[0], p[1], p[2], p[3]);
      api.setTestRenderState({ time: 2.5, mouseX: 0.5, mouseY: 0.5, bass: 0.2, mid: 0.1, treble: 0.1 });
    }, params);
    const frame = await page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.frameStats?.framesRendered ?? 0);
    await page.waitForFunction(
      (n) => ((window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.frameStats?.framesRendered ?? 0) >= n + 3,
      frame,
      { timeout: 90_000, polling: 250 },
    );
    const png: string | null = await page.evaluate(() => (window as any).__pixelocity__.captureThumbnailPng(64));
    if (!png) throw new Error('Crystal capture returned no image');
    const stats = await sharp(Buffer.from(png.replace(/^data:image\/png;base64,/, ''), 'base64')).stats();
    expect(Math.max(...stats.channels.slice(0, 3).map((c) => c.max))).toBeGreaterThan(10);
    expect(Math.max(...stats.channels.slice(0, 3).map((c) => c.stdev))).toBeGreaterThan(1);
    expect(await readGpuUncapturedErrors(page)).toEqual([]);
  }

  const source = readFileSync(resolve('public/shaders', `${ID}.wgsl`), 'utf8');
  const instrumented = source.replace('col *= ao;', 'col = vec3<f32>(ledge, twin, 0.0);');
  expect(instrumented).not.toBe(source);
  await page.route('**/shaders/sentient-face-masks.wgsl', (route) =>
    route.fulfill({ contentType: 'text/plain', body: instrumented }));
  const masksLoaded = await page.evaluate(async () => {
    const api = (window as any).__pixelocity__;
    const ok = await api.loadShader('sentient-face-masks', './shaders/sentient-face-masks.wgsl');
    api.setSlotShader(0, 'sentient-face-masks');
    api.renderer.setSlotParams(0, 1, 1, 0, 1);
    api.setTestRenderState({ time: 2.5, mouseX: 0.5, mouseY: 0.5 });
    return ok;
  });
  expect(masksLoaded).toBe(true);
  const frame = await page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.frameStats?.framesRendered ?? 0);
  await page.waitForFunction(
    (n) => ((window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.frameStats?.framesRendered ?? 0) >= n + 3,
    frame,
    { timeout: 90_000, polling: 250 },
  );
  const masksPng: string | null = await page.evaluate(() => (window as any).__pixelocity__.captureThumbnailPng(128));
  if (!masksPng) throw new Error('Crystal face-mask capture returned no image');
  const masks = await sharp(Buffer.from(masksPng.replace(/^data:image\/png;base64,/, ''), 'base64')).stats();
  for (const channel of masks.channels.slice(0, 2)) {
    expect(channel.max).toBeGreaterThan(20);
    expect(channel.stdev).toBeGreaterThan(1);
  }
  expect(await readGpuUncapturedErrors(page)).toEqual([]);
});
