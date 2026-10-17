/**
 * @jest-environment jsdom
 *
 * initWasmRenderer is an async export: under ASYNCIFY, CreateDevice() suspends
 * in wgpuInstanceWaitAny and a plain ccall hands back Emscripten's Promise as
 * if it were the result (truthy, so "ready" with no device). The bridge must
 * ccall it with { async: true }, report ready only when that promise resolves
 * to 1, and never shut the instance down while it is still suspended.
 */

type CppState = { initialized: number; stage: number };

function deferred<T>() {
  let resolve!: (v: T) => void;
  const promise = new Promise<T>((r) => { resolve = r; });
  return { promise, resolve };
}

function fakeModule(cpp: CppState) {
  const calls: string[] = [];
  const initCall = deferred<number>();
  const opts: unknown[] = [];
  const mod = {
    ccall: jest.fn((name: string, _ret: unknown, _types: unknown, _args: unknown, o?: unknown) => {
      calls.push(name);
      switch (name) {
        case 'initWasmRenderer':
          opts.push(o);
          return initCall.promise; // what Emscripten's ccall returns once the export suspends
        case 'isRendererInitialized':
          return cpp.initialized;
        case 'getLastInitErrorStage':
          return cpp.stage;
        case 'getLastInitErrorMessage':
          return cpp.stage === 2 ? 'adapter requests timed out' : '';
        case 'getAdapterSummary':
          return '';
        case 'getColorFormat':
          return 0;
        case 'getMaxShaderSlots':
          return 6;
        default:
          return 0;
      }
    }),
    _getMaxShaderSlots: () => 6,
  };
  return { mod, calls, initCall, opts };
}

async function loadBridge(cpp: CppState) {
  jest.resetModules();
  const fake = fakeModule(cpp);
  (window as any).PixelocityWASM = jest.fn(() => Promise.resolve(fake.mod));
  const init = await import('../wasm/bridge/init');
  const diagnostics = await import('../wasm/bridge/diagnostics');
  return { init, diagnostics, ...fake };
}

function canvas(): HTMLCanvasElement {
  const c = document.createElement('canvas');
  c.width = 256;
  c.height = 256;
  document.body.appendChild(c);
  return c;
}

async function flushMicrotasks() {
  for (let i = 0; i < 20; i++) await Promise.resolve(); // eslint-disable-line no-await-in-loop
}

/** Advance fake time in steps, flushing the promise chain between them (Jest 27). */
async function advance(ms: number) {
  for (let t = 0; t < ms; t += 50) {
    await flushMicrotasks(); // eslint-disable-line no-await-in-loop
    jest.advanceTimersByTime(50);
    await flushMicrotasks(); // eslint-disable-line no-await-in-loop
  }
}

describe('WASM bridge init gate', () => {
  beforeEach(() => {
    jest.useFakeTimers('modern');
    jest.spyOn(performance, 'now').mockImplementation(() => Date.now());
    jest.spyOn(console, 'log').mockImplementation(() => {});
    jest.spyOn(console, 'error').mockImplementation(() => {});
    jest.spyOn(console, 'warn').mockImplementation(() => {});
  });
  afterEach(() => {
    jest.useRealTimers();
    jest.restoreAllMocks();
    delete (window as any).PixelocityWASM;
  });

  it('ccalls init with { async: true } and is ready only when it resolves to 1', async () => {
    const cpp = { initialized: 0, stage: 0 };
    const { init, opts, initCall } = await loadBridge(cpp);
    let settled: boolean | null = null;
    void init.initWasmRenderer(canvas()).then((ok) => { settled = ok; });

    await advance(1_000);
    expect(opts).toEqual([{ async: true }]);
    // The pending promise is truthy; the old sync ccall treated it as success.
    expect(settled).toBeNull();
    expect(init.isInitialized()).toBe(false);

    cpp.initialized = 1;
    cpp.stage = 8;
    initCall.resolve(1);
    await advance(100);
    expect(settled).toBe(true);
    expect(init.isInitialized()).toBe(true);
  });

  it('resolves false at the C++ failure stage without calling shutdown', async () => {
    const cpp = { initialized: 0, stage: 0 };
    const { init: bridge, diagnostics, calls, initCall } = await loadBridge(cpp);
    let settled: boolean | null = null;
    void bridge.initWasmRenderer(canvas()).then((ok) => { settled = ok; });

    await advance(500);
    cpp.stage = 2; // every adapter WaitAny timed out → C++ ran its own Shutdown()
    initCall.resolve(0);
    await advance(100);
    expect(settled).toBe(false);
    expect(bridge.isInitialized()).toBe(false);
    expect(calls).not.toContain('shutdownWasmRenderer');
    const d = diagnostics.getDiagnostics();
    expect(d.failedStageName).toBe('Adapter');
    expect(d.lastInitError).toContain('timed out');
  });

  it('times out without touching the suspended module, then reaps it once init returns', async () => {
    const cpp = { initialized: 0, stage: 0 };
    const { init: bridge, diagnostics, calls, initCall } = await loadBridge(cpp);
    let settled: boolean | null = null;
    void bridge.initWasmRenderer(canvas()).then((ok) => { settled = ok; });

    await advance(bridge.CPP_INIT_TIMEOUT_MS + 100);
    expect(settled).toBe(false);
    expect(bridge.isInitialized()).toBe(false);
    const d = diagnostics.getDiagnostics();
    expect(d.failedStageName).toBe('Timeout');
    expect(d.hasModule).toBe(false);
    expect(d.lastInitError).toMatch(/still pending/);
    // Nothing but the init call itself reached C++ while it was suspended.
    expect(calls).toEqual(['initWasmRenderer']);

    // Bridge-level shutdown is a no-op: nothing was initialized.
    bridge.shutdownWasmRenderer();
    await advance(5_000);
    expect(calls).not.toContain('shutdownWasmRenderer');

    cpp.initialized = 1; // the WaitAny finally resolved
    cpp.stage = 8;
    initCall.resolve(1);
    await advance(100);
    expect(calls.filter((c) => c === 'shutdownWasmRenderer')).toHaveLength(1);
  });
});
