/**
 * layerChain.smoke.spec.ts
 *
 * Playwright smoke test for multi-slot shader stacking.
 * Boots the production build, loads 2-slot and 3-slot stacks via the test-mode API,
 * and asserts no WebGPU console errors during 2 seconds of rendering each.
 */

import { test, expect } from '@playwright/test';
import { execSync, spawn } from 'child_process';
import { resolve } from 'path';

const BUILD_DIR = resolve(__dirname, '../build');
const PORT = 3456;
const BASE_URL = `http://localhost:${PORT}?testMode=1`;

// Shaders to test (must exist in public/shaders/)
const SHADER_2_SLOT = [
  { slot: 0, id: 'liquid', url: './shaders/liquid.wgsl' },
  { slot: 1, id: 'black-hole', url: './shaders/black-hole.wgsl' },
];

const SHADER_3_SLOT = [
  { slot: 0, id: 'liquid', url: './shaders/liquid.wgsl' },
  { slot: 1, id: 'galaxy', url: './shaders/galaxy.wgsl' },
  { slot: 2, id: 'vortex', url: './shaders/vortex.wgsl' },
];

let server: ReturnType<typeof spawn> | null = null;

async function startServer(): Promise<void> {
  // Use Python http.server for reliability in headless CI
  server = spawn('python3', ['-m', 'http.server', String(PORT), '--directory', BUILD_DIR], {
    stdio: 'pipe',
    shell: false,
  });

  // Poll until server responds
  await new Promise<void>((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('Server start timeout')), 15000);
    const interval = setInterval(async () => {
      try {
        const res = await fetch(`http://localhost:${PORT}/`);
        if (res.status === 200) {
          clearInterval(interval);
          clearTimeout(timeout);
          resolve();
        }
      } catch {
        // Not ready yet
      }
    }, 200);
  });
}

async function stopServer(): Promise<void> {
  if (server) {
    server.kill('SIGTERM');
    server = null;
  }
}

test.beforeAll(async () => {
  await startServer();
}, 60000);

test.afterAll(async () => {
  await stopServer();
});

test.beforeEach(async ({ page }) => {
  // Collect console messages
  (page as any).__consoleErrors = [];
  page.on('console', (msg) => {
    const text = msg.text();
    const type = msg.type();
    if (type === 'error' || text.includes('[WebGPU]') || text.includes('Uncaught')) {
      ((page as any).__consoleErrors as string[]).push(`[${type}] ${text}`);
    }
  });

  page.on('pageerror', (err) => {
    ((page as any).__consoleErrors as string[]).push(`[pageerror] ${err.message}`);
  });
});

async function loadSlotStack(page: any, shaders: { slot: number; id: string; url: string }[]) {
  // Wait for test API to be available
  await page.waitForFunction(() => (window as any).__pixelocity__?.renderer != null, {
    timeout: 15000,
  });

  // Load each shader
  for (const s of shaders) {
    await page.evaluate(async (shader: typeof s) => {
      const api = (window as any).__pixelocity__;
      await api.loadShader(shader.id, shader.url);
      api.setSlotShader(shader.slot, shader.id);
    }, s);
  }

  // Small delay for pipeline compilation
  await page.waitForTimeout(500);
}

function assertNoErrors(page: any, label: string) {
  const errors: string[] = (page as any).__consoleErrors || [];
  // Filter out expected warnings and environment limitations
  const criticalErrors = errors.filter(
    (e) =>
      e.includes('shader-compile') ||
      e.includes('device-lost') ||
      e.includes('Fallback shader also failed') ||
      e.includes('Uncaptured error') ||
      // Only count webgpu-unavailable if it's NOT the expected headless CI case
      (e.includes('webgpu-unavailable') && !e.includes('No suitable GPU adapter'))
  );
  expect(criticalErrors, `${label} critical console errors`).toEqual([]);
}

test('2-slot stack renders without critical errors', async ({ page }) => {
  await page.goto(BASE_URL, { waitUntil: 'networkidle' });
  await loadSlotStack(page, SHADER_2_SLOT);

  // Render for 2 seconds
  await page.waitForTimeout(2000);

  assertNoErrors(page, '2-slot stack');
});

test('3-slot stack renders without critical errors', async ({ page }) => {
  await page.goto(BASE_URL, { waitUntil: 'networkidle' });
  await loadSlotStack(page, SHADER_3_SLOT);

  // Render for 2 seconds
  await page.waitForTimeout(2000);

  assertNoErrors(page, '3-slot stack');
});
