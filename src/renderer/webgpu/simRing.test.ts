/**
 * Group-1 sim ring (bind_group1.json): contract, OOM ladder, params upload.
 */

import simRingContract from '../../contracts/bind_group1.json';
import webgpuLimits from '../../contracts/webgpu_limits.json';
import {
  SIM_RING_OOM_CAP_KEY,
  SIM_RING_STATE_RUNGS,
  SimRingPool,
  allocateSimRing,
  createSimRingBindGroupLayout,
  declaresSimRing,
  getSimRingStateCap,
} from './simRing';

const BU = { MAP_READ: 1, COPY_SRC: 4, COPY_DST: 8, UNIFORM: 64, STORAGE: 128 } as const;

beforeAll(() => {
  const g = global as unknown as Record<string, unknown>;
  g.GPUBufferUsage = BU;
  g.GPUShaderStage = { VERTEX: 1, FRAGMENT: 2, COMPUTE: 4 };
});

beforeEach(() => {
  try {
    sessionStorage.clear();
  } catch {
    /* ignore */
  }
});

interface FakeBuffer { label: string; size: number; usage: number; destroyed: boolean; destroy(): void }

/** Every createBuffer pair inside one error scope is one rung; the first `oomRungs` rungs OOM. */
function makeDevice(oomRungs = 0) {
  let scopes = 0;
  const buffers: FakeBuffer[] = [];
  const device = {
    pushErrorScope: jest.fn(),
    popErrorScope: jest.fn(async () => {
      scopes += 1;
      return scopes <= oomRungs ? ({ message: 'GPUOutOfMemoryError' } as GPUError) : null;
    }),
    createBuffer: jest.fn((desc: GPUBufferDescriptor) => {
      const b: FakeBuffer = {
        label: desc.label ?? '',
        size: desc.size,
        usage: desc.usage,
        destroyed: false,
        destroy() { this.destroyed = true; },
      };
      buffers.push(b);
      return b;
    }),
    createBindGroupLayout: jest.fn((desc: GPUBindGroupLayoutDescriptor) => desc),
    createBindGroup: jest.fn((desc: GPUBindGroupDescriptor) => desc),
  };
  return { device: device as unknown as GPUDevice, raw: device, buffers };
}

describe('bind_group1.json contract', () => {
  it('fits inside the raised webgpu_limits.json storage/uniform budget', () => {
    const storage = simRingContract.bindings.filter((b) => b.bufferType !== 'uniform').length;
    const uniform = simRingContract.bindings.filter((b) => b.bufferType === 'uniform').length;
    // group 0: extraBuffer + plasmaBuffer, u
    expect(2 + storage).toBe(webgpuLimits.minimumComputeLimits.maxStorageBuffersPerShaderStage);
    expect(1 + uniform).toBe(webgpuLimits.minimumComputeLimits.maxUniformBuffersPerShaderStage);
    expect(webgpuLimits.minimumComputeLimits.maxStorageBuffersPerShaderStage).toBe(4);
  });

  it('builds the group-1 layout straight from the contract', () => {
    const { device } = makeDevice();
    const layout = createSimRingBindGroupLayout(device) as unknown as GPUBindGroupLayoutDescriptor;
    expect(Array.from(layout.entries).map((e) => [e.binding, e.buffer?.type])).toEqual([
      [0, 'storage'],
      [1, 'read-only-storage'],
      [2, 'uniform'],
    ]);
  });

  it('documents a Pascal-safe default (~2 MiB)', () => {
    const bytes = SIM_RING_STATE_RUNGS[0] * 16 + SIM_RING_STATE_RUNGS[0] * 4 * 4 + 16;
    expect(bytes).toBe(simRingContract.oomLadder.defaultVramBytes);
    expect(bytes).toBeLessThan(4 * 1024 * 1024);
  });
});

describe('declaresSimRing', () => {
  it('detects @group(1) declarations and ignores comments', () => {
    expect(declaresSimRing('@group(1) @binding(0) var<storage, read_write> simState: array<vec4<f32>>;'))
      .toBe(true);
    expect(declaresSimRing('@group( 1 ) @binding(2) var<uniform> simParams: SimParams;')).toBe(true);
    expect(declaresSimRing('// @group(1) @binding(0) var<storage> x: array<u32>;\n@group(0) @binding(0) var s: sampler;'))
      .toBe(false);
    expect(declaresSimRing('/* @group(1) */ @group(0) @binding(10) var<storage, read_write> e: array<f32>;'))
      .toBe(false);
    expect(declaresSimRing('@group(0) @binding(13) var historyTexture: texture_2d_array<f32>;')).toBe(false);
  });
});

