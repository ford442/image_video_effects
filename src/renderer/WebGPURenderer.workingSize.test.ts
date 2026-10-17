import { WebGPURenderer } from './WebGPURenderer';
import { DEFAULT_CONFIG } from './Renderer';
import { allocateWorkingPool } from './webgpu/historyTexProbe';
import { allowsFullWorkingSize } from '../config/vramBudget';

jest.mock('./webgpu/historyTexProbe', () => {
  const actual = jest.requireActual('./webgpu/historyTexProbe');
  return { ...actual, allocateWorkingPool: jest.fn() };
});

jest.mock('../config/vramBudget', () => {
  const actual = jest.requireActual('../config/vramBudget');
  return { ...actual, allowsFullWorkingSize: jest.fn(() => false), persistHistoryOomCap: jest.fn() };
});

type Alloc = Awaited<ReturnType<typeof allocateWorkingPool>>;

const okSet = (size: number): Alloc => ({
  ok: true,
  set: { destroyMarker: size } as unknown as Alloc['set'],
  workingSize: size,
  layers: 4,
  deviceLost: false,
  oom: false,
});
const failed = (deviceLost: boolean): Alloc => ({
  ok: false,
  workingSize: 1024,
  layers: 4,
  deviceLost,
  oom: true,
});

interface Internals {
  tryUpgradeToFullWorkingSize(
    device: GPUDevice, format: string, layers: number,
  ): Promise<'ok' | 'lost' | 'oom' | 'kept'>;
  setupGpuResources(hasF32: boolean, format: string): Promise<'ok' | 'lost' | 'oom'>;
  device: GPUDevice | null;
  pipeline: { setupComputeLayout: unknown };
}

describe('working-size upgrade outcomes', () => {
  const alloc = allocateWorkingPool as jest.Mock;
  const device = {} as GPUDevice;
  let wgpu: WebGPURenderer;
  let internals: Internals;

  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(console, 'log').mockImplementation(() => undefined);
    jest.spyOn(console, 'warn').mockImplementation(() => undefined);
    jest.spyOn(console, 'error').mockImplementation(() => undefined);
    wgpu = new WebGPURenderer(DEFAULT_CONFIG);
    internals = wgpu as unknown as Internals;
  });

  afterEach(() => jest.restoreAllMocks());

  describe('tryUpgradeToFullWorkingSize', () => {
    it('keeps 1024 when the 2048 upgrade OOMs and the restore succeeds', async () => {
      alloc.mockResolvedValueOnce(failed(false)).mockResolvedValueOnce(okSet(1024));
      expect(await internals.tryUpgradeToFullWorkingSize(device, 'rgba16float', 4)).toBe('kept');
    });

    it('reports oom (not lost) when the 1024 restore fails on a live device', async () => {
      alloc.mockResolvedValueOnce(failed(false)).mockResolvedValueOnce(failed(false));
      expect(await internals.tryUpgradeToFullWorkingSize(device, 'rgba16float', 4)).toBe('oom');
    });

    it('reports lost when the device is lost during the 1024 restore', async () => {
      alloc.mockResolvedValueOnce(failed(false)).mockResolvedValueOnce(failed(true));
      expect(await internals.tryUpgradeToFullWorkingSize(device, 'rgba16float', 4)).toBe('lost');
    });

    it('reports lost when the device is lost during the 2048 upgrade itself', async () => {
      alloc.mockResolvedValueOnce(failed(true));
      expect(await internals.tryUpgradeToFullWorkingSize(device, 'rgba16float', 4)).toBe('lost');
      expect(alloc).toHaveBeenCalledTimes(1);
    });
  });

  describe('setupGpuResources', () => {
    beforeEach(() => {
      (allowsFullWorkingSize as jest.Mock).mockReturnValue(true);
      internals.device = { limits: { maxBufferSize: 1 << 30 } } as unknown as GPUDevice;
      jest.spyOn(internals.pipeline as { setupComputeLayout: () => void }, 'setupComputeLayout')
        .mockImplementation(() => undefined);
      jest.spyOn(
        (wgpu as unknown as { resources: { applyTextureSet: () => void; ensureSamplersAndBuffers: () => void } }).resources,
        'applyTextureSet',
      ).mockImplementation(() => undefined);
      jest.spyOn(
        (wgpu as unknown as { resources: { ensureSamplersAndBuffers: () => void } }).resources,
        'ensureSamplersAndBuffers',
      ).mockImplementation(() => undefined);
      alloc.mockResolvedValue(okSet(1024));
    });

    it("propagates 'oom' from a failed restore so init does not request a new device", async () => {
      jest.spyOn(wgpu as unknown as Internals, 'tryUpgradeToFullWorkingSize').mockResolvedValue('oom');
      expect(await internals.setupGpuResources(false, 'rgba16float')).toBe('oom');
    });

    it("still propagates 'lost' so init retries on a fresh device", async () => {
      jest.spyOn(wgpu as unknown as Internals, 'tryUpgradeToFullWorkingSize').mockResolvedValue('lost');
      expect(await internals.setupGpuResources(false, 'rgba16float')).toBe('lost');
    });
  });
});
