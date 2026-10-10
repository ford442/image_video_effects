/**
 * #1395 D: compile-checking catalog shaders must report failures through the
 * compile service and never through `uncapturederror`.
 *
 * Runs ShaderScanner's compile path (`__pixelocity__.compileCheckShader`, which
 * fetches with include expansion and compiles on the renderer's device against
 * its pipeline layout) over the naga known-failure shaders, which are broken on
 * purpose, plus a deterministic sample of the catalog. `PX_FULL_CATALOG=1`
 * checks every shader (slow on SwiftShader: each pipeline is JIT-compiled).
 *
 * Needs a production build: `SKIP_WASM_BUILD=1 npm run build`.
 */
import { expect, test, type Page } from '@playwright/test';
import { readdirSync, readFileSync } from 'fs';
import { resolve } from 'path';
import {
  installGpuUncapturedErrorHook,
  readGpuUncapturedErrors,
  startStaticServer,
  stopStaticServer,
} from './helpers/rendererHarness';

const PORT = 3463;
const ROOT = resolve(__dirname, '..');
const FULL = process.env.PX_FULL_CATALOG === '1';
const SAMPLE_EVERY = 40;

type Mode = 'main' | 'worker';

function catalogIds(): string[] {
  const dir = resolve(ROOT, 'public/shader-lists');
  const ids = new Set<string>();
  for (const file of readdirSync(dir).filter((f) => f.endsWith('.json')).sort()) {
    const list = JSON.parse(readFileSync(resolve(dir, file), 'utf8')) as Array<{ id: string }>;
    for (const entry of list) ids.add(entry.id);
  }
  return [...ids].sort();
}

function knownBrokenIds(): string[] {
  const contract = JSON.parse(readFileSync(resolve(ROOT, 'src/contracts/wgsl_validation.json'), 'utf8'));
  return contract.knownFailures.ids as string[];
}

function targets(): string[] {
  if (process.env.PX_IDS) return process.env.PX_IDS.split(',');
  const all = catalogIds();
  const sample = FULL ? all : all.filter((_, i) => i % SAMPLE_EVERY === 0);
  return [...new Set([...knownBrokenIds(), ...sample])].filter((id) => !id.endsWith('-sg'));
}

test.beforeAll(async () => {
  await startStaticServer(PORT);
});

test.afterAll(async () => {
  await stopStaticServer();
});

async function boot(page: Page, mode: Mode): Promise<void> {
  await installGpuUncapturedErrorHook(page);
  await page.goto(`http://localhost:${PORT}/?renderer=${mode}&testMode=1`, { waitUntil: 'load' });
  await page.waitForFunction(
    () => {
      const w = window as any;
      return w.webgpuProbe != null && w.__pixelocity__?.renderer?.isGpuDeviceActive?.() === true;
    },
    null,
    { timeout: 90_000 },
  );
  const probe = await page.evaluate(() => (window as any).webgpuProbe);
  test.skip(!probe.ok, `no WebGPU adapter: ${probe.failedStage} ${probe.lastError}`);
}

/** Page-device errors come from the requestDevice hook; worker errors from its diagnostics ring. */
async function uncaptured(page: Page, mode: Mode): Promise<string[]> {
  if (mode === 'main') return (await readGpuUncapturedErrors(page)).map((e) => e.message);
  return page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics()?.webgpu?.gpuErrors ?? []);
}

for (const mode of ['main', 'worker'] as Mode[]) {
  test(`compile-checks catalog shaders without uncaptured GPU errors (${mode})`, async ({ page }) => {
    const ids = targets();
    test.setTimeout(Math.max(180_000, ids.length * 15_000));
    await boot(page, mode);
    const before = await uncaptured(page, mode);

    const results = await page.evaluate(async (list: string[]) => {
      const api = (window as any).__pixelocity__;
      const out: Array<{ id: string; ok: boolean; errors: string[] }> = [];
      for (const id of list) out.push({ id, ...(await api.compileCheckShader(id)) });
      return out;
    }, ids);

    // Wait out a few frames so any error the checks leaked has been delivered.
    await page.waitForTimeout(1500);
    const leaked = (await uncaptured(page, mode)).slice(before.length);
    expect(leaked, `uncapturederror during compile checks:\n${leaked.join('\n')}`).toEqual([]);

    expect(results.filter((r) => r.errors.includes('fetch failed'))).toEqual([]);
    const broken = new Set(knownBrokenIds());
    const failed = results.filter((r) => !r.ok).map((r) => r.id);
    // naga known failures are not all Tint failures, but at least some must be reported here.
    expect(failed.filter((id) => broken.has(id)).length).toBeGreaterThan(0);
    console.log(`[${mode}] ${results.length} checked, ${failed.length} failed:`);
    for (const r of results.filter((x) => !x.ok)) console.log(`  ${r.id}: ${r.errors[0]?.slice(0, 200)}`);
  });
}
