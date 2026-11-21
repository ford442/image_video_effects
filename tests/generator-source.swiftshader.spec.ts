/**
 * Generative input mode on a software WebGPU device: the picked generative shader is a dedicated
 * source stage (webgpu/generator.ts) that the effect slots process. Before it, choosing
 * "Generative" only cleared the source, so the effect in slot 0 (Liquid) rendered over black.
 *
 * Drives the real UI (the Input Source radios), then reads pixels back through the renderer, because
 * compositor screenshots of a WebGPU canvas are blank on this VM.
 *
 * Needs a production build: `npm run build && npm run test:engine2 -- -g "Generative input"`.
 */
import { expect, test, type Page } from '@playwright/test';
import sharp from 'sharp';
import {
  installGpuUncapturedErrorHook,
  readGpuUncapturedErrors,
  startStaticServer,
  stopStaticServer,
} from './helpers/rendererHarness';

const PORT = 3476;

test.beforeAll(async () => {
  await startStaticServer(PORT);
});

test.afterAll(async () => {
  await stopStaticServer();
});

type Mode = 'main' | 'worker';
const MODES: Mode[] = ['main', 'worker'];

async function boot(page: Page, mode: Mode): Promise<void> {
  await installGpuUncapturedErrorHook(page);
  await page.goto(`http://localhost:${PORT}/?renderer=${mode}&testMode=1`, { waitUntil: 'load' });
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
  // The app's boot effect puts Liquid in slot 0 once the shader lists load.
  await page.waitForFunction(() => /^liquid(-original)?$/.test((window as any).__pixelocity__.getSlotState(0)?.shaderId ?? ''), null, {
    timeout: 60_000,
    polling: 250,
  });
}

interface Stats { mean: number; max: number; stdev: number }

/** Luminance-ish stats of the renderer's current picture (channels averaged). */
async function picture(page: Page, frames = 3): Promise<Stats> {
  await page.evaluate((n) => (window as any).__pixelocity__.waitFrames(n), frames);
  const png: string | null = await page.evaluate(() => (window as any).__pixelocity__.captureThumbnailPng(64));
  if (!png) return { mean: 0, max: 0, stdev: 0 };
  const b64 = png.includes(',') ? png.split(',')[1] ?? '' : png;
  const stats = await sharp(Buffer.from(b64, 'base64')).stats();
  const rgb = stats.channels.slice(0, 3);
  return {
    mean: rgb.reduce((s, c) => s + c.mean, 0) / 3,
    max: Math.max(...rgb.map((c) => c.max)),
    stdev: Math.max(...rgb.map((c) => c.stdev)),
  };
}

/** Wait (shader compile on SwiftShader is slow) until the picture has structure; return the best frame. */
async function pictureWithContent(page: Page, tries = 24): Promise<Stats> {
  let best: Stats = { mean: 0, max: 0, stdev: 0 };
  for (let i = 0; i < tries; i++) {
    const s = await picture(page, 2);
    if (s.max > best.max) best = s;
    if (s.max > 48 && s.stdev > 4) return s;
    await page.waitForTimeout(500);
  }
  return best;
}

/**
 * The generator is armed once the shader compiled. The app defaults to gen-orb, but a device that
 * cannot run it (the catalog hides rgba32float / deep-workgroup shaders) gets another generative
 * shader instead of a black source, so any non-null id counts.
 */
async function generatorArmed(page: Page): Promise<string> {
  const handle = await page.waitForFunction(
    () => (window as any).__pixelocity__.renderer.getGenerator() || null,
    null,
    { timeout: 120_000, polling: 500 },
  );
  return (await handle.jsonValue()) as string;
}

const state = (page: Page, slot: number) =>
  page.evaluate((i) => (window as any).__pixelocity__.getSlotState(i), slot);

async function gpuErrors(page: Page, mode: Mode): Promise<string[]> {
  if (mode === 'main') return (await readGpuUncapturedErrors(page)).map((e) => e.message);
  return page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.gpuErrors ?? []);
}

test.describe('Generative input source (dedicated generator stage)', () => {
  for (const mode of MODES) {
    test(`${mode}: the Generative radio shows the generator and Liquid still processes it`, async ({ page }) => {
      test.setTimeout(240_000);
      await boot(page, mode);
      expect(await page.evaluate(() => (window as any).__pixelocity__.renderer.getGenerator())).toBeNull();

      // The user's path: the Input Source radio. (force: the control panel may be scrolled / collapsed.)
      await page.locator('input[type="radio"][value="generative"]').first().check({ force: true });
      await generatorArmed(page);

      const withLiquid = await pictureWithContent(page);
      // The bug: Liquid over a cleared source read back black.
      expect(withLiquid.max, `liquid over the generator is black: ${JSON.stringify(withLiquid)}`).toBeGreaterThan(48);
      expect(withLiquid.stdev).toBeGreaterThan(4);

      // The generator is not an effect slot: Liquid is still in slot 0, nothing was displaced.
      expect(await state(page, 0)).toMatchObject({ shaderId: expect.stringMatching(/^liquid(-original)?$/), enabled: true });
      expect((await state(page, 1)).shaderId).toBeNull();

      expect(await gpuErrors(page, mode)).toEqual([]);
    });

    test(`${mode}: every effect slot processes the generator, and clearing them shows it raw`, async ({ page }) => {
      test.setTimeout(240_000);
      await boot(page, mode);
      await page.locator('input[type="radio"][value="generative"]').first().check({ force: true });
      await generatorArmed(page);

      // Slots empty: the raw generator picture.
      await page.evaluate(() => (window as any).__pixelocity__.setSlotShader(0, ''));
      const raw = await pictureWithContent(page);
      expect(raw.max).toBeGreaterThan(48);

      // A strong colour effect in a *second* slot changes what is on screen.
      await page.evaluate(async () => {
        const api = (window as any).__pixelocity__;
        await api.loadShader('solarize-warp', './shaders/solarize-warp.wgsl');
        api.setSlotShader(0, 'solarize-warp');
      });
      const effected = await pictureWithContent(page);
      expect(effected.max).toBeGreaterThan(48);
      expect(
        Math.abs(effected.mean - raw.mean),
        `effect did not change the picture: raw=${JSON.stringify(raw)} effected=${JSON.stringify(effected)}`,
      ).toBeGreaterThan(1.5);

      expect(await gpuErrors(page, mode)).toEqual([]);
    });

    test(`${mode}: leaving Generative turns the generator off`, async ({ page }) => {
      test.setTimeout(240_000);
      await boot(page, mode);
      await page.locator('input[type="radio"][value="generative"]').first().check({ force: true });
      await generatorArmed(page);
      await page.locator('input[type="radio"][value="image"]').first().check({ force: true });
      await page.waitForFunction(() => (window as any).__pixelocity__.renderer.getGenerator() === null, null, {
        timeout: 30_000,
      });
      expect(await state(page, 0)).toMatchObject({ shaderId: expect.stringMatching(/^liquid(-original)?$/) });
    });
  }
});
