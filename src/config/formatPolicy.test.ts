import {
  DEFAULT_FORMAT_CAPABILITIES,
  estimateInternalTextureMiB,
  inferRequiresRgba32Float,
  resolveColorFormat,
} from './formatPolicy';
import { resolvePerformancePolicy, type RenderQualityMode } from './performancePolicy';

describe('formatPolicy', () => {
  it('maps ultra to rgba32float and balanced/battery to rgba16float', () => {
    expect(resolveColorFormat('ultra')).toBe('rgba32float');
    expect(resolveColorFormat('balanced')).toBe('rgba16float');
    expect(resolveColorFormat('battery')).toBe('rgba16float');
  });

  it('auto picks FP32 on discrete desktop and FP16 on integrated', () => {
    expect(
      resolveColorFormat('auto', {
        ...DEFAULT_FORMAT_CAPABILITIES,
        adapterGpuType: 'discrete',
        isMobile: false,
      }),
    ).toBe('rgba32float');

    expect(
      resolveColorFormat('auto', {
        ...DEFAULT_FORMAT_CAPABILITIES,
        adapterGpuType: 'integrated',
        isMobile: false,
      }),
    ).toBe('rgba16float');
  });

  it('estimates texture memory for FP16 at ~50% of FP32', () => {
    const fp32 = estimateInternalTextureMiB(2048, 2048, 'rgba32float');
    const fp16 = estimateInternalTextureMiB(2048, 2048, 'rgba16float');
    expect(fp16).toBeLessThan(fp32);
    expect(fp16 / fp32).toBeCloseTo(0.5, 1);
  });

  it('infers FP32 requirement from simulation category and physics tags', () => {
    expect(inferRequiresRgba32Float({ category: 'simulation' })).toBe(true);
    expect(inferRequiresRgba32Float({ tags: ['physics'] })).toBe(true);
    expect(inferRequiresRgba32Float({ category: 'generative', tags: ['neon'] })).toBe(false);
    expect(inferRequiresRgba32Float({ requiresRgba32Float: true })).toBe(true);
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
