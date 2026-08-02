/**
 * @jest-environment jsdom
 *
 * Tests WASM bridge input-source mapping and pending-source flush on init.
 * Uses the real wasm_bridge.js (not the mock in WASMBridge.test.ts).
 */

describe('WASM bridge uniforms (setInputSource)', () => {
  const ccall = jest.fn();
  const malloc = jest.fn().mockReturnValue(1000);
  const free = jest.fn();

  function makeMockModule() {
    return {
      ccall,
      _malloc: malloc,
      _free: free,
      HEAPU8: { set: jest.fn() },
    };
  }

  beforeEach(() => {
    jest.resetModules();
    ccall.mockReset();
    malloc.mockClear();
    free.mockClear();
    (window as unknown as { PixelocityWASM?: unknown }).PixelocityWASM = jest
      .fn()
      .mockResolvedValue(makeMockModule());
  });

  async function initBridge() {
    const bridge = await import('../wasm/wasm_bridge.js');
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

    const cases: Array<[string, number]> = [
      ['none', 0],
      ['image', 1],
      ['video', 2],
      ['webcam', 3],
      ['generative', 4],
      ['live', 5],
    ];

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
    const bridge = await import('../wasm/wasm_bridge.js');

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
});
