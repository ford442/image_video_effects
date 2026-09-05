/**
 * Precision guard: FP32-required shaders must never run on FP16 storage.
 * docs/FORMAT_TIERS.md — "Do not silently run physics sims at FP16."
 */

import { inferRequiresRgba32Float, resolveFp32Pin } from './formatPolicy';
import { resolvePerformancePolicy, type RenderQualityMode } from './performancePolicy';

const TIERS: RenderQualityMode[] = ['battery', 'balanced', 'ultra', 'auto'];

describe('resolveFp32Pin', () => {
  it('leaves the tier format alone when nothing requires FP32', () => {
    expect(resolveFp32Pin('rgba16float', [])).toEqual({
      colorFormat: 'rgba16float',
      pinned: false,
      pinnedBy: [],
    });
  });

  it('pins FP16 tiers to rgba32float while an FP32 shader is loaded', () => {
    const pin = resolveFp32Pin('rgba16float', ['ripple-tank']);
    expect(pin.colorFormat).toBe('rgba32float');
    expect(pin.pinned).toBe(true);
    expect(pin.pinnedBy).toEqual(['ripple-tank']);
  });

  it('does not report a pin when the tier already asked for FP32', () => {
    const pin = resolveFp32Pin('rgba32float', ['ripple-tank']);
    expect(pin.colorFormat).toBe('rgba32float');
    expect(pin.pinned).toBe(false);
  });

  it('reports every pin holder, sorted', () => {
    expect(resolveFp32Pin('rgba16float', ['zebra-sim', 'acid-fluid']).pinnedBy).toEqual([
      'acid-fluid',
      'zebra-sim',
    ]);
  });

  it('no tier can produce an FP16 path for an FP32-required shader', () => {
    for (const tier of TIERS) {
      for (const gpuType of ['discrete', 'integrated', 'cpu', 'unknown'] as const) {
        for (const isMobile of [false, true]) {
          const policy = resolvePerformancePolicy(tier, {
            supportsDeepWorkgroup: true,
            formatCaps: {
              adapterGpuType: gpuType,
              isMobile,
              supportsRgba32FloatStorage: true,
              supportsRgba16FloatStorage: true,
              supportsFloat16Array: true,
              hasFloat32Filterable: true,
              hasFloat32Blendable: false,
            },
          });
          const pin = resolveFp32Pin(policy.colorFormat, ['sim-fluid-feedback-coupled']);
          expect(pin.colorFormat).toBe('rgba32float');
        }
      }
    }
  });
});

describe('FP32 inference feeding the pin', () => {
  it.each([
    [{ category: 'simulation' }, false],
    [{ tags: ['fluid'] }, false],
    [{ tags: ['reaction-diffusion'] }, false],
    [{ tags: ['physics'] }, false],
    [{ requiresRgba32Float: true }, true],
    [{ id: 'ripple-tank' }, true],
    [{ id: 'gray-scott-tank' }, true],
    [{ category: 'generative', tags: ['neon', 'audio'] }, false],
  ])('infers %o → %s and pins accordingly', (shader, expected) => {
    const requiresFp32 = inferRequiresRgba32Float(shader);
    expect(requiresFp32).toBe(expected);

    const pin = resolveFp32Pin('rgba16float', requiresFp32 ? ['x'] : []);
    expect(pin.colorFormat).toBe(expected ? 'rgba32float' : 'rgba16float');
  });
});
