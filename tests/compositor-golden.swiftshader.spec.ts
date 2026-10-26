/**
 * Layer compositor golden frames (#1512 Part C) on a real WebGPU device.
 *
 * Two parallel slots: slot 0 draws gradient A (replace), slot 1 gradient B with a
 * blend mode / opacity / mask. Every fixture is read back through
 * `__pixelocity__.captureThumbnailPng` (the presented working texture, downsampled
 * on the GPU) and compared with the CPU reference of composite.wgsl
 * (src/renderer/webgpu/compositeReference.ts) using the pixel-diff helper the
 * WASM parity suite uses (`diffFrames`). The expectation is built from A and B as
 * this device rendered them, so the check is the blend math, not the gradients.
 *
 * Fixtures: 9 blend modes × {rgba16float, rgba32float}, the acceptance case
 * (screen at 50 %), four mask sources + feather, and the f16 / f32 helper pair
 * within ΔE < 1. The same file runs on SwiftShader (`npm run test:engine2`) and on
 * the GPU runner (`.github/workflows/gpu-required.yml`, suite `compositor-golden`).
 *
 * Needs a production build: `SKIP_WASM_BUILD=1 npm run build && npm run test:engine2 -- -g "golden"`.
 */
import { expect, test, type Page } from '@playwright/test';
import { readFileSync } from 'fs';
import { resolve } from 'path';
import sharp from 'sharp';
import {
  annotateBootAdapter,
  diffFrames,
  startStaticServer,
  stopStaticServer,
  writeFrameArtifact,
  type FrameCapture,
} from './helpers/rendererHarness';
import { planCompositeGroup } from '../src/renderer/webgpu/compositor';
import { compositePixel, type Rgba } from '../src/renderer/webgpu/compositeReference';
import { BLEND_MODES, DEFAULT_SLOT_OUTPUT, type SlotOutput } from '../src/renderer/slotOutput';

const PORT = Number(process.env.PX_GOLDEN_PORT ?? 3471);
const THREAD = process.env.PX_RENDER_THREAD === 'main' ? 'main' : 'worker';
/** Readback grid (cells). Gradients are linear, so a cell's mean is its centre value. */
const GRID = 32;
/** Per-channel tolerance in linear light, 0–1 (8-bit sRGB readback + fp16 storage). */
const MAX_DELTA = 5 / 255;
const MEAN_DELTA = 2 / 255;
const ARTIFACTS = 'test-results/compositor-golden';

type Api = Record<string, any>;
type Format = 'rgba16float' | 'rgba32float';

const fixture = (name: string) =>
  `data:text/plain;base64,${Buffer.from(readFileSync(resolve(__dirname, 'fixtures/compositor', `${name}.wgsl`))).toString('base64')}`;

test.beforeAll(async () => {
  await startStaticServer(PORT);
});

test.afterAll(async () => {
  await stopStaticServer();
});

async function boot(page: Page): Promise<void> {
  await page.goto(`http://localhost:${PORT}/?renderer=${THREAD}&testMode=1`, { waitUntil: 'load' });
  await page.waitForFunction(
    () => (window as any).webgpuProbe != null && (window as any).__pixelocity__?.renderer != null,
    null,
    { timeout: 60_000 },
  );
  const probe = await page.evaluate(() => (window as any).webgpuProbe);
  expect(probe.ok, `boot probe failed: ${probe.failedStage} ${probe.lastError}`).toBe(true);
  await annotateBootAdapter(page, test.info());
  // Let the app's default slot-0 shader land before the fixtures replace it.
  await page
    .waitForFunction(() => !!(window as any).__pixelocity__.getSlotState?.(0)?.shaderId, null, { timeout: 60_000 })
    .catch(() => undefined);
}

const framesRendered = (page: Page): Promise<number> =>
  page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.frameStats?.framesRendered ?? 0);

/**
 * Wait until the renderer has drawn a few frames after the last command. The worker
 * snapshot is ~4 Hz and outputs ride the next page frame, so the starting count is read
 * only once a fresh snapshot can have arrived.
 */
async function settle(page: Page, frames = 3): Promise<void> {
  await page.waitForTimeout(THREAD === 'worker' ? 600 : 100);
  const start = await framesRendered(page);
  await expect.poll(() => framesRendered(page), { timeout: 90_000, intervals: [250] }).toBeGreaterThanOrEqual(start + frames);
}

async function setFormat(page: Page, format: Format): Promise<void> {
  await page.evaluate((mode) => (window as any).__pixelocity__.setRenderQuality(mode), format === 'rgba32float' ? 'ultra' : 'balanced');
  await expect
    .poll(() => page.evaluate(() => (window as any).__pixelocity__.getPerformanceStatus().colorFormat), { timeout: 30_000 })
    .toBe(format);
}

