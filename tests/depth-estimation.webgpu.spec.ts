/**
 * depth-estimation.webgpu.spec.ts
 *
 * Playwright smoke for production depth path with device=webgpu.
 * Requires WebGPU-capable Chromium. Skips when unavailable.
 *
 * Production model: Xenova/dpt-hybrid-midas (same as src/App.tsx)
 */

import { test, expect } from '@playwright/test';
import { execSync, spawn } from 'child_process';
import { resolve } from 'path';
import fs from 'fs';

const ROOT = resolve(__dirname, '..');
const SMOKE_DIR = resolve(__dirname, 'smoke');
const BUNDLE_DIR = resolve(SMOKE_DIR, '.bundle');
const BUNDLE_FILE = resolve(BUNDLE_DIR, 'depth-webgpu.mjs');
const PORT = 3460;
const BASE = `http://localhost:${PORT}`;

let server: ReturnType<typeof spawn> | null = null;

function hasGpuTests(): boolean {
  return process.env.DEPTH_GPU_TESTS === '1' || process.env.CI !== 'true';
}

async function startServer(): Promise<void> {
  server = spawn(
    'python3',
    ['-m', 'http.server', String(PORT), '--directory', ROOT],
    { stdio: 'pipe' }
  );
  await new Promise<void>((resolvePromise, reject) => {
    const timeout = setTimeout(() => reject(new Error('Server timeout')), 30000);
    const interval = setInterval(async () => {
      try {
        const res = await fetch(`${BASE}/`);
        if (res.ok) {
          clearInterval(interval);
          clearTimeout(timeout);
          resolvePromise();
        }
      } catch {
        // not ready
      }
    }, 200);
  });
}

test.beforeAll(async () => {
  fs.mkdirSync(BUNDLE_DIR, { recursive: true });
  execSync(
    `npx esbuild "${resolve(SMOKE_DIR, 'depth-webgpu-entry.mjs')}" --bundle --format=esm --platform=browser --outfile="${BUNDLE_FILE}"`,
    { cwd: ROOT, stdio: 'inherit' }
  );
  await startServer();
}, 120000);

test.afterAll(async () => {
  if (server) {
    server.kill('SIGTERM');
    server = null;
  }
});

test('production depth model runs on WebGPU', async ({ page }) => {
  test.skip(!hasGpuTests(), 'Set DEPTH_GPU_TESTS=1 with WebGPU-capable Chromium');

  const webgpu = await page.evaluate(async () => {
    try {
      if (!navigator.gpu) return { ok: false, reason: 'no navigator.gpu' };
      const adapter = await navigator.gpu.requestAdapter();
      if (!adapter) return { ok: false, reason: 'no adapter' };
      return { ok: true };
    } catch (e: any) {
      return { ok: false, reason: e?.message || String(e) };
    }
  });

  if (!webgpu.ok) {
    test.skip(true, `WebGPU unavailable: ${webgpu.reason}`);
  }

  await page.goto(`${BASE}/tests/smoke/depth-webgpu-harness.html`, { waitUntil: 'load' });

  const result = await page.evaluate(async ({ bundleUrl, imageUrl }) => {
    const mod = await import(/* webpackIgnore: true */ bundleUrl);
    return mod.runDepthWebgpuSmoke(imageUrl);
  }, {
    bundleUrl: `${BASE}/tests/smoke/.bundle/depth-webgpu.mjs`,
    imageUrl: `${BASE}/tests/smoke/fixtures/sample-rgb.png`,
  });

  expect(result.dims.length).toBeGreaterThanOrEqual(2);
  expect(result.dataLength).toBeGreaterThan(0);
});
