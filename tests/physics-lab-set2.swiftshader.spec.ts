/**
 * Physics Lab set 2 (#1619) on a real — software — WebGPU device: `physarum-agents` (sim ring, no
 * hash) and `sph-fluid` (sim ring + hash, keepsHash density pass) through the shipped TS renderer,
 * on the page (`?renderer=main`).
 *
 * Asserted per shader: the entries compile against the real Tint pipeline layouts, the planner's
 * report shows the expected pass count (physarum 3; fluid 4 = scatter + density + force + render),
 * nothing reaches `uncapturederror`, the frame read back through the renderer is not black, and it
 * changes between frame 5 and frame 30 after the load (the sim moves). Compositor screenshots of a
 * WebGPU canvas are blank on SwiftShader, so pixels come from `captureThumbnailPng`. SwiftShader is
 * not a performance reference.
 *
 * Needs a production build: `npm run build && npx playwright test --project=swiftshader physics-lab-set2`.
 */
import { expect, test, type Page } from '@playwright/test';
import { mkdirSync, readFileSync, writeFileSync } from 'fs';
import { resolve } from 'path';
import sharp from 'sharp';
import {
  installGpuUncapturedErrorHook,
  readGpuUncapturedErrors,
  startStaticServer,
  stopStaticServer,
} from './helpers/rendererHarness';

const PORT = 3467;
const OUT_DIR = resolve(__dirname, '../test-results/physics-lab-set2');
const SIZE = 192;
const FIXTURE = resolve(__dirname, '../public/fixtures/thumbnail-scene.png');

interface Case {
  id: string;
  url: string;
  passes: number;
}

const CASES: Case[] = [
  { id: 'physarum-agents', url: './shaders/physarum-agents-diffuse.wgsl', passes: 3 },
  { id: 'sph-fluid', url: './shaders/sph-fluid-density.wgsl', passes: 4 },
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

async function boot(page: Page): Promise<void> {
  await installGpuUncapturedErrorHook(page);
  const problems: string[] = [];
  compileProblems.set(page, problems);
  page.on('console', (m) => {
    const text = m.text();
    if (/failed to compile|Shader compile failed|shader-compile/i.test(text)) problems.push(text.slice(0, 400));
  });
  // The app loads a random manifest image once its image manifest arrives (and another when a remote
  // load fails). Serve every remote image as the fixture, so whichever one lands, the input is the
  // same picture and two frames can only differ because the sim moved. No network needed either.
  const fixture = readFileSync(FIXTURE);
  await page.route(/^https?:\/\/(?!localhost)[^/]+\/.*\.(png|jpe?g|webp)(\?.*)?$/i, (route) =>
    route.fulfill({ status: 200, contentType: 'image/png', body: fixture }),
  );
  await page.goto(`http://localhost:${PORT}/?renderer=main&testMode=1`, { waitUntil: 'load' });
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
  // Let the app's boot put its default shader (Liquid) in slot 0 first: it does so once the shader
  // lists load, and landing mid-test it would replace the sim under the capture.
  await page
    .waitForFunction(() => (window as any).__pixelocity__.getSlotState(0)?.shaderId === 'liquid', null, {
      timeout: 60_000,
      polling: 250,
    })
    .catch(() => undefined);
  // The fixture image, not the generative source (that starts the attract showcase, which would swap
  // the slot's shader while the slow software device is still drawing).
  await page.evaluate(async () => {
    const api = (window as any).__pixelocity__;
    api.overrideSlotCap(1);
    api.setInputSource('image');
    api.setRenderQuality('ultra');
    await api.renderer.loadImage('./fixtures/thumbnail-scene.png');
  });
}

/** Slot 0's shader: it must still be the sim when we capture (the app's boot must not have replaced it). */
const slotShader = (page: Page): Promise<string | null> =>
  page.evaluate(() => (window as any).__pixelocity__.getSlotState(0)?.shaderId ?? null);

const framesRendered = (page: Page): Promise<number> =>
  page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.frameStats?.framesRendered ?? 0);

async function waitForFrame(page: Page, n: number): Promise<void> {
  await page.waitForFunction(
    (min) => ((window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.frameStats?.framesRendered ?? 0) >= min,
    n,
    { timeout: 240_000, polling: 100 },
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
  return (await handle.jsonValue()) as { shaderId: string; requested: number; executed: number; truncated: number; errors: string[] };
}

/** Raw RGB of a renderer readback, plus per-channel stats. */
async function capture(page: Page, name: string) {
  const png: string | null = await page.evaluate((s) => (window as any).__pixelocity__.captureThumbnailPng(s), SIZE);
  expect(png, 'captureThumbnailPng returned null').toBeTruthy();
  const b64 = (png as string).includes(',') ? (png as string).split(',')[1] ?? '' : (png as string);
  const buf = Buffer.from(b64, 'base64');
  writeFileSync(resolve(OUT_DIR, `${name}.png`), buf);
  const { data, info } = await sharp(buf).removeAlpha().resize(SIZE, SIZE, { fit: 'fill' }).raw().toBuffer({ resolveWithObject: true });
  const stats = await sharp(buf).stats();
  return {
    rgb: data,
    channels: info.channels,
    max: Math.max(...stats.channels.slice(0, 3).map((ch) => ch.max)),
    stdev: Math.max(...stats.channels.slice(0, 3).map((ch) => ch.stdev)),
  };
}

function meanAbsDiff(a: Buffer, b: Buffer): number {
  let sum = 0;
  for (let i = 0; i < a.length; i++) sum += Math.abs(a[i]! - b[i]!);
  return sum / a.length;
}

for (const c of CASES) {
  test(`${c.id}: compiles, plans ${c.passes} passes, draws and moves between frames 5 and 30`, async ({ page }) => {
    test.setTimeout(600_000);
    await boot(page);
    const ok = await page.evaluate(
      async ({ id, url }) => {
        const api = (window as any).__pixelocity__;
        const loaded = await api.loadShader(id, url);
        api.setSlotShader(0, id);
        return loaded;
      },
      { id: c.id, url: c.url },
    );
    expect(ok, `${c.id} entries failed to compile`).toBe(true);

    const r = await report(page, c.id);
    expect(r).toMatchObject({ shaderId: c.id, requested: c.passes, executed: c.passes, truncated: 0, errors: [] });

    const start = await framesRendered(page);
    await waitForFrame(page, start + 5);
    expect(await slotShader(page)).toBe(c.id);
    const early = await capture(page, `${c.id}-frame05`);
    await waitForFrame(page, start + 30);
    const late = await capture(page, `${c.id}-frame30`);
    expect(await slotShader(page)).toBe(c.id);

    expect(late.max, `frame 30 looks black: ${JSON.stringify({ max: late.max, stdev: late.stdev })}`).toBeGreaterThan(24);
    expect(late.stdev, 'frame 30 is a flat colour').toBeGreaterThan(4);
    const diff = meanAbsDiff(early.rgb, late.rgb);
    expect(diff, `frames 5 and 30 are identical (mean |Δ| ${diff.toFixed(3)})`).toBeGreaterThan(0.5);

    expect(compileProblems.get(page) ?? [], 'a shader fell back to the pass-through').toEqual([]);
    expect((await readGpuUncapturedErrors(page)).map((e) => e.message)).toEqual([]);
  });
}
