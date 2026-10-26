import { WebGPURenderer } from './WebGPURenderer';
import { DEFAULT_CONFIG } from './Renderer';
import { DEFAULT_SLOT_OUTPUT } from './slotOutput';
import type { ShaderSlot } from './webgpu/webgpuConstants';

interface Internals {
  device: GPUDevice | null;
  scaledW: number;
  scaledH: number;
  slots: ShaderSlot[];
  resources: { depthRead: GPUTexture };
  compositorLoad: Promise<void> | null;
}

describe('WebGPURenderer: lazy layer compositor (#1512)', () => {
  let wgpu: WebGPURenderer;
  let internals: Internals;

  beforeEach(() => {
    wgpu = new WebGPURenderer(DEFAULT_CONFIG);
    internals = wgpu as unknown as Internals;
    internals.device = {} as GPUDevice;
    internals.scaledW = 256;
    internals.scaledH = 256;
    internals.resources.depthRead = {} as GPUTexture;
    internals.slots[0] = { ...internals.slots[0]!, shaderId: 'a', enabled: true, mode: 'parallel' };
    internals.slots[1] = { ...internals.slots[1]!, shaderId: 'b', enabled: true, mode: 'parallel' };
  });

  it('never loads the chunk while every parallel output is replace', () => {
    expect(wgpu.getCompositor()).toBeNull();
    expect(internals.compositorLoad).toBeNull();
    expect(wgpu.getCompositorStats()).toMatchObject({ layers: 0, masks: 0, composites: 0, error: null });
  });

  it('keeps last-one-wins for the frame that starts the load, then composites', async () => {
    internals.slots[1] = { ...internals.slots[1]!, output: { ...DEFAULT_SLOT_OUTPUT, mode: 'blend', blend: 'screen' } };
    expect(wgpu.getCompositor()).toBeNull();
    expect(internals.compositorLoad).not.toBeNull();
    const pending = internals.compositorLoad;
    expect(wgpu.getCompositor()).toBeNull();
    expect(internals.compositorLoad).toBe(pending); // one load, however many frames ask

    await pending;
    const compositor = wgpu.getCompositor();
    expect(compositor).not.toBeNull();
    expect(wgpu.getCompositor()).toBe(compositor);
    expect(wgpu.getCompositorStats()).toMatchObject({ layers: 0, error: null });
  });
});
