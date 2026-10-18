/**
 * #1314 D — C++ measurement exports on a real (software) WebGPU device.
 *
 * Runs in the `swiftshader` Playwright project. Needs a production build
 * (`SKIP_WASM_BUILD=1 npm run build`, or plain `npm run build` with emsdk).
 *
 * Why the second test drives its own Module: the app bridge calls the
 * suspending `loadShader` export with a sync `ccall`. Under ASYNCIFY the
 * C++ LoadShader unwinds in wgpuInstanceWaitAny (error-scope pop), the ccall
 * returns a Promise the bridge reads as "failed", and the bridge frees the id
 * buffer before C++ resumes (the shader then registers under a garbage id).
 * That is the pre-existing sync-ccall hazard fixed only on the JSPI branch
 * (WASM_BACKEND_POLICY feature freeze), so no slot renders through the app on
 * this build. The measurement exports are exercised on a standalone instance
 * of the same artifact on a bare page, called with `{ async: true }`.
 */
import { expect, test, type Page } from '@playwright/test';
import {
  buildAppUrl,
  installGpuUncapturedErrorHook,
  readGpuUncapturedErrors,
  startStaticServer,
  stopStaticServer,
} from './helpers/rendererHarness';

const PORT = 3463;

test.beforeAll(async () => {
  await startStaticServer(PORT);
});

test.afterAll(async () => {
  await stopStaticServer();
});

/** Boot ?renderer=wasm and wait until C++ Initialize() has really finished on a device. */
async function bootWasm(page: Page): Promise<void> {
  await installGpuUncapturedErrorHook(page);
  await page.goto(buildAppUrl('wasm', {}, PORT), { waitUntil: 'load' });
  await page.waitForFunction(
    () => {
      const w = window as any;
      return w.webgpuProbe?.backend === 'wasm' && w.__pixelocity__?.renderer != null;
    },
    null,
    { timeout: 60_000 },
  );
  const probe = await page.evaluate(() => (window as any).webgpuProbe);
  expect(probe.ok, `WASM probe failed: ${probe.failedStage} ${probe.lastError}`).toBe(true);
}

