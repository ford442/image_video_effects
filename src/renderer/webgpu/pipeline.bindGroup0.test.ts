/**
 * Bind group 0 layout ↔ src/contracts/bind_group0.json, on a mock device that
 * does NOT have `float32-filterable` (bugs: filterable sample type keyed on the
 * feature instead of the format; TS/C++ layouts disagreeing on depth).
 */
import type { Mock } from 'vitest';
import bindGroup0Contract from '../../contracts/bind_group0.json';
import { DEFAULT_FORMAT_CAPABILITIES, resolveColorFormat } from '../../config/formatPolicy';
import { createComputeBindGroupLayout } from './pipeline';

beforeAll(() => {
  (globalThis as unknown as { GPUShaderStage: { COMPUTE: number } }).GPUShaderStage = { COMPUTE: 4 };
});

/** A device with no optional features — createBindGroupLayout just records its descriptor. */
function featurelessDevice(): GPUDevice {
  return {
    features: new Set<string>(),
    createBindGroupLayout: vi.fn((d: GPUBindGroupLayoutDescriptor) => ({ label: d.label })),
    createPipelineLayout: vi.fn(() => ({})),
  } as unknown as GPUDevice;
}

function layoutEntries(device: GPUDevice): GPUBindGroupLayoutEntry[] {
  const desc = (device.createBindGroupLayout as Mock).mock.calls[0]?.[0] as GPUBindGroupLayoutDescriptor;
  return [...desc.entries];
}

const byName = (name: string) => {
  const b = bindGroup0Contract.bindings.find((x) => x.name === name);
  if (!b) throw new Error(`no binding ${name}`);
  return b.binding;
};

describe('compute bind group 0 layout (feature-less device)', () => {
  const hasF32Filt = DEFAULT_FORMAT_CAPABILITIES.hasFloat32Filterable; // false

  it('builds every contract binding, dense 0..13', () => {
    const device = featurelessDevice();
    createComputeBindGroupLayout(device, hasF32Filt, 'rgba16float');
    expect(layoutEntries(device).map((e) => e.binding)).toEqual(bindGroup0Contract.bindings.map((b) => b.binding));
    expect(bindGroup0Contract.bindings.map((b) => b.binding)).toEqual([...Array(14).keys()]);
  });

  it('keeps rgba16float colour bindings filterable without float32-filterable (regression)', () => {
    const device = featurelessDevice();
    createComputeBindGroupLayout(device, hasF32Filt, 'rgba16float');
    const entries = layoutEntries(device);
    for (const name of ['readTexture', 'dataTextureC', 'historyTexture']) {
      expect(entries[byName(name)]?.texture?.sampleType).toBe('float');
    }
    expect(entries[byName('u_sampler')]?.sampler?.type).toBe('filtering');
    expect(entries[byName('historyTexture')]?.texture?.viewDimension).toBe('2d-array');
    expect(entries[byName('writeTexture')]?.storageTexture?.format).toBe('rgba16float');
  });

  it('binds depth as unfilterable-float on every device (matches the generated C++ table)', () => {
    for (const filt of [false, true]) {
      const device = featurelessDevice();
      createComputeBindGroupLayout(device, filt, 'rgba32float');
      expect(layoutEntries(device)[byName('readDepthTexture')]?.texture?.sampleType).toBe('unfilterable-float');
    }
  });

  it('only rgba32float without the feature is unfilterable — and the policy avoids picking it', () => {
    const device = featurelessDevice();
    createComputeBindGroupLayout(device, hasF32Filt, 'rgba32float');
    expect(layoutEntries(device)[byName('readTexture')]?.texture?.sampleType).toBe('unfilterable-float');
    for (const mode of ['ultra', 'auto', 'balanced', 'battery'] as const) {
      expect(resolveColorFormat(mode, { ...DEFAULT_FORMAT_CAPABILITIES, adapterGpuType: 'discrete', supportsRgba32FloatStorage: true }))
        .toBe('rgba16float');
    }
  });
});
