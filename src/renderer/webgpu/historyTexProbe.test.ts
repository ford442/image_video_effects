/**
 * historyTex VRAM probe (#1204)
 */

import {
  HISTORY_OOM_CAP_KEY,
  WASM_BLOCK_AFTER_OOM_KEY,
  getHistoryWorkingSizeCap,
  isWasmBlockedAfterOom,
  persistHistoryOomCap,
} from '../../config/vramBudget';
import { probeHistoryTex, rungsForRequest } from './historyTexProbe';

const TU = {
  COPY_SRC: 0x01,
  COPY_DST: 0x02,
  TEXTURE_BINDING: 0x04,
  STORAGE_BINDING: 0x08,
} as const;

beforeAll(() => {
  (global as unknown as { GPUTextureUsage: typeof TU }).GPUTextureUsage = TU;
});

beforeEach(() => {
  try {
    sessionStorage.clear();
  } catch {
    /* ignore */
  }
});

function makeDevice(opts: {
  oomUntil?: number;
  lost?: boolean;
}): GPUDevice {
  let creates = 0;
  const oomUntil = opts.oomUntil ?? 0;
  const lost = opts.lost
    ? Promise.resolve({ reason: 'unknown', message: 'oom' } as GPUDeviceLostInfo)
    : new Promise<GPUDeviceLostInfo>(() => undefined);
  return {
    lost,
    pushErrorScope: jest.fn(),
    popErrorScope: jest.fn(async () => {
      creates += 1;
      if (creates <= oomUntil) {
        return { message: 'GPUOutOfMemoryError' } as GPUError;
      }
      return null;
    }),
    createTexture: jest.fn(() => ({ destroy: jest.fn() })),
  } as unknown as GPUDevice;
}

describe('vramBudget', () => {
  it('defaults to 2048 and persists 1024 + wasm block after OOM', () => {
    expect(getHistoryWorkingSizeCap()).toBe(2048);
    expect(isWasmBlockedAfterOom()).toBe(false);
    persistHistoryOomCap();
    expect(getHistoryWorkingSizeCap()).toBe(1024);
    expect(isWasmBlockedAfterOom()).toBe(true);
    expect(sessionStorage.getItem(HISTORY_OOM_CAP_KEY)).toBe('1024');
    expect(sessionStorage.getItem(WASM_BLOCK_AFTER_OOM_KEY)).toBe('1');
  });
});

describe('rungsForRequest', () => {
  it('skips 2048 when the session cap is 1024', () => {
    const rungs = rungsForRequest(2048, 1024);
    expect(rungs.every((r) => r.size <= 1024)).toBe(true);
    expect(rungs[0]).toEqual({ size: 1024, layers: 8 });
  });

  it('does not probe larger than requested working size', () => {
    const rungs = rungsForRequest(1024, 2048);
    expect(rungs.some((r) => r.size === 2048)).toBe(false);
  });
});

describe('probeHistoryTex', () => {
  it('takes the first successful rung', async () => {
    const device = makeDevice({ oomUntil: 0 });
    const result = await probeHistoryTex(device, 2048, 'rgba32float');
    expect(result.ok).toBe(true);
    expect(result.workingSize).toBe(2048);
    expect(result.layers).toBe(8);
    expect(result.oom).toBe(false);
    expect(getHistoryWorkingSizeCap()).toBe(2048);
  });

  it('drops to 1024×8 after 2048 OOM and does not retry 2048', async () => {
    const device = makeDevice({ oomUntil: 1 });
    const result = await probeHistoryTex(device, 2048, 'rgba16float');
    expect(result.ok).toBe(true);
    expect(result.workingSize).toBe(1024);
    expect(result.layers).toBe(8);
    expect(getHistoryWorkingSizeCap()).toBe(1024);
    expect(isWasmBlockedAfterOom()).toBe(true);

    const again = rungsForRequest(2048, getHistoryWorkingSizeCap());
    expect(again.some((r) => r.size === 2048)).toBe(false);
  });

  it('reports deviceLost without allocating the pool', async () => {
    const device = makeDevice({ lost: true });
    const result = await probeHistoryTex(device, 2048, 'rgba32float');
    expect(result.ok).toBe(false);
    expect(result.deviceLost).toBe(true);
  });
});
