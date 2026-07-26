import { WebGPUResourcePool, createTextures } from './resources';

// Minimal WebGPU globals for unit tests (no real GPU in Jest).
// Values match the WebGPU TextureUsage bitflags.
const TU = {
  COPY_SRC: 0x01,
  COPY_DST: 0x02,
  TEXTURE_BINDING: 0x04,
  STORAGE_BINDING: 0x08,
  RENDER_ATTACHMENT: 0x10,
} as const;
(global as unknown as { GPUTextureUsage: typeof TU }).GPUTextureUsage = TU;
(global as unknown as { GPUBufferUsage: { UNIFORM: number; COPY_DST: number; STORAGE: number } }).GPUBufferUsage = {
  UNIFORM: 0x40,
  COPY_DST: 0x08,
  STORAGE: 0x80,
};

function makeMockDevice(): GPUDevice {
  const textures: GPUTexture[] = [];
  return {
    createTexture: jest.fn(() => {
      const tex = { destroy: jest.fn(), createView: jest.fn() } as unknown as GPUTexture;
      textures.push(tex);
      return tex;
    }),
    createSampler: jest.fn(() => ({} as GPUSampler)),
    createBuffer: jest.fn(() => ({ destroy: jest.fn() } as unknown as GPUBuffer)),
    queue: { writeTexture: jest.fn() },
    _textures: textures,
  } as unknown as GPUDevice & { _textures: GPUTexture[] };
}

describe('WebGPUResourcePool', () => {
  it('recreateScaleTextures destroys old textures and creates new ones', () => {
    const device = makeMockDevice();
    const pool = new WebGPUResourcePool();

    pool.setup(device, 1920, 1080, 960, 540);
    const firstRead = pool.readTex;
    const firstWrite = pool.writeTex;

    pool.recreateScaleTextures(device, 1920, 1080, 480, 270);

    expect(firstRead.destroy).toHaveBeenCalled();
    expect(firstWrite.destroy).toHaveBeenCalled();
    expect(pool.readTex).not.toBe(firstRead);
    expect(pool.writeTex).not.toBe(firstWrite);
    expect(device.createTexture).toHaveBeenCalled();
  });

  it('createTextures uses scaled dimensions for working textures', () => {
    const device = makeMockDevice();
    const set = createTextures(device, 1920, 1080, 960, 544);

    expect(device.createTexture).toHaveBeenCalled();
    expect(set.sourceTex).toBeDefined();
    expect(set.readTex).toBeDefined();
    expect(set.readTex).not.toBe(set.sourceTex);
  });

  it('createTextures uses rgba16float when requested', () => {
    const device = makeMockDevice();
    createTextures(device, 1920, 1080, 960, 544, 'rgba16float');

    const createTexture = device.createTexture as unknown as {
      mock: { calls: Array<[{ label?: string; format: string }]> };
    };
    const sourceCall = createTexture.mock.calls.find(
      (call) => call[0]?.label === 'sourceTex',
    );
    expect(sourceCall?.[0].format).toBe('rgba16float');
  });

  it('createTextures gives readTex RENDER_ATTACHMENT for scalePass', () => {
    const device = makeMockDevice();
    createTextures(device, 800, 600, 400, 300);

    const createTexture = device.createTexture as unknown as {
      mock: { calls: Array<[{ label?: string; usage: number }]> };
    };
    const readCall = createTexture.mock.calls.find(
      (call) => call[0]?.label === 'readTex',
    );
    expect(readCall).toBeDefined();
    const usage = readCall![0].usage;
    expect(usage & TU.RENDER_ATTACHMENT).toBe(TU.RENDER_ATTACHMENT);
    expect(usage & TU.STORAGE_BINDING).toBe(TU.STORAGE_BINDING);
  });
});
