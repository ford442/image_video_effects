/**
 * @jest-environment jsdom
 *
 * Suspending-export ABI (src/wasm/bridge/call.ts) against both Emscripten builds.
 * No GPU: each mock module reproduces how its build's ccall behaves.
 *
 *  - asyncify: exports that reach WaitAny unwind; ccall returns Asyncify.whenDone()
 *    (a Promise) whether or not { async: true } is passed. Other exports are sync.
 *  - jspi:     JSPI_EXPORTS are WebAssembly.promising-wrapped and always return a
 *    Promise; ccall without { async: true } would hand that Promise back as the value.
 */
import compileFlags from '../contracts/wasm_compile_flags.json';

type Shape = 'asyncify' | 'jspi';
type Deferred = { resolve: (v: unknown) => void; ident: string; args: unknown[] };

const SUSPENDING = new Set(compileFlags.jspi.jspiExports);

function makeModule(shape: Shape) {
  const deferred: Deferred[] = [];
  const log: string[] = [];
  let autoResolve = true;
  const results: Record<string, unknown> = {
    initWasmRenderer: 1,
    loadShader: 1,
    reloadShader: 1,
    getColorFormat: 0,
  };

  const ccall = jest.fn(
    (ident: string, _ret: string | null, _types: string[], args: unknown[], opts?: { async?: boolean }) => {
      log.push(`call:${ident}`);
      if (!SUSPENDING.has(ident)) return results[ident];
      if (shape === 'jspi' && !opts?.async) {
        throw new Error(`test: JSPI export ${ident} ccalled without { async: true }`);
      }
      return new Promise((resolve) => {
        const done = (v: unknown) => {
          log.push(`done:${ident}`);
          resolve(v);
        };
        if (autoResolve) queueMicrotask(() => done(results[ident]));
        else deferred.push({ resolve: done, ident, args });
      });
    },
  );

  const module = {
    ccall,
    _malloc: jest.fn().mockReturnValue(4096),
    _free: jest.fn((ptr: number) => log.push(`free:${ptr}`)),
    getValue: jest.fn().mockReturnValue(0),
    lengthBytesUTF8: (s: string) => s.length,
    stringToUTF8: jest.fn(),
    HEAPU8: { set: jest.fn() },
    HEAPF32: { set: jest.fn() },
  };
  return {
    module,
    ccall,
    log,
    deferred,
    hold() {
      autoResolve = false;
    },
    release() {
      autoResolve = true;
      deferred.splice(0).forEach((d) => d.resolve(results[d.ident]));
    },
  };
}

async function flush() {
  for (let i = 0; i < 5; i++) await Promise.resolve();
}

describe('SUSPENDING_EXPORTS contract', () => {
  it('equals wasm_compile_flags.json jspi.jspiExports', async () => {
    const { SUSPENDING_EXPORTS } = await import('../wasm/bridge/call');
    expect([...SUSPENDING_EXPORTS].sort()).toEqual([...compileFlags.jspi.jspiExports].sort());
  });

  it('artifact file names match the contract graphs', async () => {
    const { WASM_ARTIFACT_JS } = await import('../wasm/bridge/init');
    expect(WASM_ARTIFACT_JS.asyncify).toBe(compileFlags.jsOutputName);
    expect(WASM_ARTIFACT_JS.jspi).toBe(compileFlags.jspi.jsOutputName);
  });
});

