import {
  DEFAULT_FORMAT_CAPABILITIES,
  estimateInternalTextureMiB,
  floatToHalfBits,
  inferRequiresRgba32Float,
  packRgbaUploadData,
  probeFormatCapabilities,
  resolveColorFormat,
} from './formatPolicy';
import { resolvePerformancePolicy, type RenderQualityMode } from './performancePolicy';

const TU = {
  COPY_SRC: 0x01,
  COPY_DST: 0x02,
  TEXTURE_BINDING: 0x04,
  STORAGE_BINDING: 0x08,
  RENDER_ATTACHMENT: 0x10,
} as const;

beforeAll(() => {
  (global as unknown as { GPUTextureUsage: typeof TU }).GPUTextureUsage = TU;
});

describe('formatPolicy', () => {
  it('maps ultra to rgba32float and balanced/battery to rgba16float', () => {
    expect(resolveColorFormat('ultra')).toBe('rgba32float');
    expect(resolveColorFormat('balanced')).toBe('rgba16float');
    expect(resolveColorFormat('battery')).toBe('rgba16float');
  });

  it('auto picks FP32 on discrete desktop only when FP32 storage was measured', () => {
    expect(
      resolveColorFormat('auto', {
        ...DEFAULT_FORMAT_CAPABILITIES,
        adapterGpuType: 'discrete',
        isMobile: false,
        supportsRgba32FloatStorage: true,
      }),
    ).toBe('rgba32float');

    expect(
      resolveColorFormat('auto', {
        ...DEFAULT_FORMAT_CAPABILITIES,
        adapterGpuType: 'discrete',
        isMobile: false,
        supportsRgba32FloatStorage: false,
      }),
    ).toBe('rgba16float');

    expect(
      resolveColorFormat('auto', {
        ...DEFAULT_FORMAT_CAPABILITIES,
        adapterGpuType: 'integrated',
        isMobile: false,
      }),
    ).toBe('rgba16float');
  });

  it('fail-softs balanced/battery to FP32 without Float16Array or FP16 storage', () => {
    expect(
      resolveColorFormat('balanced', {
        ...DEFAULT_FORMAT_CAPABILITIES,
        supportsFloat16Array: false,
      }),
    ).toBe('rgba32float');
    expect(
      resolveColorFormat('battery', {
        ...DEFAULT_FORMAT_CAPABILITIES,
        supportsRgba16FloatStorage: false,
      }),
    ).toBe('rgba32float');
  });

  it('estimates texture memory for FP16 at ~50% of FP32', () => {
    const fp32 = estimateInternalTextureMiB(2048, 2048, 'rgba32float');
    const fp16 = estimateInternalTextureMiB(2048, 2048, 'rgba16float');
    expect(fp16).toBeLessThan(fp32);
    expect(fp16 / fp32).toBeCloseTo(0.5, 1);
  });

  it('infers FP32 only from the JSON flag or the state-shader allowlist', () => {
    expect(inferRequiresRgba32Float({ category: 'simulation' })).toBe(false);
    expect(inferRequiresRgba32Float({ tags: ['physics'] })).toBe(false);
    expect(inferRequiresRgba32Float({ tags: ['fluid'] })).toBe(false);
    expect(inferRequiresRgba32Float({ category: 'generative', tags: ['neon'] })).toBe(false);
    expect(inferRequiresRgba32Float({ requiresRgba32Float: true })).toBe(true);
    expect(inferRequiresRgba32Float({ id: 'ripple-tank' })).toBe(true);
    expect(inferRequiresRgba32Float({ id: 'fabric-of-reality' })).toBe(true);
    expect(inferRequiresRgba32Float({ id: 'chromatographic-fluid' })).toBe(true);
    expect(inferRequiresRgba32Float({ id: 'gray-scott-tank' })).toBe(true);
    expect(inferRequiresRgba32Float({ id: 'liquid' })).toBe(false);
  });
});

