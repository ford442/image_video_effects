/**
 * App smoke suite (Release 2/5): the core user flows against a production build
 * or a deployed URL, in both render threads, failing on any console error,
 * uncaught exception or failed / 4xx / 5xx request.
 *
 *   npm run build && npm run test:smoke                       # local build/ (isolated server)
 *   SMOKE_BASE_URL=https://preview.example/ npm run test:smoke # deployed preview
 *
 * Env:
 *   SMOKE_BASE_URL     target origin (+ path). Unset: serve build/ with COOP/COEP.
 *   SMOKE_ALLOW_HOSTS  comma-separated hosts whose network failures (and the console
 *                      errors they cause) are tolerated. Defaults to the media hosts
 *                      that are blocked in CI VMs when no SMOKE_BASE_URL is set;
 *                      defaults to empty (strict) against a deployed URL.
 *   SMOKE_CHROMIUM_PATH optional Chromium binary (e.g. /opt/pw-browsers/chromium).
 *   SMOKE_REPORT_DIR   where pixel-readback PNGs + the JSON log summary go
 *                      (default test-results/app-smoke).
 *
 * Compositor screenshots of a WebGPU canvas are blank on SwiftShader, so pixels are
 * read back through the renderer (__pixelocity__.captureThumbnailPng). Page
 * screenshots are still saved: they show the UI chrome.
 */
import { expect, test, chromium, type Page, type Request } from '@playwright/test';
import { mkdirSync, writeFileSync } from 'fs';
import { resolve } from 'path';
import sharp from 'sharp';
import { startStaticServer, stopStaticServer, waitForBootDefaultShader } from './helpers/rendererHarness';

const PORT = 3471;
const DEPLOYED = !!process.env.SMOKE_BASE_URL;
const BASE_URL = (process.env.SMOKE_BASE_URL || `http://localhost:${PORT}/`).replace(/\/?$/, '/');
const CI_BLOCKED_HOSTS = ['storage.noahcohn.com', 'storage.googleapis.com', 'images.unsplash.com', 'unsplash.com', 'api.unsplash.com'];
const ALLOW_HOSTS = (process.env.SMOKE_ALLOW_HOSTS ?? (DEPLOYED ? '' : CI_BLOCKED_HOSTS.join(',')))
  .split(',')
  .map((h) => h.trim())
  .filter(Boolean);
const REPORT_DIR = resolve(process.env.SMOKE_REPORT_DIR ?? 'test-results/app-smoke');

type Thread = 'worker' | 'main';
const THREADS: Thread[] = ['worker', 'main'];

interface Problem {
  kind: 'console' | 'pageerror' | 'requestfailed' | 'http';
  text: string;
  allowed: boolean;
}

const summary: Record<string, { problems: Problem[]; requests: number }> = {};

function hostAllowed(url: string): boolean {
  try {
    const host = new URL(url).hostname;
    return ALLOW_HOSTS.some((h) => host === h || host.endsWith(`.${h}`));
  } catch {
    return false;
  }
}

/** Collects every console error / page error / failed request on the page. */
function watch(page: Page, key: string): Problem[] {
  const problems: Problem[] = [];
  const entry = (summary[key] = { problems, requests: 0 });
  page.on('request', () => entry.requests++);
  page.on('console', (msg) => {
    if (msg.type() !== 'error') return;
    const loc = msg.location()?.url ?? '';
    const text = `${msg.text()}${loc ? ` @ ${loc}` : ''}`;
    problems.push({ kind: 'console', text, allowed: hostAllowed(loc) || ALLOW_HOSTS.some((h) => msg.text().includes(h)) });
  });
  page.on('pageerror', (err) => problems.push({ kind: 'pageerror', text: String(err?.stack ?? err), allowed: false }));
  page.on('requestfailed', (req: Request) => {
    const failure = req.failure()?.errorText ?? 'failed';
    // Aborted navigations of media elements (a src swap) are not failures.
    if (failure === 'net::ERR_ABORTED' && ['media', 'image'].includes(req.resourceType())) return;
    problems.push({ kind: 'requestfailed', text: `${req.method()} ${req.url()} ${failure}`, allowed: hostAllowed(req.url()) });
  });
  page.on('response', (res) => {
    if (res.status() >= 400) {
      problems.push({ kind: 'http', text: `${res.status()} ${res.request().method()} ${res.url()}`, allowed: hostAllowed(res.url()) });
    }
  });
  return problems;
}

function expectClean(problems: Problem[]): void {
  const blocking = problems.filter((p) => !p.allowed).map((p) => `[${p.kind}] ${p.text}`);
  expect(blocking, 'console errors / page errors / failed requests').toEqual([]);
}

function url(thread: Thread, extra: Record<string, string> = {}): string {
  const params = new URLSearchParams({ renderer: thread, testMode: '1', ...extra });
  return `${BASE_URL}?${params.toString()}`;
}

