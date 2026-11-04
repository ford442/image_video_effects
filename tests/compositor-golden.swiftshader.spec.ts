/**
 * Layer compositor golden frames + rendering tier 2 on a WebGPU device (#1512 Part C).
 *
 * Runs in the `swiftshader` Playwright project, and unchanged on a self-hosted GPU runner
 * (.github/workflows/gpu-required.yml, suite `compositor-golden`).
 *
 *   - every blend mode at 50% opacity across two parallel slots, at rgba16float and
 *     rgba32float, against the CPU reference (src/renderer/testing/compositorReference.ts)
 *   - an f16-opted shader (`// @requires f16`, _half.wgsl) renders within ΔE < 1 of its f32 form
 *   - the boot probe reports the tier-2 fields; an HDR request lands on a canvas that presents
 *
 * The fixture shaders are solid colours, served by the route below, so each golden pixel is
 * exact. Pixels are read back through the renderer (`captureThumbnailPng`): compositor
 * screenshots of a WebGPU canvas stay blank on SwiftShader.
 *
 * Needs a production build: `npm run build && npm run test:engine2 -- compositor-golden`.
 */
import { expect, test, type Page } from '@playwright/test';
import sharp from 'sharp';
import { BLEND_MODES, type BlendMode, type SlotLayer } from '../src/renderer/layerState';
import { referenceComposite, type Rgba } from '../src/renderer/testing/compositorReference';
import {
  captureRgb,
  EQUIVALENT_DELTA_E,
  GOLDEN_CHANNEL_TOLERANCE,
  imageDeltaE,
  maxChannelDelta,
} from '../src/renderer/testing/goldenTolerance';
import {
  installGpuUncapturedErrorHook,
  readGpuUncapturedErrors,
  startStaticServer,
  stopStaticServer,
} from './helpers/rendererHarness';

const PORT = 3466;

/** Bottom slot (replace) and top slot (blended over it), linear light. */
const COLOR_A: Rgba = [0.6, 0.25, 0.4, 1];
const COLOR_B: Rgba = [0.3, 0.7, 0.2, 1];
const OPACITY = 0.5;

const solidShader = (c: Rgba) => `#include "_prelude.wgsl"
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = textureDimensions(writeTexture);
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }
  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(${c.map((v) => v.toFixed(4)).join(', ')}));
}
`;

/** Opts into the half variant; all math in hf* types from _half.wgsl. */
const F16_SHADER = `// @requires f16
#include "_prelude.wgsl"
#include "_half.wgsl"
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = textureDimensions(writeTexture);
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }
  let uv = vec2<f32>(gid.xy) / vec2<f32>(dims);
  let n = fbm4_h(uv * 6.0);
  let base = hf3(hf(uv.x), n, hf(1.0 - uv.y));
  let c = reinhard_h(saturate_h(hue_rotate_h(base, n * 3.0), 1.2) * 1.5);
  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(vec3<f32>(c), 1.0));
}
`;

const FIXTURES: Record<string, string> = {
  'golden-solid-a': solidShader(COLOR_A),
  'golden-solid-b': solidShader(COLOR_B),
  'golden-f16': F16_SHADER,
};

const FORMATS = [
  { format: 'rgba16float', quality: 'balanced' },
  { format: 'rgba32float', quality: 'ultra' },
] as const;

type Mode = 'main' | 'worker';

test.beforeAll(async () => {
  await startStaticServer(PORT);
});

test.afterAll(async () => {
  await stopStaticServer();
});

async function boot(page: Page, mode: Mode): Promise<void> {
  // Context-level so render-worker fetches are served too.
  await page.context().route(/\/shaders\/golden-[a-z0-9-]+\.wgsl$/, async (route) => {
    const id = new URL(route.request().url()).pathname.split('/').pop()?.replace(/\.wgsl$/, '') ?? '';
    const body = FIXTURES[id];
    await (body ? route.fulfill({ status: 200, contentType: 'text/plain', body }) : route.fulfill({ status: 404 }));
  });
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
  // load; fixtures set before that would be overwritten (engine2-device-loss does the same).
  await page
    .waitForFunction(() => (window as any).__pixelocity__.getSlotState(0)?.shaderId === 'liquid', null, {
      timeout: 60_000,
      polling: 250,
    })
    .catch(() => undefined);
}

async function gpuErrors(page: Page, mode: Mode): Promise<string[]> {
  if (mode === 'main') return (await readGpuUncapturedErrors(page)).map((e) => e.message);
  return page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.gpuErrors ?? []);
}

