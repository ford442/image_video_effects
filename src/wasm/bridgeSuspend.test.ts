/**
 * #1400 H1: async exports suspend under ASYNCIFY. The call seam (bridge/call.ts)
 * awaits them with { async: true }, runs them one at a time, and applies each
 * sync export's contract `whileSuspended` policy in the meantime.
 */

import * as cpp from './bridge/_generated';
import { getSeamDiagnostics, isSuspended, runWhenIdle } from './bridge/call';
import { loadShader, setSlotShader } from './bridge/shader';
import { state, wasmRef, type EmscriptenModule } from './bridge/state';
import { updateUniforms } from './bridge/uniforms';
import { resizeCanvas, uploadImageData } from './bridge/capture';
import exportsContract from '../contracts/wasm_exports.json';

function deferred<T>() {
  let resolve!: (v: T) => void;
  const promise = new Promise<T>((r) => { resolve = r; });
  return { promise, resolve };
}

const flush = async () => {
  for (let i = 0; i < 10; i++) await Promise.resolve(); // eslint-disable-line no-await-in-loop
};

/** Async exports return a pending promise the test resolves; sync ones answer from `values`. */
function fakeModule(values: Record<string, unknown> = {}) {
  const log: string[] = [];
  const pending: Record<string, ReturnType<typeof deferred<number>>[]> = {};
  const asyncNames = new Set<string>(cpp.ASYNC_EXPORTS);
  const mod = {
    ccall: jest.fn((name: string, _r: unknown, _t: unknown, args: unknown[], opts?: { async?: boolean }) => {
      log.push(name);
      if (asyncNames.has(name)) {
        expect(opts).toEqual({ async: true });
        const d = deferred<number>();
        (pending[name] ??= []).push(d);
        return d.promise;
      }
      expect(opts).toBeUndefined();
      const v = values[name];
      return typeof v === 'function' ? (v as (...a: unknown[]) => unknown)(...args) : v ?? 0;
    }),
    _malloc: jest.fn(() => 64),
    _free: jest.fn(),
    getValue: jest.fn(() => 0),
    lengthBytesUTF8: (s: string) => s.length,
    stringToUTF8: jest.fn(),
    HEAPU8: new Uint8Array(1 << 16),
    HEAPF32: new Float32Array(16),
  } as EmscriptenModule & { ccall: jest.Mock; _free: jest.Mock };
  return { mod, log, pending };
}

describe('generated wrappers', () => {
  it('cover every contract export, async ones included', () => {
    const names = Object.keys(exportsContract.exports);
    for (const name of names) expect(typeof (cpp as Record<string, unknown>)[name]).toBe('function');
    const asyncInContract = names.filter((n) => (exportsContract.exports as Record<string, { async?: boolean }>)[n]!.async);
    expect([...cpp.ASYNC_EXPORTS].sort()).toEqual(asyncInContract.sort());
  });

  it('setActiveShader is void in C++ and in the wrapper (no NaN result to misread)', () => {
    const { mod } = fakeModule();
    expect(cpp.setActiveShader(mod, 'x')).toBeUndefined();
    expect(mod.ccall).toHaveBeenCalledWith('setActiveShader', null, ['string'], ['x']);
  });
});

describe('call seam', () => {
  it('runs async exports one at a time and resolves with the C++ result', async () => {
    const { mod, log, pending } = fakeModule();
    const a = cpp.resizeCanvas(mod, 256, 256);
    const b = cpp.setColorFormat(mod, 1);
    await flush();
    expect(log).toEqual(['resizeCanvas']);
    expect(isSuspended(mod)).toBe(true);

    pending.resizeCanvas![0]!.resolve(0);
    await a;
    await flush();
    expect(log).toEqual(['resizeCanvas', 'setColorFormat']);
    pending.setColorFormat![0]!.resolve(0);
    await b;
    expect(isSuspended(mod)).toBe(false);
  });

  it('applies whileSuspended: call runs, skip drops, queue runs afterwards in order', async () => {
    const { mod, log, pending } = fakeModule({ getFPS: 60 });
    const resize = cpp.resizeCanvas(mod, 512, 512);

    expect(cpp.getFPS(mod)).toBe(60); // call
    cpp.updateUniforms(mod); // skip
    cpp.setSlotShader(mod, 0, 'a'); // queue
    cpp.setInputSource(mod, 4); // queue
    expect(log).toEqual(['resizeCanvas', 'getFPS']);
    expect(getSeamDiagnostics(mod)).toMatchObject({ active: 'resizeCanvas', queued: 2, skipped: { updateUniforms: 1 } });

    pending.resizeCanvas![0]!.resolve(0);
    await resize;
    await flush();
    expect(log).toEqual(['resizeCanvas', 'getFPS', 'setSlotShader', 'setInputSource']);

    cpp.updateUniforms(mod);
    expect(log[log.length - 1]).toBe('updateUniforms');
  });

  it('runWhenIdle runs now when idle, after the suspended call otherwise', async () => {
    const { mod, pending } = fakeModule();
    const order: string[] = [];
    await runWhenIdle(mod, () => order.push('idle'));
    const resize = cpp.resizeCanvas(mod, 64, 64);
    const later = runWhenIdle(mod, () => order.push('after'));
    expect(order).toEqual(['idle']);
    pending.resizeCanvas![0]!.resolve(0);
    await resize;
    await later;
    expect(order).toEqual(['idle', 'after']);
  });

  it('keeps one module’s stuck init from blocking another module', async () => {
    const stuck = fakeModule();
    void cpp.initWasmRenderer(stuck.mod, 1, 1, '#c');
    const fresh = fakeModule({ getFPS: 30 });
    cpp.updateUniforms(fresh.mod);
    expect(fresh.log).toEqual(['updateUniforms']);
  });
});

