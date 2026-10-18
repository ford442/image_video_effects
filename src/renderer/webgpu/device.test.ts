/**
 * device.test.ts — optional feature collection, canvas configure, init paths.
 */

import type { Mock } from 'vitest';
import {
  appendAdapterSummaryFields,
  attachUncapturedErrorRouter,
  buildCanvasConfigureOptions,
  collectOptionalDeviceFeatures,
  createErrorRateLimiter,
  formatEnabledDeviceFeatures,
  initializeWebGPUDevice,
  resolveCanvasColorOptIns,
  resolveSubgroupFeatureName,
  attachDeviceLostHandler,
} from './device';
import canvasConfigureContract from '../../contracts/canvas_configure.json';
import { setRendererErrorHandler, type RendererError } from '../ErrorHandling';
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
    requestDevice: vi.fn(),
  } as unknown as GPUAdapter;
}

function makeDevice(featureNames: GPUFeatureName[] = []): GPUDevice {
  return {
    features: new Set(featureNames),
    limits: makeLimits({ maxTextureDimension2D: 4096, maxComputeInvocationsPerWorkgroup: 256 }),
    addEventListener: vi.fn(),
    destroy: vi.fn(),
    lost: Promise.resolve({ reason: 'destroyed', message: '' }),
    createShaderModule: vi.fn().mockReturnValue({}),
    createComputePipeline: vi.fn().mockReturnValue({}),
    createTexture: vi.fn(() => ({ destroy: vi.fn() })),
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
    expect(opts).not.toHaveProperty('colorSpace');
    expect(opts).not.toHaveProperty('toneMapping');
    expect(opts).not.toHaveProperty('presentMode');
  });

  it('adds COPY_SRC only when opted in', () => {
    const device = makeDevice();
    const opts = buildCanvasConfigureOptions(device, 'rgba8unorm', { copySrc: true });
    expect(opts.usage).toBe(TU.RENDER_ATTACHMENT | TU.COPY_SRC);
    expect(opts.alphaMode).toBe('opaque');
    expect(opts.format).toBe('rgba8unorm');
  });

  it('sets display-p3 only when opted in', () => {
    const opts = buildCanvasConfigureOptions(makeDevice(), 'bgra8unorm', { displayP3: true });
    expect(opts.colorSpace).toBe('display-p3');
    expect(opts).not.toHaveProperty('toneMapping');
  });

  it('ignores extended tone mapping without the display-p3 opt-in', () => {
    const opts = buildCanvasConfigureOptions(makeDevice(), 'bgra8unorm', { extendedToneMapping: true });
    expect(opts).not.toHaveProperty('colorSpace');
    expect(opts).not.toHaveProperty('toneMapping');
  });

  it('sets extended tone mapping behind display-p3', () => {
    const opts = buildCanvasConfigureOptions(makeDevice(), 'bgra8unorm', {
      displayP3: true,
      extendedToneMapping: true,
    });
    expect(opts).toMatchObject({ colorSpace: 'display-p3', toneMapping: { mode: 'extended' } });
  });
});

describe('canvas_configure.json contract', () => {
  it('keeps conservative v1 defaults', () => {
    expect(canvasConfigureContract).toMatchObject({
      alphaMode: 'opaque',
      usage: ['RENDER_ATTACHMENT'],
      presentModeWasm: 'fifo',
      colorSpace: 'srgb',
      toneMapping: 'standard',
    });
  });

  it('usageBits match the WebGPU spec GPUTextureUsage bits', () => {
    for (const [name, bit] of Object.entries(canvasConfigureContract.usageBits)) {
      expect(TU[name as keyof typeof TU]).toBe(bit);
    }
  });

  it('declares backends for every capability (copySrc on both, color TS-only)', () => {
    const backends = Object.fromEntries(
      Object.entries(canvasConfigureContract.optIn).map(([k, v]) => [k, v.backends]),
    );
    expect(backends).toEqual({
      copySrc: ['ts', 'wasm'],
      displayP3: ['ts'],
      extendedToneMapping: ['ts'],
    });
    expect(canvasConfigureContract.optIn.extendedToneMapping.requires).toBe('displayP3');
  });

  it('keeps the generated C++ header in sync with the JSON', () => {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const gen = require('../../../scripts/gen-canvas-configure-header.js') as {
      renderHeader: (c: unknown) => string;
      headerPath: (c: unknown) => string;
    };
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const fs = require('fs') as typeof import('fs');
    const header = gen.renderHeader(canvasConfigureContract);
    expect(fs.readFileSync(gen.headerPath(canvasConfigureContract), 'utf8')).toBe(header);
    expect(header).toContain('kUsage = WGPUTextureUsage_RenderAttachment;');
    expect(header).toContain('kCopySrcUsage = WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_CopySrc;');
    expect(header).toContain('kAlphaModeJs = "opaque";');
    expect(header).toContain('kPresentMode = WGPUPresentMode_Fifo;');
  });
});

