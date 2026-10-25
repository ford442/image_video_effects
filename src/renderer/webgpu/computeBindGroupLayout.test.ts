/**
 * #1511 bug 3: the compute BGL's color bindings take their sample type from the
 * texture format, so a device without 'float32-filterable' keeps the catalog's
 * readTexture + filtering u_sampler pairs valid on rgba16float.
 */
import { createComputeBindGroupLayout } from './pipeline';
import { DEFAULT_FORMAT_CAPABILITIES, resolveColorFormat } from '../../config/formatPolicy';
import type { RenderQualityMode } from '../../config/performancePolicy';

beforeAll(() => {
  (globalThis as unknown as { GPUShaderStage: Record<string, number> }).GPUShaderStage ??= {
    VERTEX: 1, FRAGMENT: 2, COMPUTE: 4,
  };
});

/** A device that was granted no optional features. */
function featurelessDevice() {
  const layouts: GPUBindGroupLayoutDescriptor[] = [];
  const device = {
    features: new Set<string>(),
    createBindGroupLayout: vi.fn((desc: GPUBindGroupLayoutDescriptor) => {
      layouts.push(desc);
      return { label: desc.label } as GPUBindGroupLayout;
    }),
    createPipelineLayout: vi.fn(() => ({}) as GPUPipelineLayout),
  } as unknown as GPUDevice;
  return { device, layouts };
}

function sampleTypes(desc: GPUBindGroupLayoutDescriptor): Record<number, string | undefined> {
  const out: Record<number, string | undefined> = {};
  for (const e of desc.entries) if (e.texture) out[e.binding] = e.texture.sampleType;
  return out;
}

describe('compute bind group layout on a device without float32-filterable', () => {
  it("uses 'float' for readTexture, dataTextureC and the history array on rgba16float", () => {
    const { device, layouts } = featurelessDevice();
    createComputeBindGroupLayout(device, device.features.has('float32-filterable'), 'rgba16float');
    const types = sampleTypes(layouts[0]!);
    expect(types[1]).toBe('float');
    expect(types[9]).toBe('float');
    expect(types[13]).toBe('float');
    // Depth (r32float) stays unfilterable.
    expect(types[4]).toBe('unfilterable-float');
  });

  it("uses 'unfilterable-float' on rgba32float and 'float' once the feature is granted", () => {
    const { device, layouts } = featurelessDevice();
    createComputeBindGroupLayout(device, false, 'rgba32float');
    createComputeBindGroupLayout(device, true, 'rgba32float');
    expect(sampleTypes(layouts[0]!)).toMatchObject({ 1: 'unfilterable-float', 9: 'unfilterable-float', 13: 'unfilterable-float', 4: 'unfilterable-float' });
    expect(sampleTypes(layouts[1]!)).toMatchObject({ 1: 'float', 9: 'float', 13: 'float', 4: 'unfilterable-float' });
  });

  it('resolveColorFormat never returns rgba32float for such a device', () => {
    const { device } = featurelessDevice();
    const caps = {
      ...DEFAULT_FORMAT_CAPABILITIES,
      adapterGpuType: 'discrete' as const,
      supportsRgba32FloatStorage: true,
      hasFloat32Filterable: device.features.has('float32-filterable'),
    };
    for (const mode of ['ultra', 'auto', 'balanced', 'battery'] as RenderQualityMode[]) {
      expect(resolveColorFormat(mode, caps)).not.toBe('rgba32float');
    }
  });
});
