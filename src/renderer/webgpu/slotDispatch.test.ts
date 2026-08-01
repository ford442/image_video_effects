import { createWaveTankGraph } from '../multipassGraph';
import {
  countSlotComputePasses,
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
      'wave-step',
    ]);
    expect(countSlotComputePasses(program, 2, () => true)).toBe(2);
    expect(countSlotComputePasses(program, 2, () => false)).toBe(0);
  });
});
