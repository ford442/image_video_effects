/// <reference types="@webgpu/types" />
/**
 * gpu-adapter-check.ts — what WebGPU adapter does this machine give headless Chromium? (#1512 Part C)
 *
 * The first step of every GPU_REQUIRED suite on the self-hosted runner (docs/GPU_RUNNER.md).
 * Launches Playwright's Chromium with the same flags as the `gpu` Playwright project, asks for a
 * core and a compatibility adapter, and records vendor / architecture, the tier 2 features
 * (#1512) and the limits that pick a limits tier. With --strict a missing or software adapter
 * (SwiftShader, llvmpipe, lavapipe, WARP) exits 1, so a misprovisioned runner fails before any
 * suite produces numbers that are not hardware evidence.
 *
 *   npx tsx --tsconfig scripts/tsconfig.scripts.json scripts/gpu-adapter-check.ts [--strict] [--software]
 *
 * --software uses the SwiftShader flags instead (a GPU-less dev box: the check then reports the
 * software adapter and --strict fails, which is the point). Writes test-results/gpu-adapter.json
 * and, under GitHub Actions, a table to the job summary.
 */
import { appendFileSync, mkdirSync, writeFileSync } from 'fs';
import { createServer } from 'http';
import type { AddressInfo } from 'net';
import { chromium } from '@playwright/test';
import { buildGpuLaunchArgs } from '../src/utils/gpuLaunchArgs';
import { inferAdapterGpuType } from '../src/config/adapterIdentity';
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { SWIFTSHADER_WEBGPU_ARGS } = require('./lib/swiftshaderArgs') as { SWIFTSHADER_WEBGPU_ARGS: string[] };

const TIER2_FEATURES = ['shader-f16', 'bgra8unorm-storage', 'float32-blendable', 'dual-source-blending', 'float32-filterable', 'subgroups', 'timestamp-query'];
const LIMITS = ['maxComputeInvocationsPerWorkgroup', 'maxTextureDimension2D', 'maxStorageBufferBindingSize', 'maxBufferSize'];

interface AdapterReport {
  featureLevel: 'core' | 'compatibility';
  found: boolean;
  vendor: string;
  architecture: string;
  device: string;
  description: string;
  isFallbackAdapter: boolean;
  gpuType: string;
  features: string[];
  limits: Record<string, number>;
  preferredCanvasFormat: string;
}

async function main(): Promise<void> {
  const strict = process.argv.includes('--strict');
  const software = process.argv.includes('--software');
  const args = software ? SWIFTSHADER_WEBGPU_ARGS : buildGpuLaunchArgs(process.platform, true);

  // navigator.gpu needs a secure context: localhost is one, about:blank and data: are not.
  const server = createServer((_req, res) => {
    res.writeHead(200, { 'content-type': 'text/html' });
    res.end('<!doctype html><title>adapter</title>');
  });
  await new Promise<void>((done) => server.listen(0, '127.0.0.1', done));
  const { port } = server.address() as AddressInfo;

  const browser = await chromium.launch({ channel: software ? undefined : 'chromium', args });
  let reports: Array<Omit<AdapterReport, 'gpuType'>> = [];
  try {
    const page = await browser.newPage();
    await page.goto(`http://localhost:${port}/`);
    reports = await page.evaluate(async ({ features, limits }) => {
      const out = [];
      for (const featureLevel of ['core', 'compatibility'] as const) {
        const gpu = (navigator as Navigator & { gpu?: GPU }).gpu;
        const adapter = gpu
          ? await gpu.requestAdapter(featureLevel === 'core' ? {} : ({ featureLevel } as GPURequestAdapterOptions))
          : null;
        const info = (adapter?.info ?? {}) as GPUAdapterInfo & { isFallbackAdapter?: boolean };
        const lim = (adapter?.limits ?? {}) as unknown as Record<string, number>;
        out.push({
          featureLevel,
          found: !!adapter,
          vendor: info.vendor ?? '',
          architecture: info.architecture ?? '',
          device: info.device ?? '',
          description: info.description ?? '',
          isFallbackAdapter: Boolean(info.isFallbackAdapter),
          features: features.filter((f) => adapter?.features.has(f) ?? false),
          limits: Object.fromEntries(limits.map((l) => [l, Number(lim[l] ?? 0)])),
          preferredCanvasFormat: gpu?.getPreferredCanvasFormat?.() ?? '',
        });
      }
      return out;
    }, { features: TIER2_FEATURES, limits: LIMITS });
  } finally {
    await browser.close();
    server.close();
  }

  const full: AdapterReport[] = reports.map((r) => ({ ...r, gpuType: r.found ? inferAdapterGpuType(r) : 'none' }));
  mkdirSync('test-results', { recursive: true });
  writeFileSync('test-results/gpu-adapter.json', `${JSON.stringify({ args, adapters: full }, null, 2)}\n`);

  const rows = full.map((r) =>
    `| ${r.featureLevel} | ${r.found ? [r.vendor, r.architecture, r.description].filter(Boolean).join(' · ') : '—'} | ${r.gpuType} | ${r.features.join(', ') || '—'} | ${LIMITS.map((l) => r.limits[l] ?? 0).join(' / ')} | ${r.preferredCanvasFormat} |`,
  );
  const table = [
    '| level | adapter | type | features | invocations / tex2D / storage / buffer | canvas |',
    '|---|---|---|---|---|---|',
    ...rows,
  ].join('\n');
  console.log(table);
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, `## WebGPU adapter\n\n${table}\n\n`);

  const core = full[0];
  const problem = !core?.found
    ? 'no WebGPU adapter'
    : core.gpuType === 'cpu'
      ? `software adapter (${core.vendor} ${core.architecture})`
      : null;
  if (problem) {
    const msg = `${problem}: GPU_REQUIRED numbers from this runner are not hardware evidence`;
    if (strict) {
      console.error(`::error::${msg}`);
      process.exit(1);
    }
    console.warn(`::warning::${msg}`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
