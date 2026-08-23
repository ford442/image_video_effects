/**
 * WebGPU boot probe tests (mocked GPU — no real adapter required).
 */

import {
  runWebGpuBootProbe,
  toWebGpuProbeBreadcrumb,
  publishWebGpuProbe,
  collectUserAgentBrands,
} from './webgpuBootProbe';
import { ADAPTER_ATTEMPT_LADDER } from './webgpuDevicePolicy';

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

function makeMockDevice(pipelineThrows = false): GPUDevice {
  const limits = makeLimits();
  const createComputePipeline = pipelineThrows
    ? jest.fn(() => {
        throw new Error('probe pipeline failed');
      })
    : jest.fn(() => ({} as GPUComputePipeline));

  return {
    limits,
    features: new Set<GPUFeatureName>(),
    createShaderModule: jest.fn(() => ({} as GPUShaderModule)),
    createComputePipeline,
    destroy: jest.fn(),
    addEventListener: jest.fn(),
  } as unknown as GPUDevice;
}

function makeMockAdapter(
  limits: Partial<GPUSupportedLimits> = {},
  device?: GPUDevice,
): GPUAdapter {
  const fullLimits = makeLimits(limits);
  const dev = device ?? makeMockDevice();
  return {
    limits: fullLimits,
    features: new Set<GPUFeatureName>(),
    info: {
      vendor: 'test-vendor',
      architecture: 'test-arch',
      device: 'test-device',
      description: 'mock adapter',
    },
    requestDevice: jest.fn().mockResolvedValue(dev),
  } as unknown as GPUAdapter;
}

function makeMockContext(): GPUCanvasContext {
  return {
    configure: jest.fn(),
    unconfigure: jest.fn(),
  } as unknown as GPUCanvasContext;
}

describe('webgpuBootProbe', () => {
  const originalGpu = (navigator as Navigator & { gpu?: GPU }).gpu;

  afterEach(() => {
    (navigator as Navigator & { gpu?: GPU }).gpu = originalGpu;
  });

  it('returns ok:false with ladder attempts when all adapters null', async () => {
    const requestAdapter = jest.fn().mockResolvedValue(null);
    (navigator as Navigator & { gpu?: GPU }).gpu = {
      requestAdapter,
      getPreferredCanvasFormat: () => 'bgra8unorm',
    } as unknown as GPU;

    const canvas = document.createElement('canvas');
    canvas.width = 1024;
    canvas.height = 1024;

    const result = await runWebGpuBootProbe(canvas, 1024, 1024);
    expect(result.ok).toBe(false);
    expect(result.attempts.length).toBe(ADAPTER_ATTEMPT_LADDER.length);
    expect(requestAdapter).toHaveBeenCalledTimes(ADAPTER_ATTEMPT_LADDER.length);
    expect(result.failedStage).toBe('requestAdapter');
    expect(toWebGpuProbeBreadcrumb(result)).not.toHaveProperty('handoff');
  });

  it('records contract failure and continues ladder', async () => {
    const badAdapter = makeMockAdapter({ maxBindingsPerBindGroup: 4 });
    const goodAdapter = makeMockAdapter();
    const requestAdapter = jest
      .fn()
      .mockResolvedValueOnce(badAdapter)
      .mockResolvedValueOnce(goodAdapter);

    const context = makeMockContext();
    const canvas = document.createElement('canvas');
    canvas.width = 1024;
    canvas.height = 1024;
    canvas.getContext = jest.fn(() => context) as unknown as typeof canvas.getContext;

    (navigator as Navigator & { gpu?: GPU }).gpu = {
      requestAdapter,
      getPreferredCanvasFormat: () => 'bgra8unorm',
    } as unknown as GPU;

    const result = await runWebGpuBootProbe(canvas, 1024, 1024);
    expect(result.ok).toBe(true);
    expect(result.handoff).toBeDefined();
    expect(result.attempts.some((a) => a.failedStage === 'contract')).toBe(true);
  });

  it('fails at probePipeline stage when pipeline create throws', async () => {
    const device = makeMockDevice(true);
    const adapter = makeMockAdapter({}, device);
    const requestAdapter = jest.fn().mockResolvedValue(adapter);
    const context = makeMockContext();
    const canvas = document.createElement('canvas');
    canvas.width = 1024;
    canvas.height = 1024;
    canvas.getContext = jest.fn(() => context) as unknown as typeof canvas.getContext;

    (navigator as Navigator & { gpu?: GPU }).gpu = {
      requestAdapter,
      getPreferredCanvasFormat: () => 'bgra8unorm',
    } as unknown as GPU;

    const result = await runWebGpuBootProbe(canvas, 1024, 1024);
    expect(result.ok).toBe(false);
    expect(result.attempts.some((a) => a.failedStage === 'probePipeline')).toBe(true);
    expect(device.destroy).toHaveBeenCalled();
  });

  it('collectUserAgentBrands returns array (may be empty in jsdom)', () => {
    const brands = collectUserAgentBrands();
    expect(Array.isArray(brands)).toBe(true);
  });

  it('returns early when navigator.gpu is missing', async () => {
    Object.defineProperty(navigator, 'gpu', { configurable: true, value: undefined });
    const canvas = document.createElement('canvas');
    const result = await runWebGpuBootProbe(canvas, 512, 512);
    expect(result.ok).toBe(false);
    expect(result.attempts).toHaveLength(0);
  });

  it('publishWebGpuProbe writes breadcrumb without handoff handles', async () => {
    const requestAdapter = jest.fn().mockResolvedValue(null);
    (navigator as Navigator & { gpu?: GPU }).gpu = {
      requestAdapter,
      getPreferredCanvasFormat: () => 'bgra8unorm',
    } as unknown as GPU;

    const canvas = document.createElement('canvas');
    const result = await runWebGpuBootProbe(canvas, 512, 512);
    publishWebGpuProbe(result);
    expect(window.webgpuProbe).toBeDefined();
    expect(window.webgpuProbe?.ok).toBe(false);
    expect(window.webgpuProbe?.attempts.length).toBe(ADAPTER_ATTEMPT_LADDER.length);
    expect(Array.isArray(window.webgpuProbe?.userAgentBrands)).toBe(true);
    expect(window.webgpuProbe).not.toHaveProperty('handoff');
    delete window.webgpuProbe;
  });

  it('success path returns handoff and ok:true', async () => {
    const adapter = makeMockAdapter();
    const context = makeMockContext();
    const canvas = document.createElement('canvas');
    canvas.width = 1024;
    canvas.height = 1024;
    canvas.getContext = jest.fn(() => context) as unknown as typeof canvas.getContext;

    (navigator as Navigator & { gpu?: GPU }).gpu = {
      requestAdapter: jest.fn().mockResolvedValue(adapter),
      getPreferredCanvasFormat: () => 'bgra8unorm',
    } as unknown as GPU;

    const result = await runWebGpuBootProbe(canvas, 1024, 1024);
    expect(result.ok).toBe(true);
    expect(result.handoff?.device).toBeDefined();
    expect(result.adapterAttemptLabel).toBe('HighPerformance');
    const crumb = toWebGpuProbeBreadcrumb(result);
    expect(crumb.ok).toBe(true);
    expect(crumb).not.toHaveProperty('handoff');
  });
});