test.describe('WASM measurement exports on SwiftShader WebGPU', () => {
  test('app diagnostics carry passTimings and the error ring', async ({ page }) => {
    await bootWasm(page);
    const wasm = await page.evaluate(() => (window as any).__pixelocity__.renderer.getDiagnostics()?.wasm);
    expect(wasm.failedStageName).toBe('Ready');
    expect(wasm.adapterInfo).toContain('timestamp-query');
    expect(Array.isArray(wasm.passTimings)).toBe(true);
    expect(wasm.errors).toEqual(
      expect.objectContaining({ count: expect.any(Number), last: expect.any(String), recent: expect.any(Array) }),
    );
  });

  test('per-slot GPU timestamps, phase timings and the error ring on a live device', async ({ page }) => {
    // A bare same-origin page: the app's own WASM renderer is not needed here,
    // and a second C++ renderer beside its 1024² one crashed the SwiftShader tab.
    await installGpuUncapturedErrorHook(page);
    await page.goto(`http://localhost:${PORT}/wasm/package.json`, { waitUntil: 'load' });
    await page.addScriptTag({ url: '/wasm/pixelocity_wasm.js' });
    await page.waitForFunction(() => typeof (window as any).PixelocityWASM === 'function');

    const result = await page.evaluate(async () => {
      const w = window as any;
      const canvas = document.createElement('canvas');
      canvas.id = 'px-measure-canvas';
      canvas.width = 256;
      canvas.height = 256;
      document.body.appendChild(canvas);

      const M = await w.PixelocityWASM({ locateFile: (p: string) => `/wasm/${p}` });
      const call = (name: string, ret: string | null, types: string[], args: unknown[]) =>
        M.ccall(name, ret, types, args, { async: true });
      const cstr = (s: string) => {
        const n = M.lengthBytesUTF8 ? M.lengthBytesUTF8(s) + 1 : new TextEncoder().encode(s).length + 1;
        const ptr = M._malloc(n);
        M.stringToUTF8(s, ptr, n);
        return ptr;
      };
      const json = (fn: string) => JSON.parse(M.UTF8ToString(M[fn]()));
      const raf = () => new Promise((r) => requestAnimationFrame(() => r(null)));
      const gpuTimings = () => {
        const p = M._malloc(16);
        M.ccall('getGPUTimings', null, ['number', 'number', 'number', 'number'], [p, p + 4, p + 8, p + 12]);
        const out = {
          parallel: M.getValue(p, 'float'),
          chained: M.getValue(p + 4, 'float'),
          total: M.getValue(p + 8, 'float'),
          available: M.getValue(p + 12, 'i32'),
        };
        M._free(p);
        return out;
      };
      const loadShader = async (id: string, wgsl: string) => {
        const idPtr = cstr(id);
        const codePtr = cstr(wgsl);
        try {
          return Number(await call('loadShader', 'number', ['number', 'number'], [idPtr, codePtr]));
        } finally {
          M._free(idPtr);
          M._free(codePtr);
        }
      };

      const before = {
        passes: json('_getPassTimingsJson'),
        ring: json('_getErrorRingJson'),
      };

      const selector = cstr('#px-measure-canvas');
      const init = Number(await call('initWasmRenderer', 'number', ['number', 'number', 'number'], [256, 256, selector]));
      const deadline = performance.now() + 30_000;
      while (performance.now() < deadline && M._isRendererInitialized() !== 1) await raf();
      M._setInputSource(4); // generative

      const ids = ['plasma', 'kaleidoscope'];
      const loaded: Record<string, number> = {};
      for (const id of ids) {
        const code = await (await fetch(`/shaders/${id}.wgsl`)).text();
        loaded[id] = await loadShader(id, code);
      }
      call('setSlotShader', null, ['number', 'string'], [0, 'plasma']);
      call('setSlotShader', null, ['number', 'string'], [1, 'kaleidoscope']);
      call('setSlotMode', null, ['number', 'number'], [1, 1]); // slot 1 parallel

      let passes: any[] = [];
      let frames = 0;
      const renderDeadline = performance.now() + 45_000;
      while (performance.now() < renderDeadline) {
        M._setTime(frames / 60);
        M._updateUniforms();
        frames++;
        await raf();
        passes = json('_getPassTimingsJson');
        if (frames > 10 && passes.length === 2) break;
      }
      const timings = gpuTimings();
      const ringAfterFrames = json('_getErrorRingJson');

      // Invalid WGSL: createShaderModule sits outside LoadShader's error scope,
      // so its validation error is uncaptured and must land in the ring.
      const badLoaded = await loadShader('bad-wgsl', 'fn main( {');
      const ringDeadline = performance.now() + 10_000;
      let ringAfterBad = json('_getErrorRingJson');
      while (performance.now() < ringDeadline && ringAfterBad.count === ringAfterFrames.count) {
        await raf();
        ringAfterBad = json('_getErrorRingJson');
      }
      const lastError = M.UTF8ToString(M._getLastError());
      M._clearErrorRing();
      const ringCleared = json('_getErrorRingJson');
      const lastAfterClear = M.UTF8ToString(M._getLastError());
      M._shutdownWasmRenderer();
      M._free(selector);

      return {
        before, init, loaded, frames, passes, timings, ringAfterFrames,
        badLoaded, ringAfterBad, lastError, ringCleared, lastAfterClear,
      };
    });

    console.log(`[wasm-measurement] ${JSON.stringify({ frames: result.frames, passes: result.passes, timings: result.timings })}`);
    console.log(`[wasm-measurement] ring after bad shader: ${JSON.stringify(result.ringAfterBad)}`);

    // No renderer yet: plain getters still answer.
    expect(result.before.passes).toEqual([]);
    expect(result.before.ring).toEqual({ count: 0, messages: [] });

    expect(result.init).toBe(1);
    expect(result.loaded).toEqual({ plasma: 1, kaleidoscope: 1 });

    // One entry per slot compute pass, keyed by slot + dispatched pipeline.
    expect(result.passes.map((p: any) => [p.slot, p.shaderId, p.label, p.iterations])).toEqual([
      [0, 'plasma', 'plasma', 1],
      [1, 'kaleidoscope', 'kaleidoscope', 1],
    ]);
    for (const p of result.passes) expect(p.gpuMs).toBeGreaterThanOrEqual(0);

    // Phase timings still decode (getGPUTimings unchanged) from the rebuilt phase block.
    expect(result.timings.available).toBe(1);
    expect(result.timings.total).toBeGreaterThan(0);

    // Per-pass stamping must not cost a validation error (double-written query, bad range).
    expect(result.ringAfterFrames).toEqual({ count: 0, messages: [] });

    expect(result.badLoaded).toBe(0);
    expect(result.ringAfterBad.count).toBeGreaterThan(0);
    expect(result.ringAfterBad.messages.length).toBe(Math.min(result.ringAfterBad.count, 16));
    expect(result.lastError).toMatch(/^Validation: /);
    expect(result.lastError).toBe(result.ringAfterBad.messages[result.ringAfterBad.messages.length - 1]);
    expect(result.lastError.length).toBeLessThanOrEqual(255);
    expect(result.ringCleared).toEqual({ count: result.ringAfterBad.count, messages: [] });
    expect(result.lastAfterClear).toBe('');

    // The page-level hook saw the same invalid-module error and nothing else.
    const hooked = await readGpuUncapturedErrors(page);
    expect(hooked.length).toBe(result.ringAfterBad.count);
  });
});
