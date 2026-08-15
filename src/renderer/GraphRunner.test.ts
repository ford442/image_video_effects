import { GraphRunner } from '../renderer/GraphRunner';
import { capGraphDispatches, createWaveTankGraph } from '../renderer/multipassGraph';

function mockCtx(overrides: {
  dispatched: string[];
  getPipeline?: (id: string) => GPUComputePipeline | undefined;
  maxPassesPerFrame?: number;
}) {
  return {
    device: {} as GPUDevice,
    pipelineLayout: {} as GPUPipelineLayout,
    getPipeline: overrides.getPipeline ?? ((id: string) => {
      overrides.dispatched.push(id);
      return {} as GPUComputePipeline;
    }),
    getWorkgroupSize: () => ({ x: 16, y: 16 }),
    createBindGroupForRoles: () => ({} as GPUBindGroup),
    textures: {
      read: {} as GPUTexture,
      color: {} as GPUTexture,
      dataA: {} as GPUTexture,
      dataB: {} as GPUTexture,
      dataC: {} as GPUTexture,
    },
    scaledW: 512,
    scaledH: 512,
    maxPassesPerFrame: overrides.maxPassesPerFrame ?? 2,
  };
}

describe('GraphRunner', () => {
  it('clamps dispatches to maxPassesPerFrame while keeping the color write', () => {
    const runner = new GraphRunner();
    const graph = createWaveTankGraph();
    const dispatched: string[] = [];
    const copies: string[] = [];

    const encoder = {
      copyTextureToTexture: () => { copies.push('copy'); },
      beginComputePass: () => ({
        setPipeline: () => {},
        setBindGroup: () => {},
        dispatchWorkgroups: () => {},
        end: () => {},
      }),
    } as unknown as GPUCommandEncoder;

    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    const report = runner.runGraph(encoder, graph, mockCtx({ dispatched }));
    warn.mockRestore();

    expect(dispatched).toEqual(['wave-step', 'wave-render']);
    expect(dispatched).toHaveLength(2);
    expect(copies.length).toBeGreaterThan(0);
    expect(report.requested).toBe(5);
    expect(report.truncated).toBe(3);
    expect(report.executed).toBe(2);
    expect(capGraphDispatches(graph, 2).map((d) => d.entry)).toEqual(['wave-step', 'wave-render']);
  });

  it('skips invalid graphs and surfaces errors on the report', () => {
    const runner = new GraphRunner();
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    const encoder = {
      beginComputePass: jest.fn(),
    } as unknown as GPUCommandEncoder;

    const report = runner.runGraph(encoder, { maxPassesPerFrame: 0, nodes: [] }, {
      ...mockCtx({ dispatched: [] }),
      maxPassesPerFrame: 8,
    });

    expect(warn).toHaveBeenCalled();
    expect(encoder.beginComputePass).not.toHaveBeenCalled();
    expect(report.errors.length).toBeGreaterThan(0);
    expect(runner.lastReport?.errors).toEqual(report.errors);
    warn.mockRestore();
  });
});
