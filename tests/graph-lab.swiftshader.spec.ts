/**
 * Graph Lab (#1399) e2e on a real — software — WebGPU device.
 *
 * A draft graph that was never saved to shader_definitions/ is registered as a
 * runtime graph and run through the TS renderer, in the page and in the render
 * worker. The assertions are on what the shipped planner reports
 * (`getDiagnostics().webgpu.graph`) and on pixels read back through the renderer
 * (compositor screenshots of a WebGPU canvas are blank on SwiftShader).
 *
 * Reference graph: the 2-node `predator-prey-ecology` step → render (a real
 * same-frame dataA → dataC handoff plus cross-frame feedback). Its entry ids are
 * read from the shipped definition, not hard-coded.
 *
 * Needs a production build: `SKIP_WASM_BUILD=1 npm run build && npm run test:engine2`.
 */
import { expect, test, type Page } from '@playwright/test';
import { readFileSync } from 'fs';
import { resolve } from 'path';
import sharp from 'sharp';
import {
  installGpuUncapturedErrorHook,
  readGpuUncapturedErrors,
  startStaticServer,
  stopStaticServer,
} from './helpers/rendererHarness';

const PORT = 3465;
const ROOT_ID = 'graphlab-draft';

type Mode = 'main' | 'worker';
const MODES: Mode[] = ['main', 'worker'];

interface GraphNode {
  id: string;
  entry: string;
  reads: string[];
  writes: string[];
  repeat?: number;
}
interface Graph {
  maxPassesPerFrame: number;
  nodes: GraphNode[];
}
interface GraphReport {
  shaderId: string | null;
  requested: number;
  executed: number;
  truncated: number;
  cap: number;
  errors: string[];
}

const DEFINITION = JSON.parse(
  readFileSync(resolve(__dirname, '../shader_definitions/simulation/predator-prey-ecology.json'), 'utf-8'),
) as { id: string; url: string; multipass: { graph: Graph } };
const REFERENCE: Graph = DEFINITION.multipass.graph;
const ROOT_URL = `./${DEFINITION.url}`;

/** The reference graph with its simulation node repeated: 4 + 1 = 5 requested passes. */
const ITERATED: Graph = {
  ...REFERENCE,
  maxPassesPerFrame: 16,
  nodes: REFERENCE.nodes.map((n, i) => (i === 0 ? { ...n, repeat: 4 } : { ...n })),
};

/** The display node reads dataB, which nothing produces: the planner must refuse it. */
const BROKEN: Graph = {
  maxPassesPerFrame: 8,
  nodes: REFERENCE.nodes.map((n, i) => (i === REFERENCE.nodes.length - 1 ? { ...n, reads: ['dataB'] } : { ...n })),
};

test.beforeAll(async () => {
  await startStaticServer(PORT, { isolated: false });
});
test.afterAll(async () => {
  await stopStaticServer();
});

async function boot(page: Page, mode: Mode, extra = ''): Promise<void> {
  await installGpuUncapturedErrorHook(page);
  const renderer = mode === 'worker' ? 'worker' : 'main';
  await page.goto(`http://localhost:${PORT}/?renderer=${renderer}&testMode=1${extra}`, { waitUntil: 'load' });
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
}

async function setup(page: Page, mode: Mode, quality: 'ultra' | 'battery', extra = ''): Promise<void> {
  await boot(page, mode, extra);
  await page.evaluate((q) => {
    const api = (window as any).__pixelocity__;
    api.overrideSlotCap(1);
    api.setInputSource('generative');
    api.setRenderQuality(q);
  }, quality);
}

/** Register `graph` as the runtime draft, compile its entries and put it in slot 0. */
async function runDraft(page: Page, graph: Graph): Promise<boolean> {
  return page.evaluate(
    async ({ graph, rootId, rootUrl }) => {
      const api = (window as any).__pixelocity__;
      if (!api.renderer.setRuntimeGraph(rootId, graph)) return false;
      const ok = await api.loadShader(rootId, rootUrl);
      api.setSlotShader(0, rootId);
      api.setTestRenderState({ time: 2.5, mouseX: 0.5, mouseY: 0.5 });
      return ok;
    },
    { graph, rootId: ROOT_ID, rootUrl: ROOT_URL },
  );
}

