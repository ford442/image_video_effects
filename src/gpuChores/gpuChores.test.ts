import {
  autoExposureFromHistogram,
  autoExposureFromMean,
  applyGain2d,
  buildLumaClassifyLut,
  classifyBandsToRgba,
  downsample2d,
  GpuChoresHost,
  HISTOGRAM_BINS,
  isGpuComputeKillSwitchEnabled,
  lumaBt709,
  lumaHistogramBt709,
  lumaToBin,
  lutU8Map,
  MIDDLE_GREY,
  PREVIEW_SIZE,
  reduceF32FromHistogram,
  reduceF32Luma,
  shouldEncodeSourceGain,
  shrinkCpuSource,
  sourceGainStatus,
  unpackClassifyRgba8,
} from './index';

function solidRgba(w: number, h: number, r: number, g: number, b: number, a = 1): Float32Array {
  const out = new Float32Array(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    out[i * 4] = r;
    out[i * 4 + 1] = g;
    out[i * 4 + 2] = b;
    out[i * 4 + 3] = a;
  }
  return out;
}

function probeOk(): void {
  window.webgpuProbe = {
    ok: true,
    finishedAt: new Date().toISOString(),
    userAgent: 'test',
    userAgentBrands: [],
    attempts: [],
  };
}

function stubTexture(): GPUTexture {
  return {
    createView: () => ({}),
    destroy: () => {},
  } as unknown as GPUTexture;
}

function stubBuffer(): GPUBuffer {
  return {
    destroy: () => {},
    mapAsync: async () => {},
    getMappedRange: () => new ArrayBuffer(4),
    unmap: () => {},
  } as unknown as GPUBuffer;
}

/** Minimal adopted device so GpuChoresHost.createGpu succeeds in Jest. */
function stubAdoptedGpuDevice(): GPUDevice {
  const g = globalThis as Record<string, unknown>;
  if (!g.GPUShaderStage) g.GPUShaderStage = { COMPUTE: 4 };
  if (!g.GPUBufferUsage) {
    g.GPUBufferUsage = {
      MAP_READ: 1,
      COPY_SRC: 4,
      COPY_DST: 8,
      UNIFORM: 64,
      STORAGE: 128,
    };
  }
  if (!g.GPUTextureUsage) {
    g.GPUTextureUsage = {
      COPY_SRC: 1,
      COPY_DST: 2,
      TEXTURE_BINDING: 4,
      STORAGE_BINDING: 8,
    };
  }
  return {
    createShaderModule: () => ({}),
    createComputePipeline: () => ({}),
    createPipelineLayout: () => ({}),
    createBindGroupLayout: () => ({}),
    createBindGroup: () => ({}),
    createBuffer: () => stubBuffer(),
    createTexture: () => stubTexture(),
    createCommandEncoder: () => ({
      copyBufferToBuffer() {},
      copyTextureToBuffer() {},
      finish() { return {}; },
    }),
    queue: {
      writeBuffer() {},
      submit() {},
    },
  } as unknown as GPUDevice;
}

interface DispatchRecord {
  label: string;
  x: number;
  y: number;
  z?: number;
}

function spyEncoder(labels: string[], dispatches?: DispatchRecord[]) {
  return {
    beginComputePass: (desc?: { label?: string }) => {
      const label = desc?.label ?? '';
      labels.push(label);
      return {
        setPipeline() {},
        setBindGroup() {},
        dispatchWorkgroups(x: number, y = 1, z?: number) {
          dispatches?.push({ label, x, y, z });
        },
        end() {},
      };
    },
    copyBufferToBuffer() {},
    clearBuffer() {},
    copyTextureToTexture() {},
    copyTextureToBuffer() {},
  } as unknown as GPUCommandEncoder;
}