async function boot(page: Page, thread: Thread, extra: Record<string, string> = {}): Promise<void> {
  await page.goto(url(thread, extra), { waitUntil: 'load' });
  await page.waitForFunction(
    () => {
      const w = window as any;
      return w.webgpuProbe != null && w.__pixelocity__?.renderer != null;
    },
    null,
    { timeout: 90_000 },
  );
  const probe = await page.evaluate(() => (window as any).webgpuProbe);
  expect(probe.ok, `boot probe failed: ${probe.failedStage} ${probe.lastError}`).toBe(true);
  expect(await page.evaluate(() => (window as any).__pixelocity__.getRenderThread?.())).toBe(thread);
  await waitForBootDefaultShader(page);
}

async function framesRendered(page: Page): Promise<number> {
  return page.evaluate(
    () => (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.frameStats?.framesRendered ?? 0,
  );
}

async function waitMoreFrames(page: Page, n: number): Promise<void> {
  const start = await framesRendered(page);
  await page.waitForFunction(
    ({ start, n }) =>
      ((window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.frameStats?.framesRendered ?? 0) >= start + n,
    { start, n },
    { timeout: 90_000, polling: 250 },
  );
}

/** Renderer readback: PNG buffer + per-channel stats. Retries to skip a dim animated frame. */
async function readback(page: Page, size = 128, attempts = 4) {
  let best: { png: Buffer; max: number; stdev: number } | null = null;
  for (let i = 0; i < attempts; i++) {
    const data: string | null = await page.evaluate((s) => (window as any).__pixelocity__.captureThumbnailPng(s), size);
    expect(data, 'captureThumbnailPng returned null').toBeTruthy();
    const png = Buffer.from(data!.includes(',') ? (data!.split(',')[1] ?? '') : data!, 'base64');
    const stats = await sharp(png).stats();
    const max = Math.max(...stats.channels.slice(0, 3).map((c) => c.max));
    const stdev = Math.max(...stats.channels.slice(0, 3).map((c) => c.stdev));
    if (!best || stdev > best.stdev) best = { png, max, stdev };
    if (best.max > 32 && best.stdev > 4) break;
    await page.waitForTimeout(400);
  }
  return best!;
}

async function meanDiff(a: Buffer, b: Buffer): Promise<number> {
  const [ra, rb] = await Promise.all([a, b].map((p) => sharp(p).removeAlpha().raw().toBuffer()));
  const len = Math.min(ra!.length, rb!.length);
  let sum = 0;
  for (let i = 0; i < len; i++) sum += Math.abs(ra![i]! - rb![i]!);
  return sum / len;
}

function save(name: string, buf: Buffer): void {
  mkdirSync(REPORT_DIR, { recursive: true });
  writeFileSync(resolve(REPORT_DIR, name), buf);
}

interface ListEntry {
  id: string;
  name: string;
  url: string;
  params?: unknown[];
  multipass?: unknown;
}

/** An image-input shader with at least one slider, from the shipped list. */
async function pickImageShader(page: Page): Promise<ListEntry> {
  const list: ListEntry[] = await page.evaluate(async (base) => {
    const res = await fetch(new URL('shader-lists/image.json', base).toString());
    return res.json();
  }, BASE_URL);
  expect(list.length, 'shader-lists/image.json is empty').toBeGreaterThan(0);
  const single = list.filter((s) => !s.multipass);
  const preferred = ['circular-pixelate', 'color-channel-weave', 'graphic-novel'];
  const pick = single.find((s) => preferred.includes(s.id)) ?? single.find((s) => Array.isArray(s.params) && s.params.length > 0) ?? single[0] ?? list[0]!;
  return { ...pick, url: pick.url.startsWith('.') || pick.url.includes('://') ? pick.url : `./${pick.url}` };
}

test.describe.configure({ mode: 'serial' });

test.beforeAll(async () => {
  if (!DEPLOYED) await startStaticServer(PORT, { isolated: true });
});
test.afterAll(async () => {
  if (!DEPLOYED) await stopStaticServer();
  mkdirSync(REPORT_DIR, { recursive: true });
  writeFileSync(
    resolve(REPORT_DIR, 'log-summary.json'),
    JSON.stringify(
      {
        baseUrl: BASE_URL,
        allowHosts: ALLOW_HOSTS,
        runs: Object.fromEntries(
          Object.entries(summary).map(([k, v]) => [
            k,
            {
              requests: v.requests,
              blocking: v.problems.filter((p) => !p.allowed),
              allowed: v.problems.filter((p) => p.allowed).length,
            },
          ]),
        ),
      },
      null,
      2,
    ),
  );
});

for (const thread of THREADS) {
  test.describe(`render thread: ${thread}`, () => {
    test(`boot, probe, cross-origin isolation [${thread}]`, async ({ page }, info) => {
      const problems = watch(page, info.title);
      await boot(page, thread);
      expect(await page.evaluate(() => crossOriginIsolated), 'crossOriginIsolated').toBe(true);
      await waitMoreFrames(page, 3);
      save(`page-boot-${thread}.png`, await page.screenshot());
      expectClean(problems);
    });

    test(`image + shader picked via search renders, slider changes output [${thread}]`, async ({ page }, info) => {
      const problems = watch(page, info.title);
      await boot(page, thread);
      const shader = await pickImageShader(page);
      const imageUrl = new URL('thumbnails/adaptive-mosaic.png', BASE_URL).toString();
      await page.evaluate(async (imageUrl) => {
        const api = (window as any).__pixelocity__;
        await api.loadImage(imageUrl);
        api.setInputSource('image');
        api.setTestRenderState({ time: 1.5, mouseX: 0.5, mouseY: 0.5 });
      }, imageUrl);

      // Select through the UI: search the name, Enter applies the top hit to slot 1.
      const search = page.getByRole('searchbox', { name: 'Filter controls and effects' });
      await search.fill(shader.name);
      await expect(page.getByRole('option', { name: shader.name, exact: true })).toBeVisible({ timeout: 15_000 });
      await search.press('Enter');
      await search.fill('');
      await page.waitForFunction(
        (id) => (window as any).__pixelocity__.getSlotState(0)?.shaderId === id,
        shader.id,
        { timeout: 60_000 },
      );

      const slider = page.locator('.params-grid input[type="range"]').first();
      await expect(slider).toBeVisible({ timeout: 15_000 });
      const [min, max] = await slider.evaluate((el: HTMLInputElement) => [el.min, el.max]);
      await slider.fill(min!);
      await waitMoreFrames(page, 4);
      const a = await readback(page);
      expect(a.max, `${shader.id} rendered a black frame`).toBeGreaterThan(16);
      expect(a.stdev, `${shader.id} rendered a flat frame`).toBeGreaterThan(8);
      save(`readback-${shader.id}-${thread}-p1-min.png`, a.png);

      await slider.fill(max!);
      await waitMoreFrames(page, 4);
      const b = await readback(page);
      save(`readback-${shader.id}-${thread}-p1-max.png`, b.png);
      expect(await meanDiff(a.png, b.png), 'moving Param 1 did not change the output').toBeGreaterThan(0.5);
      expectClean(problems);
    });

    test(`shader list + search return results [${thread}]`, async ({ page }, info) => {
      const problems = watch(page, info.title);
      await boot(page, thread);
      const search = page.getByRole('searchbox', { name: 'Filter controls and effects' });
      await expect(search).toBeVisible({ timeout: 30_000 });
      await search.fill('liquid');
      const results = page.getByRole('listbox', { name: /Matching effects/ });
      await expect(results).toBeVisible({ timeout: 15_000 });
      expect(await results.getByRole('option').count()).toBeGreaterThan(0);
      save(`page-search-${thread}.png`, await page.screenshot());
      expectClean(problems);
    });

    test(`video input path keeps rendering [${thread}]`, async ({ page }, info) => {
      const problems = watch(page, info.title);
      await boot(page, thread);
      // No media hosts in CI: switching to the video source must not crash or stall the loop.
      await page.evaluate(() => (window as any).__pixelocity__.setInputSource('video'));
      await waitMoreFrames(page, 3);
      await page.evaluate(() => (window as any).__pixelocity__.setInputSource('generative'));
      await waitMoreFrames(page, 3);
      expectClean(problems);
    });

    test(`Graph Lab lazy chunk loads [${thread}]`, async ({ page }, info) => {
      const problems = watch(page, info.title);
      await boot(page, thread, { graphlab: '1' });
      const chunk = page.waitForResponse((r) => /\/graph-lab\.[0-9a-f]+\.chunk\.js(\?|$)/.test(r.url()) && r.ok(), {
        timeout: 30_000,
      });
      await page.getByTestId('graph-lab-toggle').click();
      await chunk;
      await expect(page.getByText('Loading Graph Lab…')).toBeHidden({ timeout: 30_000 });
      save(`page-graphlab-${thread}.png`, await page.screenshot());
      expectClean(problems);
    });
  });
}

/** No adapter: the overlay renders with the probe JSON and nothing crashes. */
test('no-GPU flow shows the WebGPU required overlay', async ({}, info) => {
  const browser = await chromium.launch({
    // Default flags: no SwiftShader adapter.
    ...(process.env.SMOKE_CHROMIUM_PATH ? { executablePath: process.env.SMOKE_CHROMIUM_PATH } : {}),
  });
  try {
    const page = await browser.newPage();
    // Force the no-adapter path even on hosts with a real GPU.
    await page.addInitScript(() => {
      const gpu = (navigator as any).gpu;
      if (gpu) gpu.requestAdapter = async () => null;
    });
    const problems = watch(page, info.title);
    // Main thread: the stub above cannot reach a render worker's navigator.gpu.
    await page.goto(url('main'), { waitUntil: 'load' });
    const overlay = page.getByTestId('webgpu-probe-failure');
    await expect(overlay).toBeVisible({ timeout: 60_000 });
    await expect(overlay.locator('pre')).toContainText('"failedStage"');
    const probe = await page.evaluate(() => (window as any).webgpuProbe);
    expect(probe?.ok).toBe(false);
    save('page-no-gpu.png', await page.screenshot());
    // The probe failure itself may be logged; anything else (an exception, a 404) fails.
    expect(problems.filter((p) => p.kind !== 'console' && !p.allowed)).toEqual([]);
  } finally {
    await browser.close();
  }
});
