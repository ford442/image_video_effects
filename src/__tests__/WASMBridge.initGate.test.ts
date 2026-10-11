/**
 * @jest-environment jsdom
 *
 * The ASYNCIFY init ccall returns while C++ CreateDevice() is still suspended in
 * wgpuInstanceWaitAny. The bridge must not report ready (or let anyone shut the
 * instance down) until C++ itself settles: ready, failed at a stage, or the
 * bridge backstop times out and hands the module to the reaper.
 */

type CppState = { initialized: number; stage: number };

function fakeModule(cpp: CppState) {
  const calls: string[] = [];
  const mod = {
    ccall: jest.fn((name: string) => {
      calls.push(name);
      switch (name) {
        case 'initWasmRenderer':
          return 1; // what an unwound ASYNCIFY export hands back: meaningless
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
        default:
          return 0;
      }
    }),
    _getMaxShaderSlots: () => 6,
  };
  return { mod, calls };
}

const POLLS = new Set(['isRendererInitialized', 'getLastInitErrorStage']);

async function loadBridge(cpp: CppState) {
  jest.resetModules();
  const { mod, calls } = fakeModule(cpp);
  (window as any).PixelocityWASM = jest.fn(() => Promise.resolve(mod));
  const init = await import('../wasm/bridge/init');
  const diagnostics = await import('../wasm/bridge/diagnostics');
  return { init, diagnostics, calls };
}

function canvas(): HTMLCanvasElement {
  const c = document.createElement('canvas');
  c.width = 256;
  c.height = 256;
  document.body.appendChild(c);
  return c;
}

/** Advance fake time in poll-sized steps, flushing the promise chain between them (Jest 27). */
async function advance(ms: number) {
  for (let t = 0; t < ms; t += 50) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
    jest.advanceTimersByTime(50);
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
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

  it('resolves true only once C++ reports Ready', async () => {
    const cpp = { initialized: 0, stage: 0 };
    const { init } = await loadBridge(cpp);
    let settled: boolean | null = null;
    void init.initWasmRenderer(canvas()).then((ok) => { settled = ok; });

    await advance(1_000);
    expect(settled).toBeNull();
    expect(init.isInitialized()).toBe(false);

    cpp.initialized = 1;
    cpp.stage = 8;
    await advance(100);
    expect(settled).toBe(true);
    expect(init.isInitialized()).toBe(true);
  });

  it('resolves false at the C++ failure stage without calling shutdown', async () => {
    const cpp = { initialized: 0, stage: 0 };
    const { init, diagnostics, calls } = await loadBridge(cpp);
    let settled: boolean | null = null;
    void init.initWasmRenderer(canvas()).then((ok) => { settled = ok; });

    await advance(500);
    cpp.stage = 2; // C++ Adapter WaitAny timed out on every attempt → its own Shutdown()
    await advance(100);
    expect(settled).toBe(false);
    expect(init.isInitialized()).toBe(false);
    expect(calls).not.toContain('shutdownWasmRenderer');
    const d = diagnostics.getDiagnostics();
    expect(d.failedStageName).toBe('Adapter');
    expect(d.lastInitError).toContain('timed out');
  });

  it('times out without touching the suspended module, then reaps it once C++ settles', async () => {
    const cpp = { initialized: 0, stage: 0 };
    const { init, diagnostics, calls } = await loadBridge(cpp);
    let settled: boolean | null = null;
    void init.initWasmRenderer(canvas()).then((ok) => { settled = ok; });

    await advance(init.CPP_INIT_TIMEOUT_MS + 100);
    expect(settled).toBe(false);
    expect(init.isInitialized()).toBe(false);
    const d = diagnostics.getDiagnostics();
    expect(d.failedStageName).toBe('Timeout');
    expect(d.hasModule).toBe(false);
    expect(d.lastInitError).toMatch(/still pending/);
    // Only plain getters ever reached C++ while it was suspended.
    expect(calls.filter((c) => c !== 'initWasmRenderer' && !POLLS.has(c))).toEqual([]);

    // Bridge-level shutdown is a no-op: nothing was initialized.
    init.shutdownWasmRenderer();
    expect(calls).not.toContain('shutdownWasmRenderer');

    await advance(5_000);
    expect(calls).not.toContain('shutdownWasmRenderer');

    cpp.initialized = 1; // the WaitAny finally resolved
    cpp.stage = 8;
    await advance(1_000);
    expect(calls.filter((c) => c === 'shutdownWasmRenderer')).toHaveLength(1);
  });
});
