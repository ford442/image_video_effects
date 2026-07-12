# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: wasm-renderer.smoke.spec.ts >> WASM renderer initializes (testMode API + diagnostics)
- Location: tests/wasm-renderer.smoke.spec.ts:36:5

# Error details

```
Error: Missing /root/image_video_effects/build/index.html. Run "npm run build" (or SKIP_WASM_BUILD=1 npm run build) before Playwright WASM tests.
```

# Test source

```ts
  1   | /**
  2   |  * Shared Playwright harness for WASM / WebGPU renderer tests.
  3   |  */
  4   | import { spawn, type ChildProcessWithoutNullStreams } from 'child_process';
  5   | import { existsSync, mkdirSync, writeFileSync } from 'fs';
  6   | import { resolve } from 'path';
  7   | import { expect, type Page } from '@playwright/test';
  8   | import type { ParityShaderCase } from '../fixtures/parityMatrix';
  9   | 
  10  | export const BUILD_DIR = resolve(__dirname, '../../build');
  11  | export const DEFAULT_PORT = 3458;
  12  | export const MIN_WASM_FPS = 5;
  13  | export const PROMOTION_SPEEDUP_RATIO = 1.25;
  14  | export const PROMOTION_MIN_SHADERS = 3;
  15  | 
  16  | export type RendererBackend = 'wasm' | 'webgpu';
  17  | 
  18  | export interface ImageStats {
  19  |   width: number;
  20  |   height: number;
  21  |   meanLuminance: number;
  22  |   activePixelRatio: number;
  23  | }
  24  | 
  25  | export interface BenchResult {
  26  |   shaderId: string;
  27  |   backend: string;
  28  |   avgFps: number;
  29  |   avgTotalMs: number;
  30  |   gpuTimingsAvailable: boolean;
  31  |   timingSource?: string;
  32  |   p95TotalMs: number;
  33  | }
  34  | 
  35  | export interface BenchComparison {
  36  |   shaderId: string;
  37  |   wasmFps: number;
  38  |   webgpuFps: number;
  39  |   wasmAvgTotalMs: number;
  40  |   webgpuAvgTotalMs: number;
  41  |   /** WASM fps / WebGPU fps (or inverse frame-time ratio). ≥1.25 meets promotion gate. */
  42  |   speedupRatio: number;
  43  |   meetsPromotionGate: boolean;
  44  | }
  45  | 
  46  | export interface WasmBenchmarkReport {
  47  |   generatedAt: string;
  48  |   strictGpuMode: boolean;
  49  |   gpuBackendObserved: boolean;
  50  |   results: BenchResult[];
  51  |   comparisons: BenchComparison[];
  52  |   promotionGateMet: boolean;
  53  |   promotionMinShaders: number;
  54  |   promotionSpeedupRatio: number;
  55  | }
  56  | 
  57  | let server: ChildProcessWithoutNullStreams | null = null;
  58  | let serverPort = DEFAULT_PORT;
  59  | 
  60  | /** Opt-in strict mode: fail when WebGPU/WASM backends are unavailable (local GPU runs). */
  61  | export function isStrictGpuMode(): boolean {
  62  |   return process.env.WASM_GPU_TESTS === '1';
  63  | }
  64  | 
  65  | /** @deprecated Use isStrictGpuMode() — kept for existing specs. */
  66  | export function hasGpuForTests(): boolean {
  67  |   return isStrictGpuMode();
  68  | }
  69  | 
  70  | export function buildAppUrl(
  71  |   backend: RendererBackend,
  72  |   extraParams: Record<string, string> = {},
  73  |   port = serverPort
  74  | ): string {
  75  |   const params = new URLSearchParams({
  76  |     renderer: backend,
  77  |     testMode: '1',
  78  |     ...extraParams,
  79  |   });
  80  |   return `http://localhost:${port}/?${params.toString()}`;
  81  | }
  82  | 
  83  | export async function startStaticServer(port = DEFAULT_PORT): Promise<void> {
  84  |   const indexHtml = resolve(BUILD_DIR, 'index.html');
  85  |   if (!existsSync(indexHtml)) {
> 86  |     throw new Error(
      |           ^ Error: Missing /root/image_video_effects/build/index.html. Run "npm run build" (or SKIP_WASM_BUILD=1 npm run build) before Playwright WASM tests.
  87  |       `Missing ${indexHtml}. Run "npm run build" (or SKIP_WASM_BUILD=1 npm run build) before Playwright WASM tests.`
  88  |     );
  89  |   }
  90  | 
  91  |   serverPort = port;
  92  |   server = spawn('python3', ['-m', 'http.server', String(port), '--directory', BUILD_DIR], {
  93  |     stdio: 'pipe',
  94  |   });
  95  | 
  96  |   await new Promise<void>((resolvePromise, reject) => {
  97  |     const timeout = setTimeout(() => reject(new Error('Static server start timeout')), 60000);
  98  |     const interval = setInterval(async () => {
  99  |       try {
  100 |         const res = await fetch(`http://localhost:${port}/`);
  101 |         if (res.ok) {
  102 |           clearInterval(interval);
  103 |           clearTimeout(timeout);
  104 |           resolvePromise();
  105 |         }
  106 |       } catch {
  107 |         // not ready
  108 |       }
  109 |     }, 200);
  110 |   });
  111 | }
  112 | 
  113 | export async function stopStaticServer(): Promise<void> {
  114 |   if (server) {
  115 |     server.kill('SIGTERM');
  116 |     server = null;
  117 |   }
  118 | }
  119 | 
  120 | export function attachConsoleCollector(page: Page): {
  121 |   criticalErrors: string[];
  122 |   consoleErrors: string[];
  123 | } {
  124 |   const criticalErrors: string[] = [];
  125 |   const consoleErrors: string[] = [];
  126 | 
  127 |   page.on('console', (msg) => {
  128 |     const text = msg.text();
  129 |     const type = msg.type();
  130 |     if (type === 'error') {
  131 |       consoleErrors.push(text);
  132 |     }
  133 |     if (
  134 |       (type === 'error' &&
  135 |         (text.includes('device-lost') ||
  136 |           text.includes('shader-compile-error') ||
  137 |           text.includes('Uncaptured error') ||
  138 |           text.includes('Fallback shader also failed'))) ||
  139 |       text.includes('[pageerror]')
  140 |     ) {
  141 |       criticalErrors.push(text);
  142 |     }
  143 |   });
  144 | 
  145 |   page.on('pageerror', (err) => {
  146 |     criticalErrors.push(`[pageerror] ${err.message}`);
  147 |   });
  148 | 
  149 |   return { criticalErrors, consoleErrors };
  150 | }
  151 | 
  152 | export async function waitForTestApi(page: Page, timeoutMs = 30000): Promise<void> {
  153 |   await page.waitForFunction(() => (window as any).__pixelocity__?.renderer != null, {
  154 |     timeout: timeoutMs,
  155 |   });
  156 | }
  157 | 
  158 | export async function getActiveBackend(page: Page): Promise<RendererBackend | 'js' | null> {
  159 |   return page.evaluate(() => {
  160 |     return (window as any).__pixelocity__?.getRendererType?.() ?? null;
  161 |   });
  162 | }
  163 | 
  164 | export async function assertExpectedBackend(
  165 |   page: Page,
  166 |   expected: RendererBackend
  167 | ): Promise<RendererBackend | 'js' | null> {
  168 |   const active = await getActiveBackend(page);
  169 |   if (isStrictGpuMode()) {
  170 |     expect(active, `Expected ${expected} backend (WASM_GPU_TESTS=1)`).toBe(expected);
  171 |   } else if (active !== expected) {
  172 |     console.log(
  173 |       `[harness] Backend is "${active}" not "${expected}" — acceptable without WASM_GPU_TESTS=1`
  174 |     );
  175 |   }
  176 |   return active;
  177 | }
  178 | 
  179 | export async function loadShaderOnSlot(
  180 |   page: Page,
  181 |   shader: { id: string; url: string; slot?: number },
  182 |   inputSource: 'generative' | 'image' | 'none' = 'generative'
  183 | ): Promise<void> {
  184 |   await page.evaluate(
  185 |     async ({ s, source }) => {
  186 |       const api = (window as any).__pixelocity__;
```