async function loadFixtures(page: Page, names: string[]): Promise<void> {
  const urls = Object.fromEntries(names.map((n) => [n, fixture(n)]));
  const ok = await page.evaluate(async (entries) => {
    const api = (window as any).__pixelocity__ as Api;
    api.overrideSlotCap(6);
    api.setRenderScale(0.25); // SwiftShader is slow at full size; the math is size-independent
    api.setInputSource('generative');
    const results: boolean[] = [];
    for (const [id, url] of Object.entries(entries)) results.push(await api.loadShader(id, url));
    for (let i = 0; i < 6; i++) api.setSlotShader(i, '');
    return results.every(Boolean);
  }, urls);
  expect(ok, 'fixture shaders compile').toBe(true);
}

/** slots: [shaderId, output] per slot, all parallel. Unlisted slots are cleared. */
async function stack(page: Page, slots: Array<[string, Partial<SlotOutput>]>): Promise<void> {
  await page.evaluate((list) => {
    const api = (window as any).__pixelocity__ as Api;
    for (let i = 0; i < 6; i++) {
      const entry = list[i];
      api.setSlotShader(i, entry ? entry[0] : '');
      api.setSlotMode(i, 'parallel');
      api.setSlotOutput(i, { mode: 'replace', blend: 'normal', opacity: 1, mask: 'none', maskInvert: false, feather: 0, keyThreshold: 0.5, ...(entry?.[1] ?? {}) });
    }
  }, slots);
  await settle(page);
}

async function capture(page: Page): Promise<FrameCapture> {
  const b64: string | null = await page.evaluate((size) => (window as any).__pixelocity__.captureThumbnailPng(size), GRID);
  expect(b64, 'thumbnail readback').toBeTruthy();
  const png = b64!.includes(',') ? b64!.split(',')[1]! : b64!;
  const { data, info } = await sharp(Buffer.from(png, 'base64')).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  return { png, width: info.width, height: info.height, grid: Array.from(data), gridSize: info.width };
}

const toLinear = (v8: number) => Math.pow(v8 / 255, 2.2);

/** RGB in linear light (alpha untouched) as a FrameCapture grid, for diffFrames. */
function linearGrid(c: FrameCapture): FrameCapture {
  const grid = c.grid.map((v, i) => (i % 4 === 3 ? v : Math.round(toLinear(v) * 255)));
  return { ...c, grid };
}

function cellColor(c: FrameCapture, i: number): Rgba {
  const o = i * 4;
  return [toLinear(c.grid[o]!), toLinear(c.grid[o + 1]!), toLinear(c.grid[o + 2]!), c.grid[o + 3]! / 255];
}

/** Expected composite (linear 8-bit grid) from the layers this device rendered. */
function expectedGrid(
  outputs: SlotOutput[],
  layers: FrameCapture[],
  depthAt: (u: number) => number = () => 0,
): FrameCapture {
  const plan = planCompositeGroup(outputs.map((output, slotIndex) => ({ slotIndex, output })))!;
  const grid: number[] = [];
  const cells = GRID * GRID;
  for (let i = 0; i < cells; i++) {
    const u = ((i % GRID) + 0.5) / GRID;
    const px = compositePixel(plan, [0, 0, 0, 1], layers.map((l) => cellColor(l, i)), depthAt(u));
    grid.push(...px.slice(0, 3).map((v) => Math.round(Math.min(1, Math.max(0, v)) * 255)), Math.round(px[3] * 255));
  }
  return { png: '', width: GRID, height: GRID, grid, gridSize: GRID };
}

/** Grid cells whose column is not within `margin` of u = edge (key / mask steps). */
function withoutColumnsNear(c: FrameCapture, edge: number, margin: number): FrameCapture {
  const grid = [...c.grid];
  for (let i = 0; i < GRID * GRID; i++) {
    const u = ((i % GRID) + 0.5) / GRID;
    if (Math.abs(u - edge) < margin) for (let k = 0; k < 4; k++) grid[i * 4 + k] = 0;
  }
  return { ...c, grid };
}

