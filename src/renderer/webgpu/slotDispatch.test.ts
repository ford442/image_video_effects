import { createWaveTankGraph } from '../multipassGraph';
import type { WebGPUFrameState } from './frameState';
import {
  buildFrameSlotDispatchPlan,
  countSlotComputePasses,
  dispatchFrameSlots,
  getCappedGraphDispatches,
  getFeedbackCopyOrder,
  resolveSlotDispatchProgram,
} from './slotDispatch';

describe('slotDispatch helpers', () => {
  it('copies secondary feedback first and primary simulation state last', () => {
    expect(getFeedbackCopyOrder(true, true, true)).toEqual([
      'dataTexB',
      'dataTexA',
    ]);
    expect(getFeedbackCopyOrder(true, true, false)).toEqual(['dataTexA']);
    expect(getFeedbackCopyOrder(false, true, true)).toEqual([]);
  });

  it('gates registered graph roots into GraphRunner and leaves ordinary shaders linear', () => {
    const graphProgram = resolveSlotDispatchProgram('ripple-tank');
    const linearProgram = resolveSlotDispatchProgram('wave-step');

    expect(graphProgram.kind).toBe('graph');
    expect(linearProgram).toEqual({ kind: 'chain', shaderIds: ['wave-step'] });
  });

  it('applies the render-quality cap before counting available graph pipelines', () => {
    const graph = createWaveTankGraph();
    const program = { kind: 'graph' as const, graph };

    expect(getCappedGraphDispatches(graph, 2).map((dispatch) => dispatch.entry)).toEqual([
      'wave-step',
      'wave-render',
    ]);
    expect(countSlotComputePasses(program, 2, () => true)).toBe(2);
    expect(countSlotComputePasses(program, 2, () => false)).toBe(0);
  });
});

describe('slotDispatch sim ring (bind_group1.json)', () => {
  function makeState(ids: string[], ringIds: Set<string>, ring: unknown): WebGPUFrameState {
    const tex = {} as GPUTexture;
    return {
      device: {} as GPUDevice,
      slots: ids.map((shaderId) => ({ shaderId, enabled: true, mode: 'chained' })),
      hasPipeline: () => true,
      getPipeline: () => ({} as GPUComputePipeline),
      getWorkgroupSize: () => ({ x: 16, y: 16 }),
      getBindingUsage: (id: string) => ({
        writesDataA: false,
        writesDataB: false,
        readsDataC: false,
        usesHistory: false,
        usesSimRing: ringIds.has(id),
      }),
      simRing: { getBindings: () => ring, beginFrame: jest.fn() },
      computeBindGroup: {} as GPUBindGroup,
      timestampRuntime: { tracker: { reset: () => {} }, supportsTimestampQuery: false, querySet: null },
      maxPassesPerFrame: 8,
      scaledW: 64,
      scaledH: 64,
      readTex: tex,
      writeTex: tex,
      dataTexC: tex,
      frameCount: 1,
    } as unknown as WebGPUFrameState;
  }

  function recordingEncoder(groups: number[][]) {
    return {
      copyTextureToTexture: () => {},
      beginComputePass: () => {
        const g: number[] = [];
        groups.push(g);
        return {
          setPipeline: () => {},
          setBindGroup: (i: number) => { g.push(i); },
          dispatchWorkgroups: () => {},
          end: () => {},
        };
      },
    } as unknown as GPUCommandEncoder;
  }

  it('flags anyUsesSimRing only when an enabled pipeline declares group 1', () => {
    const ring = { bindGroup: {} };
    expect(buildFrameSlotDispatchPlan(makeState(['plain-a'], new Set(), ring)).anyUsesSimRing)
      .toBe(false);
    expect(buildFrameSlotDispatchPlan(makeState(['plain-a', 'ring-b'], new Set(['ring-b']), ring))
      .anyUsesSimRing).toBe(true);
  });

  it('binds group 1 on linear ring passes and leaves catalog passes on group 0 only', () => {
    const state = makeState(['plain-a', 'ring-b'], new Set(['ring-b']), { bindGroup: {} });
    const groups: number[][] = [];
    dispatchFrameSlots(state, recordingEncoder(groups), buildFrameSlotDispatchPlan(state));
    expect(groups).toEqual([[0], [0, 1]]);
  });

  it('skips a ring pass instead of dispatching an unbindable pipeline when the ring is missing', () => {
    const state = makeState(['ring-b'], new Set(['ring-b']), null);
    const groups: number[][] = [];
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    dispatchFrameSlots(state, recordingEncoder(groups), buildFrameSlotDispatchPlan(state));
    warn.mockRestore();
    expect(groups).toEqual([]);
  });
});
