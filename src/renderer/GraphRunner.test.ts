import { GraphRunner } from '../renderer/GraphRunner';
import { createWaveTankGraph } from '../renderer/multipassGraph';

describe('GraphRunner', () => {
  it('clamps dispatches to maxPassesPerFrame', () => {
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

    runner.runGraph(encoder, graph, {
      device: {} as GPUDevice,
      pipelineLayout: {} as GPUPipelineLayout,
      getPipeline: (id) => {
        dispatched.push(id);
        return {} as GPUComputePipeline;
      },
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
      maxPassesPerFrame: 2,
    });

    expect(dispatched).toHaveLength(2);
    expect(copies.length).toBeGreaterThan(0);
  });

  it('skips invalid graphs', () => {
    const runner = new GraphRunner();
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    const encoder = {
      beginComputePass: jest.fn(),
    } as unknown as GPUCommandEncoder;

    runner.runGraph(encoder, { maxPassesPerFrame: 0, nodes: [] }, {
      device: {} as GPUDevice,
      pipelineLayout: {} as GPUPipelineLayout,
      getPipeline: () => undefined,
      getWorkgroupSize: () => ({ x: 8, y: 8 }),
      createBindGroupForRoles: () => ({} as GPUBindGroup),
      textures: {
        read: {} as GPUTexture,
        color: {} as GPUTexture,
        dataA: {} as GPUTexture,
        dataB: {} as GPUTexture,
        dataC: {} as GPUTexture,
      },
      scaledW: 256,
      scaledH: 256,
      maxPassesPerFrame: 8,
    });

    expect(warn).toHaveBeenCalled();
    expect(encoder.beginComputePass).not.toHaveBeenCalled();
    warn.mockRestore();
  });
});
