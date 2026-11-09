/**
 * Async exports suspend in wgpuInstanceWaitAny under both builds. The call seam
 * (bridge/call.ts) awaits them with { async: true }, runs them one at a time per
 * module, and applies each sync export's contract `whileSuspended` policy
 * (src/contracts/wasm_exports.json `exports`) in the meantime.
 */
import { vi, type Mock } from 'vitest';
import * as cpp from './bridge/_generated';
import { abandonSeam, getSeamDiagnostics, isBusy, isSuspended, runWhenIdle } from './bridge/call';
import { captureFrame, resizeCanvas, uploadImageData, uploadVideoFrame } from './bridge/capture';
import { readErrorRing } from './bridge/diagnostics';
import { shutdownWasmRenderer } from './bridge/init';
import { loadShader, setActiveShader, setSlotShader } from './bridge/shader';
import { state, wasmRef, type EmscriptenModule } from './bridge/state';
import { setInputSource, updateDepthMap, updateUniforms } from './bridge/uniforms';
import exportsContract from '../contracts/wasm_exports.json';
import compileFlags from '../contracts/wasm_compile_flags.json';

type ExportEntry = { returns: string; args: string[]; async?: boolean; whileSuspended?: string; optional?: boolean };
const EXPORTS = exportsContract.exports as Record<string, ExportEntry>;