async function framesRendered(page: Page): Promise<number> {
  return page.evaluate(
    () => (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.frameStats?.framesRendered ?? 0,
  );
}

/** Let `n` more frames render, so a state change has reached the presented texture. */
async function settle(page: Page, n = 3): Promise<void> {
  const target = (await framesRendered(page)) + n;
  await page.waitForFunction(
    (min) => ((window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.frameStats?.framesRendered ?? 0) >= min,
    target,
    { timeout: 90_000, polling: 250 },
  );
}

/** Raw RGBA bytes of a renderer readback. */
async function capture(page: Page, size: number): Promise<{ data: Buffer; width: number; height: number }> {
  const png: string | null = await page.evaluate((s) => (window as any).__pixelocity__.captureThumbnailPng(s), size);
  expect(png, 'captureThumbnailPng returned null').toBeTruthy();
  const b64 = png!.includes(',') ? png!.split(',')[1] ?? '' : png!;
  const { data, info } = await sharp(Buffer.from(b64, 'base64')).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  return { data, width: info.width, height: info.height };
}

async function readCenter(page: Page): Promise<number[]> {
  const { data, width, height } = await capture(page, 16);
  const o = ((height >> 1) * width + (width >> 1)) * 4;
  return [data[o] ?? 0, data[o + 1] ?? 0, data[o + 2] ?? 0];
}

/**
 * Centre pixel once two consecutive readbacks agree: adaptive quality can resize the
 * working pool between frames on a slow adapter, and the frame right after shows only input.
 */
async function centerPixel(page: Page): Promise<number[]> {
  let last = await readCenter(page);
  for (let i = 0; i < 6; i++) {
    await settle(page, 1);
    const next = await readCenter(page);
    if (maxChannelDelta(next, last) <= 1) return next;
    last = next;
  }
  return last;
}

/** A readback once two consecutive ones agree (mean ΔE < 0.5); see centerPixel. */
async function stableCapture(page: Page, size: number) {
  let last = await capture(page, size);
  for (let i = 0; i < 6; i++) {
    await settle(page, 1);
    const next = await capture(page, size);
    if (imageDeltaE(next.data, last.data).mean < 0.5) return next;
    last = next;
  }
  return last;
}

/** Quality tier → internal format; returns the format the renderer actually runs. */
async function useQuality(page: Page, quality: string): Promise<string> {
  await page.evaluate((q) => (window as any).__pixelocity__.setRenderQuality(q), quality);
  return page.evaluate(() => (window as any).__pixelocity__.getPerformanceStatus()?.colorFormat ?? 'unknown');
}

/** Slot 0 = A (replace), slot 1 = B, both parallel. */
async function loadParallelPair(page: Page): Promise<void> {
  const ok = await page.evaluate(async () => {
    const api = (window as any).__pixelocity__;
    api.overrideSlotCap(2);
    api.setRenderScale(0.25);
    api.setInputSource('generative');
    const a = await api.loadShader('golden-solid-a', './shaders/golden-solid-a.wgsl');
    const b = await api.loadShader('golden-solid-b', './shaders/golden-solid-b.wgsl');
    api.setSlotShader(0, 'golden-solid-a');
    api.setSlotShader(1, 'golden-solid-b');
    api.setSlotMode(0, 'parallel');
    api.setSlotMode(1, 'parallel');
    return a && b;
  });
  expect(ok, 'fixture shaders failed to load').toBe(true);
}

function layer(blend: BlendMode, opacity = OPACITY): SlotLayer {
  return { output: 'blend', blend, opacity, mask: { source: 'none' } };
}

function expectedPixel(blend: BlendMode, opacity = OPACITY): [number, number, number] {
  // Depth is 0 with no depth map: depth-key keeps the base.
  return captureRgb(referenceComposite([0, 0, 0, 1], [
    { output: 'replace', blend: 'normal', opacity: 1, color: COLOR_A },
    { output: 'blend', blend, opacity, color: COLOR_B },
  ], 0));
}

async function goldenFor(page: Page, blend: BlendMode, opacity = OPACITY) {
  await page.evaluate(
    ({ l }) => (window as any).__pixelocity__.setSlotLayer(1, l),
    { l: layer(blend, opacity) },
  );
  await settle(page);
  const actual = await centerPixel(page);
  const expected = expectedPixel(blend, opacity);
  return { blend, actual, expected, delta: maxChannelDelta(actual, expected) };
}

test.describe('layer compositor golden frames (WebGPU)', () => {
  for (const { format, quality } of FORMATS) {
    test(`${format}: every blend mode at 50% over two parallel slots matches the reference`, async ({ page }) => {
      test.setTimeout(300_000);
      await boot(page, 'main');
      const running = await useQuality(page, quality);
      test.skip(running !== format, `adapter runs ${running} for "${quality}", not ${format}`);
      await loadParallelPair(page);

      // Replace (the default layer) is last-wins: slot 1's colour.
      await settle(page);
      expect(maxChannelDelta(await centerPixel(page), captureRgb(COLOR_B))).toBeLessThanOrEqual(GOLDEN_CHANNEL_TOLERANCE);

      const results = [];
      for (const blend of BLEND_MODES) results.push(await goldenFor(page, blend));
      test.info().annotations.push({ type: 'golden', description: JSON.stringify({ format, results }) });
      for (const r of results) {
        expect.soft(r.delta, `${r.blend}: got ${r.actual}, expected ${r.expected}`).toBeLessThanOrEqual(GOLDEN_CHANNEL_TOLERANCE);
      }

      const stats = await page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.compositor);
      expect(stats?.layers ?? 0).toBeGreaterThanOrEqual(2);
      expect(await gpuErrors(page, 'main')).toEqual([]);
    });
  }

  test('worker: screen at 50% across two parallel slots passes the golden', async ({ page }) => {
    test.setTimeout(180_000);
    await boot(page, 'worker');
    await loadParallelPair(page);
    const r = await goldenFor(page, 'screen');
    expect(r.delta, `got ${r.actual}, expected ${r.expected}`).toBeLessThanOrEqual(GOLDEN_CHANNEL_TOLERANCE);
    // Back to replace: the compositor stands down (stack freed) and the last-wins colour returns.
    await page.evaluate(() => (window as any).__pixelocity__.setSlotLayer(1, { output: 'replace' }));
    await settle(page);
    expect(maxChannelDelta(await centerPixel(page), captureRgb(COLOR_B))).toBeLessThanOrEqual(GOLDEN_CHANNEL_TOLERANCE);
    expect(await gpuErrors(page, 'worker')).toEqual([]);
  });

  test('a // @requires f16 shader renders within ΔE < 1 of its f32 form', async ({ page }) => {
    test.setTimeout(180_000);
    await boot(page, 'main');
    const render = async (f16: boolean) => {
      const ok = await page.evaluate(async (on) => {
        const api = (window as any).__pixelocity__;
        api.setRenderScale(0.25);
        api.setInputSource('generative');
        api.setShaderF16Enabled(on);
        // Toggling drops compiled pipelines: load again so the new variant compiles.
        const loaded = await api.loadShader('golden-f16', './shaders/golden-f16.wgsl');
        api.setSlotShader(0, 'golden-f16');
        return loaded;
      }, f16);
      expect(ok, 'golden-f16 failed to load').toBe(true);
      await settle(page);
      const precision = await page.evaluate(() => (window as any).__pixelocity__.getShaderPrecisionInfo());
      const image = await stableCapture(page, 32);
      await test.info().attach(`golden-f16-${f16 ? 'f16' : 'f32'}.png`, {
        body: await sharp(image.data, { raw: { width: image.width, height: image.height, channels: 4 } }).png().toBuffer(),
        contentType: 'image/png',
      });
      return { image, precision };
    };

    const half = await render(true);
    const full = await render(false);
    const supported = !!half.precision?.supported;
    expect(full.precision?.precisions?.['golden-f16']).toBe('f32');
    expect(half.precision?.precisions?.['golden-f16']).toBe(supported ? 'f16' : 'f32');
    if (!supported) test.info().annotations.push({ type: 'note', description: 'adapter lacks shader-f16: compared f32 with f32' });

    const dE = imageDeltaE(half.image.data, full.image.data);
    test.info().annotations.push({ type: 'deltaE', description: JSON.stringify(dE) });
    expect(dE.mean, `ΔE ${JSON.stringify(dE)}`).toBeLessThan(EQUIVALENT_DELTA_E);
    // The image is not flat: the comparison measured something.
    const lum = [...half.image.data].filter((_, i) => i % 4 === 1);
    expect(Math.max(...lum) - Math.min(...lum)).toBeGreaterThan(40);
    expect(await gpuErrors(page, 'main')).toEqual([]);
  });

  test('the probe reports the tier-2 ladder; an HDR request keeps presenting', async ({ page }) => {
    test.setTimeout(120_000);
    await boot(page, 'main');
    const probe = await page.evaluate(() => (window as any).webgpuProbe);
    for (const key of ['shaderF16', 'bgra8unormStorage', 'dualSourceBlending', 'float32Blendable', 'compat', 'canvasStorageBinding']) {
      expect(typeof probe[key], key).toBe('boolean');
    }
    expect(['core', 'compatibility']).toContain(probe.featureLevel);
    expect(['base', 'deep-workgroup', 'big-buffer']).toContain(probe.limitsTier);

    await page.evaluate(async () => {
      const api = (window as any).__pixelocity__;
      api.setRenderScale(0.25);
      api.setInputSource('generative');
      await api.loadShader('golden-solid-a', './shaders/golden-solid-a.wgsl');
      api.setSlotShader(0, 'golden-solid-a');
    });
    const hdr = await page.evaluate(() => (window as any).__pixelocity__.renderer.setDisplayP3(true, true));
    const color = await page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics()?.canvasColor
      ?? (window as any).webgpuProbe);
    test.info().annotations.push({ type: 'hdr', description: JSON.stringify({ hdr, color }) });
    if (hdr?.toneMapping === 'extended') {
      // Extended tone mapping is only ever configured on the rgba16float canvas.
      expect(hdr.canvasFormat ?? (await page.evaluate(() => (window as any).webgpuProbe.canvasFormat))).toBe('rgba16float');
    }
    await settle(page);
    expect(maxChannelDelta(await centerPixel(page), captureRgb(COLOR_A))).toBeLessThanOrEqual(GOLDEN_CHANNEL_TOLERANCE);

    const direct = await page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.directPresent);
    test.info().annotations.push({ type: 'directPresent', description: JSON.stringify(direct) });
    await page.evaluate(() => (window as any).__pixelocity__.renderer.setDisplayP3(false, false));
    await settle(page, 4);
    expect(await gpuErrors(page, 'main')).toEqual([]);
  });
});