describe('allocateSimRing OOM ladder', () => {
  it('allocates the default rung with the right sizes and usages', async () => {
    const { device } = makeDevice(0);
    const ring = await allocateSimRing(device);
    expect(ring).not.toBeNull();
    expect(ring!.stateCount).toBe(65536);
    expect(ring!.indexCount).toBe(262144);
    expect(ring!.truncated).toBe(false);
    expect(ring!.stateBuf.size).toBe(1024 * 1024);
    expect(ring!.indexBuf.size).toBe(1024 * 1024);
    expect(ring!.paramsBuf.size).toBe(16);
    expect(ring!.stateBuf.usage & BU.COPY_SRC).toBeTruthy();
    expect(ring!.indexBuf.usage & BU.COPY_DST).toBeTruthy();
    expect(ring!.paramsBuf.usage & BU.UNIFORM).toBeTruthy();
    expect(sessionStorage.getItem(SIM_RING_OOM_CAP_KEY)).toBeNull();
  });

  it('shrinks on OOM, destroys the failed rung, and latches the smaller cap', async () => {
    const { device, buffers } = makeDevice(1);
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    const ring = await allocateSimRing(device);
    warn.mockRestore();

    expect(ring!.stateCount).toBe(32768);
    expect(ring!.truncated).toBe(true);
    expect(buffers.filter((b) => b.size === 1024 * 1024).every((b) => b.destroyed)).toBe(true);
    expect(sessionStorage.getItem(SIM_RING_OOM_CAP_KEY)).toBe('32768');
    expect(getSimRingStateCap()).toBe(32768);
  });

  it('never retries the fat size once the latch is set', async () => {
    sessionStorage.setItem(SIM_RING_OOM_CAP_KEY, '16384');
    const { raw, device } = makeDevice(0);
    const ring = await allocateSimRing(device);
    expect(ring!.stateCount).toBe(16384);
    const sizes = raw.createBuffer.mock.calls.map(([d]) => (d as GPUBufferDescriptor).size);
    expect(Math.max(...sizes)).toBe(16384 * 16); // simIndex bytes == simState bytes
    expect(sizes).not.toContain(65536 * 16);
    expect(sizes).not.toContain(32768 * 16);
  });

  it('returns null and latches 0 when every rung OOMs', async () => {
    const { device } = makeDevice(SIM_RING_STATE_RUNGS.length);
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    expect(await allocateSimRing(device)).toBeNull();
    warn.mockRestore();
    expect(sessionStorage.getItem(SIM_RING_OOM_CAP_KEY)).toBe('0');
    expect(await allocateSimRing(makeDevice(0).device)).toBeNull();
  });
});

describe('SimRingPool', () => {
  it('de-duplicates concurrent ensure() calls and exposes bindings', async () => {
    const { device, raw } = makeDevice(0);
    const pool = new SimRingPool();
    const log = jest.spyOn(console, 'log').mockImplementation(() => {});
    const layout = {} as GPUBindGroupLayout;
    const [a, b] = await Promise.all([pool.ensure(device, layout), pool.ensure(device, layout)]);
    log.mockRestore();

    expect(a && b).toBe(true);
    expect(raw.createBindGroup).toHaveBeenCalledTimes(1);
    const bindings = pool.getBindings()!;
    expect(bindings.stateCount).toBe(65536);
    expect(bindings.copyBytes).toBe(1024 * 1024);
  });

  it('uploads SimParams with an advancing frame counter', async () => {
    const { device } = makeDevice(0);
    const pool = new SimRingPool();
    const log = jest.spyOn(console, 'log').mockImplementation(() => {});
    await pool.ensure(device, {} as GPUBindGroupLayout);
    log.mockRestore();

    const writes: number[][] = [];
    const queue = {
      writeBuffer: (_b: GPUBuffer, _o: number, data: Uint32Array) => writes.push(Array.from(data)),
    } as unknown as GPUQueue;
    pool.beginFrame(queue);
    pool.beginFrame(queue);
    expect(writes).toEqual([
      [65536, 262144, 0, 0],
      [65536, 262144, 1, 0],
    ]);
  });

  it('is a no-op before allocation and resets on destroy', async () => {
    const pool = new SimRingPool();
    const queue = { writeBuffer: jest.fn() } as unknown as GPUQueue;
    pool.beginFrame(queue);
    expect(queue.writeBuffer).not.toHaveBeenCalled();
    expect(pool.getBindings()).toBeNull();

    const { device, buffers } = makeDevice(0);
    const log = jest.spyOn(console, 'log').mockImplementation(() => {});
    await pool.ensure(device, {} as GPUBindGroupLayout);
    log.mockRestore();
    pool.destroy();
    expect(pool.getBindings()).toBeNull();
    expect(buffers.every((b) => b.destroyed)).toBe(true);
  });
});
