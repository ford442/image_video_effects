/**
 * Shared Playwright helpers for thumbnail generation (mirrors tests/helpers/rendererHarness.ts).
 */
import { spawn } from 'child_process';
import { createRequire } from 'module';
import { existsSync } from 'fs';
import { resolve, join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

export const ROOT = resolve(__dirname, '..', '..');
export const BUILD_DIR = resolve(ROOT, 'build');
export const DEFAULT_PORT = 3459;

/** Only standalone generative shaders render without an input image. */
export const GENERATIVE_CATEGORIES = new Set(['generative']);

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

/** Abort every request that is not same-origin with the local build server. */
export async function blockExternalRequests(page) {
  await page.route(
    (url) => url.hostname !== 'localhost' && url.hostname !== '127.0.0.1' && url.protocol.startsWith('http'),
    (route) => route.abort(),
  );
}

export async function waitForTestApi(page, timeoutMs = 60000) {
  await page.waitForFunction(() => window.__pixelocity__?.renderer != null, null, {
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

/**
 * Reallocate the working textures (a resolution-scale change does that), so the
 * next shader's dataTextureC starts at zero. Ends at `scale` (default: battery 0.5).
 */
export async function resetFeedbackState(page, scale = null) {
  await page.evaluate((target) => {
    const api = window.__pixelocity__;
    if (typeof api?.setRenderScale !== 'function') return;
    const base = target ?? api.getPerformanceStatus?.()?.scale ?? 0.5;
    api.setRenderScale(base >= 1 ? base - 0.125 : base + 0.125);
    api.setRenderScale(base);
  }, scale);
}

export async function applyTestState(page, state) {
  await page.evaluate((s) => {
    window.__pixelocity__?.setTestRenderState(s);
  }, state);
}

export async function waitFrames(page, frameCount) {
  await page.evaluate((n) => window.__pixelocity__?.waitFrames(n), frameCount);
}

// Frame classification lives in one CommonJS module shared with the audit and tests.
const frameAnalysis = createRequire(import.meta.url)('./thumbnailFrameAnalysis.js');
export const {
  isBlackFrame,
  isMagentaFrame,
  isFlatFrame,
  isErrorFrame,
  classifyErrorFrame,
  formatFrameStats,
  statsFromPngBuffer,
} = frameAnalysis;

/**
 * Wait until the backend has rendered `n` more frames. Page rAF ticks are not
 * rendered frames: on a slow device (SwiftShader) or in the render worker the
 * page can tick many times per presented frame.
 */
export async function waitRenderedFrames(page, n, timeoutMs = 180000) {
  const start = await renderedFrameCount(page);
  if (start == null) {
    await waitFrames(page, n);
    return;
  }
  await page.waitForFunction(
    (min) => (window.__pixelocity__?.renderer?.getDiagnostics?.()?.webgpu?.frameStats?.framesRendered ?? 0) >= min,
    start + n,
    { timeout: timeoutMs, polling: 100 },
  );
}

async function renderedFrameCount(page) {
  return page.evaluate(
    () => window.__pixelocity__?.renderer?.getDiagnostics?.()?.webgpu?.frameStats?.framesRendered ?? null,
  );
}

/** Adapter description reported by the live renderer (manifest provenance). */
export async function getAdapterInfo(page) {
  return page.evaluate(() => window.__pixelocity__?.renderer?.getDiagnostics?.()?.webgpu?.adapterInfo ?? null);
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

/**
 * Every effect except a standalone generator samples the input image, as it
 * does in the app; a cleared input renders those effects black.
 */
export function inputSourceForCategory(category) {
  return GENERATIVE_CATEGORIES.has(category) ? 'generative' : 'image';
}

/** Same-origin URL for a catalog entry: its list `url` when present (graph steps, renamed files). */
export function localShaderUrl(id, listUrl = null) {
  if (listUrl && !/^https?:/i.test(listUrl)) {
    return `./${listUrl.replace(/^\.?\/+/, '')}`;
  }
  return `./shaders/${id}.wgsl`;
}

/** Procedural 512² scene, see scripts/make-thumbnail-fixture.py. */
export const THUMBNAIL_FIXTURE = 'fixtures/thumbnail-scene.png';

export function imageFixtureUrl() {
  return `./${THUMBNAIL_FIXTURE}`;
}
