/**
 * simRing.ts
 *
 * Opt-in @group(1) simulation ring (src/contracts/bind_group1.json).
 *
 * Group 0 is at the contract ceiling (14 bindings, 4 storage textures, 2 storage
 * buffers). Indexable state that is not a texture — walkers, photon pools,
 * neighbour tables — lives here instead of in extraBuffer[133..] or RGBA tiles.
 *
 * Only shaders that declare @group(1) are compiled against the two-group
 * pipeline layout, and the buffers are allocated the first time one compiles,
 * so the rest of the catalog pays nothing.
 */

import simRingContract from '../../contracts/bind_group1.json';
import { isGpuOutOfMemoryError } from '../../config/vramBudget';

export type SimBufferRole = 'simState' | 'simIndex';

export const SIM_BUFFER_ROLES: readonly SimBufferRole[] = ['simState', 'simIndex'] as const;

/** Roles a shader (and therefore a graph node) may write. simIndex is host-published only. */
export const WRITABLE_SIM_BUFFER_ROLES: readonly SimBufferRole[] = SIM_BUFFER_ROLES.filter(
  (role) => simRingContract.bufferRoles[role].graphWrites,
);

export const SIM_RING_GROUP = simRingContract.group;

type ContractBinding = (typeof simRingContract.bindings)[number];

function contractBinding(name: string): ContractBinding {
  const b = simRingContract.bindings.find((entry) => entry.name === name);
  if (!b) throw new Error(`bind_group1.json is missing binding "${name}"`);
  return b;
}

const STATE = contractBinding('simState');
const INDEX = contractBinding('simIndex');
const PARAMS = contractBinding('simParams');

export const SIM_STATE_ELEMENT_BYTES = STATE.elementBytes as number;
export const SIM_INDEX_ELEMENT_BYTES = INDEX.elementBytes as number;
export const SIM_PARAMS_BYTES = PARAMS.sizeBytes as number;
export const SIM_STATE_DEFAULT_CAPACITY = STATE.defaultCapacity as number;
export const SIM_INDEX_DEFAULT_CAPACITY = INDEX.defaultCapacity as number;

/** Particle-count ladder, largest first. Never retry a larger rung after an OOM this tab. */
export const SIM_RING_STATE_RUNGS: readonly number[] = simRingContract.oomLadder.stateRungs;
export const SIM_RING_INDEX_PER_STATE = simRingContract.oomLadder.indexElementsPerStateElement;
export const SIM_RING_OOM_CAP_KEY = simRingContract.oomLadder.sessionStorageKey;

/** Strip WGSL comments so a commented-out `@group(1)` does not opt a shader in. */
function stripWgslComments(wgsl: string): string {
  return wgsl.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
}

/** True when the shader declares any @group(1) binding (i.e. needs the two-group layout). */
export function declaresSimRing(wgsl: string): boolean {
  return /@group\(\s*1\s*\)/.test(stripWgslComments(wgsl));
}

export function createSimRingBindGroupLayout(device: GPUDevice): GPUBindGroupLayout {
  const V = GPUShaderStage.COMPUTE;
  return device.createBindGroupLayout({
    label: 'simRingBGL',
    entries: simRingContract.bindings.map((b) => ({
      binding: b.binding,
      visibility: V,
      buffer: { type: b.bufferType as GPUBufferBindingType },
    })),
  });
}

function readCap(): number | null {
  try {
    if (typeof sessionStorage === 'undefined') return null;
    const raw = sessionStorage.getItem(SIM_RING_OOM_CAP_KEY);
    if (raw === null) return null;
    const n = parseInt(raw, 10);
    return Number.isFinite(n) ? n : null;
  } catch {
    return null;
  }
}

/** Largest simState rung this tab may still try (latched down after OOM). */
export function getSimRingStateCap(): number {
  return readCap() ?? SIM_RING_STATE_RUNGS[0];
}

export function persistSimRingOomCap(cap: number): void {
  try {
    if (typeof sessionStorage === 'undefined') return;
    sessionStorage.setItem(SIM_RING_OOM_CAP_KEY, String(cap));
  } catch {
    /* private mode / SSR */
  }
}

export function simRingRungsForCap(cap: number): number[] {
  return SIM_RING_STATE_RUNGS.filter((rung) => rung <= cap);
}

export interface SimRingAllocation {
  stateBuf: GPUBuffer;
  indexBuf: GPUBuffer;
  paramsBuf: GPUBuffer;
  stateCount: number;
  indexCount: number;
  truncated: boolean;
}

/** What the frame loop and GraphRunner need from an allocated ring. */
export interface SimRingBindings {
  bindGroup: GPUBindGroup;
  stateBuf: GPUBuffer;
  indexBuf: GPUBuffer;
  stateCount: number;
  indexCount: number;
  /** Bytes published by a simState → simIndex barrier. */
  copyBytes: number;
  truncated: boolean;
}

/** Frame-loop surface (kept narrow so tests can fake it). */
export interface SimRingFrameSource {
  getBindings(): SimRingBindings | null;
  beginFrame(queue: GPUQueue): void;
}

function destroyQuietly(buf: GPUBuffer | undefined): void {
  try {
    buf?.destroy();
  } catch {
    /* already invalid after OOM */
  }
}

