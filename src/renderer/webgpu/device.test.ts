/**
 * device.test.ts — optional feature collection, canvas configure, init paths.
 */

import {
  appendAdapterSummaryFields,
  buildCanvasConfigureOptions,
  collectOptionalDeviceFeatures,
  formatEnabledDeviceFeatures,
  initializeWebGPUDevice,
  resolveSubgroupFeatureName,
} from './device';
import { UNIFORM_BUFFER_LAYOUT } from '../types';

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
  const base = {
    maxTextureDimension2D: 8192,
    maxBindingsPerBindGroup: 1000,
    maxSampledTexturesPerShaderStage: 16,
    maxSamplersPerShaderStage: 16,
    maxStorageTexturesPerShaderStage: 8,
    maxStorageBuffersPerShaderStage: 8,
    maxUniformBuffersPerShaderStage: 12,
    maxUniformBufferBindingSize: 65536,
    maxComputeInvocationsPerWorkgroup: 256,
    maxComputeWorkgroupSizeX: 256,
    maxComputeWorkgroupSizeY: 256,
  } as unknown as GPUSupportedLimits;
  return { ...base, ...overrides };
}

function makeAdapter(
  featureNames: GPUFeatureName[] = [],
  limits: Partial<GPUSupportedLimits> = {},
): GPUAdapter {
  return {
    limits: makeLimits(limits),
    features: new Set(featureNames),
    info: { adapterType: 'discrete' } as unknown as GPUAdapterInfo,
    requestDevice: jest.fn(),
  } as unknown as GPUAdapter;
}

function makeDevice(featureNames: GPUFeatureName[] = []): GPUDevice {
  return {
    features: new Set(featureNames),
    limits: makeLimits({ maxTextureDimension2D: 4096, maxComputeInvocationsPerWorkgroup: 256 }),
    addEventListener: jest.fn(),
    destroy: jest.fn(),
    lost: Promise.resolve({ reason: 'destroyed', message: '' }),
    createShaderModule: jest.fn().mockReturnValue({}),
    createComputePipeline: jest.fn().mockReturnValue({}),
  } as unknown as GPUDevice;
}

describe('collectOptionalDeviceFeatures', () => {
  it('returns float32-filterable then timestamp-query in order', () => {
    const adapter = makeAdapter(['float32-filterable', 'timestamp-query']);
    expect(collectOptionalDeviceFeatures(adapter)).toEqual([
      'float32-filterable',
      'timestamp-query',
    ]);
  });

  it('omits timestamp-query when adapter lacks it', () => {
    const adapter = makeAdapter(['float32-filterable', 'subgroups']);
    expect(collectOptionalDeviceFeatures(adapter)).toEqual([
      'float32-filterable',
      'subgroups',
    ]);
  });

  it('prefers subgroups over chromium-experimental-subgroups', () => {
    const adapter = makeAdapter([
      'subgroups',
      'chromium-experimental-subgroups' as GPUFeatureName,
    ]);
    expect(collectOptionalDeviceFeatures(adapter)).toEqual(['subgroups']);
  });

  it('falls back to chromium-experimental-subgroups', () => {
    const adapter = makeAdapter(['chromium-experimental-subgroups' as GPUFeatureName]);
    expect(collectOptionalDeviceFeatures(adapter)).toEqual([
      'chromium-experimental-subgroups',
    ]);
  });
});

describe('formatEnabledDeviceFeatures', () => {
  it('lists only Pixelocity-requested features present on device', () => {
    const device = makeDevice(['float32-filterable', 'timestamp-query']);
    expect(formatEnabledDeviceFeatures(device)).toBe(
      'features=[float32-filterable,timestamp-query]',
    );
  });

  it('returns empty brackets when none enabled', () => {
    expect(formatEnabledDeviceFeatures(makeDevice())).toBe('features=[]');
  });
});

describe('buildCanvasConfigureOptions', () => {
  // WASM also calls ConfigureSurface() after JS_CreateSurfaceFromCanvas
  // (Fifo + width/height). Do not "unify" away that second configure.
  it('sets opaque alpha and RENDER_ATTACHMENT usage', () => {
    const device = makeDevice();
    const opts = buildCanvasConfigureOptions(device, 'bgra8unorm');
    expect(opts).toEqual({
      device,
      format: 'bgra8unorm',
      alphaMode: 'opaque',
      usage: TU.RENDER_ATTACHMENT,
    });
  });
});

