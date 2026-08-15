import {
  autoExposureFromHistogram,
  autoExposureFromMean,
  buildLumaClassifyLut,
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
  shrinkCpuSource,
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

  it('keeps histogram bin count at 256', () => {
    expect(HISTOGRAM_BINS).toBe(256);
  });
});