describe.each<Shape>(['asyncify', 'jspi'])('bridge over the %s build', (shape) => {
  let mock: ReturnType<typeof makeModule>;
  let bridge: typeof import('../wasm/wasm_bridge');

  beforeEach(() => {
    jest.resetModules();
    mock = makeModule(shape);
    (window as unknown as { PixelocityWASM?: unknown }).PixelocityWASM = jest
      .fn()
      .mockResolvedValue(mock.module);
  });

  async function initBridge() {
    bridge = await import('../wasm/wasm_bridge');
    const canvas = document.createElement('canvas');
    canvas.width = 64;
    canvas.height = 64;
    await expect(bridge.initWasmRenderer(canvas)).resolves.toBe(true);
  }

  afterEach(() => {
    bridge.shutdownWasmRenderer();
    delete (window as unknown as { PixelocityWASM?: unknown }).PixelocityWASM;
  });

  it('ccalls every suspending export with { async: true } and sync exports without', async () => {
    await initBridge();
    await bridge.loadShader('a', 'code');
    await bridge.reloadShader('a', 'code');
    await bridge.resizeCanvas(32, 32);
    await bridge.setColorFormat(1);
    bridge.setInputSource('image');

    const wrongShape = mock.ccall.mock.calls
      .filter(([ident, , , , opts]) => (SUSPENDING.has(ident) ? opts?.async !== true : opts !== undefined))
      .map(([ident]) => ident);
    expect(wrongShape).toEqual([]);
    const called = new Set(mock.ccall.mock.calls.map((c) => c[0]));
    for (const exp of SUSPENDING) expect(called.has(exp)).toBe(true);
  });

  it('loadShader resolves the C++ result and frees buffers only after it settles', async () => {
    await initBridge();
    mock.hold();
    const p = bridge.loadShader('shader-x', 'wgsl');
    await flush();
    expect(mock.module._free).not.toHaveBeenCalled();
    mock.release();
    await expect(p).resolves.toBe(true);
    expect(mock.module._free).toHaveBeenCalledTimes(2);
    const doneAt = mock.log.indexOf('done:loadShader');
    expect(mock.log.findIndex((l) => l.startsWith('free:'))).toBeGreaterThan(doneAt);
  });

  it('serializes overlapping suspending calls', async () => {
    await initBridge();
    mock.hold();
    const a = bridge.resizeCanvas(32, 32);
    const b = bridge.resizeCanvas(48, 48);
    await flush();
    expect(mock.ccall.mock.calls.filter((c) => c[0] === 'resizeCanvas')).toHaveLength(1);
    mock.release();
    await flush();
    mock.release();
    await Promise.all([a, b]);
    const order = mock.log.filter((l) => l.endsWith(':resizeCanvas'));
    expect(order).toEqual(['call:resizeCanvas', 'done:resizeCanvas', 'call:resizeCanvas', 'done:resizeCanvas']);
  });

  it('drops frames and per-frame uploads while suspended, defers image upload', async () => {
    await initBridge();
    mock.hold();
    const p = bridge.resizeCanvas(32, 32);
    await flush();
    mock.ccall.mockClear();

    bridge.updateUniforms({ time: 1 });
    bridge.uploadVideoFrame(new Uint8Array(16), 2, 2);
    bridge.updateDepthMap(new Float32Array(4), 2, 2);
    bridge.uploadImageData(new Uint8Array(16), 2, 2);
    const idents = mock.ccall.mock.calls.map((c) => c[0]);
    expect(idents).not.toContain('updateUniforms');
    expect(idents).not.toContain('uploadVideoFrame');
    expect(idents).not.toContain('updateDepthMap');
    expect(idents).not.toContain('loadImageData');

    mock.release();
    await p;
    expect(mock.ccall.mock.calls.map((c) => c[0])).toContain('loadImageData');

    mock.ccall.mockClear();
    bridge.updateUniforms({ time: 2 });
    expect(mock.ccall.mock.calls.map((c) => c[0])).toContain('updateUniforms');
  });

  it('a rejected suspending call does not wedge the queue', async () => {
    await initBridge();
    mock.ccall.mockImplementationOnce(() => Promise.reject(new Error('trap')));
    await expect(bridge.resizeCanvas(8, 8)).rejects.toThrow('trap');
    await expect(bridge.loadShader('after', 'code')).resolves.toBe(true);
    mock.ccall.mockClear();
    bridge.updateUniforms({ time: 3 });
    expect(mock.ccall.mock.calls.map((c) => c[0])).toContain('updateUniforms');
  });
});

