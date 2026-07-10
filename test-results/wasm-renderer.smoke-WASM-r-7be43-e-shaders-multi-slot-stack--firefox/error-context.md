# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: wasm-renderer.smoke.spec.ts >> WASM renderer loads multiple shaders (multi-slot stack)
- Location: tests/wasm-renderer.smoke.spec.ts:198:5

# Error details

```
Error: expect(received).toEqual(expected) // deep equality

- Expected  - 1
+ Received  + 3

- Array []
+ Array [
+   "[WebGPU] navigator.gpu is unavailable in this browser",
+ ]
```

# Test source

```ts
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
  173 |     { timeout: 30000 }
  174 |   );
  175 |
  176 |   // Load a single shader
  177 |   const shader = TEST_SHADERS[0];
  178 |   await page.evaluate(async (s: typeof shader) => {
  179 |     const api = (window as any).__pixelocity__;
  180 |     await api.loadShader(s.id, s.url);
  181 |     api.setSlotShader(0, s.id);
  182 |   }, shader);
  183 |
  184 |   // Let it render for 2 seconds
  185 |   await page.waitForTimeout(2000);
  186 |
  187 |   // Verify no critical errors
  188 |   const criticalErrors: string[] = (page as any).__criticalErrors || [];
  189 |   expect(criticalErrors).toEqual([]);
  190 |
  191 |   // Verify renderer is still functioning
  192 |   const fps = await page.evaluate(() => {
  193 |     return (window as any).__pixelocity__?.renderer?.getDiagnostics?.()?.fps ?? 0;
  194 |   });
  195 |   expect(fps).toBeGreaterThanOrEqual(0);
  196 | });
  197 |
  198 | test('WASM renderer loads multiple shaders (multi-slot stack)', async ({ page }) => {
  199 |   await page.goto(WASM_URL, { waitUntil: 'networkidle' });
  200 |
  201 |   // Wait for test API
  202 |   await page.waitForFunction(
  203 |     () => (window as any).__pixelocity__ != null,
  204 |     { timeout: 30000 }
  205 |   );
  206 |
  207 |   // Load multiple shaders into different slots
  208 |   const slotsToTest = TEST_SHADERS.slice(0, 3); // Test first 3 shaders
  209 |   for (const shader of slotsToTest) {
  210 |     await page.evaluate(async (s: typeof shader) => {
  211 |       const api = (window as any).__pixelocity__;
  212 |       await api.loadShader(s.id, s.url);
  213 |       api.setSlotShader(s.slot, s.id);
  214 |     }, shader);
  215 |
  216 |     // Small delay between shader loads
  217 |     await page.waitForTimeout(300);
  218 |   }
  219 |
  220 |   // Render with multiple shaders for 3 seconds
  221 |   await page.waitForTimeout(3000);
  222 |
  223 |   // Verify no critical errors
  224 |   const criticalErrors: string[] = (page as any).__criticalErrors || [];
> 225 |   expect(criticalErrors).toEqual([]);
      |                          ^ Error: expect(received).toEqual(expected) // deep equality
  226 |
  227 |   // Verify renderer is still functioning
  228 |   const fps = await page.evaluate(() => {
  229 |     return (window as any).__pixelocity__?.renderer?.getDiagnostics?.()?.fps ?? 0;
  230 |   });
  231 |   expect(fps).toBeGreaterThanOrEqual(0);
  232 | });
  233 |
  234 | test('WASM renderer handles shader loading with minimal console errors', async ({ page }) => {
  235 |   await page.goto(WASM_URL, { waitUntil: 'networkidle' });
  236 |
  237 |   // Wait for test API
  238 |   await page.waitForFunction(
  239 |     () => (window as any).__pixelocity__ != null,
  240 |     { timeout: 30000 }
  241 |   );
  242 |
  243 |   // Load first shader
  244 |   const shader = TEST_SHADERS[0];
  245 |   await page.evaluate(async (s: typeof shader) => {
  246 |     const api = (window as any).__pixelocity__;
  247 |     await api.loadShader(s.id, s.url);
  248 |     api.setSlotShader(0, s.id);
  249 |   }, shader);
  250 |
  251 |   // Render for 2 seconds
  252 |   await page.waitForTimeout(2000);
  253 |
  254 |   // Check console messages for any critical patterns
  255 |   const consoleErrors: string[] = (page as any).__consoleErrors || [];
  256 |   const criticalErrorPatterns = [
  257 |     'device-lost',
  258 |     'shader-compile-error',
  259 |     'Fallback shader also failed',
  260 |     'Uncaptured error',
  261 |   ];
  262 |
  263 |   for (const pattern of criticalErrorPatterns) {
  264 |     const foundCritical = consoleErrors.find((e) => e.includes(pattern));
  265 |     expect(foundCritical).toBeUndefined();
  266 |   }
  267 |
  268 |   // Verify diagnostics are still good
  269 |   const diagnostics = await page.evaluate(() => {
  270 |     console.log('DIAGNOSTICS:', JSON.stringify((window as any).__pixelocity__?.renderer?.getDiagnostics?.() || {}, null, 2));
  271 |     return (window as any).__pixelocity__?.renderer?.getDiagnostics?.();
  272 |   });
  273 |   if (diagnostics?.wasm) expect(diagnostics?.wasm?.errorCount ?? 0).toBeLessThan(5); // Allow 0-4 errors as warnings
  274 | });
  275 |
  276 | test('WASM renderer collects performance metrics', async ({ page }) => {
  277 |   await page.goto(WASM_URL, { waitUntil: 'networkidle' });
  278 |
  279 |   // Wait for test API
  280 |   await page.waitForFunction(
  281 |     () => (window as any).__pixelocity__ != null,
  282 |     { timeout: 30000 }
  283 |   );
  284 |
  285 |   // Load shader
  286 |   const shader = TEST_SHADERS[0];
  287 |   await page.evaluate(async (s: typeof shader) => {
  288 |     const api = (window as any).__pixelocity__;
  289 |     await api.loadShader(s.id, s.url);
  290 |     api.setSlotShader(0, s.id);
  291 |   }, shader);
  292 |
  293 |   // Render for 3 seconds to collect stable metrics
  294 |   await page.waitForTimeout(3000);
  295 |
  296 |   // Collect WASM diagnostics
  297 |   const wasmDiags = await page.evaluate(() => {
  298 |     const renderer = (window as any).__pixelocity__?.renderer;
  299 |     const diags = renderer?.getDiagnostics?.();
  300 |     return {
  301 |       wasmFps: diags?.wasm?.fps,
  302 |       wasmInitTime: diags?.wasm?.initTime,
  303 |       wasmHasModule: diags?.wasm?.hasModule,
  304 |     };
  305 |   });
  306 |
  307 |   // Log metrics for CI reporting
  308 |   console.log('=== WASM Renderer Metrics ===\n' + JSON.stringify(wasmDiags, null, 2));
  309 |   console.log(`FPS: ${wasmDiags.wasmFps}`);
  310 |   console.log(`Init Time: ${wasmDiags.wasmInitTime}`);
  311 |   console.log(`Has Module: ${wasmDiags.wasmHasModule}`);
  312 |   console.log('==============================');
  313 |
  314 |   if (wasmDiags.rendererType === 'wasm') {
  315 |     // Assertions for WASM
  316 |     expect(wasmDiags.wasmFps).toBeGreaterThanOrEqual(0);
  317 |     expect(wasmDiags.wasmHasModule).toBe(true);
  318 |   } else {
  319 |     console.log(`Skipping WASM performance metric assertions because renderer fell back to ${wasmDiags.rendererType}`);
  320 |   }
  321 | });
  322 |
```