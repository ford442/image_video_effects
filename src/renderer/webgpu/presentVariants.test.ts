import { createFakeGpu, summarizeOps } from '../testing/fakeGpu';
import { buildCanvasConfigureOptions, effectiveCanvasFormat, isHdrCanvas } from './device';
import {
  DEFAULT_HDR_PRESENT,
  HdrPresent,
  StoragePresent,
  hdrPresentUniform,
  hdrShoulder,
  normalizeHdrPresent,
} from './presentVariants';

describe('HDR present (#1512)', () => {
  it('keeps SDR values and rolls highlights off towards the peak (> 1.0 survives)', () => {
    expect(hdrShoulder(0.5, 4.9)).toBe(0.5);
    expect(hdrShoulder(1, 4.9)).toBe(1);
    expect(hdrShoulder(3, 4.9)).toBeGreaterThan(2);
    expect(hdrShoulder(3, 4.9)).toBeLessThan(3);
    expect(hdrShoulder(1e6, 4.9)).toBeLessThanOrEqual(4.9);
    // No headroom: a plain clamp, like the SDR blit.
    expect(hdrShoulder(3, 1)).toBe(1);
  });

  it('packs paper white and peak relative to the SDR reference white', () => {
    const u = hdrPresentUniform({ paperWhiteNits: 203, peakNits: 1015 });
    expect(u[0]).toBeCloseTo(1);
    expect(u[1]).toBeCloseTo(5);
    expect(normalizeHdrPresent({ paperWhiteNits: 10, peakNits: 50 })).toEqual({ paperWhiteNits: 80, peakNits: 80 });
    expect(normalizeHdrPresent()).toEqual(DEFAULT_HDR_PRESENT);
  });

  it('configures rgba16float only for the full display-p3 + extended + HDR canvas opt-in', () => {
    const device = createFakeGpu().device;
    expect(buildCanvasConfigureOptions(device, 'bgra8unorm', { displayP3: true, extendedToneMapping: true, hdrCanvas: true }).format)
      .toBe('rgba16float');
    expect(buildCanvasConfigureOptions(device, 'bgra8unorm', { hdrCanvas: true }).format).toBe('bgra8unorm');
    expect(isHdrCanvas({ displayP3: true, extendedToneMapping: false, hdrCanvas: true })).toBe(false);
    expect(effectiveCanvasFormat('rgba8unorm', {})).toBe('rgba8unorm');
    expect(buildCanvasConfigureOptions(device, 'bgra8unorm', { storagePresent: true, copySrc: true }).usage).toBe(0x10 | 0x08 | 0x01);
  });

  it('builds the HDR pipelines once per device / format / blit layout', () => {
    const fake = createFakeGpu();
    const hdr = new HdrPresent();
    const layout = { label: 'blitBGL' } as unknown as GPUBindGroupLayout;
    const a = hdr.get(fake.device, layout, 'rgba16float');
    expect(a).toMatchObject({ kind: 'hdr' });
    expect(hdr.get(fake.device, layout, 'rgba16float')).toBe(a);
    expect(fake.counters.createRenderPipeline).toBe(2);
    hdr.setSettings({ peakNits: 2000 });
    expect(hdr.getSettings()).toEqual({ paperWhiteNits: 203, peakNits: 2000 });
  });
});

describe('storage present (#1512)', () => {
  it('writes a bgra8unorm swapchain in one compute pass, and declines any other format', () => {
    const fake = createFakeGpu();
    const present = new StoragePresent(() => fake.device);
    const encoder = fake.device.createCommandEncoder({ label: 'frame' });
    const target = { ...fake.texture('canvas', 64, 64), format: 'bgra8unorm' } as unknown as GPUTexture;
    const rgba = { ...fake.texture('canvas8', 64, 64), format: 'rgba8unorm' } as unknown as GPUTexture;
    if (present.variant.kind !== 'storage') throw new Error('expected the storage variant');
    expect(present.variant.encode(encoder, fake.texture('readTex'), rgba, false)).toBe(false);
    expect(present.variant.encode(encoder, fake.texture('readTex'), target, true)).toBe(true);
    expect(summarizeOps(fake.ops)).toEqual(['compute:present']);
    expect(present.presents).toBe(1);
  });
});