describe('gpu-chores CPU goldens (Chromashift-shaped BT.709)', () => {
  it('maps luma to 256 bins with BT.709 weights', () => {
    expect(lumaToBin(0)).toBe(0);
    expect(lumaToBin(1)).toBe(255);
    expect(lumaBt709(1, 1, 1)).toBeCloseTo(1, 5);
    expect(lumaBt709(1, 0, 0)).toBeCloseTo(0.2126, 5);
  });

  it('histograms solid black and white', () => {
    const black = lumaHistogramBt709(solidRgba(4, 4, 0, 0, 0), 4, 4);
    expect(black.pixelCount).toBe(16);
    expect(black.bins[0]).toBe(16);
    expect(black.bins[255]).toBe(0);

    const white = lumaHistogramBt709(solidRgba(2, 2, 1, 1, 1), 2, 2);
    expect(white.bins[255]).toBe(4);
    expect(white.bins[0]).toBe(0);
  });

  it('reduce_f32 matches per-pixel min/max/mean', () => {
    const rgba = new Float32Array([
      0, 0, 0, 1,
      1, 1, 1, 1,
      0.5, 0.5, 0.5, 1,
      0.25, 0.25, 0.25, 1,
    ]);
    const reduced = reduceF32Luma(rgba, 2, 2);
    expect(reduced.min).toBeCloseTo(0, 5);
    expect(reduced.max).toBeCloseTo(1, 5);
    const mean =
      (lumaBt709(0, 0, 0) + lumaBt709(1, 1, 1) + lumaBt709(0.5, 0.5, 0.5) + lumaBt709(0.25, 0.25, 0.25)) / 4;
    expect(reduced.mean).toBeCloseTo(mean, 5);
  });

  it('histogram-derived reduce agrees with solid grey', () => {
    const grey = 0.5;
    const hist = lumaHistogramBt709(solidRgba(8, 8, grey, grey, grey), 8, 8);
    const fromHist = reduceF32FromHistogram(hist);
    const fromPx = reduceF32Luma(solidRgba(8, 8, grey, grey, grey), 8, 8);
    expect(fromHist.mean).toBeCloseTo(fromPx.mean, 2);
    expect(hist.bins[lumaToBin(grey)]).toBe(64);
  });

  it('lut_u8_map classifies luma into 8 Chromashift-style bands', () => {
    const lut = buildLumaClassifyLut(8);
    expect(lut[0]).toBe(0);
    expect(lut[32]).toBe(1);
    expect(lut[255]).toBe(7);
    const mapped = lutU8Map(solidRgba(2, 1, 1, 1, 1), 2, 1, lut);
    expect(Array.from(mapped)).toEqual([7, 7]);
  });

  it('downsample_2d box-filters and can apply auto-exposure gain', () => {
    const src = new Float32Array(4 * 4 * 4);
    for (let i = 0; i < 16; i++) {
      src[i * 4] = i < 8 ? 0 : 1;
      src[i * 4 + 1] = i < 8 ? 0 : 1;
      src[i * 4 + 2] = i < 8 ? 0 : 1;
      src[i * 4 + 3] = 1;
    }
    const dest = downsample2d(src, 4, 4, 2, 2, 1);
    expect(dest.length).toBe(16);
    expect(dest[0]).toBeCloseTo(0, 5);
    expect(dest[8]).toBeCloseTo(1, 5);
    const boosted = downsample2d(src, 4, 4, 2, 2, 2);
    expect(boosted[8]).toBeCloseTo(2, 5);
  });

  it('downsample_2d supports dest sizes other than 64', () => {
    const src = solidRgba(8, 8, 0.5, 0.25, 0.125, 1);
    const dest = downsample2d(src, 8, 8, 2, 2, 1);
    expect(dest.length).toBe(16);
    expect(dest[0]).toBeCloseTo(0.5, 5);
    expect(dest[3]).toBeCloseTo(1, 5);
  });

  it('applyGain2d moves dark luma toward middle grey and keeps alpha', () => {
    const dark = 0.045;
    const src = solidRgba(2, 2, dark, dark, dark, 0.8);
    const gained = applyGain2d(src, 2, 2, MIDDLE_GREY / dark);
    expect(gained[0]).toBeCloseTo(MIDDLE_GREY, 5);
    expect(gained[3]).toBeCloseTo(0.8, 5);
    const nanSafe = applyGain2d(src, 2, 2, Number.NaN);
    expect(nanSafe[0]).toBeCloseTo(dark, 5);
  });

  it('classifyBandsToRgba paints 8-band false color', () => {
    const rgba = classifyBandsToRgba(new Uint8Array([0, 7]), 2, 1);
    expect(rgba[0]).toBe(20);
    expect(rgba[4]).toBe(200);
    expect(rgba[7]).toBe(255);
  });

  it('unpackClassifyRgba8 reads band indices from packed R', () => {
    const packed = new Uint8Array(256 * 2);
    packed[0] = 3;
    packed[256] = 7;
    const bands = unpackClassifyRgba8(packed, 1, 2, 256);
    expect(Array.from(bands)).toEqual([3, 7]);
  });

  it('auto-exposure targets middle grey without NaNs', () => {
    const dark = autoExposureFromMean(0.045);
    expect(dark.gain).toBeCloseTo(MIDDLE_GREY / 0.045, 5);
    expect(dark.ev).toBeCloseTo(Math.log2(dark.gain), 5);
    const hist = lumaHistogramBt709(solidRgba(4, 4, 0.18, 0.18, 0.18), 4, 4);
    const mid = autoExposureFromHistogram(hist);
    expect(mid.gain).toBeCloseTo(1, 1);
  });
});