describe('artifact selection', () => {
  const wa = globalThis.WebAssembly as unknown as Record<string, unknown>;
  const saved = { Suspending: wa.Suspending, promising: wa.promising };

  afterEach(() => {
    wa.Suspending = saved.Suspending;
    wa.promising = saved.promising;
    delete (window as unknown as { PixelocityWASM?: unknown }).PixelocityWASM;
    jest.restoreAllMocks();
  });

  function setJspi(on: boolean) {
    wa.Suspending = on ? function Suspending() {} : undefined;
    wa.promising = on ? () => undefined : undefined;
  }

  it('orders JSPI first only when WebAssembly.Suspending + promising exist', async () => {
    jest.resetModules();
    const { wasmArtifactOrder } = await import('../wasm/bridge/init');
    setJspi(true);
    expect(wasmArtifactOrder()).toEqual(['jspi', 'asyncify']);
    setJspi(false);
    expect(wasmArtifactOrder()).toEqual(['asyncify']);
  });

  /** Fake <script> loading: per file name, fail to load or register a factory. */
  function fakeScripts(behaviour: Record<string, 'error' | (() => Promise<unknown>)>) {
    const loaded: string[] = [];
    jest.spyOn(document.head, 'appendChild').mockImplementation(<T extends Node>(node: T): T => {
      const script = node as unknown as HTMLScriptElement;
      const name = script.src.split('/').pop() as string;
      loaded.push(name);
      queueMicrotask(() => {
        const b = behaviour[name];
        if (b === 'error' || !b) {
          script.onerror?.(new Event('error'));
        } else {
          (window as unknown as { PixelocityWASM?: unknown }).PixelocityWASM = b;
          script.onload?.(new Event('load'));
        }
      });
      return node;
    });
    return loaded;
  }

  it.each([
    ['JSPI glue 404s', 'error' as const],
    ['JSPI instantiation rejects', () => Promise.reject(new Error('no JSPI'))],
  ])('falls back to ASYNCIFY when %s', async (_label, jspiBehaviour) => {
    jest.resetModules();
    setJspi(true);
    const asyncify = makeModule('asyncify');
    const loaded = fakeScripts({
      'pixelocity_wasm_jspi.js': jspiBehaviour,
      'pixelocity_wasm.js': () => Promise.resolve(asyncify.module),
    });
    const bridge = await import('../wasm/wasm_bridge');
    const canvas = document.createElement('canvas');
    await expect(bridge.initWasmRenderer(canvas)).resolves.toBe(true);
    expect(loaded).toEqual(['pixelocity_wasm_jspi.js', 'pixelocity_wasm.js']);
    expect(bridge.getDiagnostics().wasmArtifact).toBe('asyncify');
    bridge.shutdownWasmRenderer();
  });

  it('loads only the ASYNCIFY build when JSPI is absent', async () => {
    jest.resetModules();
    setJspi(false);
    const asyncify = makeModule('asyncify');
    const loaded = fakeScripts({ 'pixelocity_wasm.js': () => Promise.resolve(asyncify.module) });
    const bridge = await import('../wasm/wasm_bridge');
    await expect(bridge.initWasmRenderer(document.createElement('canvas'))).resolves.toBe(true);
    expect(loaded).toEqual(['pixelocity_wasm.js']);
    bridge.shutdownWasmRenderer();
  });

  it('uses the JSPI build when available', async () => {
    jest.resetModules();
    setJspi(true);
    const jspi = makeModule('jspi');
    const loaded = fakeScripts({ 'pixelocity_wasm_jspi.js': () => Promise.resolve(jspi.module) });
    const bridge = await import('../wasm/wasm_bridge');
    await expect(bridge.initWasmRenderer(document.createElement('canvas'))).resolves.toBe(true);
    expect(loaded).toEqual(['pixelocity_wasm_jspi.js']);
    expect(bridge.getDiagnostics().wasmArtifact).toBe('jspi');
    bridge.shutdownWasmRenderer();
  });

  it('reports failure when no build loads', async () => {
    jest.resetModules();
    setJspi(true);
    fakeScripts({});
    const bridge = await import('../wasm/wasm_bridge');
    await expect(bridge.initWasmRenderer(document.createElement('canvas'))).resolves.toBe(false);
    expect(bridge.getDiagnostics().lastLoadError).toMatch(/pixelocity_wasm\.js/);
  });
});
