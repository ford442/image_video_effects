import {
  ADAPTER_ATTEMPT_LADDER,
  assertAdapterMeetsContract,
  buildRequiredLimits,
  MINIMUM_COMPUTE_LIMITS,
  requestAdapterWithFallback,
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
    requestDevice: jest.fn(),
  } as unknown as GPUAdapter;
}

describe('webgpuDevicePolicy', () => {
  describe('buildRequiredLimits', () => {
    it('always includes explicit requiredLimits matching C++ CreateDevice policy', () => {
      const limits = buildRequiredLimits(1920);
      expect(limits).toMatchObject({
        maxTextureDimension2D: 8192,
        maxBindingsPerBindGroup: 14,
        maxSampledTexturesPerShaderStage: 3,
        maxSamplersPerShaderStage: 3,
        maxStorageTexturesPerShaderStage: 4,
        maxStorageBuffersPerShaderStage: 2,
        maxUniformBuffersPerShaderStage: 1,
        maxUniformBufferBindingSize: UNIFORM_BUFFER_LAYOUT.TOTAL_SIZE,
        maxComputeWorkgroupSizeX: 16,
        maxComputeWorkgroupSizeY: 16,
        maxComputeInvocationsPerWorkgroup: 256,
      });
      expect(limits!.maxUniformBufferBindingSize).toBe(MINIMUM_COMPUTE_LIMITS.maxUniformBufferBindingSize);
      expect(limits!.maxTextureDimension2D).toBe(MINIMUM_COMPUTE_LIMITS.maxTextureDimension2D);
    });

    it('does not canvas-scale maxTextureDimension2D (no pointer / pixel-count need)', () => {
      // Regression: mis-ordered initWasmRenderer args once fed a heap pointer (~79984)
      // into the WASM CheckLimit need. The JS mirror must stay on the named 8192 floor.
      expect(buildRequiredLimits(79984)!.maxTextureDimension2D).toBe(8192);
      expect(buildRequiredLimits(2048)!.maxTextureDimension2D).toBe(8192);
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

    it('checks maxTextureDimension2D against the named 8192 floor, not canvas dim', () => {
      const adapter = makeAdapter({ maxTextureDimension2D: 4096 });
      const result = assertAdapterMeetsContract(adapter, { maxCanvasDim: 1024 });
      expect(result.ok).toBe(false);
      expect(result.failures.some((f) => f.includes('maxTextureDimension2D') && f.includes('8192'))).toBe(true);
    });
  });

  describe('requestAdapterWithFallback', () => {
    it('tries the 4-step ladder until an adapter is returned', async () => {
      const mockAdapter = makeAdapter();
      const requestAdapter = jest
        .fn()
        .mockResolvedValueOnce(null)
        .mockResolvedValueOnce(null)
        .mockResolvedValueOnce(mockAdapter);

      const gpu = { requestAdapter } as unknown as GPU;
      const { adapter, attemptLabel, attemptLogs } = await requestAdapterWithFallback(gpu);

      expect(adapter).toBe(mockAdapter);
      expect(attemptLabel).toBe('LowPower');
      expect(requestAdapter).toHaveBeenCalledTimes(3);
      expect(attemptLogs.length).toBe(3);
      expect(attemptLogs[2].adapterPresent).toBe(true);
    });

    it('returns null after all ladder attempts fail', async () => {
      const requestAdapter = jest.fn().mockResolvedValue(null);
      const gpu = { requestAdapter } as unknown as GPU;
      const { adapter, attemptLogs } = await requestAdapterWithFallback(gpu);
      expect(adapter).toBeNull();
      expect(requestAdapter).toHaveBeenCalledTimes(ADAPTER_ATTEMPT_LADDER.length);
      expect(attemptLogs.length).toBe(ADAPTER_ATTEMPT_LADDER.length);
      expect(attemptLogs.every((l) => !l.adapterPresent)).toBe(true);
    });

    it('passes forceFallbackAdapter on the final attempt', async () => {
      const requestAdapter = jest.fn().mockResolvedValue(null);
      const gpu = { requestAdapter } as unknown as GPU;
      await requestAdapterWithFallback(gpu);

      const lastCall = requestAdapter.mock.calls[ADAPTER_ATTEMPT_LADDER.length - 1][0];
      expect(lastCall.forceFallbackAdapter).toBe(true);
    });
  });
});
