import {
  ADAPTER_ATTEMPT_LADDER,
  assertAdapterMeetsContract,
  BASE_LIMITS,
  buildRequiredLimits,
  BUFFER_SIZE_LIMIT_FLOORS,
  DEEP_WORKGROUP_LIMITS,
  isCompatibilityDevice,
  meetsDeepWorkgroupLimits,
  MINIMUM_COMPUTE_LIMITS,
  resolveAdapterLadder,
  resolveLimitsTiers,
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
    it('requests no base limit on a core adapter: every one is at or below the spec default (#1512)', () => {
      for (const name of Object.keys(BASE_LIMITS) as Array<keyof typeof BASE_LIMITS>) {
        expect(BASE_LIMITS[name]).toBeLessThanOrEqual(SPEC_DEFAULT_LIMITS.core[name]);
      }
      expect(buildRequiredLimits(1920, makeLimits())).toEqual({});
      expect(buildRequiredLimits(1920)).toEqual({});
      // The C++ mirror keeps its explicit floors (webgpu_limits.h).
      expect(MINIMUM_COMPUTE_LIMITS.maxUniformBufferBindingSize).toBe(UNIFORM_BUFFER_LAYOUT.TOTAL_SIZE);
      expect(MINIMUM_COMPUTE_LIMITS.maxTextureDimension2D).toBe(8192);
    });

    it('requests what a compatibility device lacks: 256 invocations and up to 8192 texels', () => {
      const compatAdapter = makeLimits({ maxTextureDimension2D: 16384 });
      expect(buildRequiredLimits(1920, compatAdapter, 'compatibility')).toEqual({
        maxComputeInvocationsPerWorkgroup: 256,
        maxTextureDimension2D: 8192,
      });
      // A GL ES adapter that stops at 4096 is still enough (the canvas is <= 2048).
      expect(buildRequiredLimits(1920, makeLimits({ maxTextureDimension2D: 4096 }), 'compatibility'))
        .toEqual({ maxComputeInvocationsPerWorkgroup: 256 });
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
      expect(buildRequiredLimits(1920, deep, 'compatibility')).toMatchObject(DEEP_WORKGROUP_LIMITS);
    });

    it('keeps 16x16 / 256 when the adapter falls short on any deep limit', () => {
      const shallow = makeLimits({ maxComputeInvocationsPerWorkgroup: 256 });
      const narrowY = makeLimits({
        maxComputeInvocationsPerWorkgroup: 1024,
        maxComputeWorkgroupSizeX: 1024,
        maxComputeWorkgroupSizeY: 16,
      });
      for (const limits of [shallow, narrowY, undefined]) {
        // The core default (256 / 256×256) already covers the 16×16 catalog: nothing to ask for.
        expect(buildRequiredLimits(1920, limits)).not.toHaveProperty('maxComputeInvocationsPerWorkgroup');
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
      // into the WASM CheckLimit need. Only the adapter and the 8192 comfort cap decide.
      expect(buildRequiredLimits(79984)).not.toHaveProperty('maxTextureDimension2D');
      expect(buildRequiredLimits(79984, makeLimits({ maxTextureDimension2D: 16384 }), 'compatibility')!.maxTextureDimension2D)
        .toBe(8192);
    });
  });

  describe('limits tiers and the compatibility rung (#1512)', () => {
    it('probes base / deep-workgroup / big-buffer from granted limits', () => {
      expect(resolveLimitsTiers(makeLimits())).toEqual(['base']);
      expect(resolveLimitsTiers(makeLimits({
        maxComputeInvocationsPerWorkgroup: 1024,
        maxComputeWorkgroupSizeX: 1024,
        maxComputeWorkgroupSizeY: 1024,
        maxBufferSize: 2 ** 31,
      }))).toEqual(['base', 'deep-workgroup', 'big-buffer']);
      // A compat device that was not granted 256 invocations misses the base tier.
      expect(resolveLimitsTiers(makeLimits({ maxComputeInvocationsPerWorkgroup: 128 }))).toEqual([]);
    });

    it('ends the ladder with the compatibility rung and can start there', () => {
      expect(ADAPTER_ATTEMPT_LADDER.at(-1)).toMatchObject({ featureLevel: 'compatibility', label: 'Compatibility' });
      expect(ADAPTER_ATTEMPT_LADDER.slice(0, 4).every((a) => a.featureLevel === undefined)).toBe(true);
      expect(resolveAdapterLadder('?feature_level=compatibility')).toEqual([ADAPTER_ATTEMPT_LADDER.at(-1)]);
      expect(resolveAdapterLadder('')).toBe(ADAPTER_ATTEMPT_LADDER);
    });

    it('treats a device as compat only on the compat rung without core-features-and-limits', () => {
      const device = (features: string[]) => ({ features: new Set(features) }) as unknown as GPUDevice;
      expect(isCompatibilityDevice(device([]), 'compatibility')).toBe(true);
      expect(isCompatibilityDevice(device(['core-features-and-limits']), 'compatibility')).toBe(false);
      expect(isCompatibilityDevice(device([]), undefined)).toBe(false);
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

    it('checks maxTextureDimension2D against the minimum viable 4096, not canvas dim', () => {
      expect(assertAdapterMeetsContract(makeAdapter({ maxTextureDimension2D: 4096 }), { maxCanvasDim: 79984 }).ok).toBe(true);
      const result = assertAdapterMeetsContract(makeAdapter({ maxTextureDimension2D: 2048 }), { maxCanvasDim: 1024 });
      expect(result.ok).toBe(false);
      expect(result.failures.some((f) => f.includes('maxTextureDimension2D') && f.includes('4096'))).toBe(true);
    });

    it('validates the 256 invocations the 16×16 catalog needs (a compat adapter may stop at 128)', () => {
      const result = assertAdapterMeetsContract(makeAdapter({ maxComputeInvocationsPerWorkgroup: 128 }));
      expect(result.ok).toBe(false);
      expect(result.failures.join(' ')).toContain('maxComputeInvocationsPerWorkgroup');
    });
  });
});
