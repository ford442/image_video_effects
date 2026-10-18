/**
 * deviceCounters.ts
 *
 * Cheap per-device counters for `queue.submit` and `createBindGroup`, so the
 * frame loop can report submits / bind groups per frame in diagnostics
 * (#1314 acceptance: one submit per frame) without a GPU profiler.
 */

export interface DeviceCounters {
  submits: number;
  bindGroups: number;
}

const counters = new WeakMap<GPUDevice, DeviceCounters>();

/** Wrap the device's submit / createBindGroup once; returns the live counters. */
export function instrumentDevice(device: GPUDevice): DeviceCounters {
  const existing = counters.get(device);
  if (existing) return existing;

  const c: DeviceCounters = { submits: 0, bindGroups: 0 };
  counters.set(device, c);

  // Partial devices (tests, exotic wrappers) simply go uncounted.
  const queue = device.queue;
  if (queue && typeof queue.submit === 'function') {
    const submit = queue.submit.bind(queue);
    queue.submit = (commandBuffers: Iterable<GPUCommandBuffer>) => {
      c.submits++;
      submit(commandBuffers);
    };
  }
  if (typeof device.createBindGroup === 'function') {
    const createBindGroup = device.createBindGroup.bind(device);
    device.createBindGroup = (descriptor: GPUBindGroupDescriptor) => {
      c.bindGroups++;
      return createBindGroup(descriptor);
    };
  }
  return c;
}

export function readDeviceCounters(device: GPUDevice | null): DeviceCounters | null {
  return device ? counters.get(device) ?? null : null;
}

export interface FrameStats {
  /** queue.submit calls between the previous frame start and this one. */
  submitsLastFrame: number;
  /** createBindGroup calls over the same interval. */
  bindGroupsLastFrame: number;
  framesRendered: number;
}

export function createFrameStats(): FrameStats {
  return { submitsLastFrame: 0, bindGroupsLastFrame: 0, framesRendered: 0 };
}

/** Frame-start bookkeeping: fold the counter deltas since the last frame start. */
export class FrameStatsTracker {
  readonly stats = createFrameStats();
  private lastSubmits = -1;
  private lastBindGroups = 0;
  private lastDevice: GPUDevice | null = null;

  onFrameStart(device: GPUDevice | null): void {
    const c = readDeviceCounters(device);
    if (!c) return;
    if (device !== this.lastDevice || this.lastSubmits < 0) {
      this.lastDevice = device;
      this.lastSubmits = c.submits;
      this.lastBindGroups = c.bindGroups;
      return;
    }
    this.stats.submitsLastFrame = c.submits - this.lastSubmits;
    this.stats.bindGroupsLastFrame = c.bindGroups - this.lastBindGroups;
    this.stats.framesRendered++;
    this.lastSubmits = c.submits;
    this.lastBindGroups = c.bindGroups;
  }
}