describe('resolveCanvasColorOptIns', () => {
  it('is off by default', () => {
    expect(resolveCanvasColorOptIns('', () => true)).toEqual({
      displayP3: false,
      extendedToneMapping: false,
    });
  });

  it('enables display-p3 from ?display_p3=1 on SDR displays', () => {
    expect(resolveCanvasColorOptIns('?display_p3=1', () => false)).toEqual({
      displayP3: true,
      extendedToneMapping: false,
    });
  });

  it('enables extended tone mapping only with display-p3 on HDR displays', () => {
    expect(resolveCanvasColorOptIns('display_p3=1&x=2', () => true)).toEqual({
      displayP3: true,
      extendedToneMapping: true,
    });
    expect(resolveCanvasColorOptIns('?display_p3=0', () => true).extendedToneMapping).toBe(false);
  });

  it('honors the persisted setting without a URL param', () => {
    expect(resolveCanvasColorOptIns('', () => false, true)).toEqual({ displayP3: true, extendedToneMapping: false });
    expect(resolveCanvasColorOptIns('', () => true, true)).toEqual({ displayP3: true, extendedToneMapping: true });
  });

  it('keeps a stored-off setting off, and lets the URL force it on', () => {
    expect(resolveCanvasColorOptIns('', () => true, false).displayP3).toBe(false);
    expect(resolveCanvasColorOptIns('?display_p3=1', () => false, false).displayP3).toBe(true);
  });

  it('declares the storage key in the contract', () => {
    expect(canvasConfigureContract.optIn.displayP3.storageKey).toBe('px_display_p3');
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
    vi.restoreAllMocks();
  });

  it('returns ok:false when navigator.gpu is missing', async () => {
    Object.defineProperty(navigator, 'gpu', { configurable: true, value: undefined });
    const canvas = document.createElement('canvas');
    const result = await initializeWebGPUDevice(canvas, 800, 600);
    expect(result).toMatchObject({ ok: false, adapterSummary: '' });
  });

  it('returns ok:false when adapter ladder fails', async () => {
    const requestAdapter = vi.fn().mockResolvedValue(null);
    Object.defineProperty(navigator, 'gpu', {
      configurable: true,
      value: { requestAdapter, getPreferredCanvasFormat: () => 'bgra8unorm' },
    });
    const canvas = document.createElement('canvas');
    const result = await initializeWebGPUDevice(canvas, 800, 600);
    expect(result).toMatchObject({
      ok: false,
      lastInitError: expect.stringMatching(/Failed to obtain a WebGPU adapter/),
    });
  });

  it('requests timestamp-query when adapter offers it', async () => {
    const mockDevice = makeDevice(['float32-filterable', 'timestamp-query']);
    const adapter = makeAdapter(['float32-filterable', 'timestamp-query']);
    (adapter.requestDevice as Mock).mockResolvedValue(mockDevice);

    const configure = vi.fn();
    const canvas = {
      width: 800,
      height: 600,
      getContext: vi.fn().mockReturnValue({ configure, unconfigure: vi.fn() }),
    } as unknown as HTMLCanvasElement;

    const requestAdapter = vi.fn().mockResolvedValue(adapter);
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
    const summary = result.ok ? result.adapterSummary : '';
    expect(summary).toContain('features=[float32-filterable,timestamp-query]');
    expect(summary).toContain('surfaceFormat=bgra8unorm');
  });

  it('omits timestamp-query and still succeeds when adapter lacks it', async () => {
    const mockDevice = makeDevice(['float32-filterable']);
    const adapter = makeAdapter(['float32-filterable']);
    (adapter.requestDevice as Mock).mockResolvedValue(mockDevice);

    const configure = vi.fn();
    const canvas = {
      width: 800,
      height: 600,
      getContext: vi.fn().mockReturnValue({ configure, unconfigure: vi.fn() }),
    } as unknown as HTMLCanvasElement;

    const requestAdapter = vi.fn().mockResolvedValue(adapter);
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

describe('uncaptured error routing', () => {
  it('rate limits per message and per minute', () => {
    let now = 0;
    const allow = createErrorRateLimiter(() => now, { perMessageMs: 5000, maxPerMinute: 3 });
    expect(allow('a')).toBe(true);
    expect(allow('a')).toBe(false);
    now = 5000;
    expect(allow('a')).toBe(true);
    expect(allow('b')).toBe(true);
    expect(allow('c')).toBe(false); // 3 per minute reached
    now = 61_000;
    expect(allow('c')).toBe(true);
  });

  it('sends OOM to onOom and validation errors to reportError, and detaches', () => {
    const reported: RendererError[] = [];
    setRendererErrorHandler((e) => reported.push(e));
    let listener: ((ev: Event) => void) | null = null;
    const device = {
      addEventListener: vi.fn((_t: string, fn: (ev: Event) => void) => { listener = fn; }),
      removeEventListener: vi.fn(() => { listener = null; }),
    } as unknown as GPUDevice;
    const onOom = vi.fn();
    const detach = attachUncapturedErrorRouter(device, { onOom });

    listener!({ error: { name: 'GPUOutOfMemoryError', message: 'oom' } } as unknown as Event);
    listener!({ error: { name: 'GPUValidationError', message: 'bad layout' } } as unknown as Event);
    expect(onOom).toHaveBeenCalledTimes(1);
    expect(reported).toEqual([
      { type: 'gpu-validation', message: 'GPUValidationError: bad layout', recoverable: true },
    ]);

    detach();
    expect(listener).toBeNull();
    setRendererErrorHandler((e) => console.error(e));
  });
});

describe('attachDeviceLostHandler', () => {
  const errors: RendererError[] = [];
  beforeEach(() => {
    errors.length = 0;
    setRendererErrorHandler((e) => errors.push(e));
    vi.spyOn(console, 'error').mockImplementation(() => undefined);
  });
  afterEach(() => {
    vi.restoreAllMocks();
    setRendererErrorHandler((e) => console.error(e));
  });

  function lostDevice(info: { reason: string; message: string }) {
    return { lost: Promise.resolve(info) } as unknown as GPUDevice;
  }
  const ctx = () => ({ unconfigure: vi.fn() }) as unknown as GPUCanvasContext & { unconfigure: Mock };
  const settle = () => new Promise((r) => setTimeout(r, 0));

  it('a real loss is reported as recoverable, unconfigures and calls onLost once', async () => {
    const context = ctx();
    const onLost = vi.fn();
    attachDeviceLostHandler(lostDevice({ reason: 'unknown', message: 'driver reset' }), context, onLost);
    await settle();
    expect(onLost).toHaveBeenCalledTimes(1);
    expect(onLost).toHaveBeenCalledWith({ reason: 'unknown', message: 'driver reset' });
    expect(context.unconfigure).toHaveBeenCalled();
    expect(errors).toEqual([expect.objectContaining({ type: 'device-lost', recoverable: true })]);
    expect(errors[0]!.message).not.toMatch(/reload/i);
  });

  it('a destroy is silent and leaves the (possibly reused) context alone', async () => {
    const context = ctx();
    const onLost = vi.fn();
    attachDeviceLostHandler(lostDevice({ reason: 'destroyed', message: '' }), context, onLost);
    await settle();
    expect(onLost).not.toHaveBeenCalled();
    expect(context.unconfigure).not.toHaveBeenCalled();
    expect(errors).toEqual([]);
  });

  it('a simulated loss (test hook destroy) takes the loss path', async () => {
    const onLost = vi.fn();
    attachDeviceLostHandler(lostDevice({ reason: 'destroyed', message: '' }), ctx(), onLost, {
      isSimulated: () => true,
    });
    await settle();
    expect(onLost).toHaveBeenCalledWith(expect.objectContaining({ reason: 'simulated' }));
    expect(errors).toHaveLength(1);
  });
});
