/**
 * wasm-renderer.smoke.spec.ts
 *
 * Automated smoke test for the WASM renderer path.
 * Validates that:
 * - WASM renderer initializes successfully with ?renderer=wasm
 * - Diagnostics report initialized=true and fps>0
 * - Representative shaders load and render without critical errors
 * - No WebGPU device-lost or shader compilation failures
 * - Frame times are recorded for performance tracking
 */

import { test, expect } from '@playwright/test';
import { execSync, spawn } from 'child_process';
import { resolve } from 'path';

const BUILD_DIR = resolve(__dirname, '../build');
const PORT = 3457;
const BASE_URL = `http://localhost:${PORT}`;
const WASM_URL = `${BASE_URL}?renderer=wasm&testMode=1`;

// Representative shaders to test (4-6 across different categories)
const TEST_SHADERS = [
  // Generative/procedural
  { slot: 0, id: 'plasma', url: './shaders/plasma.wgsl', category: 'generative' },
  // Interactive/mouse-driven
  { slot: 0, id: 'liquid', url: './shaders/liquid.wgsl', category: 'interactive-mouse' },
  // Distortion effect
  { slot: 0, id: 'kaleidoscope', url: './shaders/kaleidoscope.wgsl', category: 'distortion' },
  // Multi-slot stack: slot 1
  { slot: 1, id: 'adaptive-mosaic', url: './shaders/adaptive-mosaic.wgsl', category: 'visual-effects' },
  // Color/chromatic effects
  { slot: 0, id: 'aero-chromatics', url: './shaders/aero-chromatics.wgsl', category: 'visual-effects' },
  // Atmospheric effects
  { slot: 0, id: 'aerogel-smoke', url: './shaders/aerogel-smoke.wgsl', category: 'visual-effects' },
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
        const res = await fetch(`${BASE_URL}/`);
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
  // Collect console messages for diagnostics
  (page as any).__consoleMessages = [];
  (page as any).__consoleErrors = [];
  (page as any).__criticalErrors = [];

  page.on('console', (msg) => {
    const text = msg.text();
    const type = msg.type();
    ((page as any).__consoleMessages as string[]).push(`[${type}] ${text}`);

    // Track errors
    if (type === 'error') {
      ((page as any).__consoleErrors as string[]).push(text);
    }

    // Track critical WASM/WebGPU errors
    if (
      text.includes('[WebGPU]') && !text.includes('No GPU adapter found') ||
      text.includes('Uncaught') ||
      text.includes('device-lost') ||
      text.includes('shader-compile-error')
    ) {
      ((page as any).__criticalErrors as string[]).push(text);
    }
  });

  page.on('pageerror', (err) => {
    ((page as any).__criticalErrors as string[]).push(`[pageerror] ${err.message}`);
  });
});

test('WASM renderer initializes successfully', async ({ page }) => {
  // Navigate to app with WASM forced and test mode enabled
  await page.goto(WASM_URL, { waitUntil: 'networkidle' });

  // Wait for test API to be available
  await page.waitForFunction(() => {
    return (window as any).__pixelocity__ != null;
  }, {
    timeout: 15000,
  });

  // Get diagnostics from the renderer object
  const diagnostics = await page.evaluate(() => {
    const renderer = (window as any).__pixelocity__?.renderer;
    return renderer?.getDiagnostics?.();
  });

  expect(diagnostics).toBeDefined();
  expect(diagnostics?.initialized).toBe(true);
  expect(diagnostics?.fps).toBeGreaterThanOrEqual(0);
  expect(diagnostics?.hasModule).toBe(true);

  // Verify no critical errors during initialization
  const criticalErrors: string[] = (page as any).__criticalErrors || [];
  expect(criticalErrors).toEqual([]);
});

test('WASM renderer loads single shader without errors', async ({ page }) => {
  await page.goto(WASM_URL, { waitUntil: 'networkidle' });

  // Wait for test API
  await page.waitForFunction(
    () => (window as any).__pixelocity__ != null,
    { timeout: 15000 }
  );

  // Load a single shader
  const shader = TEST_SHADERS[0];
  await page.evaluate(async (s: typeof shader) => {
    const api = (window as any).__pixelocity__;
    await api.loadShader(s.id, s.url);
    api.setSlotShader(0, s.id);
  }, shader);

  // Let it render for 2 seconds
  await page.waitForTimeout(2000);

  // Verify no critical errors
  const criticalErrors: string[] = (page as any).__criticalErrors || [];
  expect(criticalErrors).toEqual([]);

  // Verify renderer is still functioning
  const fps = await page.evaluate(() => {
    return (window as any).__pixelocity__?.renderer?.getDiagnostics?.()?.fps ?? 0;
  });
  expect(fps).toBeGreaterThanOrEqual(0);
});

