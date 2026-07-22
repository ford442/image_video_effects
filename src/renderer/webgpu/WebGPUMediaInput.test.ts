/**
 * @jest-environment jsdom
 */
import {
  createMediaInputState,
  uploadRGBA8,
  uploadSourceRGBA8,
  restoreSourceFromOffscreen,
  WebGPUMediaInputContext,
} from './WebGPUMediaInput';

function makeCtx(overrides: Partial<{
  canvasW: number;
  canvasH: number;
  readW: number;
  readH: number;
}> = {}): {
  ctx: WebGPUMediaInputContext;
  writeTexture: jest.Mock;
  sourceTex: GPUTexture;
  readTex: GPUTexture;
} {
  const writeTexture = jest.fn();
  const sourceTex = { width: overrides.canvasW ?? 64, height: overrides.canvasH ?? 48 } as unknown as GPUTexture;
  const readTex = {
    width: overrides.readW ?? overrides.canvasW ?? 64,
    height: overrides.readH ?? overrides.canvasH ?? 48,
  } as unknown as GPUTexture;

  const ctx: WebGPUMediaInputContext = {
    device: {
      queue: { writeTexture },
    } as unknown as GPUDevice,
    sourceTex,
    readTex,
    canvasW: overrides.canvasW ?? 64,
    canvasH: overrides.canvasH ?? 48,
    filterSampler: {} as GPUSampler,
    supportsExternalTexture: false,
    videoCopyPipeline: null,
    videoCopyBindGroupLayout: null,
  };

  return { ctx, writeTexture, sourceTex, readTex };
}

describe('WebGPUMediaInput', () => {
  it('uploadSourceRGBA8 writes only sourceTex', () => {
    const { ctx, writeTexture, sourceTex, readTex } = makeCtx();
    const pixels = new Uint8ClampedArray(64 * 48 * 4);
    pixels[0] = 255;

    uploadSourceRGBA8(ctx, pixels, 64, 48);

    expect(writeTexture).toHaveBeenCalledTimes(1);
    expect(writeTexture.mock.calls[0][0].texture).toBe(sourceTex);
    expect(writeTexture.mock.calls[0][0].texture).not.toBe(readTex);
  });

  it('uploadRGBA8 skips readTex when it is resolution-scaled', () => {
    const { ctx, writeTexture, sourceTex, readTex } = makeCtx({
      canvasW: 64,
      canvasH: 48,
      readW: 32,
      readH: 24,
    });
    const pixels = new Uint8ClampedArray(64 * 48 * 4);

    uploadRGBA8(ctx, pixels, 64, 48);

    expect(writeTexture).toHaveBeenCalledTimes(1);
    expect(writeTexture.mock.calls[0][0].texture).toBe(sourceTex);
    expect(writeTexture.mock.calls.every((c) => c[0].texture !== readTex)).toBe(true);
  });

  it('uploadRGBA8 writes both textures when sizes match', () => {
    const { ctx, writeTexture, sourceTex, readTex } = makeCtx();
    const pixels = new Uint8ClampedArray(64 * 48 * 4);

    uploadRGBA8(ctx, pixels, 64, 48);

    expect(writeTexture).toHaveBeenCalledTimes(2);
    expect(writeTexture.mock.calls[0][0].texture).toBe(sourceTex);
    expect(writeTexture.mock.calls[1][0].texture).toBe(readTex);
  });

  it('restoreSourceFromOffscreen re-uploads after texture recreate', () => {
    const { ctx, writeTexture, sourceTex } = makeCtx();
    const state = createMediaInputState();

    const pixels = new Uint8ClampedArray(64 * 48 * 4);
    pixels[0] = 10;
    pixels[1] = 20;
    pixels[2] = 30;
    pixels[3] = 255;

    const canvas = document.createElement('canvas');
    canvas.width = 64;
    canvas.height = 48;
    const offCtx = {
      getImageData: jest.fn(() => ({ data: pixels, width: 64, height: 48 })),
    } as unknown as CanvasRenderingContext2D;
    state.offscreen = canvas;
    state.offCtx = offCtx;

    expect(restoreSourceFromOffscreen(ctx, state)).toBe(true);
    expect(offCtx.getImageData).toHaveBeenCalledWith(0, 0, 64, 48);
    expect(writeTexture).toHaveBeenCalledTimes(1);
    expect(writeTexture.mock.calls[0][0].texture).toBe(sourceTex);

    const floats = writeTexture.mock.calls[0][1] as Float32Array;
    expect(floats[0]).toBeCloseTo(10 / 255, 5);
    expect(floats[1]).toBeCloseTo(20 / 255, 5);
    expect(floats[2]).toBeCloseTo(30 / 255, 5);
  });

  it('restoreSourceFromOffscreen returns false when offscreen missing or wrong size', () => {
    const { ctx, writeTexture } = makeCtx();
    const empty = createMediaInputState();
    expect(restoreSourceFromOffscreen(ctx, empty)).toBe(false);

    const state = createMediaInputState();
    const canvas = document.createElement('canvas');
    canvas.width = 16;
    canvas.height = 16;
    state.offscreen = canvas;
    state.offCtx = {
      getImageData: jest.fn(),
    } as unknown as CanvasRenderingContext2D;
    expect(restoreSourceFromOffscreen(ctx, state)).toBe(false);
    expect(writeTexture).not.toHaveBeenCalled();
  });
});