describe('bridge on the seam', () => {
  const prev = { initialized: state.initialized, module: wasmRef.module };
  beforeEach(() => {
    jest.spyOn(console, 'log').mockImplementation(() => {});
    jest.spyOn(console, 'warn').mockImplementation(() => {});
    jest.spyOn(console, 'error').mockImplementation(() => {});
  });
  afterEach(() => {
    state.initialized = prev.initialized;
    wasmRef.module = prev.module;
    jest.restoreAllMocks();
  });

  it('loadShader keeps id/code allocated until C++ returns, and reads its real result', async () => {
    const { mod, pending } = fakeModule({ getColorFormat: 0, getSlotShaderId: 'plasma' });
    state.initialized = true;
    wasmRef.module = mod;

    const load = loadShader('plasma', '@compute @workgroup_size(8u, 4) fn main() {}');
    await flush();
    const call = mod.ccall.mock.calls.find((c) => c[0] === 'loadShader')!;
    expect(call[3].slice(2)).toEqual([8, 4, 0]); // workgroup from the TS analysis, no usage bits
    expect(mod._free).not.toHaveBeenCalled();

    // Frames are skipped and the slot assignment waits for the pipeline.
    updateUniforms(1);
    expect(setSlotShader(0, 'plasma')).toBe(true);
    expect(mod.ccall.mock.calls.map((c) => c[0])).not.toContain('updateUniforms');
    expect(mod.ccall.mock.calls.map((c) => c[0])).not.toContain('setSlotShader');

    pending.loadShader![0]!.resolve(1);
    await expect(load).resolves.toBe(true);
    await flush();
    expect(mod._free).toHaveBeenCalledTimes(2);
    expect(mod.ccall.mock.calls.map((c) => c[0])).toContain('setSlotShader');
    expect(state.droppedSlots.has(0)).toBe(false);
  });

  it('resizeCanvas resolves false when C++ could not rebuild the textures (H2)', async () => {
    const { mod, pending } = fakeModule();
    state.initialized = true;
    wasmRef.module = mod;
    const resize = resizeCanvas(4096, 4096);
    await flush();
    pending.resizeCanvas![0]!.resolve(0);
    await expect(resize).resolves.toBe(false);
  });

  it('a failed loadShader reports false instead of NaN-as-failure-after-success', async () => {
    const { mod, pending } = fakeModule({ getColorFormat: 0 });
    state.initialized = true;
    wasmRef.module = mod;
    const load = loadShader('bad', '@compute @workgroup_size(16, 16) fn main() {}');
    await flush();
    pending.loadShader![0]!.resolve(0);
    await expect(load).resolves.toBe(false);
  });

  it('defers a still image that arrives during a resize, on a copy of the pixels', async () => {
    const { mod, pending } = fakeModule();
    state.initialized = true;
    wasmRef.module = mod;
    const resize = resizeCanvas(32, 32);
    const pixels = new Uint8Array(4 * 4 * 4).fill(7);
    uploadImageData(pixels, 4, 4);
    pixels.fill(0); // the caller reuses its buffer
    expect(mod.ccall.mock.calls.map((c) => c[0])).not.toContain('loadImageData');

    pending.resizeCanvas![0]!.resolve(1);
    await expect(resize).resolves.toBe(true);
    await flush();
    expect(mod.ccall.mock.calls.map((c) => c[0])).toContain('loadImageData');
    expect(Array.from(mod.HEAPU8.subarray(64, 64 + 64))).toEqual(new Array(64).fill(7));
  });
});
