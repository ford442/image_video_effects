import {
  ADAPTER_ATTEMPT_LADDER,
  assertAdapterMeetsContract,
  buildRequiredLimits,
  BUFFER_SIZE_LIMIT_FLOORS,
  DEEP_WORKGROUP_LIMITS,
  LIMITS_TIERS,
  meetsDeepWorkgroupLimits,
  MINIMUM_COMPUTE_LIMITS,
  resolveLimitsTier,
  SPEC_DEFAULT_LIMITS,
} from './webgpuDevicePolicy';
import { UNIFORM_BUFFER_LAYOUT } from './types';

function makeLimits(overrides: Partial<GPUSupportedLimits> = {}): GPUSupportedLimits {
  const base: GPUSupportedLimits = {
    maxTextureDimension1D: 8192,
    maxTextureDimension2D: 8192,
    maxTextureDimension3D: 2048,
    maxTextureArrayLayers: 256,
    maxBindGroups: 4,
    maxBindGroupsPlusVertexBuffers: 24,
    maxBindingsPerBindGroup: 1000,
    maxDynamicUniformBuffersPerPipelineLayout: 8,
    maxDynamicStorageBuffersPerPipelineLayout: 4,
    maxSampledTexturesPerShaderStage: 16,
    maxSamplersPerShaderStage: 16,
    maxStorageBuffersPerShaderStage: 8,
    maxStorageTexturesPerShaderStage: 8,
    maxUniformBuffersPerShaderStage: 12,
    maxUniformBufferBindingSize: 65536,
    maxStorageBufferBindingSize: 134217728,
    minUniformBufferOffsetAlignment: 256,
    minStorageBufferOffsetAlignment: 256,
    maxVertexBuffers: 8,
    maxBufferSize: 268435456,
    maxVertexAttributes: 16,
    maxVertexBufferArrayStride: 2048,
    maxInterStageShaderComponents: 60,
    maxInterStageShaderVariables: 16,
    maxColorAttachments: 8,
    maxColorAttachmentBytesPerSample: 32,
    maxComputeWorkgroupStorageSize: 16384,
    maxComputeInvocationsPerWorkgroup: 256,
    maxComputeWorkgroupSizeX: 256,
    maxComputeWorkgroupSizeY: 256,
    maxComputeWorkgroupSizeZ: 64,
  } as unknown as GPUSupportedLimits;

  return { ...base, ...overrides };
}

function makeAdapter(limits: Partial<GPUSupportedLimits> = {}): GPUAdapter {
  const fullLimits = makeLimits(limits);
  return {
    limits: fullLimits,
    features: new Set<GPUFeatureName>(),
    requestDevice: vi.fn(),
  } as unknown as GPUAdapter;
}

