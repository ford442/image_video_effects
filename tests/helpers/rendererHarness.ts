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
  qualityMode?: string;
  colorFormat?: string;
  estimatedTextureMiB?: number;
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

  page.on('pageerror', (error) => {
    const msg = error.message || String(error);
    if (!isStrictGpuMode()) {
      if (msg.includes('No GPU adapter found') || msg.includes('Failed to obtain a WebGPU adapter') || msg.includes('Failed to get WebGPU adapter')) {
        return;
      }
    }
    criticalErrors.push(`[pageerror] ${error.message}`);
  });

  return { criticalErrors, consoleErrors };
}

export async function waitForWebGpuProbe(page: Page, timeoutMs = 30000): Promise<void> {
  await page.waitForFunction(
    () => {
      const w = window as { webgpuProbe?: { ok: boolean }; __pixelocity__?: { renderer?: unknown } };
      return w.webgpuProbe != null || w.__pixelocity__?.renderer != null;
    },
    { timeout: timeoutMs },
  );
}

export async function isGpuProbeOk(page: Page): Promise<boolean> {
  return page.evaluate(() => {
    const w = window as {
      webgpuProbe?: { ok: boolean };
      __pixelocity__?: { renderer?: unknown };
    };
    if (w.webgpuProbe != null) return w.webgpuProbe.ok === true;
    return w.__pixelocity__?.renderer != null;
  });
}

