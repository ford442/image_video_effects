/**
 * Sim-ring spatial hash on a real — software — WebGPU device.
 *
 * `murmuration` and `photon-bins` (simRing.spatialHash) and `dla-crystals` (no
 * hash) run through the shipped TS renderer, in the page and in the render
 * worker. Asserted: the shaders compile against the real Tint pipeline layouts
 * (4-binding group 1 for the hash entries), the planner's report shows the
 * scatter pass counted in the budget, nothing reaches `uncapturederror`, and
 * pixels read back through the renderer are not blank (compositor screenshots of
 * a WebGPU canvas are blank on SwiftShader).
 *
 * Needs a production build: `SKIP_WASM_BUILD=1 npm run build && npm run test:engine2`.
 */
import { expect, test, type Page } from '@playwright/test';
import { mkdirSync, writeFileSync } from 'fs';
import { resolve } from 'path';
import sharp from 'sharp';
import {
  installGpuUncapturedErrorHook,
  readGpuUncapturedErrors,
  startStaticServer,
  stopStaticServer,
} from './helpers/rendererHarness';

const PORT = 3466;
const OUT_DIR = resolve(__dirname, '../test-results/sim-hash');

type Mode = 'main' | 'worker';
const MODES: Mode[] = ['main', 'worker'];

interface Case {
  id: string;
  url: string;
  /** Planner passes: nodes plus the scatter when the graph reads simHash. */
  passes: number;
  hash: boolean;
}

const CASES: Case[] = [
  { id: 'murmuration', url: './shaders/murmuration-flock.wgsl', passes: 3, hash: true },
  { id: 'photon-bins', url: './shaders/photon-bins-march.wgsl', passes: 4, hash: true },
  { id: 'dla-crystals', url: './shaders/dla-walkers.wgsl', passes: 2, hash: false },
];

test.beforeAll(async () => {
  await startStaticServer(PORT, { isolated: false });
  mkdirSync(OUT_DIR, { recursive: true });
});
test.afterAll(async () => {
  await stopStaticServer();
});

/** Console lines that mean a shader fell back to the pass-through (Tint is stricter than naga). */
const compileProblems = new WeakMap<Page, string[]>();

async function boot(page: Page, mode: Mode): Promise<void> {
  await installGpuUncapturedErrorHook(page);
  const problems: string[] = [];
  compileProblems.set(page, problems);
  page.on('console', (m) => {
    const text = m.text();
    if (/failed to compile|Shader compile failed|shader-compile/i.test(text)) problems.push(text.slice(0, 400));
  });
  await page.goto(`http://localhost:${PORT}/?renderer=${mode === 'worker' ? 'worker' : 'main'}&testMode=1`, {
    waitUntil: 'load',
  });
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
  // The fixture image, not the generative source: that one starts the attract showcase, which swaps
  // the slot's shader while a slow software device is still drawing.
  await page.evaluate(async () => {
    const api = (window as any).__pixelocity__;
    api.overrideSlotCap(1);
    api.setInputSource('image');
    api.setRenderQuality('ultra');
    await api.renderer.loadImage('./fixtures/thumbnail-scene.png');
  });
}

async function run(page: Page, c: Case): Promise<boolean> {
  return page.evaluate(
    async ({ id, url }) => {
      const api = (window as any).__pixelocity__;
      const ok = await api.loadShader(id, url);
      api.setSlotShader(0, id);
      api.setTestRenderState({ time: 2.5, mouseX: 0.5, mouseY: 0.5 });
      return ok;
    },
    { id: c.id, url: c.url },
  );
}

async function waitForRenderedFrames(page: Page, n: number): Promise<void> {
  await page.waitForFunction(
    (min) => ((window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.frameStats?.framesRendered ?? 0) >= min,
    n,
    { timeout: 180_000, polling: 250 },
  );
}

async function report(page: Page, id: string) {
  const handle = await page.waitForFunction(
    (shaderId) => {
      const r = (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.graph;
      return r && r.shaderId === shaderId && r.executed > 0 ? r : null;
    },
    id,
    { timeout: 180_000, polling: 250 },
  );
  return (await handle.jsonValue()) as {
    shaderId: string;
    requested: number;
    executed: number;
    truncated: number;
    errors: string[];
  };
}

async function gpuErrors(page: Page, mode: Mode): Promise<string[]> {
  if (mode === 'main') return (await readGpuUncapturedErrors(page)).map((e) => e.message);
  return page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.gpuErrors ?? []);
}

/** Brightest of a few captures; saves the best one for a human to look at. */
async function capture(page: Page, name: string, size = 256, attempts = 6) {
  let best = { max: 0, stdev: 0 };
  for (let i = 0; i < attempts; i++) {
    const png: string | null = await page.evaluate((s) => (window as any).__pixelocity__.captureThumbnailPng(s), size);
    expect(png, 'captureThumbnailPng returned null').toBeTruthy();
    const b64 = (png as string).includes(',') ? (png as string).split(',')[1] ?? '' : (png as string);
    const buf = Buffer.from(b64, 'base64');
    const stats = await sharp(buf).stats();
    const max = Math.max(...stats.channels.slice(0, 3).map((ch) => ch.max));
    const stdev = Math.max(...stats.channels.slice(0, 3).map((ch) => ch.stdev));
    if (max > best.max) {
      best = { max, stdev };
      writeFileSync(resolve(OUT_DIR, `${name}.png`), buf);
    }
    if (best.max > 48 && best.stdev > 4) break;
    await page.waitForTimeout(500);
  }
  return best;
}

for (const mode of MODES) {
  test.describe(`spatial hash flagships [${mode}]`, () => {
    for (const c of CASES) {
      test(`${c.id} compiles, plans ${c.passes} pass(es) and draws`, async ({ page }) => {
        test.setTimeout(300_000);
        await boot(page, mode);
        expect(await run(page, c), `${c.id} entries failed to compile`).toBe(true);
        await waitForRenderedFrames(page, 12);

        const r = await report(page, c.id);
        // The scatter pass is part of the budget: murmuration 3, photon-bins 4, DLA unchanged at 2.
        expect(r).toMatchObject({ shaderId: c.id, requested: c.passes, executed: c.passes, truncated: 0, errors: [] });

        // The planner built the scatter pass for the hash graphs only, and DLA never gets one.
        const keys = (await page.evaluate(
          (id) =>
            (window as any).__pixelocity__
              .getPassTimings()
              .filter((t: any) => t.shaderId === id && t.kind === 'compute')
              .map((t: any) => t.key as string),
          c.id,
        )) as string[];
        if (keys.length > 0) {
          expect(keys.includes('0:__simHashBuild')).toBe(c.hash);
        }

        const px = await capture(page, `${c.id}-${mode}`);
        expect(px.max, `output looks blank: ${JSON.stringify(px)}`).toBeGreaterThan(24);
        expect(compileProblems.get(page) ?? [], 'a shader fell back to the pass-through').toEqual([]);
        expect(await gpuErrors(page, mode)).toEqual([]);
      });
    }
  });
}
