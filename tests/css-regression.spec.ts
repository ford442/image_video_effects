/**
 * CSS cascade regression screenshots (#1228).
 *
 * Guards the global stylesheet barrel (src/styles/index.css): any change to
 * import order, selector text, or specificity shows up as a pixel diff in one
 * of these chrome states. The canvas slot renders the WebGPU boot-probe failure
 * overlay on GPU-less hosts (#1107) — that is expected and still exercises CSS.
 *
 * Baselines are environment-specific (font hinting / AA). Capture and compare
 * on the same image:
 *   SKIP_WASM_BUILD=1 npm run build
 *   npx playwright test tests/css-regression.spec.ts --project=chromium --update-snapshots
 *
 * Threshold: the global maxDiffPixelRatio (0.25) is far too loose for cascade
 * checks, so every assertion here overrides it with CSS_MAX_DIFF_PIXELS.
 */

import { test, expect, type Page } from '@playwright/test';
import { startStaticServer, stopStaticServer } from './helpers/rendererHarness';

const PORT = 3461;
const BASE = `http://localhost:${PORT}/`;
const CSS_MAX_DIFF_PIXELS = 150;
const SNAPSHOT_OPTIONS = {
  maxDiffPixels: CSS_MAX_DIFF_PIXELS,
  maxDiffPixelRatio: undefined,
  animations: 'disabled' as const,
  caret: 'hide' as const,
  fullPage: false,
};

test.describe.configure({ mode: 'serial' });
test.use({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 });

test.beforeAll(async ({ browserName }) => {
  test.skip(browserName !== 'chromium', 'CSS baselines are pinned to chromium');
  await startStaticServer(PORT);
}, 60000);

test.afterAll(async () => {
  await stopStaticServer();
});

/** Keep captures deterministic: no remote CDN assets, no animated media. */
async function isolate(page: Page): Promise<void> {
  await page.route('**/*', route => {
    const url = route.request().url();
    return url.startsWith(BASE) ? route.continue() : route.abort();
  });
}

async function open(page: Page, search = ''): Promise<void> {
  await isolate(page);
  await page.goto(`${BASE}${search}`, { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle').catch(() => undefined);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(1500);
}

function volatileMasks(page: Page) {
  // Canvas stays unmasked: on GPU-less hosts it is blank and the probe overlay is CSS.
  return [page.locator('video'), page.locator('img')];
}

async function snap(page: Page, name: string): Promise<void> {
  await expect(page).toHaveScreenshot(name, { ...SNAPSHOT_OPTIONS, mask: volatileMasks(page) });
}

test('default view (controls panel open)', async ({ page }) => {
  await open(page);
  await expect(page.locator('.header')).toBeVisible();
  await snap(page, 'default-controls-open.png');
});

test('chrome hidden / fullscreen', async ({ page }) => {
  await open(page);
  await page.getByRole('button', { name: 'Hide Controls' }).click();
  await expect(page.locator('.show-controls-overlay')).toBeVisible();
  await page.waitForTimeout(500);
  await snap(page, 'chrome-hidden.png');
});

test('coordinate browser overlay open', async ({ page }) => {
  await open(page);
  const trigger = page.getByText(/Browse by Coordinate/).first();
  await trigger.scrollIntoViewIfNeeded();
  await trigger.click();
  await page.waitForTimeout(800);
  await snap(page, 'overlay-coordinate-browser.png');
});

test('storage browser over canvas', async ({ page }) => {
  await open(page);
  const trigger = page.getByText(/VPS Storage Browser/).first();
  await trigger.scrollIntoViewIfNeeded();
  await trigger.click();
  await page.waitForTimeout(800);
  await snap(page, 'storage-browser.png');
});

test('remote surface', async ({ page, context }) => {
  // RemoteApp shows "LOST CONNECTION" until a MainApp in the same browser context syncs.
  const main = await context.newPage();
  await open(main);
  await open(page, '?mode=remote');
  await expect(page.locator('.remote-app')).toBeVisible();
  await snap(page, 'remote-app.png');
  await main.close();
});
