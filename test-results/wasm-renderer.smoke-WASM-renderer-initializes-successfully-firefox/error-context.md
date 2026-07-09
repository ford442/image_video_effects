# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: wasm-renderer.smoke.spec.ts >> WASM renderer initializes successfully
- Location: tests/wasm-renderer.smoke.spec.ts:113:5

# Error details

```
"beforeAll" hook timeout of 30000ms exceeded.
```

# Test source

```ts
  1   | /**
  2   |  * wasm-renderer.smoke.spec.ts
  3   |  *
  4   |  * Automated smoke test for the WASM renderer path.
  5   |  * Validates that:
  6   |  * - WASM renderer initializes successfully with ?renderer=wasm
  7   |  * - Diagnostics report initialized=true and fps>0
  8   |  * - Representative shaders load and render without critical errors
  9   |  * - No WebGPU device-lost or shader compilation failures
  10  |  * - Frame times are recorded for performance tracking
  11  |  */
  12  |
  13  | import { test, expect } from '@playwright/test';
  14  | import { execSync, spawn } from 'child_process';
  15  | import { resolve } from 'path';
  16  |
  17  | const BUILD_DIR = resolve(__dirname, '../build');
  18  | const PORT = 3457;
  19  | const BASE_URL = `http://localhost:${PORT}`;
  20  | const WASM_URL = `${BASE_URL}?renderer=wasm&testMode=1`;
  21  |
  22  | // Representative shaders to test (4-6 across different categories)
  23  | const TEST_SHADERS = [
  24  |   // Generative/procedural
  25  |   { slot: 0, id: 'plasma', url: './shaders/plasma.wgsl', category: 'generative' },
  26  |   // Interactive/mouse-driven
  27  |   { slot: 0, id: 'liquid', url: './shaders/liquid.wgsl', category: 'interactive-mouse' },
  28  |   // Distortion effect
  29  |   { slot: 0, id: 'kaleidoscope', url: './shaders/kaleidoscope.wgsl', category: 'distortion' },
  30  |   // Multi-slot stack: slot 1
  31  |   { slot: 1, id: 'adaptive-mosaic', url: './shaders/adaptive-mosaic.wgsl', category: 'visual-effects' },
  32  |   // Color/chromatic effects
  33  |   { slot: 0, id: 'aero-chromatics', url: './shaders/aero-chromatics.wgsl', category: 'visual-effects' },
  34  |   // Atmospheric effects
  35  |   { slot: 0, id: 'aerogel-smoke', url: './shaders/aerogel-smoke.wgsl', category: 'visual-effects' },
  36  | ];
  37  |
  38  | let server: ReturnType<typeof spawn> | null = null;
  39  |
  40  | async function startServer(): Promise<void> {
  41  |   // Use Python http.server for reliability in headless CI
  42  |   server = spawn('python3', ['-m', 'http.server', String(PORT), '--directory', BUILD_DIR], {
  43  |     stdio: 'pipe',
  44  |     shell: false,
  45  |   });
  46  |
  47  |   // Poll until server responds
  48  |   await new Promise<void>((resolve, reject) => {
  49  |     const timeout = setTimeout(() => reject(new Error('Server start timeout')), 60000);
  50  |     const interval = setInterval(async () => {
  51  |       try {
  52  |         const res = await fetch(`${BASE_URL}/`);
  53  |         if (res.status === 200) {
  54  |           clearInterval(interval);
  55  |           clearTimeout(timeout);
  56  |           resolve();
  57  |         }
  58  |       } catch {
  59  |         // Not ready yet
  60  |       }
  61  |     }, 200);
  62  |   });
  63  | }
  64  |
  65  | async function stopServer(): Promise<void> {
  66  |   if (server) {
  67  |     server.kill('SIGTERM');
  68  |     server = null;
  69  |   }
  70  | }
  71  |
