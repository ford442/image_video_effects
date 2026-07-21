/**
 * Shared Playwright helpers for thumbnail generation (mirrors tests/helpers/rendererHarness.ts).
 */
import { spawn } from 'child_process';
import { existsSync } from 'fs';
import { resolve, join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

export const ROOT = resolve(__dirname, '..', '..');
export const BUILD_DIR = resolve(ROOT, 'build');
export const DEFAULT_PORT = 3459;

/** Categories that need an image input source. */
export const IMAGE_CATEGORIES = new Set(['image', 'hybrid', 'advanced-hybrid']);

let server = null;
let serverPort = DEFAULT_PORT;

export function buildAppUrl({
  renderer = 'webgpu',
  renderQuality = 'battery',
  extraParams = {},
  port = serverPort,
} = {}) {
  const params = new URLSearchParams({
    renderer,
    testMode: '1',
    renderQuality,
    ...extraParams,
  });
  return `http://localhost:${port}/?${params.toString()}`;
}

export async function startStaticServer(buildDir = BUILD_DIR, port = DEFAULT_PORT) {
  const indexHtml = resolve(buildDir, 'index.html');
  if (!existsSync(indexHtml)) {
    throw new Error(
      `Missing ${indexHtml}. Run "SKIP_WASM_BUILD=1 npm run build" before thumbnail generation.`,
    );
  }

  serverPort = port;
  server = spawn('python3', ['-m', 'http.server', String(port), '--directory', buildDir], {
    stdio: 'pipe',
  });

  await new Promise((resolvePromise, reject) => {
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

export async function stopStaticServer() {
  if (server) {
    server.kill('SIGTERM');
    server = null;
  }
}

export function attachConsoleCollector(page) {
  const criticalErrors = [];
  const consoleErrors = [];

  page.on('console', (msg) => {
    const text = msg.text();
    const type = msg.type();
    if (type === 'error') consoleErrors.push(text);
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

export async function waitForTestApi(page, timeoutMs = 60000) {
  await page.waitForFunction(() => window.__pixelocity__?.renderer != null, {
    timeout: timeoutMs,
  });
}

export async function getActiveBackend(page) {
  return page.evaluate(() => window.__pixelocity__?.getRendererType?.() ?? null);
}

export async function loadShaderOnSlot(
  page,
  shader,
  inputSource = 'generative',
  imageUrl = null,
) {
  await page.evaluate(
    async ({ s, source, img }) => {
      const api = window.__pixelocity__;
      api.setInputSource(source);
      if (source === 'image' && img) {
        await api.loadImage(img);
      }
      const ok = await api.loadShader(s.id, s.url);
      if (!ok) throw new Error(`loadShader failed for ${s.id}`);
      api.setSlotShader(s.slot ?? 0, s.id);
    },
    { s: shader, source: inputSource, img: imageUrl },
  );
}

export async function applyTestState(page, state) {
  await page.evaluate((s) => {
    window.__pixelocity__?.setTestRenderState(s);
  }, state);
}

export async function waitFrames(page, frameCount) {
  await page.evaluate((n) => window.__pixelocity__?.waitFrames(n), frameCount);
}

/** Sample canvas pixels in-browser (works for WebGPU-backed canvases). */
export async function captureCanvasStats(page) {
  return page.evaluate(() => {
    if (typeof window.__pixelocity__?.captureCanvasStats === 'function') {
      return window.__pixelocity__.captureCanvasStats();
    }
    const canvas = document.querySelector('canvas');
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

export function isBlackFrame(stats, { minActive = 0.02, minLuminance = 0.01 } = {}) {
  return stats.activePixelRatio < minActive || stats.meanLuminance < minLuminance;
}

/** Capture canvas as base64 PNG, optionally downscaled to size×size. */
export async function captureThumbnailPng(page, size = 256) {
  return page.evaluate(async (outSize) => {
    if (typeof window.__pixelocity__?.captureThumbnailPng === 'function') {
      return window.__pixelocity__.captureThumbnailPng(outSize);
    }
    const dataUrl = await window.__pixelocity__?.captureCanvasScreenshot?.();
    if (!dataUrl) return null;
    return dataUrl.replace(/^data:image\/png;base64,/, '');
  }, size);
}

export function inputSourceForCategory(category) {
  return IMAGE_CATEGORIES.has(category) ? 'image' : 'generative';
}

export function localShaderUrl(id) {
  return `./shaders/${id}.wgsl`;
}

export function imageFixtureUrl() {
  return './fixtures/thumbnail-sample.png';
}
