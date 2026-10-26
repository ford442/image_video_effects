/**
 * Bind group 0 is generated from one contract (src/contracts/bind_group0.json) for TS and C++,
 * and the colour bindings' sample type follows the texture format: rgba16float is always
 * filterable, so a device without `float32-filterable` must not demote it to unfilterable-float
 * (that breaks every shader that samples readTexture through the filtering u_sampler).
 */
import bindGroup0Contract from '../../contracts/bind_group0.json';
import { colorSampleType, createComputeBindGroupLayout } from './pipeline';
import { resolveColorFormat, DEFAULT_FORMAT_CAPABILITIES } from '../../config/formatPolicy';

const g = globalThis as Record<string, unknown>;
if (!g.GPUShaderStage) g.GPUShaderStage = { COMPUTE: 4 };

/** A device that offers no optional features at all. */
function featurelessDevice() {
  const layouts: GPUBindGroupLayoutDescriptor[] = [];
  const device = {
    features: new Set<string>(),
    createBindGroupLayout: (desc: GPUBindGroupLayoutDescriptor) => {
      layouts.push(desc);
      return { label: desc.label } as GPUBindGroupLayout;
    },
    createPipelineLayout: (desc: GPUPipelineLayoutDescriptor) => ({ label: desc.label }) as GPUPipelineLayout,
  };
  return { device: device as unknown as GPUDevice, layouts };
}

function entries(layouts: GPUBindGroupLayoutDescriptor[]): GPUBindGroupLayoutEntry[] {
  return [...(layouts[0]?.entries ?? [])];
}

describe('compute bind group 0 layout', () => {
  it('keeps rgba16float colour bindings filterable without float32-filterable', () => {
    const { device, layouts } = featurelessDevice();
    createComputeBindGroupLayout(device, false, 'rgba16float');
    const e = entries(layouts);
    for (const b of [1, 9, 13]) {
      expect(e[b]?.texture?.sampleType).toBe('float');
    }
    expect(e[0]?.sampler?.type).toBe('filtering');
  });

  it('marks rgba32float colour bindings unfilterable only without the feature', () => {
    const { device, layouts } = featurelessDevice();
    createComputeBindGroupLayout(device, false, 'rgba32float');
    createComputeBindGroupLayout(device, true, 'rgba32float');
    const without = entries(layouts.slice(0, 1));
    const withFeat = entries(layouts.slice(1, 2));
    expect(without[1]?.texture?.sampleType).toBe('unfilterable-float');
    expect(withFeat[1]?.texture?.sampleType).toBe('float');
    expect(colorSampleType('rgba16float', false)).toBe('float');
  });

  it('never makes depth (binding 4) filterable, matching the C++ layout', () => {
    for (const hasF32 of [false, true]) {
      const { device, layouts } = featurelessDevice();
      createComputeBindGroupLayout(device, hasF32, 'rgba32float');
      expect(entries(layouts)[4]?.texture?.sampleType).toBe('unfilterable-float');
    }
  });

  it('builds every entry from bind_group0.json in binding order', () => {
    const { device, layouts } = featurelessDevice();
    createComputeBindGroupLayout(device, false, 'rgba16float');
    const e = entries(layouts);
    expect(e.map((x) => x.binding)).toEqual(bindGroup0Contract.bindings.map((b) => b.binding));
    expect(e[2]?.storageTexture?.format).toBe('rgba16float');
    expect(e[6]?.storageTexture?.format).toBe('r32float');
    expect(e[13]?.texture?.viewDimension).toBe('2d-array');
  });

  it('a feature-less device resolves every quality mode to a filterable format', () => {
    const caps = { ...DEFAULT_FORMAT_CAPABILITIES, adapterGpuType: 'discrete' as const, supportsRgba32FloatStorage: true };
    for (const mode of ['ultra', 'auto', 'balanced', 'battery'] as const) {
      const fmt = resolveColorFormat(mode, caps);
      expect(colorSampleType(fmt, caps.hasFloat32Filterable)).toBe('float');
    }
  });
});