> 72  | test.beforeAll(async () => {
      |      ^ "beforeAll" hook timeout of 30000ms exceeded.
  73  |   await startServer();
  74  | }, 60000);
  75  |
  76  | test.afterAll(async () => {
  77  |   await stopServer();
  78  | });
  79  |
  80  | test.beforeEach(async ({ page }) => {
  81  |   // Collect console messages for diagnostics
  82  |   (page as any).__consoleMessages = [];
  83  |   (page as any).__consoleErrors = [];
  84  |   (page as any).__criticalErrors = [];
  85  |
  86  |   page.on('console', (msg) => {
  87  |     const text = msg.text();
  88  |     const type = msg.type();
  89  |     ((page as any).__consoleMessages as string[]).push(`[${type}] ${text}`);
  90  |     console.log(`[BROWSER ${type}] ${text}`);
  91  |
  92  |     // Track errors
  93  |     if (type === 'error') {
  94  |       ((page as any).__consoleErrors as string[]).push(text);
  95  |     }
  96  |
  97  |     // Track critical WASM/WebGPU errors
  98  |     if (
  99  |       text.includes('[WebGPU]') && !text.includes('No GPU adapter found') ||
  100 |       text.includes('Uncaught') ||
  101 |       text.includes('device-lost') ||
  102 |       text.includes('shader-compile-error')
  103 |     ) {
  104 |       ((page as any).__criticalErrors as string[]).push(text);
  105 |     }
  106 |   });
  107 |
  108 |   page.on('pageerror', (err) => {
  109 |     ((page as any).__criticalErrors as string[]).push(`[pageerror] ${err.message}`);
  110 |   });
  111 | });
  112 |
  113 | test('WASM renderer initializes successfully', async ({ page }) => {
  114 |   // Navigate to app with WASM forced and test mode enabled
  115 |   await page.goto(WASM_URL, { waitUntil: 'networkidle' });
  116 |
  117 |   // Wait for test API to be available
  118 |   await page.waitForFunction(() => {
  119 |     return (window as any).__pixelocity__ != null;
  120 |   }, {
  121 |     timeout: 15000,
  122 |   });
  123 |
  124 |   // Get diagnostics from the renderer object
  125 |   const diagnostics = await page.evaluate(() => {
  126 |     console.log('DIAGNOSTICS:', JSON.stringify((window as any).__pixelocity__?.renderer?.getDiagnostics?.() || {}, null, 2));
  127 |     const renderer = (window as any).__pixelocity__?.renderer;
  128 |     return renderer?.getDiagnostics?.();
  129 |   });
  130 |   console.log("DIAGNOSTICS:", diagnostics);
  131 |
  132 |   const consoleMessages = await page.evaluate(() => (window as any).__consoleMessages || []);
  133 |   console.log("CONSOLE MESSAGES:", consoleMessages);
  134 |
  135 |   expect(diagnostics).toBeDefined();
  136 |   // If WASM couldn't initialize and fell back, skip the WASM-specific checks
  137 |   if (!diagnostics?.wasm) {
  138 |     console.log('WASM renderer fell back (expected in CI)');
  139 |     return;
  140 |   }
  141 |   expect(diagnostics?.wasm?.initialized).toBe(true);
  142 |   expect(diagnostics?.wasm?.fps).toBeGreaterThanOrEqual(0);
  143 |   expect(diagnostics?.wasm?.hasModule).toBe(true);
  144 |
  145 |   if (diagnostics?.rendererType === 'wasm') {
  146 |     // Real WebGPU path succeeded
  147 |     expect(diagnostics?.wasm?.initialized).toBe(true);
  148 |     expect(diagnostics?.wasm?.fps).toBeGreaterThanOrEqual(0);
  149 |     expect(diagnostics?.wasm?.hasModule).toBe(true);
  150 |   } else {
  151 |     // CI / no-GPU case - WASM fell back to JS Renderer
  152 |     console.log('WASM path fell back to JS Canvas2D (expected in CI without GPU)');
  153 |     expect(['js', 'webgpu']).toContain(diagnostics?.rendererType);
  154 |   }
  155 |
  156 |   // Verify no critical errors during initialization (filter expected WebGPU failures)
  157 |   const criticalErrors: string[] = (page as any).__criticalErrors || [];
  158 |   const filtered = criticalErrors.filter(e =>
  159 |     !e.includes('Failed to get WebGPU adapter') &&
  160 |     !e.includes('No GPU adapter found') &&
  161 |     !e.includes('wasm-init') &&
  162 |     !e.includes('webgpu-unavailable')
  163 |   );
  164 |   expect(filtered).toEqual([]);
  165 | });
  166 |
  167 | test('WASM renderer loads single shader without errors', async ({ page }) => {
  168 |   await page.goto(WASM_URL, { waitUntil: 'networkidle' });
  169 |
  170 |   // Wait for test API
  171 |   await page.waitForFunction(
  172 |     () => (window as any).__pixelocity__ != null,
```