describe('webgpuDevicePolicy', () => {
  describe('buildRequiredLimits', () => {
    it('requests nothing a core device already has: every base-tier limit is within the core defaults (#1512)', () => {
      expect(buildRequiredLimits(1920)).toEqual({});
      for (const [name, value] of Object.entries(LIMITS_TIERS.base)) {
        expect(value, name).toBeLessThanOrEqual(SPEC_DEFAULT_LIMITS.core[name as keyof typeof SPEC_DEFAULT_LIMITS.core]!);
      }
      // MINIMUM_COMPUTE_LIMITS (the C++ mirror) restates core defaults too: nothing in it can fail on core.
      for (const [name, value] of Object.entries(MINIMUM_COMPUTE_LIMITS)) {
        expect(value, name).toBeLessThanOrEqual(SPEC_DEFAULT_LIMITS.core[name as keyof typeof SPEC_DEFAULT_LIMITS.core]!);
      }
      expect(LIMITS_TIERS.base.maxUniformBufferBindingSize).toBe(UNIFORM_BUFFER_LAYOUT.TOTAL_SIZE);
    });

    it('asks a compatibility device for the base limits above the compat defaults', () => {
      expect(buildRequiredLimits(1920, undefined, { compat: true })).toEqual({ maxComputeInvocationsPerWorkgroup: 256 });
    });

    it('requests 32x32 / 1024 invocations when the adapter offers them', () => {
      const deep = makeLimits({
        maxComputeInvocationsPerWorkgroup: 1024,
        maxComputeWorkgroupSizeX: 1024,
        maxComputeWorkgroupSizeY: 1024,
      });
      expect(DEEP_WORKGROUP_LIMITS).toEqual({
        maxComputeWorkgroupSizeX: 32,
        maxComputeWorkgroupSizeY: 32,
        maxComputeInvocationsPerWorkgroup: 1024,
      });
      expect(buildRequiredLimits(1920, deep)).toMatchObject(DEEP_WORKGROUP_LIMITS);
      expect(LIMITS_TIERS['deep-workgroup']).toEqual(DEEP_WORKGROUP_LIMITS);
    });

    it('keeps 16x16 / 256 when the adapter falls short on any deep limit', () => {
      const shallow = makeLimits({ maxComputeInvocationsPerWorkgroup: 256 });
      const narrowY = makeLimits({
        maxComputeInvocationsPerWorkgroup: 1024,
        maxComputeWorkgroupSizeX: 1024,
        maxComputeWorkgroupSizeY: 16,
      });
      for (const limits of [shallow, narrowY, undefined]) {
        // Not requested at all: the core default (256 / 256×256) already covers 16×16 / 256.
        const required = buildRequiredLimits(1920, limits)!;
        expect(required).not.toHaveProperty('maxComputeInvocationsPerWorkgroup');
        expect(required).not.toHaveProperty('maxComputeWorkgroupSizeX');
      }
      expect(meetsDeepWorkgroupLimits(narrowY)).toBe(false);
    });

    it('requests the adapter buffer-size limits so the 2048 gate can see them (#1395)', () => {
      const fat = makeLimits({ maxBufferSize: 4294967296, maxStorageBufferBindingSize: 2147483648 });
      expect(buildRequiredLimits(1920, fat)).toMatchObject({
        maxBufferSize: 4294967296,
        maxStorageBufferBindingSize: 2147483648,
      });
    });

    it('leaves buffer-size limits at the spec default when the adapter offers no more', () => {
      expect(BUFFER_SIZE_LIMIT_FLOORS).toEqual({
        maxBufferSize: 268435456,
        maxStorageBufferBindingSize: 134217728,
      });
      const base = makeLimits({ maxBufferSize: 268435456, maxStorageBufferBindingSize: 134217728 });
      for (const limits of [base, undefined]) {
        const required = buildRequiredLimits(1920, limits)!;
        expect(required).not.toHaveProperty('maxBufferSize');
        expect(required).not.toHaveProperty('maxStorageBufferBindingSize');
      }
    });

    it('does not canvas-scale maxTextureDimension2D (no pointer / pixel-count need)', () => {
      // Regression: mis-ordered initWasmRenderer args once fed a heap pointer (~79984)
      // into the WASM CheckLimit need. The fixed 4096 floor is within every default.
      expect(buildRequiredLimits(79984)).not.toHaveProperty('maxTextureDimension2D');
      expect(buildRequiredLimits(79984, undefined, { compat: true })).not.toHaveProperty('maxTextureDimension2D');
    });
  });

  describe('assertAdapterMeetsContract', () => {
    it('returns ok when adapter limits are sufficient', () => {
      const adapter = makeAdapter();
      const result = assertAdapterMeetsContract(adapter, { maxCanvasDim: 1024 });
      expect(result.ok).toBe(true);
      expect(result.failures).toHaveLength(0);
    });

    it('returns ok for NVIDIA Pascal-class maxTextureDimension2D=16384', () => {
      const adapter = makeAdapter({ maxTextureDimension2D: 16384 });
      const result = assertAdapterMeetsContract(adapter, { maxCanvasDim: 79984 });
      expect(result.ok).toBe(true);
      expect(result.failures).toHaveLength(0);
    });

    it('returns failure with actionable message when limits are insufficient', () => {
      const adapter = makeAdapter({ maxBindingsPerBindGroup: 8 });
      const result = assertAdapterMeetsContract(adapter, { maxCanvasDim: 1024 });
      expect(result.ok).toBe(false);
      expect(result.message).toMatch(/compute/);
      expect(result.failures.some((f) => f.includes('maxBindingsPerBindGroup'))).toBe(true);
    });

    it('checks maxTextureDimension2D against the 4096 floor, not canvas dim', () => {
      expect(assertAdapterMeetsContract(makeAdapter({ maxTextureDimension2D: 4096 }), { maxCanvasDim: 79984 }).ok).toBe(true);
      const result = assertAdapterMeetsContract(makeAdapter({ maxTextureDimension2D: 2048 }), { maxCanvasDim: 1024 });
      expect(result.ok).toBe(false);
      expect(result.failures.some((f) => f.includes('maxTextureDimension2D') && f.includes('4096'))).toBe(true);
    });

    it('fails a compatibility adapter that cannot run 16×16 (256-invocation) workgroups', () => {
      const adapter = makeAdapter({ maxComputeInvocationsPerWorkgroup: 128 });
      const result = assertAdapterMeetsContract(adapter, { maxCanvasDim: 1024, compat: true });
      expect(result.ok).toBe(false);
      expect(result.failures.join(' ')).toContain('maxComputeInvocationsPerWorkgroup');
    });
  });

  describe('limits tiers (#1512)', () => {
    it('reports base / deep-workgroup / big-buffer from the device limits', () => {
      expect(resolveLimitsTier(makeLimits())).toBe('base');
      const deep = { maxComputeInvocationsPerWorkgroup: 1024, maxComputeWorkgroupSizeX: 1024, maxComputeWorkgroupSizeY: 1024 };
      expect(resolveLimitsTier(makeLimits(deep))).toBe('deep-workgroup');
      expect(resolveLimitsTier(makeLimits({ ...deep, maxBufferSize: 2 ** 31 }))).toBe('big-buffer');
      // Big buffers without deep workgroups stay "base": the tier name is cumulative.
      expect(resolveLimitsTier(makeLimits({ maxBufferSize: 2 ** 31 }))).toBe('base');
      expect(resolveLimitsTier(undefined)).toBe('base');
    });

    it('ends the adapter ladder with the compatibility rung', () => {
      expect(ADAPTER_ATTEMPT_LADDER.map((a) => a.label)).toEqual([
        'HighPerformance', 'Undefined', 'LowPower', 'Undefined+forceFallback', 'Compatibility',
      ]);
      expect(ADAPTER_ATTEMPT_LADDER.at(-1)).toMatchObject({ featureLevel: 'compatibility', forceFallbackAdapter: false });
    });
  });
});
