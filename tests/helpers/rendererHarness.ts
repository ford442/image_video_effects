/**
 * Shared Playwright harness for WASM / WebGPU renderer tests.
 */
import { spawn, type ChildProcessWithoutNullStreams } from 'child_process';
import type { Page } from '@playwright/test';
import { resolve } from 'path';

export const BUILD_DIR = resolve(__dirname, '../../build');
export const DEFAULT_PORT = 3458;

export type RendererBackend = 'wasm' | 'webgpu';

export interface ImageStats {
  width: number;
  height: number;
  meanLuminance: number;
  activePixelRatio: number;
}

let server: ChildProcessWithoutNullStreams | null = null;
let serverPort = DEFAULT_PORT;

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
} {
  const criticalErrors: string[] = [];

  page.on('console', (msg) => {
    const text = msg.text();
    const type = msg.type();
    if (
      type === 'error' &&
      (text.includes('device-lost') ||
        text.includes('shader-compile-error') ||
        text.includes('Uncaptured error'))
    ) {
      criticalErrors.push(text);
    }
  });

  page.on('pageerror', (err) => {
    criticalErrors.push(`[pageerror] ${err.message}`);
  });

  return { criticalErrors };
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

export async function loadShaderOnSlot(
  page: Page,
  shader: { id: string; url: string; slot?: number },
  inputSource: 'generative' | 'none' = 'generative'
): Promise<void> {
  await page.evaluate(
    async ({ s, source }) => {
      const api = (window as any).__pixelocity__;
      api.setInputSource(source);
      await api.loadShader(s.id, s.url);
      api.setSlotShader(s.slot ?? 0, s.id);
    },
    { s: shader, source: inputSource }
  );
}

export async function applyTestState(
  page: Page,
  state: NonNullable<import('../fixtures/parityMatrix').ParityShaderCase['testState']>
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

export async function renderShaderCase(
  page: Page,
  backend: RendererBackend,
  shader: import('../fixtures/parityMatrix').ParityShaderCase,
  port = serverPort
): Promise<{ backend: RendererBackend | 'js' | null; stats: ImageStats; criticalErrors: string[] }> {
  const { criticalErrors } = attachConsoleCollector(page);
  await page.goto(buildAppUrl(backend, {}, port), { waitUntil: 'networkidle' });
  await waitForTestApi(page);

  const active = await getActiveBackend(page);
  if (active !== backend) {
    return { backend: active, stats: { width: 0, height: 0, meanLuminance: 0, activePixelRatio: 0 }, criticalErrors };
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

export function hasGpuForTests(): boolean {
  return process.env.WASM_GPU_TESTS === '1' || process.env.CI !== 'true';
}
