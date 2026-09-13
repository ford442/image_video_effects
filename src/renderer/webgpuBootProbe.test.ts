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
    createTexture: jest.fn((desc: GPUTextureDescriptor) => ({
      destroy: jest.fn(),
      format: desc.format,
    } as unknown as GPUTexture)),
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

  describe('canvas configure opt-ins', () => {
    function setup(context: GPUCanvasContext, device: GPUDevice = makeMockDevice()) {
      const canvas = document.createElement('canvas');
      canvas.width = 1024;
      canvas.height = 1024;
      canvas.getContext = jest.fn(() => context) as unknown as typeof canvas.getContext;
      (navigator as Navigator & { gpu?: GPU }).gpu = {
        requestAdapter: jest.fn().mockResolvedValue(makeMockAdapter({}, device)),
        getPreferredCanvasFormat: () => 'bgra8unorm',
      } as unknown as GPU;
      return canvas;
    }

    const lastConfig = (context: GPUCanvasContext) => {
      const calls = (context.configure as jest.Mock).mock.calls;
      return calls[calls.length - 1][0] as GPUCanvasConfiguration;
    };

    it('records canvasCopySrc=true and restores render-only usage', async () => {
      const context = makeMockContext();
      const result = await runWebGpuBootProbe(setup(context), 1024, 1024);
      expect(result.ok).toBe(true);
      expect(result.canvasCopySrc).toBe(true);
      expect(result.handoff?.canvasCopySrc).toBe(true);
      expect(result.canvasColorSpace).toBe('srgb');
      expect(result.canvasToneMapping).toBe('standard');
      expect(toWebGpuProbeBreadcrumb(result).canvasCopySrc).toBe(true);
      const configs = (context.configure as jest.Mock).mock.calls.map((c) => c[0]);
      expect(configs[0].usage).toBe(0x10);
      expect(configs.some((c: GPUCanvasConfiguration) => c.usage === (0x10 | 0x01))).toBe(true);
      expect(lastConfig(context)).toMatchObject({ alphaMode: 'opaque', usage: 0x10 });
      expect(lastConfig(context)).not.toHaveProperty('colorSpace');
    });

    it('fails soft when configure throws for COPY_SRC', async () => {
      const context = makeMockContext();
      (context.configure as jest.Mock).mockImplementation((c: GPUCanvasConfiguration) => {
        if ((c.usage as number) & 0x01) throw new Error('COPY_SRC unsupported');
      });
      const result = await runWebGpuBootProbe(setup(context), 1024, 1024);
      expect(result.ok).toBe(true);
      expect(result.canvasCopySrc).toBe(false);
      expect(result.attempts.every((a) => a.failedStage === undefined)).toBe(true);
      expect(lastConfig(context).usage).toBe(0x10);
    });

    it('fails soft when COPY_SRC raises a validation error scope', async () => {
      const device = makeMockDevice();
      const context = makeMockContext();
      let pending: GPUCanvasConfiguration | null = null;
      (context.configure as jest.Mock).mockImplementation((c: GPUCanvasConfiguration) => {
        pending = c;
      });
      Object.assign(device, {
        pushErrorScope: jest.fn(),
        popErrorScope: jest.fn(async () =>
          pending && (pending.usage as number) & 0x01 ? { message: 'bad usage' } : null,
        ),
      });
      const result = await runWebGpuBootProbe(setup(context, device), 1024, 1024);
      expect(result.ok).toBe(true);
      expect(result.canvasCopySrc).toBe(false);
      expect(lastConfig(context).usage).toBe(0x10);
    });

    it('does not request display-p3 by default', async () => {
      const context = makeMockContext();
      await runWebGpuBootProbe(setup(context), 1024, 1024);
      const configs = (context.configure as jest.Mock).mock.calls.map((c) => c[0]);
      expect(configs.some((c: GPUCanvasConfiguration) => 'colorSpace' in c)).toBe(false);
    });

    describe('with ?display_p3=1', () => {
      const originalUrl = window.location.href;
      beforeEach(() => window.history.replaceState(null, '', '/?display_p3=1'));
      afterEach(() => window.history.replaceState(null, '', originalUrl));

      it('applies display-p3 when accepted', async () => {
        const context = makeMockContext();
        const result = await runWebGpuBootProbe(setup(context), 1024, 1024);
        expect(result.canvasColorSpace).toBe('display-p3');
        expect(result.handoff?.canvasColorOptIns.displayP3).toBe(true);
        expect(lastConfig(context)).toMatchObject({ colorSpace: 'display-p3', usage: 0x10 });
      });

      it('falls back to srgb when getConfiguration reports srgb', async () => {
        const context = makeMockContext();
        Object.assign(context, { getConfiguration: () => ({ colorSpace: 'srgb', usage: 0x11 }) });
        const result = await runWebGpuBootProbe(setup(context), 1024, 1024);
        expect(result.ok).toBe(true);
        expect(result.canvasColorSpace).toBe('srgb');
        expect(lastConfig(context)).not.toHaveProperty('colorSpace');
      });
    });
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
    expect(result.handoff?.formatCapabilities.supportsRgba32FloatStorage).toBe(true);
    expect(result.handoff?.formatCapabilities.supportsRgba16FloatStorage).toBe(true);
    expect(result.formatCapabilities?.supportsRgba32FloatStorage).toBe(true);
    expect(result.adapterAttemptLabel).toBe('HighPerformance');
    const crumb = toWebGpuProbeBreadcrumb(result);
    expect(crumb.ok).toBe(true);
    expect(crumb).not.toHaveProperty('handoff');
  });
});
