/**
 * @jest-environment jsdom
 */
import {
  createMediaInputState,
  uploadRGBA8,
  uploadSourceRGBA8,
  restoreSourceFromOffscreen,
  copyExternalToSource,
  letterboxRect,
  loadImage,
  WebGPUMediaInputContext,
} from './WebGPUMediaInput';

function makeCtx(overrides: Partial<{
  canvasW: number;
  canvasH: number;
  readW: number;
  readH: number;
  colorFormat: WebGPUMediaInputContext['colorFormat'];
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
    colorFormat: overrides.colorFormat ?? 'rgba32float',
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

  it('uploadSourceRGBA8 packs rgba16float with 8 bytes per pixel', () => {
    const { ctx, writeTexture } = makeCtx({ colorFormat: 'rgba16float' });
    const pixels = new Uint8ClampedArray(64 * 48 * 4);
    pixels[0] = 255;

    uploadSourceRGBA8(ctx, pixels, 64, 48);

    expect(writeTexture).toHaveBeenCalledTimes(1);
    expect(writeTexture.mock.calls[0][2].bytesPerRow).toBe(64 * 8);
    expect(writeTexture.mock.calls[0][1].byteLength).toBe(64 * 48 * 8);
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

  describe('copyExternalImageToTexture still path', () => {
    function withCopyExternal(ctx: WebGPUMediaInputContext, impl?: () => void) {
      const copyExternalImageToTexture: jest.Mock = jest.fn(impl);
      const pass = { end: jest.fn() };
      const device = ctx.device as unknown as Record<string, unknown>;
      (device.queue as Record<string, unknown>).copyExternalImageToTexture = copyExternalImageToTexture;
      (device.queue as Record<string, unknown>).submit = jest.fn();
      device.createCommandEncoder = jest.fn(() => ({
        beginRenderPass: jest.fn(() => pass),
        finish: jest.fn(),
      }));
      (ctx.sourceTex as unknown as Record<string, unknown>).createView = jest.fn();
      (ctx.readTex as unknown as Record<string, unknown>).createView = jest.fn();
      return copyExternalImageToTexture;
    }

    it('letterboxRect centers and snaps to integer texels', () => {
      expect(letterboxRect(200, 100, 64, 48)).toEqual({ x: 0, y: 8, w: 64, h: 32 });
      expect(letterboxRect(100, 200, 64, 48)).toEqual({ x: 20, y: 0, w: 24, h: 48 });
    });

    it('copyExternalToSource copies into sourceTex and unscaled readTex without writeTexture', () => {
      const { ctx, writeTexture, sourceTex, readTex } = makeCtx();
      const copy = withCopyExternal(ctx);
      const source = { width: 64, height: 32 } as ImageBitmap;

      expect(copyExternalToSource(ctx, source, 64, 32, { x: 0, y: 8 }, true)).toBe(true);

      expect(writeTexture).not.toHaveBeenCalled();
      expect(copy).toHaveBeenCalledTimes(2);
      expect(copy.mock.calls[0][1]).toMatchObject({ texture: sourceTex, origin: [0, 8], premultipliedAlpha: false });
      expect(copy.mock.calls[1][1].texture).toBe(readTex);
      expect(copy.mock.calls[0][2]).toEqual([64, 32]);
    });

    it('copyExternalToSource skips scaled readTex', () => {
      const { ctx, sourceTex } = makeCtx({ readW: 32, readH: 24 });
      const copy = withCopyExternal(ctx);
      copyExternalToSource(ctx, {} as ImageBitmap, 64, 48);
      expect(copy).toHaveBeenCalledTimes(1);
      expect(copy.mock.calls[0][1].texture).toBe(sourceTex);
    });

    it('copyExternalToSource returns false when the API is missing or throws', () => {
      const { ctx } = makeCtx();
      expect(copyExternalToSource(ctx, {} as ImageBitmap, 64, 48)).toBe(false);

      const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
      withCopyExternal(ctx, () => { throw new Error('tainted'); });
      expect(copyExternalToSource(ctx, {} as ImageBitmap, 64, 48)).toBe(false);
      warn.mockRestore();
    });

    it('restoreSourceFromOffscreen prefers the retained still bitmap', () => {
      const { ctx, writeTexture } = makeCtx();
      const copy = withCopyExternal(ctx);
      const state = createMediaInputState();
      state.still = { bitmap: { width: 64, height: 32 } as ImageBitmap, x: 0, y: 8, canvasW: 64, canvasH: 48 };

      expect(restoreSourceFromOffscreen(ctx, state)).toBe(true);
      expect(copy).toHaveBeenCalled();
      expect(writeTexture).not.toHaveBeenCalled();
    });

    describe('loadImage', () => {
      const realImage = global.Image;
      const realCreateImageBitmap = (global as { createImageBitmap?: unknown }).createImageBitmap;
      let offCtx: { fillRect: jest.Mock; drawImage: jest.Mock; getImageData: jest.Mock; fillStyle: string };

      beforeEach(() => {
        class FakeImage {
          naturalWidth = 200;
          naturalHeight = 100;
          crossOrigin = '';
          onload: (() => void) | null = null;
          onerror: (() => void) | null = null;
          set src(_v: string) { setTimeout(() => this.onload?.(), 0); }
        }
        (global as unknown as { Image: unknown }).Image = FakeImage;
        offCtx = {
          fillStyle: '',
          fillRect: jest.fn(),
          drawImage: jest.fn(),
          getImageData: jest.fn(() => ({ data: new Uint8ClampedArray(64 * 48 * 4) })),
        };
        jest.spyOn(HTMLCanvasElement.prototype, 'getContext')
          .mockImplementation((() => offCtx) as unknown as HTMLCanvasElement['getContext']);
      });

      afterEach(() => {
        (global as unknown as { Image: unknown }).Image = realImage;
        (global as { createImageBitmap?: unknown }).createImageBitmap = realCreateImageBitmap;
        jest.restoreAllMocks();
      });

      it('uses copyExternalImageToTexture when available (no getImageData)', async () => {
        const { ctx, writeTexture } = makeCtx();
        const copy = withCopyExternal(ctx);
        const bitmap = { width: 64, height: 32, close: jest.fn() };
        const createBitmap = jest.fn(async () => bitmap);
        (global as { createImageBitmap?: unknown }).createImageBitmap = createBitmap;
        const state = createMediaInputState();

        await loadImage(ctx, state, 'img.png');

        expect(createBitmap).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
          colorSpaceConversion: 'none',
          resizeWidth: 64,
          resizeHeight: 32,
        }));
        expect(copy).toHaveBeenCalled();
        expect(offCtx.getImageData).not.toHaveBeenCalled();
        expect(writeTexture).not.toHaveBeenCalled();
        expect(state.still?.bitmap).toBe(bitmap);
      });

      it('falls back to the 2D upload when copyExternalImageToTexture is missing', async () => {
        const { ctx, writeTexture } = makeCtx();
        (global as { createImageBitmap?: unknown }).createImageBitmap = jest.fn();
        const state = createMediaInputState();

        await loadImage(ctx, state, 'img.png');

        expect(offCtx.getImageData).toHaveBeenCalled();
        expect(writeTexture).toHaveBeenCalled();
        expect(state.still).toBeNull();
      });
    });
  });
});