/** Swap the running draft for a new graph object (plans are memoised per object). */
async function swapDraft(page: Page, graph: Graph): Promise<void> {
  await page.evaluate(
    ({ graph, rootId }) => (window as any).__pixelocity__.renderer.setRuntimeGraph(rootId, graph),
    { graph, rootId: ROOT_ID },
  );
}

async function waitForRenderedFrames(page: Page, n: number): Promise<void> {
  await page.waitForFunction(
    (min) => ((window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.frameStats?.framesRendered ?? 0) >= min,
    n,
    { timeout: 90_000, polling: 250 },
  );
}

/** The planner's report for the draft, once it satisfies `accept` (evaluated in the page). */
async function reportWhere(page: Page, accept: string): Promise<GraphReport> {
  const handle = await page.waitForFunction(
    ({ id, accept }) => {
      const report = (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.graph;
      // eslint-disable-next-line no-new-func
      return report && report.shaderId === id && new Function('r', `return (${accept});`)(report) ? report : null;
    },
    { id: ROOT_ID, accept },
    { timeout: 90_000, polling: 250 },
  );
  return (await handle.jsonValue()) as GraphReport;
}

async function gpuErrors(page: Page, mode: Mode): Promise<string[]> {
  if (mode === 'main') return (await readGpuUncapturedErrors(page)).map((e) => e.message);
  return page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.gpuErrors ?? []);
}

/** Brightest of a few captures; one non-blank capture proves the graph drew something. */
async function thumbnailStats(page: Page, size = 64, attempts = 5) {
  let best = { max: 0, stdev: 0 };
  for (let i = 0; i < attempts; i++) {
    const png: string | null = await page.evaluate((s) => (window as any).__pixelocity__.captureThumbnailPng(s), size);
    expect(png, 'captureThumbnailPng returned null').toBeTruthy();
    const b64 = (png as string).includes(',') ? (png as string).split(',')[1] : (png as string);
    const stats = await sharp(Buffer.from(b64, 'base64')).stats();
    const max = Math.max(...stats.channels.slice(0, 3).map((c) => c.max));
    const stdev = Math.max(...stats.channels.slice(0, 3).map((c) => c.stdev));
    if (max > best.max) best = { max, stdev };
    if (best.max > 32 && best.stdev > 2) break;
    await page.waitForTimeout(500);
  }
  return best;
}

/** Keys (`slot:nodeId`) of the draft's compute passes, once GPU timestamps have resolved. */
async function passKeys(page: Page, accept = 'keys.length > 0'): Promise<string[]> {
  const handle = await page.waitForFunction(
    ({ id, accept }) => {
      const keys = (window as any).__pixelocity__
        .getPassTimings()
        .filter((t: any) => t.shaderId === id && t.kind === 'compute')
        .map((t: any) => t.key as string);
      // eslint-disable-next-line no-new-func
      return new Function('keys', `return (${accept});`)(keys) ? keys : null;
    },
    { id: ROOT_ID, accept },
    { timeout: 90_000, polling: 250 },
  );
  return (await handle.jsonValue()) as string[];
}

test.describe('Graph Lab: a draft graph through the TS renderer', () => {
  test('the reference is the shipped 2-node feedback graph', () => {
    expect(REFERENCE.nodes.map((n) => n.id)).toEqual(['step', 'render']);
    expect(REFERENCE.nodes[1].writes).toContain('color');
  });

  for (const mode of MODES) {
    test(`runs untruncated with a live planner report and non-blank pixels [${mode}]`, async ({ page }) => {
      await setup(page, mode, 'ultra');
      expect(await runDraft(page, REFERENCE), 'draft entries failed to compile').toBe(true);
      await waitForRenderedFrames(page, 4);

      const report = await reportWhere(page, 'r.executed > 0');
      expect(report).toMatchObject({ shaderId: ROOT_ID, requested: 2, executed: 2, truncated: 0, errors: [] });
      expect(await page.evaluate(() => (window as any).__pixelocity__.getSlotState(0)?.shaderId)).toBe(ROOT_ID);
      expect(await passKeys(page, "keys.includes('0:step') && keys.includes('0:render')")).toEqual(
        expect.arrayContaining(['0:step', '0:render']),
      );

      const px = await thumbnailStats(page);
      expect(px.max, `output looks blank: ${JSON.stringify(px)}`).toBeGreaterThan(8);
      expect(await gpuErrors(page, mode)).toEqual([]);
    });

    test(`honours the pass budgets and keeps the color writer when it truncates [${mode}]`, async ({ page }) => {
      await setup(page, mode, 'battery');
      expect(await runDraft(page, ITERATED)).toBe(true);
      await waitForRenderedFrames(page, 4);

      // battery allows 4 passes per graph; the draft asks for 5 (step ×4 + render).
      const capped = await reportWhere(page, 'r.executed > 0');
      expect(capped).toMatchObject({ shaderId: ROOT_ID, requested: 5, executed: 4, truncated: 1, cap: 4, errors: [] });
      expect(await passKeys(page, "keys.includes('0:render')")).toEqual(expect.arrayContaining(['0:step', '0:render']));

      // Squeeze the whole frame to one pass: only the display pass may survive.
      await page.evaluate(() => (window as any).__pixelocity__.renderer.shaderRenderer().setFramePassBudget(1));
      const squeezed = await reportWhere(page, 'r.cap === 1');
      expect(squeezed).toMatchObject({ requested: 5, executed: 1, truncated: 4, cap: 1, errors: [] });
      expect(await passKeys(page, "keys.length === 1 && keys[0] === '0:render'")).toEqual(['0:render']);
      expect(await gpuErrors(page, mode)).toEqual([]);
    });

    test(`refuses an invalid draft with the shared validator’s message, then recovers [${mode}]`, async ({ page }) => {
      await setup(page, mode, 'ultra');
      expect(await runDraft(page, REFERENCE)).toBe(true);
      await waitForRenderedFrames(page, 4);
      await reportWhere(page, 'r.executed === 2');

      await swapDraft(page, BROKEN);
      const refused = await reportWhere(page, 'r.errors.length > 0');
      expect(refused.executed).toBe(0);
      expect(refused.errors.join(' ')).toContain('reads "dataB" before any producer in this frame');

      await swapDraft(page, JSON.parse(JSON.stringify(REFERENCE)) as Graph);
      const recovered = await reportWhere(page, 'r.errors.length === 0 && r.executed === 2');
      expect(recovered).toMatchObject({ requested: 2, executed: 2, truncated: 0 });
      expect(await gpuErrors(page, mode)).toEqual([]);
    });

    test(`the workspace runs a template, shows the live report and exports [${mode}]`, async ({ page }) => {
      await setup(page, mode, 'ultra', '&graphlab=1');
      await page.getByTestId('graph-lab-toggle').click();
      await expect(page.getByTestId('graph-lab')).toBeVisible();

      await page.getByTestId('graph-lab-template').selectOption(DEFINITION.id);
      await expect(page.getByTestId('graph-lab-diagnostics-clear')).toBeVisible();
      await expect(page.getByTestId('graph-lab-run')).toBeEnabled();

      await page.getByTestId('graph-lab-run').click();
      await expect(page.getByTestId('graph-lab-live-report')).toContainText('2 / 2 passes', { timeout: 90_000 });
      expect(await page.evaluate(() => (window as any).__pixelocity__.getSlotState(0)?.shaderId)).toBe(ROOT_ID);
      const report = await reportWhere(page, 'r.executed === 2');
      expect(report).toMatchObject({ requested: 2, truncated: 0, errors: [] });

      // The same draft exports as a shader definition the registry build already understands.
      await expect(page.getByTestId('export-download')).toBeEnabled();
      await page.getByText('Preview definition').click();
      const exported = JSON.parse((await page.getByTestId('export-json').textContent()) ?? '{}');
      expect(exported).toMatchObject({ id: `${DEFINITION.id}-lab`, url: DEFINITION.url });
      expect(exported.multipass.graph).toEqual(REFERENCE);

      await page.getByTestId('graph-lab-stop').click();
      await expect(page.getByTestId('graph-lab-run')).toBeVisible();
      expect(await page.evaluate(() => (window as any).__pixelocity__.getSlotState(0)?.shaderId)).not.toBe(ROOT_ID);
      expect(await gpuErrors(page, mode)).toEqual([]);
    });
  }
});
