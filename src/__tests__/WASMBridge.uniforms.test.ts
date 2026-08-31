/**
 * @jest-environment jsdom
 *
 * Tests WASM bridge input-source mapping and pending-source flush on init.
 * Uses the real wasm_bridge module (not the mock in WASMBridge.test.ts).
 */

describe('WASM bridge uniforms (setInputSource)', () => {
  const ccall = jest.fn();
  const malloc = jest.fn().mockReturnValue(1000);
  const free = jest.fn();
  const getValue = jest.fn((ptr: number, type: string): number => {
    if (type === 'float' && ptr === 1000) return 1.25;
    if (type === 'float' && ptr === 1004) return 2.5;
    if (type === 'float' && ptr === 1008) return 3.75;
    if (type === 'i32' && ptr === 1012) return 0;
    return 0;
  });

  function makeMockModule() {
    return {
      ccall,
      _malloc: malloc,
      _free: free,
      getValue,
      HEAPU8: { set: jest.fn() },
      HEAPF32: { set: jest.fn() },
    };
  }

  beforeEach(() => {
    jest.resetModules();
    ccall.mockReset();
    malloc.mockReset();
    malloc.mockReturnValue(1000);
    free.mockReset();
    getValue.mockReset();
    getValue.mockImplementation((ptr: number, type: string) => {
      if (type === 'float' && ptr === 1000) return 1.25;
      if (type === 'float' && ptr === 1004) return 2.5;
      if (type === 'float' && ptr === 1008) return 3.75;
      if (type === 'i32' && ptr === 1012) return 0;
      return 0;
    });
    (window as unknown as { PixelocityWASM?: unknown }).PixelocityWASM = jest
      .fn()
      .mockResolvedValue(makeMockModule());
  });

  async function initBridge() {
    const bridge = await import('../wasm/wasm_bridge');
    ccall.mockImplementation((name: string) => {
      if (name === 'initWasmRenderer') return Promise.resolve(1);
      return undefined;
    });
    const canvas = document.createElement('canvas');
    canvas.width = 64;
    canvas.height = 64;
    const ok = await bridge.initWasmRenderer(canvas);
    expect(ok).toBe(true);
    ccall.mockClear();
    return bridge;
  }

  it('maps string input sources to C++ ints', async () => {
    const bridge = await initBridge();

    const cases = [
      ['none', 0],
      ['image', 1],
      ['video', 2],
      ['webcam', 3],
      ['generative', 4],
      ['live', 5],
    ] as const;

    for (const [source, expected] of cases) {
      bridge.setInputSource(source as any);
      expect(ccall).toHaveBeenCalledWith('setInputSource', null, ['number'], [expected]);
      ccall.mockClear();
    }

    bridge.setInputSource('unknown-source' as any);
    expect(ccall).toHaveBeenCalledWith('setInputSource', null, ['number'], [0]);

    bridge.shutdownWasmRenderer();
  });

  it('queues pending input source before init and flushes on init', async () => {
    const bridge = await import('../wasm/wasm_bridge');

    bridge.setInputSource('generative');
    expect(ccall).not.toHaveBeenCalled();

    ccall.mockImplementation((name: string) => {
      if (name === 'initWasmRenderer') return Promise.resolve(1);
      return undefined;
    });
    const canvas = document.createElement('canvas');
    canvas.width = 64;
    canvas.height = 64;
    const ok = await bridge.initWasmRenderer(canvas);
    expect(ok).toBe(true);
    expect(canvas.id).toMatch(/^pixelocity-wasm-canvas-\d+$/);
    expect(ccall).toHaveBeenCalledWith('setInputSource', null, ['number'], [4]);

    bridge.shutdownWasmRenderer();
  });

  it('skips uploadImageData when width or height is zero', async () => {
    const bridge = await initBridge();
    const pixels = new Uint8Array(4);

    bridge.uploadImageData(pixels, 0, 1);
    bridge.uploadImageData(pixels, 1, 0);
    bridge.uploadImageData(new Uint8Array(0), 1, 1);

    expect(malloc).not.toHaveBeenCalled();
    expect(ccall).not.toHaveBeenCalledWith(
      'loadImageData',
      expect.anything(),
      expect.anything(),
      expect.anything(),
    );

    bridge.shutdownWasmRenderer();
  });

  it('getGPUTimings returns typed zeros before init', async () => {
    const bridge = await import('../wasm/wasm_bridge');
    expect(bridge.getGPUTimings()).toEqual({
      parallelTime: 0,
      chainedTime: 0,
      totalTime: 0,
      available: false,
      timingSource: 'unavailable',
    });
    expect(ccall).not.toHaveBeenCalled();
    expect(malloc).not.toHaveBeenCalled();
  });

  it('getGPUTimings reads C++ out-params via malloc/getValue', async () => {
    const bridge = await initBridge();

    const timings = bridge.getGPUTimings();

    expect(malloc).toHaveBeenCalledWith(16);
    expect(ccall).toHaveBeenCalledWith(
      'getGPUTimings',
      null,
      ['number', 'number', 'number', 'number'],
      [1000, 1004, 1008, 1012],
    );
    expect(getValue).toHaveBeenCalledWith(1000, 'float');
    expect(getValue).toHaveBeenCalledWith(1004, 'float');
    expect(getValue).toHaveBeenCalledWith(1008, 'float');
    expect(getValue).toHaveBeenCalledWith(1012, 'i32');
    expect(free).toHaveBeenCalledWith(1000);
    expect(timings).toEqual({
      parallelTime: 1.25,
      chainedTime: 2.5,
      totalTime: 3.75,
      available: false,
      timingSource: 'wall-clock',
    });

    bridge.shutdownWasmRenderer();
  });

  it('getGPUTimings marks gpu-timestamp when C++ available flag is set', async () => {
    getValue.mockImplementation((ptr: number, type: string) => {
      if (type === 'i32' && ptr === 1012) return 1;
      if (type === 'float') return 4;
      return 0;
    });
    const bridge = await initBridge();

    expect(bridge.getGPUTimings()).toEqual({
      parallelTime: 4,
      chainedTime: 4,
      totalTime: 4,
      available: true,
      timingSource: 'gpu-timestamp',
    });

    bridge.shutdownWasmRenderer();
  });
});
