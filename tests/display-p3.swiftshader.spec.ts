/**
 * Live Display P3 toggle on a software WebGPU device (canvas_configure.json optIn.displayP3).
 *
 * SwiftShader may or may not accept `colorSpace: 'display-p3'`. Either outcome is valid as long
 * as the canvas keeps presenting, no GPU error is raised, and a rejection lands on sRGB with a
 * fallback reason (never a dead canvas). Pixels are read back through the renderer because
 * compositor screenshots of a WebGPU canvas are blank on this VM.
 *
 * Needs a production build: `npm run build && npm run test:engine2 -- -g "Display P3"`.
 */
import { expect, test, type Page } from '@playwright/test';
import sharp from 'sharp';
import {
  installGpuUncapturedErrorHook,
  readGpuUncapturedErrors,
  startStaticServer,
  stopStaticServer,
} from './helpers/rendererHarness';

const PORT = 3465;
const STORAGE_KEY = 'px_display_p3';

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
  // The app's boot effect puts its default shader (Liquid) in slot 0 once the shader lists
  // load; plasma set before that is overwritten, and Liquid over the cleared generative
  // input reads back dark (engine2-device-loss waits the same way).
  await page
    .waitForFunction(() => (window as any).__pixelocity__.getSlotState(0)?.shaderId === 'liquid', null, {
      timeout: 60_000,
      polling: 250,
    })
    .catch(() => undefined);
  await page.evaluate(async () => {
    const api = (window as any).__pixelocity__;
    api.setInputSource('generative');
    await api.loadShader('plasma', './shaders/plasma.wgsl');
    api.setSlotShader(0, 'plasma');
    api.setTestRenderState({ time: 2.5, mouseX: 0.5, mouseY: 0.5 });
  });
}

/** Uncaptured GPU errors: the page hook sees main-thread devices, the worker reports its own. */
async function gpuErrors(page: Page, mode: Mode): Promise<string[]> {
  if (mode === 'main') return (await readGpuUncapturedErrors(page)).map((e) => e.message);
  return page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.gpuErrors ?? []);
}

/** Brightest of a few captures: an animated shader can land on a dim frame under load. */
async function presents(page: Page): Promise<boolean> {
  for (let i = 0; i < 4; i++) {
    await page.evaluate(() => (window as any).__pixelocity__.waitFrames(2));
    const png: string | null = await page.evaluate(() => (window as any).__pixelocity__.captureThumbnailPng(64));
    if (png) {
      const b64 = png.includes(',') ? png.split(',')[1] ?? '' : png;
      const stats = await sharp(Buffer.from(b64, 'base64')).stats();
      const max = Math.max(...stats.channels.slice(0, 3).map((c) => c.max));
      const stdev = Math.max(...stats.channels.slice(0, 3).map((c) => c.stdev));
      if (max > 64 && stdev > 5) return true;
    }
    await page.waitForTimeout(500);
  }
  return false;
}

const probeColor = (page: Page) =>
  page.evaluate(() => {
    const p = (window as any).webgpuProbe;
    return { space: p.canvasColorSpace, tone: p.canvasToneMapping, fallback: p.canvasColorFallback };
  });

test.describe('Display P3 live toggle on SwiftShader WebGPU', () => {
  for (const mode of MODES) {
    test(`${mode}: toggling P3 keeps presenting, errors stay empty, a rejection lands on sRGB`, async ({ page }) => {
      await boot(page, mode);

      // Default boot is sRGB / standard with nothing requested.
      expect(await probeColor(page)).toMatchObject({ space: 'srgb', tone: 'standard' });
      expect(await presents(page)).toBe(true);

      const on = await page.evaluate(() => (window as any).__pixelocity__.renderer.setDisplayP3(true, false));
      expect(on).toBeTruthy();
      expect(on.deferred).toBeFalsy();
      const applied = await probeColor(page);
      if (applied.space === 'display-p3') {
        expect(on.colorSpace).toBe('display-p3');
      } else {
        // Browser rejected P3: sRGB with a recorded reason, never a dead canvas.
        expect(applied.space).toBe('srgb');
        expect(applied.fallback).toBe('unsupported-p3');
        expect(on.colorSpace).toBe('srgb');
      }
      expect(await presents(page)).toBe(true);
      expect(await gpuErrors(page, mode)).toEqual([]);

      const off = await page.evaluate(() => (window as any).__pixelocity__.renderer.setDisplayP3(false, false));
      expect(off).toMatchObject({ colorSpace: 'srgb', toneMapping: 'standard' });
      expect(await probeColor(page)).toMatchObject({ space: 'srgb', tone: 'standard' });
      expect(await presents(page)).toBe(true);
      expect(await gpuErrors(page, mode)).toEqual([]);
    });
  }

  test('the persisted setting is honored at the next boot', async ({ page }) => {
    await page.addInitScript((key) => {
      try { localStorage.setItem(key, '1'); } catch { /* ignore */ }
    }, STORAGE_KEY);
    await boot(page, 'worker');
    const c = await probeColor(page);
    // Accepted -> display-p3; rejected -> sRGB with a reason. Never an unexplained sRGB.
    if (c.space !== 'display-p3') expect(c.fallback).toBe('unsupported-p3');
    expect(await presents(page)).toBe(true);
  });
});