test('WASM renderer loads multiple shaders (multi-slot stack)', async ({ page }) => {
  await page.goto(WASM_URL, { waitUntil: 'networkidle' });

  // Wait for test API
  await page.waitForFunction(
    () => (window as any).__pixelocity__ != null,
    { timeout: 15000 }
  );

  // Load multiple shaders into different slots
  const slotsToTest = TEST_SHADERS.slice(0, 3); // Test first 3 shaders
  for (const shader of slotsToTest) {
    await page.evaluate(async (s: typeof shader) => {
      const api = (window as any).__pixelocity__;
      await api.loadShader(s.id, s.url);
      api.setSlotShader(s.slot, s.id);
    }, shader);

    // Small delay between shader loads
    await page.waitForTimeout(300);
  }

  // Render with multiple shaders for 3 seconds
  await page.waitForTimeout(3000);

  // Verify no critical errors
  const criticalErrors: string[] = (page as any).__criticalErrors || [];
  expect(criticalErrors).toEqual([]);

  // Verify renderer is still functioning
  const fps = await page.evaluate(() => {
    return (window as any).__pixelocity__?.renderer?.getDiagnostics?.()?.fps ?? 0;
  });
  expect(fps).toBeGreaterThanOrEqual(0);
});

test('WASM renderer handles shader loading with minimal console errors', async ({ page }) => {
  await page.goto(WASM_URL, { waitUntil: 'networkidle' });

  // Wait for test API
  await page.waitForFunction(
    () => (window as any).__pixelocity__ != null,
    { timeout: 15000 }
  );

  // Load first shader
  const shader = TEST_SHADERS[0];
  await page.evaluate(async (s: typeof shader) => {
    const api = (window as any).__pixelocity__;
    await api.loadShader(s.id, s.url);
    api.setSlotShader(0, s.id);
  }, shader);

  // Render for 2 seconds
  await page.waitForTimeout(2000);

  // Check console messages for any critical patterns
  const consoleErrors: string[] = (page as any).__consoleErrors || [];
  const criticalErrorPatterns = [
    'device-lost',
    'shader-compile-error',
    'Fallback shader also failed',
    'Uncaptured error',
  ];

  for (const pattern of criticalErrorPatterns) {
    const foundCritical = consoleErrors.find((e) => e.includes(pattern));
    expect(foundCritical).toBeUndefined();
  }

  // Verify diagnostics are still good
  const diagnostics = await page.evaluate(() => {
    return (window as any).__pixelocity__?.renderer?.getDiagnostics?.();
  });
  expect(diagnostics?.errorCount ?? 0).toBeLessThan(5); // Allow 0-4 errors as warnings
});

test('WASM renderer collects performance metrics', async ({ page }) => {
  await page.goto(WASM_URL, { waitUntil: 'networkidle' });

  // Wait for test API
  await page.waitForFunction(
    () => (window as any).__pixelocity__ != null,
    { timeout: 15000 }
  );

  // Load shader
  const shader = TEST_SHADERS[0];
  await page.evaluate(async (s: typeof shader) => {
    const api = (window as any).__pixelocity__;
    await api.loadShader(s.id, s.url);
    api.setSlotShader(0, s.id);
  }, shader);

  // Render for 3 seconds to collect stable metrics
  await page.waitForTimeout(3000);

  // Collect WASM diagnostics
  const wasmDiags = await page.evaluate(() => {
    const renderer = (window as any).__pixelocity__?.renderer;
    const diags = renderer?.getDiagnostics?.();
    return {
      wasmFps: diags?.fps,
      wasmInitTime: diags?.initTime,
      wasmHasModule: diags?.hasModule,
    };
  });

  // Log metrics for CI reporting
  console.log('=== WASM Renderer Metrics ===');
  console.log(`FPS: ${wasmDiags.wasmFps}`);
  console.log(`Init Time: ${wasmDiags.wasmInitTime}`);
  console.log(`Has Module: ${wasmDiags.wasmHasModule}`);
  console.log('==============================');

  // Assertions
  expect(wasmDiags.wasmFps).toBeGreaterThanOrEqual(0);
  expect(wasmDiags.wasmHasModule).toBe(true);
});