describe('probeFormatCapabilities', () => {
  it('measures storage formats instead of hardcoding true', () => {
    const created: GPUTextureFormat[] = [];
    const device = {
      createTexture: jest.fn((desc: GPUTextureDescriptor) => {
        created.push(desc.format);
        return { destroy: jest.fn() };
      }),
    } as unknown as GPUDevice;
    const adapter = {
      features: new Set<GPUFeatureName>(['float32-filterable']),
      info: { adapterType: 'integrated' },
    } as unknown as GPUAdapter;

    const caps = probeFormatCapabilities(adapter, { isMobile: false, device });
    expect(caps.supportsRgba32FloatStorage).toBe(true);
    expect(caps.supportsRgba16FloatStorage).toBe(true);
    expect(caps.hasFloat32Filterable).toBe(true);
    expect(created).toEqual(expect.arrayContaining(['rgba16float', 'rgba32float']));
  });

  it('records false when the 1×1 storage create throws', () => {
    const device = {
      createTexture: jest.fn(() => {
        throw new Error('rgba32float storage not supported');
      }),
    } as unknown as GPUDevice;
    const adapter = {
      features: new Set<GPUFeatureName>(),
      info: {},
    } as unknown as GPUAdapter;

    const caps = probeFormatCapabilities(adapter, { device });
    expect(caps.supportsRgba32FloatStorage).toBe(false);
    expect(caps.supportsRgba16FloatStorage).toBe(false);
  });

  it('does not assume storage support without a device', () => {
    const adapter = {
      features: new Set<GPUFeatureName>(),
      info: {},
    } as unknown as GPUAdapter;
    const caps = probeFormatCapabilities(adapter, false);
    expect(caps.supportsRgba32FloatStorage).toBe(false);
    expect(caps.supportsRgba16FloatStorage).toBe(false);
  });
});

describe('packRgbaUploadData', () => {
  it('uses 16 bytes/pixel for rgba32float and 8 for rgba16float', () => {
    const floats = new Float32Array([1, 0, 0, 1, 0, 1, 0, 1]);
    const fp32 = packRgbaUploadData(floats, 2, 1, 'rgba32float');
    expect(fp32.bytesPerRow).toBe(32);
    expect(fp32.data).toBe(floats);

    const fp16 = packRgbaUploadData(floats, 2, 1, 'rgba16float');
    expect(fp16.bytesPerRow).toBe(16);
    expect(fp16.rowsPerImage).toBe(1);
    expect(fp16.data.byteLength).toBe(16);
  });

  it('packs IEEE-754 binary16 without Float16Array', () => {
    const orig = (globalThis as unknown as { Float16Array?: unknown }).Float16Array;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    delete (globalThis as any).Float16Array;
    try {
      const floats = new Float32Array([1, 0, 0.5, 1]);
      const packed = packRgbaUploadData(floats, 1, 1, 'rgba16float');
      const bits = new Uint16Array(
        packed.data.buffer,
        packed.data.byteOffset,
        packed.data.byteLength / 2,
      );
      expect(bits[0]).toBe(floatToHalfBits(1));
      expect(bits[1]).toBe(0);
      expect(bits[3]).toBe(floatToHalfBits(1));
    } finally {
      if (orig) {
        (globalThis as unknown as { Float16Array: unknown }).Float16Array = orig;
      }
    }
  });
});

describe('resolvePerformancePolicy colorFormat', () => {
  const modes: RenderQualityMode[] = ['battery', 'balanced', 'ultra', 'auto'];

  it.each(modes)('includes colorFormat for mode %s', (mode) => {
    const policy = resolvePerformancePolicy(mode, {
      supportsDeepWorkgroup: true,
      formatCaps: DEFAULT_FORMAT_CAPABILITIES,
    });
    expect(policy.colorFormat).toMatch(/^rgba(16|32)float$/);
  });
});