function expectMatches(label: string, actual: FrameCapture, expected: FrameCapture): void {
  const diff = diffFrames(label, 0, linearGrid(actual), expected, MAX_DELTA);
  if (diff.maxAbsDelta > MAX_DELTA || diff.meanAbsDelta > MEAN_DELTA) {
    writeFrameArtifact(actual, `${ARTIFACTS}/${label}.png`);
    const lin = linearGrid(actual);
    const worst = Array.from({ length: GRID * GRID }, (_, i) => i)
      .map((i) => ({ i, d: Math.max(...[0, 1, 2].map((c) => Math.abs(lin.grid[i * 4 + c]! - expected.grid[i * 4 + c]!))) }))
      .sort((x, y) => y.d - x.d)
      .slice(0, 4)
      .map(({ i }) => `cell(${i % GRID},${Math.floor(i / GRID)}) got ${lin.grid.slice(i * 4, i * 4 + 4)} want ${expected.grid.slice(i * 4, i * 4 + 4)}`);
    console.log(`[golden] ${label} worst cells (linear 8-bit):\n  ${worst.join('\n  ')}`);
  }
  expect(diff.maxAbsDelta, `${label}: max |Δ| (linear)`).toBeLessThanOrEqual(MAX_DELTA);
  expect(diff.meanAbsDelta, `${label}: mean |Δ| (linear)`).toBeLessThanOrEqual(MEAN_DELTA);
}

const out = (patch: Partial<SlotOutput>): SlotOutput => ({ ...DEFAULT_SLOT_OUTPUT, ...patch });

/** Left half near 0.2, right half 0.9 (a step, so resampling cannot blur the key). */
async function stepDepthMap(page: Page): Promise<void> {
  await page.evaluate(() => {
    const api = (window as any).__pixelocity__ as Api;
    const canvas = document.querySelector('canvas') as HTMLCanvasElement | null;
    const w = canvas?.width || 1024;
    const h = canvas?.height || 1024;
    const data = new Array<number>(w * h);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) data[y * w + x] = x < w / 2 ? 0.2 : 0.9;
    api.updateDepthMap(data, w, h);
  });
}
const stepDepth = (u: number) => (u < 0.5 ? 0.2 : 0.9);

async function captureLayers(page: Page): Promise<{ a: FrameCapture; b: FrameCapture }> {
  await stack(page, [['golden-grad-a', {}]]);
  const a = await capture(page);
  await stack(page, [['golden-grad-a', {}], ['golden-grad-b', {}]]); // replace: last one wins
  const b = await capture(page);
  return { a, b };
}

