/**
 * Shared Playwright harness for WASM / WebGPU renderer tests.
 */
import { spawn, type ChildProcessWithoutNullStreams } from 'child_process';
import { existsSync, mkdirSync, writeFileSync } from 'fs';
import { resolve } from 'path';
import { expect, type Page } from '@playwright/test';
import type { ParityShaderCase } from '../fixtures/parityMatrix';

export const BUILD_DIR = resolve(__dirname, '../../build');
export const DEFAULT_PORT = 3458;
export const MIN_WASM_FPS = 5;
export const PROMOTION_SPEEDUP_RATIO = 1.25;
export const PROMOTION_MIN_SHADERS = 3;

export type RendererBackend = 'wasm' | 'webgpu';

export interface ImageStats {
  width: number;
  height: number;
  meanLuminance: number;
  activePixelRatio: number;
}

export interface BenchResult {
  shaderId: string;
  backend: string;
  avgFps: number;
  avgTotalMs: number;
  gpuTimingsAvailable: boolean;
  timingSource?: string;
  p95TotalMs: number;
}

export interface BenchComparison {
  shaderId: string;
  wasmFps: number;
  webgpuFps: number;
  wasmAvgTotalMs: number;
  webgpuAvgTotalMs: number;
  /** WASM fps / WebGPU fps (or inverse frame-time ratio). ≥1.25 meets promotion gate. */
  speedupRatio: number;
  meetsPromotionGate: boolean;
}

export interface WasmBenchmarkReport {
  generatedAt: string;
  strictGpuMode: boolean;
  gpuBackendObserved: boolean;
  benchmarkShaderIds: string[];
  wasmAdapterSummary?: string;
  webgpuAdapterSummary?: string;
  userAgent?: string;
  results: BenchResult[];
  comparisons: BenchComparison[];
  promotionGateMet: boolean;
  promotionMinShaders: number;
  promotionSpeedupRatio: number;
}

export interface BenchmarkReportMetadata {
  benchmarkShaderIds: string[];
  wasmAdapterSummary?: string;
  webgpuAdapterSummary?: string;
  userAgent?: string;
  gpuBackendObserved?: boolean;
}

let server: ChildProcessWithoutNullStreams | null = null;
let serverPort = DEFAULT_PORT;

/** Opt-in strict mode: fail when WebGPU/WASM backends are unavailable (local GPU runs). */
export function isStrictGpuMode(): boolean {
  return process.env.WASM_GPU_TESTS === '1';
}

/** @deprecated Use isStrictGpuMode() — kept for existing specs. */
export function hasGpuForTests(): boolean {
  return isStrictGpuMode();
}

export function buildAppUrl(
  backend: RendererBackend,
  extraParams: Record<string, string> = {},
  port = serverPort
): string {
  const params = new URLSearchParams({
    renderer: backend,
    testMode: '1',
    ...extraParams,
  });
  return `http://localhost:${port}/?${params.toString()}`;
}