export async function waitForTestApi(page: Page, timeoutMs = 30000): Promise<void> {
  await waitForWebGpuProbe(page, timeoutMs);
  const probeOk = await isGpuProbeOk(page);
  if (!probeOk) {
    return;
  }
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
): Promise<boolean> {
  return page.evaluate(
    async ({ s, source }) => {
      const api = (window as any).__pixelocity__;
      api.setInputSource(source);
      const ok = await api.loadShader(s.id, s.url);
<<<<<<< HEAD
      if (!ok) {
        const diags = api.renderer?.getDiagnostics?.();
        const lastErr = diags?.wasm?.lastLoadError || 'Unknown (check console)';
        throw new Error(`loadShader failed for ${s.id}: ${lastErr}`);
      }
=======
      if (!ok) return false;
>>>>>>> origin/main
      api.setSlotShader(s.slot ?? 0, s.id);
      return true;
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
): Promise<{ loaded: boolean; fps: number; stats: ImageStats; criticalErrors: string[] }> {
  const { criticalErrors } = attachConsoleCollector(page);
  const loaded = await loadShaderOnSlot(page, shader);
  if (!loaded) return { loaded: false, fps: 0, stats: { width: 0, height: 0, nonZeroPixels: 0, rBar: 0, gBar: 0, bBar: 0 }, criticalErrors };
  if (shader.testState) {
    await applyTestState(page, shader.testState);
  }
  await page.waitForTimeout(renderMs);
  const stats = await captureCanvasStats(page);
  const fps = await getRendererFps(page);
  return { loaded: true, fps, stats, criticalErrors };
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

// ── Format-tier bench (#1008 follow-up) ─────────────────────────────────────

export interface TierMeasurement {
  workload: string;
  kind: string;
  tier: string;
  expectsFp32Pin: boolean;
  shadersLoaded: number;
  shadersRequested: number;
  avgFps: number;
  avgTotalMs: number;
  colorFormat: string;
  requestedColorFormat: string;
  fp32Pinned: boolean;
  fp32PinnedBy: string[];
  estimatedTextureMiB: number;
  internalWidth: number;
  internalHeight: number;
  scale: number;
  maxPassesPerFrame: number;
  hasRealGpuTimings: boolean;
  timingSource: string;
  passCapWarnings: string[];
  formatRewriteWarnings: string[];
}

export interface FormatTierReport {
  generatedAt: string;
  gpuObserved: boolean;
  strictGpuMode: boolean;
  adapterSummary?: string;
  userAgent?: string;
  note?: string;
  measurements: TierMeasurement[];
}

export function buildFormatTierReport(
  measurements: TierMeasurement[],
  meta: { gpuObserved: boolean; adapterSummary?: string; userAgent?: string; note?: string } = {
    gpuObserved: false,
  }
): FormatTierReport {
  return {
    generatedAt: new Date().toISOString(),
    gpuObserved: meta.gpuObserved,
    strictGpuMode: isStrictGpuMode(),
    adapterSummary: meta.adapterSummary,
    userAgent: meta.userAgent,
    note: meta.note,
    measurements,
  };
}

/** FPS / MiB deltas of each tier against the same workload at ultra. */
export function summarizeTierDeltas(report: FormatTierReport): Array<{
  workload: string;
  tier: string;
  fpsRatioVsUltra: number;
  miBRatioVsUltra: number;
}> {
  const ultra = new Map(
    report.measurements.filter((m) => m.tier === 'ultra').map((m) => [m.workload, m])
  );
  return report.measurements
    .filter((m) => m.tier !== 'ultra')
    .map((m) => {
      const base = ultra.get(m.workload);
      return {
        workload: m.workload,
        tier: m.tier,
        fpsRatioVsUltra: base && base.avgFps > 0 ? m.avgFps / base.avgFps : 0,
        miBRatioVsUltra:
          base && base.estimatedTextureMiB > 0
            ? m.estimatedTextureMiB / base.estimatedTextureMiB
            : 0,
      };
    });
}

export function renderFormatTierMarkdown(report: FormatTierReport): string {
  const lines: string[] = [];
  const day = report.generatedAt.slice(0, 10);
  lines.push(`# Format tier bench — ${day}`, '');
  lines.push('## Hardware', '');
  lines.push(`- **Adapter:** ${report.adapterSummary || '_unknown_'}`);
  lines.push(`- **User agent:** ${report.userAgent || '_unknown_'}`);
  lines.push(`- **GPU observed:** ${report.gpuObserved ? 'yes' : '**no — stub report**'}`);
  lines.push(`- **Generated:** ${report.generatedAt}`);
  if (report.note) lines.push(`- **Note:** ${report.note}`);
  lines.push('');

  if (report.measurements.length === 0) {
    lines.push('_No measurements: this environment has no WebGPU adapter._', '');
    return lines.join('\n');
  }

  lines.push('## Measurements', '');
  lines.push(
    '| Workload | Tier | Format | Pinned | Internal | ~MiB | FPS | GPU ms | Real timings | Slots | Passes cap |'
  );
  lines.push('|---|---|---|---|---|---|---|---|---|---|---|');
  for (const m of report.measurements) {
    lines.push(
      `| ${m.workload} | ${m.tier} | ${m.colorFormat} | ${m.fp32Pinned ? `yes (${m.fp32PinnedBy.join(', ')})` : 'no'} `
        + `| ${m.internalWidth}×${m.internalHeight} | ${m.estimatedTextureMiB} | ${m.avgFps.toFixed(1)} `
        + `| ${m.avgTotalMs.toFixed(2)} | ${m.hasRealGpuTimings ? 'yes' : `no (${m.timingSource})`} `
        + `| ${m.shadersLoaded}/${m.shadersRequested} | ${m.maxPassesPerFrame} |`
    );
  }
  lines.push('');

  lines.push('## Deltas vs ultra', '');
  lines.push('| Workload | Tier | FPS ×ultra | Texture MiB ×ultra |');
  lines.push('|---|---|---|---|');
  for (const d of summarizeTierDeltas(report)) {
    lines.push(
      `| ${d.workload} | ${d.tier} | ${d.fpsRatioVsUltra.toFixed(2)}× | ${d.miBRatioVsUltra.toFixed(2)}× |`
    );
  }
  lines.push('');

  const capWarnings = report.measurements.filter((m) => m.passCapWarnings.length > 0);
  const rewriteWarnings = report.measurements.filter((m) => m.formatRewriteWarnings.length > 0);
  lines.push('## Warnings', '');
  if (capWarnings.length === 0 && rewriteWarnings.length === 0) {
    lines.push('_None._', '');
  } else {
    for (const m of capWarnings) {
      lines.push(`- **pass cap** ${m.workload} @ ${m.tier}: ${m.passCapWarnings.join(' / ')}`);
    }
    for (const m of rewriteWarnings) {
      lines.push(`- **format rewrite miss** ${m.workload} @ ${m.tier}: ${m.formatRewriteWarnings.join(' / ')}`);
    }
    lines.push('');
  }

  lines.push('## Go / no-go: balanced as iGPU default', '');
  lines.push('<!-- Fill in after reading the tables above. Required to close #1008 follow-up. -->');
  lines.push('- **Verdict:** _TBD_');
  lines.push('- **Rationale:** _TBD_');
  lines.push('');
  return lines.join('\n');
}

export function writeFormatTierReport(
  report: FormatTierReport,
  jsonPath = 'test-results/format-tier-bench.json',
  markdownPath?: string
): void {
  const day = report.generatedAt.slice(0, 10);
  const mdPath = markdownPath ?? `reports/format-tier-bench-${day}.md`;
  mkdirSync(resolve(jsonPath, '..'), { recursive: true });
  writeFileSync(jsonPath, JSON.stringify(report, null, 2));
  mkdirSync(resolve(mdPath, '..'), { recursive: true });
  writeFileSync(mdPath, renderFormatTierMarkdown(report));
  console.log(`\nWrote format tier report → ${mdPath} (+ ${jsonPath})\n`);
}

// ── Pixel-diff harness (WASM Tier B evidence) ───────────────────────────────

/**
 * Frozen-seed pixel comparison between backends.
 *
 * The parity spec compares *statistics* (mean luminance, coverage), which passes even
 * when two images differ structurally. For promotion evidence we need per-pixel deltas
 * on a pinned render state, so a reviewer can see whether WASM output is actually the
 * same picture. Runs only with a real adapter; otherwise the caller skips.
 */

export interface FrameCapture {
  /** Base64 PNG (no data: prefix). */
  png: string;
  width: number;
  height: number;
  /** Downsampled RGBA grid used for the numeric diff (keeps payloads small). */
  grid: number[];
  gridSize: number;
}

export interface PixelDiffResult {
  shaderId: string;
  frameIndex: number;
  /** Mean absolute RGB difference, 0–1. */
  meanAbsDelta: number;
  /** Largest single-channel difference, 0–1. */
  maxAbsDelta: number;
  /** Fraction of grid cells whose max channel delta exceeds `cellThreshold`. */
  differingCellRatio: number;
  cellThreshold: number;
}

export const PIXEL_DIFF_GRID = 64;
export const PIXEL_DIFF_CELL_THRESHOLD = 0.1;

/** Capture the canvas as a PNG plus a downsampled RGBA grid for numeric comparison. */
export async function captureFrame(page: Page, gridSize = PIXEL_DIFF_GRID): Promise<FrameCapture | null> {
  return page.evaluate((size) => {
    const canvas = document.querySelector('canvas') as HTMLCanvasElement | null;
    if (!canvas || canvas.width === 0 || canvas.height === 0) return null;

    const tmp = document.createElement('canvas');
    tmp.width = size;
    tmp.height = size;
    const ctx = tmp.getContext('2d');
    if (!ctx) return null;
    ctx.drawImage(canvas, 0, 0, size, size);
    const { data } = ctx.getImageData(0, 0, size, size);

    return {
      png: canvas.toDataURL('image/png').replace(/^data:image\/png;base64,/, ''),
      width: canvas.width,
      height: canvas.height,
      grid: Array.from(data),
      gridSize: size,
    };
  }, gridSize);
}

/** Compare two captures cell-by-cell. Both must share a grid size. */
export function diffFrames(
  shaderId: string,
  frameIndex: number,
  a: FrameCapture,
  b: FrameCapture,
  cellThreshold = PIXEL_DIFF_CELL_THRESHOLD
): PixelDiffResult {
  if (a.gridSize !== b.gridSize) {
    throw new Error(`grid size mismatch: ${a.gridSize} vs ${b.gridSize}`);
  }

  const cells = a.gridSize * a.gridSize;
  let sum = 0;
  let max = 0;
  let differing = 0;

  for (let i = 0; i < cells; i++) {
    const o = i * 4;
    let cellMax = 0;
    for (let c = 0; c < 3; c++) {
      const d = Math.abs(a.grid[o + c] - b.grid[o + c]) / 255;
      sum += d;
      if (d > cellMax) cellMax = d;
    }
    if (cellMax > max) max = cellMax;
    if (cellMax > cellThreshold) differing++;
  }

  return {
    shaderId,
    frameIndex,
    meanAbsDelta: sum / (cells * 3),
    maxAbsDelta: max,
    differingCellRatio: differing / cells,
    cellThreshold,
  };
}

export interface PixelDiffReport {
  generatedAt: string;
  gpuObserved: boolean;
  wasmAdapterSummary?: string;
  webgpuAdapterSummary?: string;
  userAgent?: string;
  note?: string;
  frames: number;
  diffs: PixelDiffResult[];
}

export function buildPixelDiffReport(
  diffs: PixelDiffResult[],
  meta: {
    gpuObserved: boolean;
    frames?: number;
    wasmAdapterSummary?: string;
    webgpuAdapterSummary?: string;
    userAgent?: string;
    note?: string;
  }
): PixelDiffReport {
  return {
    generatedAt: new Date().toISOString(),
    gpuObserved: meta.gpuObserved,
    wasmAdapterSummary: meta.wasmAdapterSummary,
    webgpuAdapterSummary: meta.webgpuAdapterSummary,
    userAgent: meta.userAgent,
    note: meta.note,
    frames: meta.frames ?? 0,
    diffs,
  };
}

export function writePixelDiffReport(
  report: PixelDiffReport,
  path = 'test-results/wasm-pixel-diff.json'
): void {
  mkdirSync(resolve(path, '..'), { recursive: true });
  writeFileSync(path, JSON.stringify(report, null, 2));
  console.log(`\nWrote pixel diff report → ${path}\n`);
}

/** Save a capture as a PNG artifact for human review. */
export function writeFrameArtifact(
  capture: FrameCapture,
  path: string
): void {
  mkdirSync(resolve(path, '..'), { recursive: true });
  writeFileSync(path, Buffer.from(capture.png, 'base64'));
}