describe('appendAdapterSummaryFields', () => {
  it('appends device limits, features, and surfaceFormat in order', () => {
    const device = makeDevice(['float32-filterable', 'timestamp-query']);
    const summary = appendAdapterSummaryFields('base', device, 'bgra8unorm');
    expect(summary).toBe(
      'base | device: maxTex2D=4096 computeInvocations=256 | features=[float32-filterable,timestamp-query] | surfaceFormat=bgra8unorm',
    );
  });
});

describe('resolveSubgroupFeatureName', () => {
  it('returns subgroups when available', () => {
    expect(resolveSubgroupFeatureName(makeAdapter(['subgroups']))).toBe('subgroups');
  });
});

describe('initializeWebGPUDevice', () => {
  const originalGpu = navigator.gpu;

  afterEach(() => {
    Object.defineProperty(navigator, 'gpu', {
      configurable: true,
      value: originalGpu,
    });
    jest.restoreAllMocks();
  });

  it('returns ok:false when navigator.gpu is missing', async () => {
    Object.defineProperty(navigator, 'gpu', { configurable: true, value: undefined });
    const canvas = document.createElement('canvas');
    const result = await initializeWebGPUDevice(canvas, 800, 600);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.adapterSummary).toBe('');
    }
  });

  it('returns ok:false when adapter ladder fails', async () => {
    const requestAdapter = jest.fn().mockResolvedValue(null);
    Object.defineProperty(navigator, 'gpu', {
      configurable: true,
      value: { requestAdapter, getPreferredCanvasFormat: () => 'bgra8unorm' },
    });
    const canvas = document.createElement('canvas');
    const result = await initializeWebGPUDevice(canvas, 800, 600);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.lastInitError).toMatch(/Failed to obtain a WebGPU adapter/);
    }
  });

  it('requests timestamp-query when adapter offers it', async () => {
    const mockDevice = makeDevice(['float32-filterable', 'timestamp-query']);
    const adapter = makeAdapter(['float32-filterable', 'timestamp-query']);
    (adapter.requestDevice as jest.Mock).mockResolvedValue(mockDevice);

    const configure = jest.fn();
    const canvas = {
      width: 800,
      height: 600,
      getContext: jest.fn().mockReturnValue({ configure, unconfigure: jest.fn() }),
    } as unknown as HTMLCanvasElement;

    const requestAdapter = jest.fn().mockResolvedValue(adapter);
    Object.defineProperty(navigator, 'gpu', {
      configurable: true,
      value: { requestAdapter, getPreferredCanvasFormat: () => 'bgra8unorm' },
    });

    const result = await initializeWebGPUDevice(canvas, 800, 600);
    expect(result.ok).toBe(true);
    expect(adapter.requestDevice).toHaveBeenCalledWith(
      expect.objectContaining({
        requiredFeatures: ['float32-filterable', 'timestamp-query'],
        requiredLimits: expect.objectContaining({
          maxBindingsPerBindGroup: 14,
          maxUniformBufferBindingSize: UNIFORM_BUFFER_LAYOUT.TOTAL_SIZE,
        }),
      }),
    );
    if (result.ok) {
      expect(result.adapterSummary).toContain('features=[float32-filterable,timestamp-query]');
      expect(result.adapterSummary).toContain('surfaceFormat=bgra8unorm');
    }
  });

  it('omits timestamp-query and still succeeds when adapter lacks it', async () => {
    const mockDevice = makeDevice(['float32-filterable']);
    const adapter = makeAdapter(['float32-filterable']);
    (adapter.requestDevice as jest.Mock).mockResolvedValue(mockDevice);

    const configure = jest.fn();
    const canvas = {
      width: 800,
      height: 600,
      getContext: jest.fn().mockReturnValue({ configure, unconfigure: jest.fn() }),
    } as unknown as HTMLCanvasElement;

    const requestAdapter = jest.fn().mockResolvedValue(adapter);
    Object.defineProperty(navigator, 'gpu', {
      configurable: true,
      value: { requestAdapter, getPreferredCanvasFormat: () => 'bgra8unorm' },
    });

    const result = await initializeWebGPUDevice(canvas, 800, 600);
    expect(result.ok).toBe(true);
    expect(adapter.requestDevice).toHaveBeenCalledWith(
      expect.objectContaining({
        requiredFeatures: ['float32-filterable'],
      }),
    );
    expect(configure).toHaveBeenCalledWith(
      expect.objectContaining({
        alphaMode: 'opaque',
        usage: TU.RENDER_ATTACHMENT,
        format: 'bgra8unorm',
      }),
    );
  });
});
