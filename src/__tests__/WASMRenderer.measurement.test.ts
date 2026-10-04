/**
 * #1314 D — WASMRenderer surfaces the C++ per-pass timings and error ring.
 */

import * as WasmBridge from '../wasm/wasm_bridge';
import { WASMRenderer } from '../renderer/WASMRenderer';
import { DEFAULT_CONFIG } from '../renderer/Renderer';

const PASS = {
  key: '0:plasma',
  label: 'plasma',
  kind: 'compute' as const,
  slot: 0,
  shaderId: 'plasma',
  entry: 'plasma',
  scale: 1,
  gpuMs: 0.8,
  iterations: 1,
};

jest.mock('../wasm/wasm_bridge', () => ({
  getDiagnostics: jest.fn(() => ({})),
  getFPS: () => 60,
  getGPUTimings: jest.fn(),
  readPassTimings: jest.fn(),
  readErrorRing: jest.fn(),
}));

const bridge = WasmBridge as jest.Mocked<typeof WasmBridge>;

describe('WASMRenderer measurement surface', () => {
  let renderer: WASMRenderer;

  beforeEach(() => {
    jest.clearAllMocks();
    renderer = new WASMRenderer(DEFAULT_CONFIG);
    bridge.readPassTimings.mockReturnValue([PASS]);
    bridge.readErrorRing.mockReturnValue({ count: 2, last: 'Validation: b', recent: ['Validation: a', 'Validation: b'] });
  });

  it('puts passTimings and errors in getDiagnostics()', () => {
    const d = renderer.getDiagnostics();
    expect(d.passTimings).toEqual([PASS]);
    expect(d.errors).toEqual({ count: 2, last: 'Validation: b', recent: ['Validation: a', 'Validation: b'] });
  });

  it('attaches passes to GPU-timestamp timings only', () => {
    bridge.getGPUTimings.mockReturnValue({
      parallelTime: 0, chainedTime: 0.8, totalTime: 1, available: true, timingSource: 'gpu-timestamp',
    });
    expect(renderer.getGPUTimings().passes).toEqual([PASS]);

    bridge.getGPUTimings.mockReturnValue({
      parallelTime: 0, chainedTime: 2, totalTime: 3, available: false, timingSource: 'wall-clock',
    });
    expect(renderer.getGPUTimings()).not.toHaveProperty('passes');
  });

  it('omits passes when the C++ profiler has none yet', () => {
    bridge.readPassTimings.mockReturnValue([]);
    bridge.getGPUTimings.mockReturnValue({
      parallelTime: 0, chainedTime: 1, totalTime: 1, available: true, timingSource: 'gpu-timestamp',
    });
    expect(renderer.getGPUTimings()).not.toHaveProperty('passes');
    expect(renderer.getDiagnostics().passTimings).toEqual([]);
  });

  it('falls back to empty values when the bridge lacks the readers (older artifact glue)', () => {
    const b = bridge as unknown as Record<string, unknown>;
    const saved = { readPassTimings: b.readPassTimings, readErrorRing: b.readErrorRing };
    b.readPassTimings = undefined;
    b.readErrorRing = undefined;
    try {
      const d = renderer.getDiagnostics();
      expect(d.passTimings).toEqual([]);
      expect(d.errors).toEqual({ count: 0, last: '', recent: [] });
    } finally {
      Object.assign(b, saved);
    }
  });
});