test.describe(`compositor golden frames (${THREAD})`, () => {
  test.describe.configure({ timeout: 600_000 });

  for (const format of ['rgba16float', 'rgba32float'] as const) {
    test(`${format}: every blend mode matches the reference`, async ({ page }) => {
      await boot(page);
      await setFormat(page, format);
      await loadFixtures(page, ['golden-grad-a', 'golden-grad-b']);
      await stepDepthMap(page);
      const { a, b } = await captureLayers(page);

      for (const blend of BLEND_MODES) {
        const opacity = blend === 'normal' ? 0.75 : 0.5;
        const blended = out({ mode: 'blend', blend, opacity, keyThreshold: 0.5 });
        await stack(page, [['golden-grad-a', {}], ['golden-grad-b', blended]]);
        let actual = await capture(page);
        let expected = expectedGrid([out({}), blended], [a, b], stepDepth);
        if (blend === 'depth-key') {
          actual = withoutColumnsNear(actual, 0.5, 1.5 / GRID);
          expected = withoutColumnsNear(expected, 0.5, 1.5 / GRID);
        }
        expectMatches(`${format}-${blend}`, actual, expected);
      }
      const stats = await page.evaluate(() => (window as any).__pixelocity__.getCompositorStats());
      expect(stats).toMatchObject({ layers: 2, error: null });
    });
  }

  test('two parallel slots, screen at 50 % opacity (acceptance)', async ({ page }) => {
    await boot(page);
    await setFormat(page, 'rgba16float');
    await loadFixtures(page, ['golden-grad-a', 'golden-grad-b']);
    const { a, b } = await captureLayers(page);
    const screen = out({ mode: 'blend', blend: 'screen', opacity: 0.5 });
    await stack(page, [['golden-grad-a', {}], ['golden-grad-b', screen]]);
    const actual = await capture(page);
    expectMatches('acceptance-screen-50', actual, expectedGrid([out({}), screen], [a, b]));
    // And it is not either layer alone.
    expect(diffFrames('vs-a', 0, actual, a).maxAbsDelta).toBeGreaterThan(0.05);
    expect(diffFrames('vs-b', 0, actual, b).maxAbsDelta).toBeGreaterThan(0.05);
  });

  test('masks: own luma, another slot (alpha and mask-slot matte), depth, feather', async ({ page }) => {
    await boot(page);
    await setFormat(page, 'rgba16float');
    await loadFixtures(page, ['golden-grad-a', 'golden-grad-b', 'golden-matte']);
    await stepDepthMap(page);
    const { a, b } = await captureLayers(page);
    await stack(page, [['golden-matte', {}]]);
    const matte = await capture(page);

    const luma = out({ mode: 'blend', mask: 'luma' });
    await stack(page, [['golden-grad-a', {}], ['golden-grad-b', luma]]);
    expectMatches('mask-luma', await capture(page), expectedGrid([out({}), luma], [a, b]));

    // slot1 masked by its own alpha (an alpha matte: B's alpha ramps with x).
    const alpha = out({ mode: 'blend', mask: 'slot1', maskInvert: true });
    await stack(page, [['golden-grad-a', {}], ['golden-grad-b', alpha]]);
    expectMatches('mask-slot-alpha-inverted', await capture(page), expectedGrid([out({}), alpha], [a, b]));

    // A mask slot is never drawn; its luma × alpha is the matte.
    const tracked = out({ mode: 'blend', blend: 'add', opacity: 0.8, mask: 'slot2' });
    const maskSlot = out({ mode: 'mask' });
    await stack(page, [['golden-grad-a', {}], ['golden-grad-b', tracked], ['golden-matte', maskSlot]]);
    expectMatches('mask-slot-matte', await capture(page), expectedGrid([out({}), tracked, maskSlot], [a, b, matte]));

    const depth = out({ mode: 'blend', blend: 'multiply', mask: 'depth' });
    await stack(page, [['golden-grad-a', {}], ['golden-grad-b', depth]]);
    const hard = await capture(page);
    expectMatches(
      'mask-depth',
      withoutColumnsNear(hard, 0.5, 1.5 / GRID),
      withoutColumnsNear(expectedGrid([out({}), depth], [a, b], stepDepth), 0.5, 1.5 / GRID),
    );

    // Feather: far from the step nothing changes; at the step the edge softens.
    await stack(page, [['golden-grad-a', {}], ['golden-grad-b', { ...depth, feather: 1 }]]);
    const soft = await capture(page);
    expectMatches('mask-depth-feather-far', withoutColumnsNear(soft, 0.5, 6 / GRID), withoutColumnsNear(linearGrid(hard), 0.5, 6 / GRID));
    const edge = Math.floor(GRID / 2) - 1; // last cell left of the step
    const row = Math.floor(GRID / 2) * GRID;
    const hardEdge = hard.grid[(row + edge) * 4]!;
    const softEdge = soft.grid[(row + edge) * 4]!;
    expect(Math.abs(softEdge - hardEdge), 'feather softens the mask edge').toBeGreaterThan(2);
  });

  test('a @requires f16 shader matches its f32 twin within ΔE < 1', async ({ page }) => {
    await boot(page);
    const f16 = await page.evaluate(() => (window as any).webgpuProbe?.shaderF16 === true);
    await setFormat(page, 'rgba16float');
    await loadFixtures(page, ['golden-noise-f32', 'golden-noise-f16']);
    await stack(page, [['golden-noise-f32', {}]]);
    const ref = await capture(page);
    await stack(page, [['golden-noise-f16', {}]]);
    const half = await capture(page);
    const deltaE = maxDeltaE(ref, half);
    test.info().annotations.push({
      type: 'f16',
      description: f16 ? `shader-f16 device: max ΔE ${deltaE.toFixed(3)}` : `no shader-f16: f32 fallback, max ΔE ${deltaE.toFixed(3)}`,
    });
    expect(deltaE).toBeLessThan(1);
  });
});

// ── CIE76 ΔE between two sRGB grids ─────────────────────────────────────────

function srgbToLab(r8: number, g8: number, b8: number): [number, number, number] {
  const lin = (v: number) => {
    const c = v / 255;
    return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
  };
  const [r, g, b] = [lin(r8), lin(g8), lin(b8)];
  const x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
  const y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  const z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
  const f = (t: number) => (t > 0.008856 ? Math.cbrt(t) : 7.787 * t + 16 / 116);
  return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))];
}

function maxDeltaE(a: FrameCapture, b: FrameCapture): number {
  let max = 0;
  for (let i = 0; i < a.grid.length; i += 4) {
    const p = srgbToLab(a.grid[i]!, a.grid[i + 1]!, a.grid[i + 2]!);
    const q = srgbToLab(b.grid[i]!, b.grid[i + 1]!, b.grid[i + 2]!);
    max = Math.max(max, Math.hypot(p[0] - q[0], p[1] - q[1], p[2] - q[2]));
  }
  return max;
}