export async function startStaticServer(port = DEFAULT_PORT): Promise<void> {
  const indexHtml = resolve(BUILD_DIR, 'index.html');
  if (!existsSync(indexHtml)) {
    throw new Error(
      `Missing ${indexHtml}. Run "npm run build" (or SKIP_WASM_BUILD=1 npm run build) before Playwright WASM tests.`
    );
  }

  serverPort = port;
  server = spawn('python3', ['-m', 'http.server', String(port), '--directory', BUILD_DIR], {
    stdio: 'pipe',
  });

  await new Promise<void>((resolvePromise, reject) => {
    const timeout = setTimeout(() => reject(new Error('Static server start timeout')), 60000);
    const interval = setInterval(async () => {
      try {
        const res = await fetch(`http://localhost:${port}/`);
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

export async function stopStaticServer(): Promise<void> {
  if (server) {
    server.kill('SIGTERM');
    server = null;
  }
}

export function attachConsoleCollector(page: Page): {
  criticalErrors: string[];
  consoleErrors: string[];
} {
  const criticalErrors: string[] = [];
  const consoleErrors: string[] = [];

  page.on('console', (msg) => {
    const text = msg.text();
    const type = msg.type();
    if (type === 'error') {
      consoleErrors.push(text);
    }
    if (
      (type === 'error' &&
        (text.includes('device-lost') ||
          text.includes('shader-compile-error') ||
          text.includes('Uncaptured error') ||
          text.includes('Fallback shader also failed'))) ||
      text.includes('[pageerror]')
    ) {
      criticalErrors.push(text);
    }
  });

  page.on('pageerror', (err) => {
    criticalErrors.push(`[pageerror] ${err.message}`);
  });

  return { criticalErrors, consoleErrors };
}

export async function waitForTestApi(page: Page, timeoutMs = 30000): Promise<void> {
  await page.waitForFunction(() => (window as any).__pixelocity__?.renderer != null, {
    timeout: timeoutMs,
  });
}

export async function getActiveBackend(page: Page): Promise<RendererBackend | 'js' | null> {
  return page.evaluate(() => {
    return (window as any).__pixelocity__?.getRendererType?.() ?? null;
  });
}

export async function assertExpectedBackend(
  page: Page,
  expected: RendererBackend
): Promise<RendererBackend | 'js' | null> {
  const active = await getActiveBackend(page);
  if (isStrictGpuMode()) {
    expect(active, `Expected ${expected} backend (WASM_GPU_TESTS=1)`).toBe(expected);
  } else if (active !== expected) {
    console.log(
      `[harness] Backend is "${active}" not "${expected}" — acceptable without WASM_GPU_TESTS=1`
    );
  }
  return active;
}

export async function loadShaderOnSlot(
  page: Page,
  shader: { id: string; url: string; slot?: number },
  inputSource: 'generative' | 'image' | 'none' = 'generative'
): Promise<void> {
  await page.evaluate(
    async ({ s, source }) => {
      const api = (window as any).__pixelocity__;
      api.setInputSource(source);
      const ok = await api.loadShader(s.id, s.url);
      if (!ok) {
        throw new Error(`loadShader failed for ${s.id}`);
      }
      api.setSlotShader(s.slot ?? 0, s.id);
    },
    { s: shader, source: inputSource }
  );
}

export async function applyTestState(
  page: Page,
  state: NonNullable<ParityShaderCase['testState']>
): Promise<void> {
  await page.evaluate((s) => {
    (window as any).__pixelocity__?.setTestRenderState(s);
  }, state);
}

/** Sample canvas pixels in-browser (works for WebGPU-backed canvases). */
export async function captureCanvasStats(page: Page): Promise<ImageStats> {
  return page.evaluate(() => {
    const canvas = document.querySelector('canvas') as HTMLCanvasElement | null;
    if (!canvas) {
      return { width: 0, height: 0, meanLuminance: 0, activePixelRatio: 0 };
    }

    const w = canvas.width;
    const h = canvas.height;
    const tmp = document.createElement('canvas');
    tmp.width = w;
    tmp.height = h;
    const ctx = tmp.getContext('2d');
    if (!ctx) {
      return { width: w, height: h, meanLuminance: 0, activePixelRatio: 0 };
    }
    ctx.drawImage(canvas, 0, 0);
    const { data } = ctx.getImageData(0, 0, w, h);

    let lumSum = 0;
    let active = 0;
    const pixels = w * h;
    for (let i = 0; i < data.length; i += 4) {
      const r = data[i] / 255;
      const g = data[i + 1] / 255;
      const b = data[i + 2] / 255;
      const lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      lumSum += lum;
      if (lum > 0.05) active++;
    }

    return {
      width: w,
      height: h,
      meanLuminance: lumSum / pixels,
      activePixelRatio: active / pixels,
    };
  });
}

export async function getRendererFps(page: Page): Promise<number> {
  return page.evaluate(() => {
    const diags = (window as any).__pixelocity__?.renderer?.getDiagnostics?.();
    return diags?.wasm?.fps ?? diags?.webgpu?.fps ?? diags?.metrics?.fps ?? 0;
  });
}

export async function exerciseShaderOnWasm(
  page: Page,
  shader: ParityShaderCase,
  renderMs = 2500
): Promise<{ fps: number; stats: ImageStats; criticalErrors: string[] }> {
  const { criticalErrors } = attachConsoleCollector(page);
  await loadShaderOnSlot(page, shader);
  if (shader.testState) {
    await applyTestState(page, shader.testState);
  }
  await page.waitForTimeout(renderMs);
  const stats = await captureCanvasStats(page);
  const fps = await getRendererFps(page);
  return { fps, stats, criticalErrors };
}

export async function renderShaderCase(
  page: Page,
  backend: RendererBackend,
  shader: ParityShaderCase,
  port = serverPort
): Promise<{ backend: RendererBackend | 'js' | null; stats: ImageStats; criticalErrors: string[] }> {
  const { criticalErrors } = attachConsoleCollector(page);
  await page.goto(buildAppUrl(backend, {}, port), { waitUntil: 'networkidle' });
  await waitForTestApi(page);

  const active = await getActiveBackend(page);
  if (active !== backend) {
    return {
      backend: active,
      stats: { width: 0, height: 0, meanLuminance: 0, activePixelRatio: 0 },
      criticalErrors,
    };
  }

  await loadShaderOnSlot(page, shader);
  if (shader.testState) {
    await applyTestState(page, shader.testState);
  }

  await page.waitForTimeout(2500);
  if (shader.testState) {
    await applyTestState(page, shader.testState);
    await page.waitForTimeout(500);
  }

  const stats = await captureCanvasStats(page);
  return { backend: active, stats, criticalErrors };
}

export function computeSpeedupRatio(wasm: BenchResult, webgpu: BenchResult): number {
  if (wasm.avgFps > 0 && webgpu.avgFps > 0) {
    return wasm.avgFps / webgpu.avgFps;
  }
  if (wasm.avgTotalMs > 0 && webgpu.avgTotalMs > 0) {
    return webgpu.avgTotalMs / wasm.avgTotalMs;
  }
  return 0;
}

/** Collect adapter summary from the active renderer or navigator.gpu (browser context). */
export async function collectAdapterSummary(
  page: Page,
  backend: RendererBackend
): Promise<string> {
  return page.evaluate(async (expectedBackend) => {
    const api = (window as any).__pixelocity__;
    if (expectedBackend === 'wasm') {
      const fromApi = api?.getAdapterSummary?.();
      if (fromApi) return fromApi;
      return api?.renderer?.getDiagnostics?.()?.wasm?.adapterInfo ?? '';
    }

    const webgpuDiags = api?.renderer?.getDiagnostics?.()?.webgpu;
    if (webgpuDiags?.adapterInfo) return webgpuDiags.adapterInfo;

    if (!navigator.gpu) return '';
    const adapter = await navigator.gpu.requestAdapter();
    if (!adapter) return '';
    const info = adapter.info;
    return [info.vendor, info.architecture, info.device, info.description]
      .filter(Boolean)
      .join(' | ');
  }, backend);
}

export function buildBenchmarkReport(
  results: BenchResult[],
  comparisons: BenchComparison[],
  metadata: BenchmarkReportMetadata = { benchmarkShaderIds: [] }
): WasmBenchmarkReport {
  const promotionHits = comparisons.filter((c) => c.meetsPromotionGate).length;
  const gpuFromResults = results.some((r) => r.backend === 'wasm' && r.avgFps > 0);
  return {
    generatedAt: new Date().toISOString(),
    strictGpuMode: isStrictGpuMode(),
    gpuBackendObserved: metadata.gpuBackendObserved ?? gpuFromResults,
    benchmarkShaderIds: metadata.benchmarkShaderIds,
    wasmAdapterSummary: metadata.wasmAdapterSummary,
    webgpuAdapterSummary: metadata.webgpuAdapterSummary,
    userAgent: metadata.userAgent,
    results,
    comparisons,
    promotionGateMet: promotionHits >= PROMOTION_MIN_SHADERS,
    promotionMinShaders: PROMOTION_MIN_SHADERS,
    promotionSpeedupRatio: PROMOTION_SPEEDUP_RATIO,
  };
}

export function buildStubBenchmarkReport(
  benchmarkShaderIds: string[],
  overrides: Partial<BenchmarkReportMetadata> = {}
): WasmBenchmarkReport {
  return buildBenchmarkReport([], [], {
    benchmarkShaderIds,
    gpuBackendObserved: false,
    ...overrides,
  });
}

export function writeBenchmarkReport(report: WasmBenchmarkReport, path = 'test-results/wasm-benchmark-report.json'): void {
  mkdirSync(resolve(path, '..'), { recursive: true });
  writeFileSync(path, JSON.stringify(report, null, 2));
  console.log(`\nWrote benchmark report → ${path}\n`);
}
