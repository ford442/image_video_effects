import {
  describeWasmInitFailure,
  summarizeWasmInitState,
  WASM_INIT_READY_STAGE,
} from './wasmInitDiagnostics';

describe('describeWasmInitFailure', () => {
  it('flags the no-adapter case and does not call it a WASM bug', () => {
    const d = describeWasmInitFailure({ failedStage: 2, failedStageName: 'Adapter', adapterInfo: '' });
    expect(d.noAdapter).toBe(true);
    expect(d.partial).toBe(false);
    expect(d.stageName).toBe('Adapter');
    expect(d.message).toContain('adapter: none acquired');
    expect(d.hint).toMatch(/cloud\/headless VMs/i);
  });

  it('flags a partial bring-up when the device came up but the pipeline did not', () => {
    const d = describeWasmInitFailure({
      failedStage: 4,
      failedStageName: 'Surface',
      adapterInfo: 'nvidia | turing | RTX 2060',
      lastInitError: 'wgpuSurfaceConfigure failed',
    });
    expect(d.partial).toBe(true);
    expect(d.noAdapter).toBe(false);
    expect(d.reached).toEqual(['Instance', 'Adapter', 'Device']);
    expect(d.message).toContain('wgpuSurfaceConfigure failed');
    expect(d.message).toContain('Instance → Adapter → Device');
    expect(d.hint).toMatch(/WASM-side bug/i);
  });

  it('treats Pipeline as partial and Ready as not partial', () => {
    expect(describeWasmInitFailure({ failedStage: 7, adapterInfo: 'x' }).partial).toBe(true);
    expect(describeWasmInitFailure({ failedStage: WASM_INIT_READY_STAGE, adapterInfo: 'x' }).partial).toBe(false);
  });

  it('calls out a missing module before blaming the GPU', () => {
    const d = describeWasmInitFailure({ hasModule: false, lastLoadError: '404 pixelocity_wasm.wasm' });
    expect(d.hint).toMatch(/module never loaded/i);
    expect(d.message).toContain('404 pixelocity_wasm.wasm');
  });

  it('includes the attempt counter and clamps out-of-range stages', () => {
    const d = describeWasmInitFailure({ failedStage: 99 }, 2, 3);
    expect(d.message).toContain('attempt 2/3');
    expect(d.stage).toBe(WASM_INIT_READY_STAGE);
  });

  it('handles empty diagnostics without throwing', () => {
    const d = describeWasmInitFailure();
    expect(d.stage).toBe(0);
    expect(d.reached).toEqual([]);
    expect(d.message).toContain('adapter: none acquired');
  });
});

describe('summarizeWasmInitState', () => {
  it('reports ready with the adapter name', () => {
    expect(summarizeWasmInitState({ initialized: true, adapterInfo: 'intel | gen12 | Iris Xe' }))
      .toBe('ready · adapter: intel | gen12 | Iris Xe');
  });

  it('distinguishes partial from failed', () => {
    expect(summarizeWasmInitState({ failedStage: 5, adapterInfo: 'amd | rdna2 | 6600' }))
      .toContain('partial at Resources');
    expect(summarizeWasmInitState({ failedStage: 2 })).toContain('failed at Adapter');
  });
});