describe('GpuChoresHost', () => {
  it('parses the no_gpu_compute kill switch', () => {
    expect(isGpuComputeKillSwitchEnabled('')).toBe(false);
    expect(isGpuComputeKillSwitchEnabled('?renderer=wasm')).toBe(false);
    expect(isGpuComputeKillSwitchEnabled('?no_gpu_compute')).toBe(true);
    expect(isGpuComputeKillSwitchEnabled('?no_gpu_compute=1')).toBe(true);
    expect(isGpuComputeKillSwitchEnabled('?no_gpu_compute=false')).toBe(false);
  });

  it('never requests a GPU device and degrades with a reason when probe ok', () => {
    window.webgpuProbe = {
      ok: true,
      finishedAt: new Date().toISOString(),
      userAgent: 'test',
      userAgentBrands: [],
      attempts: [],
    };
    const requestAdapter = jest.fn();
    const requestDevice = jest.fn();
    const nav = navigator as unknown as { gpu?: { requestAdapter: typeof requestAdapter; requestDevice?: typeof requestDevice } };
    const previousGpu = nav.gpu;
    nav.gpu = { requestAdapter, requestDevice };
    const host = new GpuChoresHost();
    host.attach(null, 'webgpu.unavailable: No suitable GPU adapter found');
    const crumbs = host.getBreadcrumbs();
    expect(crumbs.gpuComputeAvailable).toBe(false);
    expect(crumbs.backend).toBe('ts');
    expect(crumbs.reason).toContain('webgpu.unavailable');
    expect(requestAdapter).not.toHaveBeenCalled();
    expect(requestDevice).not.toHaveBeenCalled();
    host.destroy();
    nav.gpu = previousGpu;
    delete window.webgpuProbe;
  });

  it('does not run CPU chores when boot probe failed', () => {
    window.webgpuProbe = {
      ok: false,
      finishedAt: new Date().toISOString(),
      userAgent: 'test',
      userAgentBrands: [],
      attempts: [],
      lastError: 'no adapter',
    };
    const host = new GpuChoresHost();
    host.attach(null, 'ignored');
    host.ingestRgba(solidRgba(4, 4, 0.5, 0.5, 0.5), 4, 4);
    expect(host.getPreviewRgba()).toBeNull();
    expect(host.getBreadcrumbs().reason).toContain('no adapter');
    host.destroy();
    delete window.webgpuProbe;
  });

  it('honors ?no_gpu_compute even when a device is passed', () => {
    window.webgpuProbe = {
      ok: true,
      finishedAt: new Date().toISOString(),
      userAgent: 'test',
      userAgentBrands: [],
      attempts: [],
    };
    const original = window.location;
    Object.defineProperty(window, 'location', {
      value: { ...original, search: '?no_gpu_compute' },
      configurable: true,
    });
    const createShaderModule = jest.fn();
    const host = new GpuChoresHost();
    host.attach({ createShaderModule } as unknown as GPUDevice);
    expect(createShaderModule).not.toHaveBeenCalled();
    const crumbs = host.getBreadcrumbs();
    expect(crumbs.gpuComputeAvailable).toBe(false);
    expect(crumbs.reason).toContain('no_gpu_compute');
    expect(crumbs.backend).toBe('ts');
    host.destroy();
    Object.defineProperty(window, 'location', { value: original, configurable: true });
    delete window.webgpuProbe;
  });

  it('feeds auto-exposure from CPU histogram for the thumb/preview path', () => {
    window.webgpuProbe = {
      ok: true,
      finishedAt: new Date().toISOString(),
      userAgent: 'test',
      userAgentBrands: [],
      attempts: [],
    };
    const original = window.location;
    Object.defineProperty(window, 'location', {
      value: { ...original, search: '?no_gpu_compute' },
      configurable: true,
    });
    const host = new GpuChoresHost();
    host.attach(null, 'cpu analysis');
    host.ingestRgba(solidRgba(8, 8, 0.05, 0.05, 0.05), 8, 8);
    const uniforms = host.getAutoUniforms();
    expect(uniforms.lumaMean).toBeLessThan(0.1);
    expect(uniforms.exposureGain).toBeGreaterThan(1);
    expect(host.getPreviewRgba()?.length).toBe(PREVIEW_SIZE * PREVIEW_SIZE * 4);
    expect(host.getClassifyMap()?.length).toBe(64);
    expect(host.getBreadcrumbs().lastOp).toBe('auto_exposure');
    host.destroy();
    Object.defineProperty(window, 'location', { value: original, configurable: true });
    delete window.webgpuProbe;
  });

  it('shrinks large CPU sources before histogram', () => {
    const src = solidRgba(64, 32, 1, 0, 0);
    const shrunk = shrinkCpuSource(src, 64, 32, 16);
    expect(Math.max(shrunk.width, shrunk.height)).toBe(16);
  });

  it('ingestRgba copies the snapshot and does not rewrite the caller buffer', () => {
    window.webgpuProbe = {
      ok: true,
      finishedAt: new Date().toISOString(),
      userAgent: 'test',
      userAgentBrands: [],
      attempts: [],
    };
    const original = window.location;
    Object.defineProperty(window, 'location', {
      value: { ...original, search: '?no_gpu_compute' },
      configurable: true,
    });
    const src = solidRgba(4, 4, 0.05, 0.05, 0.05);
    const before = src[0];
    const host = new GpuChoresHost();
    host.attach(null, 'cpu analysis');
    host.ingestRgba(src, 4, 4);
    expect(src[0]).toBe(before);
    expect(host.getAutoUniforms().exposureGain).toBeGreaterThan(1);
    host.destroy();
    Object.defineProperty(window, 'location', { value: original, configurable: true });
    delete window.webgpuProbe;
  });

  it('keeps histogram bin count at 256', () => {
    expect(HISTOGRAM_BINS).toBe(256);
  });

  it('dispatches reduce in 2D at 4K without exceeding workgroup limits', () => {
    probeOk();
    const labels: string[] = [];
    const dispatches: DispatchRecord[] = [];
    const host = new GpuChoresHost();
    host.attach(stubAdoptedGpuDevice());
    expect(host.getBreadcrumbs().gpuComputeAvailable).toBe(true);
    host.encodePreFx(spyEncoder(labels, dispatches), stubTexture(), 3840, 2160);
    expect(labels).toContain('gpu-chores-reduce');
    const reduce = dispatches.find((d) => d.label === 'gpu-chores-reduce');
    expect(reduce).toBeDefined();
    expect(reduce!.x).toBe(480);
    expect(reduce!.y).toBe(270);
    expect(reduce!.x).toBeLessThanOrEqual(65535);
    expect(reduce!.y).toBeLessThanOrEqual(65535);
    host.destroy();
    delete window.webgpuProbe;
  });

  it('skips apply-gain when the source toggle is off', () => {
    probeOk();
    const labels: string[] = [];
    const host = new GpuChoresHost();
    host.attach(stubAdoptedGpuDevice());
    expect(host.getBreadcrumbs().gpuComputeAvailable).toBe(true);
    host.setSourceNormalizeEnabled(false);
    const encoded = host.encodeSourceGainForTest(
      spyEncoder(labels),
      stubTexture(),
      stubTexture(),
      8,
      8,
    );
    expect(encoded).toBe(false);
    expect(labels.some((label) => label.includes('apply-gain'))).toBe(false);
    expect(host.getBreadcrumbs().sourceGain).toBe('off');
    host.destroy();
    delete window.webgpuProbe;
  });

  it('encodes apply-gain when the source toggle is on', () => {
    probeOk();
    const labels: string[] = [];
    const host = new GpuChoresHost();
    host.attach(stubAdoptedGpuDevice());
    host.setSourceNormalizeEnabled(true);
    const encoded = host.encodeSourceGainForTest(
      spyEncoder(labels),
      stubTexture(),
      stubTexture(),
      8,
      8,
    );
    expect(encoded).toBe(true);
    expect(labels).toContain('gpu-chores-apply-gain');
    expect(host.getBreadcrumbs().sourceGain).toBe('on');
    host.destroy();
    delete window.webgpuProbe;
  });

  it('skips apply-gain when a physics-pinned graph is active', () => {
    probeOk();
    const labels: string[] = [];
    const host = new GpuChoresHost();
    host.attach(stubAdoptedGpuDevice());
    host.setSourceNormalizeEnabled(true);
    host.setPhysicsPinned(true);
    const encoded = host.encodeSourceGainForTest(
      spyEncoder(labels),
      stubTexture(),
      stubTexture(),
      8,
      8,
    );
    expect(encoded).toBe(false);
    expect(labels.some((label) => label.includes('apply-gain'))).toBe(false);
    expect(host.getBreadcrumbs().sourceGain).toBe('skipped-physics');
    host.destroy();
    delete window.webgpuProbe;
  });
});

describe('shouldEncodeSourceGain', () => {
  const base = {
    toggleOn: true,
    gpuComputeAvailable: true,
    physicsPinned: false,
    killSwitch: false,
  };

  it('encodes only when toggle is on and GPU chores are live', () => {
    expect(shouldEncodeSourceGain(base)).toBe(true);
    expect(shouldEncodeSourceGain({ ...base, toggleOn: false })).toBe(false);
    expect(shouldEncodeSourceGain({ ...base, killSwitch: true })).toBe(false);
    expect(shouldEncodeSourceGain({ ...base, gpuComputeAvailable: false })).toBe(false);
    expect(shouldEncodeSourceGain({ ...base, physicsPinned: true })).toBe(false);
  });

  it('reports skipped-physics when the toggle is on but a pinned graph is active', () => {
    expect(sourceGainStatus({ ...base, physicsPinned: true })).toBe('skipped-physics');
    expect(sourceGainStatus({ ...base, toggleOn: false })).toBe('off');
    expect(sourceGainStatus(base)).toBe('on');
  });
});