async function tryAllocateRung(
  device: GPUDevice,
  stateCount: number,
): Promise<{ state: GPUBuffer; index: GPUBuffer; indexCount: number } | null> {
  const indexCount = stateCount * SIM_RING_INDEX_PER_STATE;
  const hasScopes =
    typeof device.pushErrorScope === 'function' && typeof device.popErrorScope === 'function';
  if (hasScopes) device.pushErrorScope('out-of-memory');

  let state: GPUBuffer | undefined;
  let index: GPUBuffer | undefined;
  let thrown: unknown = null;
  try {
    state = device.createBuffer({
      label: 'simState',
      size: stateCount * SIM_STATE_ELEMENT_BYTES,
      // COPY_SRC: source of the simState → simIndex barrier.
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST,
    });
    index = device.createBuffer({
      label: 'simIndex',
      size: indexCount * SIM_INDEX_ELEMENT_BYTES,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    });
  } catch (err) {
    thrown = err;
  }

  let scoped: GPUError | null = null;
  if (hasScopes) {
    try {
      scoped = await device.popErrorScope();
    } catch (err) {
      thrown = thrown ?? err;
    }
  }

  if (thrown || scoped) {
    destroyQuietly(state);
    destroyQuietly(index);
    if (thrown && !isGpuOutOfMemoryError(thrown)) {
      console.warn('[SimRing] allocation threw a non-OOM error; treating as OOM:', thrown);
    }
    return null;
  }
  return { state: state!, index: index!, indexCount };
}

/**
 * Allocate simState + simIndex under an out-of-memory scope, walking the ladder
 * down from `cap`. Each failed rung latches the next one in sessionStorage so a
 * reload never retries the fat size (same discipline as px_history_oom_cap).
 */
export async function allocateSimRing(
  device: GPUDevice,
  cap: number = getSimRingStateCap(),
): Promise<SimRingAllocation | null> {
  const rungs = simRingRungsForCap(cap);
  for (let i = 0; i < rungs.length; i++) {
    const stateCount = rungs[i];
    const got = await tryAllocateRung(device, stateCount);
    if (!got) {
      const next = rungs[i + 1] ?? 0;
      persistSimRingOomCap(next);
      console.warn(
        `[SimRing] OOM at ${stateCount} particles — latching cap ${next} (never retrying ${stateCount})`,
      );
      continue;
    }
    const paramsBuf = device.createBuffer({
      label: 'simParams',
      size: SIM_PARAMS_BYTES,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });
    return {
      stateBuf: got.state,
      indexBuf: got.index,
      paramsBuf,
      stateCount,
      indexCount: got.indexCount,
      truncated: stateCount < SIM_RING_STATE_RUNGS[0],
    };
  }
  return null;
}

/**
 * Lazily-allocated ring owned by the TS WebGPU renderer.
 * `ensure` is idempotent and de-duplicates concurrent callers (graph entries
 * load in parallel).
 */
export class SimRingPool implements SimRingFrameSource {
  private allocation: SimRingAllocation | null = null;
  private bindGroup: GPUBindGroup | null = null;
  private pending: Promise<boolean> | null = null;
  private failed = false;
  private frame = 0;
  private readonly paramsScratch = new Uint32Array(SIM_PARAMS_BYTES / 4);

  get allocated(): boolean {
    return this.allocation !== null;
  }

  ensure(device: GPUDevice, layout: GPUBindGroupLayout): Promise<boolean> {
    if (this.allocation && this.bindGroup) return Promise.resolve(true);
    if (this.failed) return Promise.resolve(false);
    if (!this.pending) {
      this.pending = (async () => {
        const allocation = await allocateSimRing(device);
        if (!allocation) {
          this.failed = true;
          console.error('[SimRing] every rung OOMed — group-1 shaders will not load this session');
          return false;
        }
        this.allocation = allocation;
        this.bindGroup = device.createBindGroup({
          label: 'simRingBG',
          layout,
          entries: [
            { binding: 0, resource: { buffer: allocation.stateBuf } },
            { binding: 1, resource: { buffer: allocation.indexBuf } },
            { binding: 2, resource: { buffer: allocation.paramsBuf } },
          ],
        });
        this.frame = 0;
        console.log(
          `[SimRing] allocated ${allocation.stateCount} particles + ${allocation.indexCount} index` +
            `${allocation.truncated ? ' (truncated by OOM ladder)' : ''}`,
        );
        return true;
      })().finally(() => {
        this.pending = null;
      });
    }
    return this.pending;
  }

  getBindings(): SimRingBindings | null {
    const a = this.allocation;
    if (!a || !this.bindGroup) return null;
    return {
      bindGroup: this.bindGroup,
      stateBuf: a.stateBuf,
      indexBuf: a.indexBuf,
      stateCount: a.stateCount,
      indexCount: a.indexCount,
      copyBytes: Math.min(a.stateBuf.size, a.indexBuf.size),
      truncated: a.truncated,
    };
  }

  /** Upload SimParams once per frame that dispatches a group-1 pipeline. */
  beginFrame(queue: GPUQueue): void {
    const a = this.allocation;
    if (!a) return;
    const p = this.paramsScratch;
    p[0] = a.stateCount;
    p[1] = a.indexCount;
    p[2] = this.frame >>> 0;
    p[3] = a.truncated ? 1 : 0;
    queue.writeBuffer(a.paramsBuf, 0, p);
    this.frame++;
  }

  destroy(): void {
    const a = this.allocation;
    if (a) {
      destroyQuietly(a.stateBuf);
      destroyQuietly(a.indexBuf);
      destroyQuietly(a.paramsBuf);
    }
    this.allocation = null;
    this.bindGroup = null;
    this.failed = false;
    this.frame = 0;
  }
}
