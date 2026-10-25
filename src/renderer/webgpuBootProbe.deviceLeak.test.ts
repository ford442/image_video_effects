/**
 * #1511 bug 9: a rejecting format probe must not leak the probe device.
 */
import { runWebGpuBootProbe } from './webgpuBootProbe';
import { probeFormatCapabilities } from '../config/formatPolicy';

vi.mock('../config/formatPolicy', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../config/formatPolicy')>();
  return { ...actual, probeFormatCapabilities: vi.fn(actual.probeFormatCapabilities) };
});

const LIMITS = {
  maxTextureDimension1D: 8192, maxTextureDimension2D: 8192, maxTextureDimension3D: 2048,
  maxTextureArrayLayers: 256, maxBindGroups: 4, maxBindGroupsPlusVertexBuffers: 24,
  maxBindingsPerBindGroup: 1000, maxDynamicUniformBuffersPerPipelineLayout: 8,
  maxDynamicStorageBuffersPerPipelineLayout: 4, maxSampledTexturesPerShaderStage: 16,
  maxSamplersPerShaderStage: 16, maxStorageBuffersPerShaderStage: 8, maxStorageTexturesPerShaderStage: 8,
  maxUniformBuffersPerShaderStage: 12, maxUniformBufferBindingSize: 65536,
  maxStorageBufferBindingSize: 134217728, minUniformBufferOffsetAlignment: 256,
  minStorageBufferOffsetAlignment: 256, maxVertexBuffers: 8, maxBufferSize: 268435456,
  maxVertexAttributes: 16, maxVertexBufferArrayStride: 2048, maxInterStageShaderComponents: 60,
  maxInterStageShaderVariables: 16, maxColorAttachments: 8, maxColorAttachmentBytesPerSample: 32,
  maxComputeWorkgroupStorageSize: 16384, maxComputeInvocationsPerWorkgroup: 256,
  maxComputeWorkgroupSizeX: 256, maxComputeWorkgroupSizeY: 256, maxComputeWorkgroupSizeZ: 64,
} as unknown as GPUSupportedLimits;

describe('webgpuBootProbe device cleanup (#1511 bug 9)', () => {
  const originalGpu = (navigator as Navigator & { gpu?: GPU }).gpu;
  beforeAll(() => {
    (global as unknown as { GPUTextureUsage: Record<string, number> }).GPUTextureUsage = {
      COPY_SRC: 0x01, COPY_DST: 0x02, TEXTURE_BINDING: 0x04, STORAGE_BINDING: 0x08, RENDER_ATTACHMENT: 0x10,
    };
  });
  afterEach(() => {
    (navigator as Navigator & { gpu?: GPU }).gpu = originalGpu;
  });

  it('destroys the probe device exactly once when probeFormatCapabilities rejects', async () => {
    const device = {
      limits: LIMITS,
      features: new Set<GPUFeatureName>(),
      createShaderModule: vi.fn(() => ({})),
      createComputePipeline: vi.fn(() => ({})),
      createTexture: vi.fn(() => ({ destroy: vi.fn() })),
      destroy: vi.fn(),
      addEventListener: vi.fn(),
    } as unknown as GPUDevice;
    const adapter = {
      limits: LIMITS,
      features: new Set<GPUFeatureName>(),
      info: { vendor: 'v', architecture: 'a', device: 'd', description: 'mock' },
      requestDevice: vi.fn().mockResolvedValue(device),
    } as unknown as GPUAdapter;
    const context = { configure: vi.fn(), unconfigure: vi.fn() } as unknown as GPUCanvasContext;
    const canvas = document.createElement('canvas');
    canvas.getContext = vi.fn(() => context) as unknown as typeof canvas.getContext;
    // Only the first ladder rung gets an adapter, so the leak check sees one device.
    (navigator as Navigator & { gpu?: GPU }).gpu = {
      requestAdapter: vi.fn().mockResolvedValueOnce(adapter).mockResolvedValue(null),
      getPreferredCanvasFormat: () => 'bgra8unorm',
    } as unknown as GPU;
    vi.mocked(probeFormatCapabilities).mockRejectedValueOnce(new Error('format probe exploded'));

    const result = await runWebGpuBootProbe(canvas, 1024, 1024);

    expect(probeFormatCapabilities).toHaveBeenCalledTimes(1);
    expect(device.destroy).toHaveBeenCalledTimes(1);
    expect(result.ok).toBe(false);
    expect(result.handoff).toBeUndefined();
    expect(result.attempts[0]).toMatchObject({ failedStage: 'probePipeline', error: 'format probe exploded' });
  });
});
