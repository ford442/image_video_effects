import { WebGPURenderer } from './WebGPURenderer';
import { DEFAULT_CONFIG } from './Renderer';
import { defaultSlotLayer } from './layerState';

describe('WebGPURenderer slot layers (#1512)', () => {
  it('normalises a layer and keeps it across shader changes', () => {
    const r = new WebGPURenderer(DEFAULT_CONFIG);
    r.setSlotLayer(1, { ...defaultSlotLayer(), output: 'blend', blend: 'screen', opacity: 3 });
    expect(r.getSlotLayer(1)).toMatchObject({ output: 'blend', blend: 'screen', opacity: 1 });

    r.setSlotShader(1, 'plasma');
    expect(r.getSlotState(1)?.layer).toMatchObject({ blend: 'screen' });
    r.setActiveShader('rain');
    expect(r.getSlotState(1)?.layer).toMatchObject({ blend: 'screen' });
    expect(r.getSlotState(0)?.layer).toEqual(defaultSlotLayer());

    // Out-of-range slots are ignored.
    r.setSlotLayer(9, { ...defaultSlotLayer(), output: 'mask' });
    expect(r.getSlotLayer(9)).toBeNull();
  });

  it('keeps the compositor idle without a device or a non-replace layer', () => {
    const r = new WebGPURenderer(DEFAULT_CONFIG);
    r.setSlotShader(0, 'plasma');
    r.setSlotLayer(0, { ...defaultSlotLayer(), output: 'blend', blend: 'add' });
    expect(r.getCompositor()).toBeNull();
    expect(r.getCompositorStats()).toEqual({ layers: 0, bytes: 0, compositesLastFrame: 0 });
  });

  it('restores ripples with their age so they resume mid-animation', () => {
    const r = new WebGPURenderer(DEFAULT_CONFIG);
    (r as unknown as { currentTime: number }).currentTime = 10;
    r.restoreRipples([[0.1, 0.2, 1.5], [0.3, 0.4, 0]]);
    expect((r as unknown as { ripples: unknown[] }).ripples).toEqual([
      { x: 0.1, y: 0.2, startTime: 8.5 },
      { x: 0.3, y: 0.4, startTime: 10 },
    ]);
  });
});