function deferred<T>() {
  let resolve!: (v: T) => void;
  let reject!: (e: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

const flush = async () => {
  for (let i = 0; i < 10; i++) await Promise.resolve();
};

type FakeModule = EmscriptenModule & { ccall: Mock; _free: Mock; _malloc: Mock };

/** Async exports return a pending promise the test settles; sync ones answer from `values`. */
function fakeModule(values: Record<string, unknown> = {}) {
  const log: string[] = [];
  const pending: Record<string, ReturnType<typeof deferred<unknown>>[]> = {};
  const asyncNames = new Set<string>(cpp.ASYNC_EXPORTS);
  let nextPtr = 64;
  const mod = {
    ccall: vi.fn((name: string, _r: unknown, _t: unknown, args: unknown[], opts?: { async?: boolean }) => {
      log.push(name);
      if (asyncNames.has(name)) {
        if (opts?.async !== true) throw new Error(`test: async export ${name} ccalled without { async: true }`);
        const d = deferred<unknown>();
        (pending[name] ??= []).push(d);
        return d.promise;
      }
      if (opts !== undefined) throw new Error(`test: sync export ${name} ccalled with opts`);
      const v = values[name];
      // Absent → undefined; the generated wrappers coerce it (0 / '').
      return typeof v === 'function' ? (v as (...a: unknown[]) => unknown)(...args) : v;
    }),
    _malloc: vi.fn((n: number) => {
      const ptr = nextPtr;
      nextPtr += Math.ceil(n / 64) * 64 + 64;
      return ptr;
    }),
    _free: vi.fn(),
    getValue: vi.fn(() => 0),
    lengthBytesUTF8: (s: string) => s.length,
    stringToUTF8: vi.fn(),
    HEAPU8: new Uint8Array(1 << 16),
    HEAPF32: new Float32Array(1 << 14),
  } as unknown as FakeModule;
  const names = () => mod.ccall.mock.calls.map((c) => c[0] as string);
  return { mod, log, pending, names };
}

describe('generated wrappers (contract surface)', () => {
  it('cover every contract export; ASYNC_EXPORTS is the async set and equals jspi.jspiExports', () => {
    const names = Object.keys(EXPORTS);
    expect([...cpp.EXPORT_NAMES]).toEqual(names);
    for (const name of names) expect(typeof (cpp as Record<string, unknown>)[name]).toBe('function');
    const asyncInContract = names.filter((n) => EXPORTS[n]?.async === true).sort();
    expect([...cpp.ASYNC_EXPORTS].sort()).toEqual(asyncInContract);
    expect([...cpp.ASYNC_EXPORTS].sort()).toEqual([...compileFlags.jspi.jspiExports].sort());
  });

  it('marshal each argument by its contract type (string → ccall string, pointers/ints/floats → number)', () => {
    const { mod } = fakeModule();
    cpp.setSlotShader(mod, 2, 'plasma');
    cpp.updateDepthMap(mod, 128, 4, 4);
    cpp.setSlotParams(mod, 1, 0.1, 0.2, 0.3, 0.4);
    expect(mod.ccall).toHaveBeenCalledWith('setSlotShader', null, ['number', 'string'], [2, 'plasma']);
    expect(mod.ccall).toHaveBeenCalledWith('updateDepthMap', null, ['number', 'number', 'number'], [128, 4, 4]);
    expect(mod.ccall).toHaveBeenCalledWith(
      'setSlotParams',
      null,
      ['number', 'number', 'number', 'number', 'number'],
      [1, 0.1, 0.2, 0.3, 0.4],
    );
  });

  it('setActiveShader is void in C++ and in the wrapper (no NaN result to misread)', () => {
    const { mod } = fakeModule();
    expect(cpp.setActiveShader(mod, 'x')).toBeUndefined();
    expect(mod.ccall).toHaveBeenCalledWith('setActiveShader', null, ['string'], ['x']);
  });

  it('coerce numeric and string returns', () => {
    const { mod } = fakeModule({ getFPS: 59.5, getSlotShaderId: undefined, getColorFormat: null });
    expect(cpp.getFPS(mod)).toBe(59.5);
    expect(cpp.getSlotShaderId(mod, 0)).toBe('');
    expect(cpp.getColorFormat(mod)).toBe(0);
  });

  it('optional exports return null on an artifact without them and call _<name> directly otherwise', () => {
    const { mod } = fakeModule();
    expect(cpp.getMaxShaderSlots(mod)).toBeNull();
    expect(cpp.getPassTimingsJson(mod)).toBeNull();

    const strings = new Map([[512, '[{"label":"a","gpuMs":1}]']]);
    const withExports = Object.assign(mod, {
      _getMaxShaderSlots: vi.fn(() => 8),
      _getPassTimingsJson: vi.fn(() => 512),
      UTF8ToString: vi.fn((ptr: number) => strings.get(ptr) ?? ''),
    });
    expect(cpp.getMaxShaderSlots(withExports)).toBe(8);
    expect(cpp.getPassTimingsJson(withExports)).toBe('[{"label":"a","gpuMs":1}]');
    expect(mod.ccall).not.toHaveBeenCalled();
  });
});

describe('call seam', () => {
  it('runs async exports one at a time and resolves with the C++ result', async () => {
    const { mod, log, pending } = fakeModule();
    const a = cpp.loadShader(mod, 64, 128, 16, 16, 0);
    const b = cpp.setColorFormat(mod, 1);
    await flush();
    expect(log).toEqual(['loadShader']);
    expect(isSuspended(mod)).toBe(true);

    pending.loadShader![0]!.resolve(1);
    await expect(a).resolves.toBe(1);
    expect(log).toEqual(['loadShader', 'setColorFormat']);
    pending.setColorFormat![0]!.resolve(undefined);
    await expect(b).resolves.toBeUndefined();
    expect(isSuspended(mod)).toBe(false);
    expect(isBusy(mod)).toBe(false);
  });

  it('applies whileSuspended: call runs, skip drops, queue runs afterwards in order', async () => {
    const { mod, log, pending } = fakeModule({ getFPS: 60 });
    const resize = cpp.resizeCanvas(mod, 512, 512);

    expect(cpp.getFPS(mod)).toBe(60); // call
    cpp.updateUniforms(mod); // skip
    cpp.setSlotShader(mod, 0, 'a'); // queue
    cpp.setInputSource(mod, 4); // queue
    expect(log).toEqual(['resizeCanvas', 'getFPS']);
    expect(getSeamDiagnostics(mod)).toMatchObject({
      active: 'resizeCanvas',
      queued: 2,
      skipped: { updateUniforms: 1 },
    });

    pending.resizeCanvas![0]!.resolve(undefined);
    await resize;
    expect(log).toEqual(['resizeCanvas', 'getFPS', 'setSlotShader', 'setInputSource']);

    cpp.updateUniforms(mod);
    expect(log[log.length - 1]).toBe('updateUniforms');
  });

  it('queued work has landed by the time the awaiting caller resumes', async () => {
    const { mod, log, pending } = fakeModule();
    const resize = cpp.resizeCanvas(mod, 8, 8);
    cpp.setInputSource(mod, 2);
    const seenAfterAwait: string[][] = [];
    const caller = resize.then(() => seenAfterAwait.push([...log]));
    pending.resizeCanvas![0]!.resolve(undefined);
    await caller;
    expect(seenAfterAwait[0]).toEqual(['resizeCanvas', 'setInputSource']);
  });

  it('a queued call made inside a draining task runs now, not behind later queued work', async () => {
    const { mod, log, pending } = fakeModule({ getSlotShaderId: 'a' });
    const resize = cpp.resizeCanvas(mod, 8, 8);
    const readBack: string[] = [];
    void runWhenIdle(mod, () => {
      cpp.setSlotShader(mod, 0, 'a'); // queue policy, but we are the running task
      readBack.push(log[log.length - 1]!);
    });
    cpp.setInputSource(mod, 1); // queued after the task above
    pending.resizeCanvas![0]!.resolve(undefined);
    await resize;
    expect(readBack).toEqual(['setSlotShader']);
    expect(log).toEqual(['resizeCanvas', 'setSlotShader', 'setInputSource']);
  });

  it('runWhenIdle runs now when idle, after the suspended call otherwise', async () => {
    const { mod, pending } = fakeModule();
    const order: string[] = [];
    await runWhenIdle(mod, () => order.push('idle'));
    expect(order).toEqual(['idle']);
    const resize = cpp.resizeCanvas(mod, 64, 64);
    const later = runWhenIdle(mod, () => order.push('after'));
    expect(order).toEqual(['idle']);
    pending.resizeCanvas![0]!.resolve(undefined);
    await resize;
    await later;
    expect(order).toEqual(['idle', 'after']);
  });

  it('a rejected async export does not wedge the queue', async () => {
    const { mod, log, pending } = fakeModule();
    const bad = cpp.reloadShader(mod, 1, 2, 16, 16, 0);
    const next = cpp.loadShader(mod, 3, 4, 16, 16, 0);
    pending.reloadShader![0]!.reject(new Error('trap'));
    await expect(bad).rejects.toThrow('trap');
    expect(log).toEqual(['reloadShader', 'loadShader']);
    pending.loadShader![0]!.resolve(1);
    await expect(next).resolves.toBe(1);
  });

  it('keeps one module’s stuck init from blocking another module', () => {
    const stuck = fakeModule();
    void cpp.initWasmRenderer(stuck.mod, 1, 1, '#c');
    expect(isSuspended(stuck.mod)).toBe(true);
    const fresh = fakeModule();
    cpp.updateUniforms(fresh.mod);
    expect(fresh.log).toEqual(['updateUniforms']);
    expect(isSuspended(fresh.mod)).toBe(false);
  });

  it('abandonSeam drops a never-settling call so queued shutdown can run (init reaper)', async () => {
    const err = vi.spyOn(console, 'error').mockImplementation(() => {});
    const { mod, log } = fakeModule();
    void cpp.initWasmRenderer(mod, 1, 1, '#c');
    const queued = runWhenIdle(mod, () => 'never');
    cpp.shutdownWasmRenderer(mod); // queued behind the stuck init
    expect(log).toEqual(['initWasmRenderer']);
    abandonSeam(mod);
    await expect(queued).rejects.toThrow(/abandoned/);
    cpp.shutdownWasmRenderer(mod);
    expect(log).toEqual(['initWasmRenderer', 'shutdownWasmRenderer']);
    expect(err).toHaveBeenCalledWith('[WASM] queued shutdownWasmRenderer threw:', expect.any(Error));
    err.mockRestore();
  });
});

describe('bridge on the seam', () => {
  const prev = { initialized: state.initialized, module: wasmRef.module, canvas: wasmRef.canvas };
  beforeEach(() => {
    vi.spyOn(console, 'log').mockImplementation(() => {});
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    vi.spyOn(console, 'error').mockImplementation(() => {});
    state.droppedSlots.clear();
    state.activeShader = null;
  });
  afterEach(() => {
    state.initialized = prev.initialized;
    wasmRef.module = prev.module;
    wasmRef.canvas = prev.canvas;
    vi.restoreAllMocks();
  });

  function attach(values: Record<string, unknown> = {}) {
    const fake = fakeModule({ getColorFormat: 0, ...values });
    state.initialized = true;
    wasmRef.module = fake.mod;
    return fake;
  }

  it('loadShader keeps id/code allocated until C++ returns; a slot assignment made meanwhile lands after it', async () => {
    let slot0 = '';
    const { mod, pending, names } = attach({
      setSlotShader: (_i: unknown, id: unknown) => {
        slot0 = String(id);
      },
      getSlotShaderId: () => slot0,
    });

    const load = loadShader('plasma', '@compute @workgroup_size(8, 8) fn main() {}');
    await flush();
    const call = mod.ccall.mock.calls.find((c) => c[0] === 'loadShader')!;
    expect(call[2]).toEqual(['number', 'number', 'number', 'number', 'number']);
    expect(mod._free).not.toHaveBeenCalled();

    // Frames are skipped and the slot assignment waits for the pipeline.
    expect(updateUniforms(1)).toBe(false);
    expect(setSlotShader(0, 'plasma')).toBe(true);
    expect(names()).not.toContain('updateUniforms');
    expect(names()).not.toContain('setSlotShader');

    pending.loadShader![0]!.resolve(1);
    await expect(load).resolves.toBe(true);
    expect(mod._free).toHaveBeenCalledTimes(2);
    expect(names()).toContain('setSlotShader');
    expect(state.droppedSlots.has(0)).toBe(false);
  });

  it('a failed loadShader reports false', async () => {
    const { pending } = attach();
    const load = loadShader('bad', '@compute @workgroup_size(16, 16) fn main() {}');
    await flush();
    pending.loadShader![0]!.resolve(0);
    await expect(load).resolves.toBe(false);
  });

  it('setActiveShader reads slot 0 back instead of the void return', async () => {
    let slot0 = '';
    const { pending } = attach({
      setActiveShader: (id: unknown) => {
        slot0 = String(id);
      },
      getSlotShaderId: () => slot0,
    });
    setActiveShader('a');
    expect(state.activeShader).toBe('a');

    const resize = resizeCanvas(16, 16);
    setActiveShader('b'); // waits for the resize
    expect(state.activeShader).toBe('a');
    pending.resizeCanvas![0]!.resolve(undefined);
    await resize;
    expect(state.activeShader).toBe('b');
  });

  it('defers a still image that arrives during a resize, on a copy of the pixels', async () => {
    const { mod, pending, names } = attach();
    const resize = resizeCanvas(32, 32);
    const pixels = new Uint8Array(4 * 4 * 4).fill(7);
    uploadImageData(pixels, 4, 4);
    pixels.fill(0); // the caller reuses its buffer
    expect(names()).not.toContain('loadImageData');

    pending.resizeCanvas![0]!.resolve(undefined);
    await resize;
    const call = mod.ccall.mock.calls.find((c) => c[0] === 'loadImageData')!;
    const ptr = (call[3] as number[])[0]!;
    expect(Array.from(mod.HEAPU8.subarray(ptr, ptr + 64))).toEqual(new Array(64).fill(7));
  });

  it('defers a depth map that arrives during a resize instead of dropping it; drops video frames', async () => {
    const { mod, pending, names } = attach();
    const resize = resizeCanvas(32, 32);
    const depth = new Float32Array([0.25, 0.5, 0.75, 1]);
    updateDepthMap(depth, 2, 2);
    depth.fill(0);
    uploadVideoFrame(new Uint8Array(16), 2, 2);
    expect(names()).not.toContain('updateDepthMap');

    pending.resizeCanvas![0]!.resolve(undefined);
    await resize;
    const call = mod.ccall.mock.calls.find((c) => c[0] === 'updateDepthMap')!;
    const ptr = (call[3] as number[])[0]!;
    expect(Array.from(mod.HEAPF32.subarray(ptr / 4, ptr / 4 + 4))).toEqual([0.25, 0.5, 0.75, 1]);
    expect(names()).not.toContain('uploadVideoFrame');
  });

  it('setInputSource and shutdown wait for a suspended call', async () => {
    const { pending, names } = attach();
    const resize = resizeCanvas(32, 32);
    setInputSource('video');
    shutdownWasmRenderer();
    expect(names()).toEqual(['resizeCanvas']);
    expect(wasmRef.module).toBeNull(); // the bridge lets go at once
    pending.resizeCanvas![0]!.resolve(undefined);
    await resize;
    expect(names()).toEqual(['resizeCanvas', 'setInputSource', 'shutdownWasmRenderer']);
  });

  it('captureFrame begins only once a suspended resize has settled', async () => {
    const raf = vi.spyOn(globalThis, 'requestAnimationFrame').mockImplementation(() => 0);
    const { pending, names } = attach();
    const resize = resizeCanvas(32, 32);
    const capture = captureFrame();
    capture.catch(() => {});
    expect(names()).not.toContain('beginFrameCapture');
    pending.resizeCanvas![0]!.resolve(undefined);
    await resize;
    expect(names()).toContain('beginFrameCapture');
    expect(raf).toHaveBeenCalled();
  });

  it('measurement readers go through the optional wrappers', () => {
    const { mod } = attach();
    expect(readErrorRing()).toEqual({ count: 0, last: '', recent: [] });
    const strings = new Map([
      [8, '{"count":2,"messages":["a","b"]}'],
      [16, 'b'],
    ]);
    Object.assign(mod, {
      _getErrorRingJson: () => 8,
      _getLastError: () => 16,
      UTF8ToString: (p: number) => strings.get(p) ?? '',
    });
    expect(readErrorRing()).toEqual({ count: 2, last: 'b', recent: ['a', 'b'] });
  });
});
