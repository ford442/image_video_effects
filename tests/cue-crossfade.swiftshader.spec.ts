/**
 * Cue crossfade on a real — software — WebGPU device.
 *
 * A cue freezes the last presented picture into one rgba8unorm hold and the present pass
 * mixes it over the live frame (src/renderer/webgpu/presentHold.ts). The math has Jest
 * coverage over a fake device; this proves the hold is not a black frame and that the mix
 * ramps from the old picture to the new one on a real device, in the render worker.
 *
 * Compositor screenshots of a WebGPU canvas stay blank, so the presented frame is read back
 * through the renderer (`captureCanvasStats` → the worker's captureFrame RPC). That path only
 * exists in worker mode; the main-thread frame loop is covered by frame.crossfade.test.ts.
 *
 * Needs a production build: `SKIP_WASM_BUILD=1 npm run build && npm run test:engine2`.
 */
import { expect, test, type Page } from '@playwright/test';
import { startStaticServer, stopStaticServer } from './helpers/rendererHarness';

const PORT = 3467;
const FADE_MS = 6000;

type Api = Record<string, any>;

test.beforeAll(async () => {
  await startStaticServer(PORT);
});

test.afterAll(async () => {
  await stopStaticServer();
});

async function boot(page: Page): Promise<void> {
  await page.goto(`http://localhost:${PORT}/?renderer=worker&testMode=1`, { waitUntil: 'load' });
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
  // The app picks its own default shader for slot 0 once the shader list has loaded. Let that
  // settle first, or it lands in the middle of a test and looks like a shader change.
  await page
    .waitForFunction(() => !!(window as any).__pixelocity__.getSlotState?.(0)?.shaderId, null, { timeout: 60_000 })
    .catch(() => undefined);
}

/**
 * A full-frame generative shader (mean luminance ~0.7 on SwiftShader, steady frame to frame).
 * Clearing its slot afterwards presents black, so old and new picture are far apart.
 */
const BRIGHT = 'gen-aurora-silk';

async function loadBright(page: Page): Promise<void> {
  const loaded = await page.evaluate(async (id) => {
    const api = (window as any).__pixelocity__ as Api;
    api.overrideSlotCap(1);
    api.setInputSource('generative');
    const ok = await api.loadShader(id, `./shaders/${id}.wgsl`);
    api.setSlotShader(0, id);
    return ok;
  }, BRIGHT);
  expect(loaded).toBe(true);
  await page.waitForFunction(
    () => ((window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.frameStats?.framesRendered ?? 0) >= 3,
    null,
    { timeout: 90_000, polling: 250 },
  );
}

const luminance = (page: Page): Promise<number> =>
  page.evaluate(async () => (await (window as any).__pixelocity__.captureCanvasStats()).meanLuminance as number);

/** Brightest of a few reads: an animated shader can land on a dim frame under load. */
async function baselineLuminance(page: Page): Promise<number> {
  let best = 0;
  for (let i = 0; i < 4; i++) best = Math.max(best, await luminance(page));
  expect(best, `${BRIGHT} should present a bright picture before the cue`).toBeGreaterThan(0.1);
  return best;
}

/** Presented luminance over time, starting the moment the cue is issued. */
async function sampleAfter(page: Page, cue: () => void, spanMs: number): Promise<Array<{ t: number; lum: number }>> {
  const startedAt = await page.evaluate(() => performance.now());
  await page.evaluate(cue);
  const samples: Array<{ t: number; lum: number }> = [];
  for (;;) {
    const lum = await luminance(page);
    const t = (await page.evaluate(() => performance.now())) - startedAt;
    samples.push({ t, lum });
    if (t > spanMs) return samples;
  }
}

async function gpuErrors(page: Page): Promise<string[]> {
  return page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.gpuErrors ?? []);
}

test.describe('cue crossfade on SwiftShader WebGPU (render worker)', () => {
  test('an armed cue dissolves the old picture into the new stack instead of cutting', async ({ page }) => {
    await boot(page);
    await loadBright(page);
    const before = await baselineLuminance(page);

    const samples = await sampleAfter(page, () => {
      const api = (window as any).__pixelocity__ as Api;
      api.renderer.armCrossfade(6000);
      api.setSlotShader(0, ''); // the shader is off: the live stack is now black
    }, FADE_MS + 3000);

    // The hold is the old picture, not a black frame: a hard cut would read ~0 here.
    expect(samples[0]!.lum).toBeGreaterThan(before * 0.25);
    // Somewhere in the ramp the picture is neither the old one nor the new one.
    expect(samples.some((s) => s.lum > before * 0.05 && s.lum < before * 0.9)).toBe(true);
    // And it settles on the new stack once the ramp is over.
    expect(samples[samples.length - 1]!.lum).toBeLessThan(before * 0.05);
    expect(await gpuErrors(page)).toEqual([]);
  });

  test('without a cue the same change is a hard cut', async ({ page }) => {
    await boot(page);
    await loadBright(page);
    const before = await baselineLuminance(page);

    const samples = await sampleAfter(page, () => {
      (window as any).__pixelocity__.setSlotShader(0, '');
    }, 2000);

    expect(samples[0]!.lum).toBeLessThan(before * 0.05);
    expect(await gpuErrors(page)).toEqual([]);
  });

  test('a duration of 0 is a hard cut: nothing is armed', async ({ page }) => {
    await boot(page);
    await loadBright(page);
    const before = await baselineLuminance(page);

    const armed = await page.evaluate(() => (window as any).__pixelocity__.renderer.armCrossfade(0));
    expect(armed).toBe(false);
    const samples = await sampleAfter(page, () => {
      (window as any).__pixelocity__.setSlotShader(0, '');
    }, 2000);

    expect(samples[0]!.lum).toBeLessThan(before * 0.05);
    expect(await gpuErrors(page)).toEqual([]);
  });

  test('param moves under an armed cue send no command; the first shader change sends exactly one', async ({ page }) => {
    await boot(page);
    await loadBright(page);
    await baselineLuminance(page);

    const sent = await page.evaluate(async () => {
      const api = (window as any).__pixelocity__ as Api;
      const backend = api.renderer.currentRenderer as { startCrossfade: (ms: number) => boolean };
      const calls: number[] = [];
      const original = backend.startCrossfade.bind(backend);
      backend.startCrossfade = (ms: number) => {
        calls.push(ms);
        return original(ms);
      };
      const current = api.getSlotState(0)?.shaderId as string;

      api.renderer.armCrossfade(6000);
      api.renderer.updateSlotParams({ zoomParam1: 0.9 }, 0);
      api.renderer.setSlotParams(0, 0.1, 0.2, 0.3, 0.4);
      api.setSlotShader(0, current); // the same shader again is not a change
      const afterParams = [...calls];

      api.setSlotShader(0, ''); // the real change
      api.setSlotShader(0, current); // lands inside the same cue: no second hold
      return { afterParams, afterChange: [...calls], current };
    });

    expect(sent.current).toBe('gen-aurora-silk');
    expect(sent.afterParams).toEqual([]);
    expect(sent.afterChange).toEqual([6000]);
    expect(await gpuErrors(page)).toEqual([]);
  });
});
