/**
 * simRing.ts
 *
 * Opt-in @group(1) sim ring: an indexable storage-buffer ring for particles,
 * walkers and photons. Group 0 is at the contract ceiling, so persistent agents
 * live here instead of in extraBuffer / plasmaBuffer.
 *
 * Contract: src/contracts/bind_group1.json (sync-checked by verify:device-policy).
 *   binding 0  simState   storage read_write array<vec4<f32>>
 *   binding 1  simIndex   read-only storage  array<u32>  (snapshot of simState)
 *   binding 2  simParams  uniform { stateCount, indexCount, frame, truncated }
 *
 * Shaders that never declare @group(1) keep the single-layout pipeline; only
 * group-1 pipelines need the group-1 limits (checked against device.limits,
 * never added to the catalog-wide requiredLimits).
 */

import bindGroup1Contract from '../../contracts/bind_group1.json';

function contractBinding(index: number): (typeof bindGroup1Contract.bindings)[number] {
  const binding = bindGroup1Contract.bindings[index];
  if (!binding) throw new Error(`bind_group1.json is missing binding ${index}`);
  return binding;
}

export const SIM_RING_GROUP = bindGroup1Contract.group;
export const SIM_STATE_ELEMENT_BYTES = contractBinding(0).elementBytes as number;
export const SIM_PARAMS_BYTES = contractBinding(2).sizeBytes as number;
export const SIM_RING_OOM_LADDER: readonly number[] = bindGroup1Contract.oom.ladder;
export const SIM_RING_OOM_CAP_KEY = bindGroup1Contract.oom.sessionStorageKey;
export const SIM_RING_DEFAULT_STATE_COUNT = bindGroup1Contract.oom.defaultStateCount;
export const SIM_STATE_WORKGROUP_SIZE_X = bindGroup1Contract.dispatch.simStateWorkgroupSize[0];
export const GROUP1_REQUIRED_LIMITS = bindGroup1Contract.group1RequiredLimits;

export type SimDispatchDomain = 'pixels' | 'simState';

// ── WGSL detection ──────────────────────────────────────────────────────────

const GROUP1_DECL = /@group\(\s*1\s*\)/;

/** Strip // and block comments so a commented-out declaration does not opt in. */
function stripWgslComments(wgsl: string): string {
  return wgsl.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
}

/** True when the WGSL declares any @group(1) binding (opts into the sim ring). */
export function declaresBindGroup1(wgsl: string): boolean {
  return GROUP1_DECL.test(stripWgslComments(wgsl));
}

const GROUP1_BINDING_PATTERNS: Record<number, { name: string; pattern: RegExp }> = {
  0: {
    name: 'simState',
    pattern: /var<\s*storage\s*,\s*read_write\s*>\s*simState\s*:\s*array<\s*vec4<\s*f32\s*>\s*>/,
  },
  1: {
    name: 'simIndex',
    pattern: /var<\s*storage\s*(?:,\s*read\s*)?>\s*simIndex\s*:\s*array<\s*u32\s*>/,
  },
  2: {
    name: 'simParams',
    pattern: /var<\s*uniform\s*>\s*simParams\s*:\s*SimParams/,
  },
};

/**
 * Validate @group(1) declarations against bind_group1.json. Only bindings 0–2
 * exist; each declared binding must use the contract name and type. A shader
 * may declare a subset (e.g. a render pass that only reads simState).
 */
export function validateGroup1Declarations(wgsl: string): string[] {
  const src = stripWgslComments(wgsl);
  const errors: string[] = [];
  const declRe = /@group\(\s*1\s*\)\s*@binding\(\s*(\d+)\s*\)\s*([^;]*);/g;
  let m: RegExpExecArray | null;
  while ((m = declRe.exec(src)) !== null) {
    const binding = parseInt(m[1]!, 10);
    const spec = GROUP1_BINDING_PATTERNS[binding];
    if (!spec) {
      errors.push(`@group(1) @binding(${binding}) is outside the sim-ring contract (0–2)`);
      continue;
    }
    if (!spec.pattern.test(m[2]!)) {
      errors.push(
        `@group(1) @binding(${binding}) must be \`${contractBinding(binding).wgsl}\``,
      );
    }
  }
  if (/@binding\(\s*\d+\s*\)\s*@group\(\s*1\s*\)/.test(src)) {
    errors.push('@group(1) declarations must be written as `@group(1) @binding(N)`');
  }
  if (/var<\s*uniform\s*>\s*simParams/.test(src)) {
    const struct = src.match(/struct\s+SimParams\s*\{([^}]*)\}/);
    if (!struct) {
      errors.push('simParams declared without `struct SimParams`');
    } else {
      const fields = contractBinding(2).fields ?? [];
      const body = struct[1]!;
      fields.forEach((field, i) => {
        const re = new RegExp(`\\b${field}\\s*:\\s*u32`);
        if (!re.test(body)) errors.push(`SimParams field ${i} must be \`${field}: u32\``);
      });
    }
  }
  return errors;
}

// ── Device limits (group-1 pipelines only) ──────────────────────────────────

export interface SimRingLimitCheck {
  ok: boolean;
  failures: string[];
}

/**
 * Group-1 pipelines need more storage/uniform buffers and a second bind group.
 * All three values sit within the WebGPU base limits (8 / 12 / 4), so every
 * conformant device already exposes them without a catalog-wide requiredLimits
 * bump — this only guards exotic adapters / mocks.
 */
export function checkSimRingLimits(
  limits: Partial<Record<keyof typeof GROUP1_REQUIRED_LIMITS, number>> | undefined,
): SimRingLimitCheck {
  const failures: string[] = [];
  for (const [name, required] of Object.entries(GROUP1_REQUIRED_LIMITS)) {
    const actual = limits?.[name as keyof typeof GROUP1_REQUIRED_LIMITS];
    if (typeof actual !== 'number' || actual < required) {
      failures.push(`${name}: need >= ${required}, device has ${actual ?? 'unknown'}`);
    }
  }
  return { ok: failures.length === 0, failures };
}

// ── Layouts ─────────────────────────────────────────────────────────────────

/** Mirrors bind_group1.json `bindings` (binding order + buffer types). */
export function createSimRingBindGroupLayout(device: GPUDevice): GPUBindGroupLayout {
  const V = GPUShaderStage.COMPUTE;
  return device.createBindGroupLayout({
    label: 'simRingBGL',
    entries: [
      { binding: 0, visibility: V, buffer: { type: 'storage' } },
      { binding: 1, visibility: V, buffer: { type: 'read-only-storage' } },
      { binding: 2, visibility: V, buffer: { type: 'uniform' } },
    ],
  });
}

/** Two-layout pipeline layout: group 0 (unchanged 14-entry) + group 1 sim ring. */
export function createSimRingPipelineLayout(
  device: GPUDevice,
  group0: GPUBindGroupLayout,
  group1: GPUBindGroupLayout,
): GPUPipelineLayout {
  return device.createPipelineLayout({
    label: 'computePL-simRing',
    bindGroupLayouts: [group0, group1],
  });
}

// ── OOM ladder ──────────────────────────────────────────────────────────────

function readStorage(key: string): string | null {
  try {
    if (typeof sessionStorage === 'undefined') return null;
    return sessionStorage.getItem(key);
  } catch {
    return null;
  }
}

function writeStorage(key: string, value: string): void {
  try {
    if (typeof sessionStorage === 'undefined') return;
    sessionStorage.setItem(key, value);
  } catch {
    /* private mode / SSR */
  }
}

/** Session cap after a sim-ring OOM (a ladder rung), or null when unset. */
export function readSimRingOomCap(): number | null {
  const raw = readStorage(SIM_RING_OOM_CAP_KEY);
  if (raw === null) return null;
  const n = parseInt(raw, 10);
  return SIM_RING_OOM_LADDER.includes(n) ? n : null;
}

export function persistSimRingOomCap(stateCount: number): void {
  writeStorage(SIM_RING_OOM_CAP_KEY, String(stateCount));
}

/** Ladder rungs to try for a request, largest first, honouring the session cap. */
export function simRingRungsForRequest(
  requested: number = SIM_RING_DEFAULT_STATE_COUNT,
  cap: number | null = readSimRingOomCap(),
): number[] {
  const ceiling = Math.min(requested, cap ?? Number.POSITIVE_INFINITY);
  const rungs = SIM_RING_OOM_LADDER.filter((n) => n <= ceiling);
  // A request below the smallest rung still gets the smallest rung.
  return rungs.length > 0 ? rungs : SIM_RING_OOM_LADDER.slice(-1);
}

/** Next rung below `stateCount`, or null at the bottom of the ladder. */
export function nextSimRingRung(stateCount: number): number | null {
  return SIM_RING_OOM_LADDER.find((n) => n < stateCount) ?? null;
}

// ── Buffers ─────────────────────────────────────────────────────────────────

export interface SimRingAllocation {
  stateBuffer: GPUBuffer;
  indexBuffer: GPUBuffer;
  paramsBuffer: GPUBuffer;
  stateCount: number;
  requested: number;
}

function isOomError(err: unknown): boolean {
  const name = (err as { name?: string } | null)?.name;
  return (
    (typeof GPUOutOfMemoryError !== 'undefined' && err instanceof GPUOutOfMemoryError) ||
    name === 'GPUOutOfMemoryError' ||
    /out of memory/i.test(String((err as { message?: string } | null)?.message ?? err))
  );
}

function destroyQuietly(buffers: (GPUBuffer | undefined)[]): void {
  for (const b of buffers) {
    try {
      b?.destroy();
    } catch {
      /* invalid buffer after OOM */
    }
  }
}

async function tryAllocateRung(
  device: GPUDevice,
  stateCount: number,
): Promise<Omit<SimRingAllocation, 'requested'> | null> {
  const hasScopes =
    typeof device.pushErrorScope === 'function' && typeof device.popErrorScope === 'function';
  if (hasScopes) device.pushErrorScope('out-of-memory');

  const bytes = stateCount * SIM_STATE_ELEMENT_BYTES;
  let stateBuffer: GPUBuffer | undefined;
  let indexBuffer: GPUBuffer | undefined;
  let paramsBuffer: GPUBuffer | undefined;
  let oom = false;
  try {
    stateBuffer = device.createBuffer({
      label: 'simState',
      size: bytes,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST,
    });
    indexBuffer = device.createBuffer({
      label: 'simIndex',
      size: bytes,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    });
    paramsBuffer = device.createBuffer({
      label: 'simParams',
      size: SIM_PARAMS_BYTES,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });
  } catch (err) {
    oom = isOomError(err) || true;
  }

  if (hasScopes) {
    try {
      if (await device.popErrorScope()) oom = true;
    } catch {
      oom = true;
    }
  }

  if (oom || !stateBuffer || !indexBuffer || !paramsBuffer) {
    destroyQuietly([stateBuffer, indexBuffer, paramsBuffer]);
    return null;
  }
  return { stateBuffer, indexBuffer, paramsBuffer, stateCount };
}

/**
 * Walk the OOM ladder (65536 → 32768 → 16384 → 4096). Each failed rung persists
 * the next rung as the session cap (`px_simring_oom_cap`) so a reload never
 * retries the size that already OOMed — same discipline as px_history_oom_cap.
 */
export async function allocateSimRing(
  device: GPUDevice,
  requested: number = SIM_RING_DEFAULT_STATE_COUNT,
): Promise<SimRingAllocation | null> {
  for (const rung of simRingRungsForRequest(requested)) {
    const alloc = await tryAllocateRung(device, rung);
    if (alloc) return { ...alloc, requested };
    const next = nextSimRingRung(rung);
    console.warn(
      `[SimRing] OOM at ${rung} elements — ` +
        (next ? `capping session at ${next}` : 'bottom of ladder, sim ring disabled'),
    );
    persistSimRingOomCap(next ?? rung);
  }
  return null;
}

/**
 * Owns the group-1 buffers + bind group. The renderer arms it lazily when the
 * first group-1 pipeline compiles; non-sim shaders never pay for it.
 */
export class SimRing {
  private alloc: SimRingAllocation | null = null;
  private bindGroup: GPUBindGroup | null = null;
  private device: GPUDevice | null = null;
  private frame = 0;
  private readonly params = new Uint32Array(SIM_PARAMS_BYTES / 4);

  get allocated(): boolean {
    return this.alloc !== null;
  }

  get stateCount(): number {
    return this.alloc?.stateCount ?? 0;
  }

  get truncated(): boolean {
    return !!this.alloc && this.alloc.stateCount < this.alloc.requested;
  }

  get stateBuffer(): GPUBuffer | null {
    return this.alloc?.stateBuffer ?? null;
  }

  get indexBuffer(): GPUBuffer | null {
    return this.alloc?.indexBuffer ?? null;
  }

  get byteSize(): number {
    return this.stateCount * SIM_STATE_ELEMENT_BYTES;
  }

  getBindGroup(): GPUBindGroup | null {
    return this.bindGroup;
  }

  /**
   * Allocate (or keep) the ring and reset the frame counter so shaders can
   * re-seed on `simParams.frame == 0u`.
   */
  async ensure(
    device: GPUDevice,
    layout: GPUBindGroupLayout,
    requested: number = SIM_RING_DEFAULT_STATE_COUNT,
  ): Promise<boolean> {
    this.frame = 0;
    // Buffers from a lost / replaced device are unusable — reallocate on the new one.
    if (this.device !== device) this.destroy();
    const wanted = simRingRungsForRequest(requested)[0];
    if (this.alloc && wanted !== undefined && this.alloc.stateCount >= wanted) {
      this.alloc.requested = Math.max(this.alloc.requested, requested);
      return true;
    }
    const next = await allocateSimRing(device, requested);
    if (!next) return this.alloc !== null;
    this.destroy();
    this.alloc = next;
    this.device = device;
    this.frame = 0;
    this.bindGroup = device.createBindGroup({
      label: 'simRingBG',
      layout,
      entries: [
        { binding: 0, resource: { buffer: next.stateBuffer } },
        { binding: 1, resource: { buffer: next.indexBuffer } },
        { binding: 2, resource: { buffer: next.paramsBuffer } },
      ],
    });
    console.log(
      `[SimRing] armed ${next.stateCount} elements (${(this.byteSize / 1048576).toFixed(2)} MiB state` +
        `${this.truncated ? `, truncated from ${requested}` : ''})`,
    );
    return true;
  }

  /** Upload simParams for this frame and advance the frame counter. */
  writeParams(queue: GPUQueue): void {
    if (!this.alloc) return;
    this.params[0] = this.alloc.stateCount;
    this.params[1] = this.alloc.stateCount * (SIM_STATE_ELEMENT_BYTES / 4);
    this.params[2] = this.frame;
    this.params[3] = this.truncated ? 1 : 0;
    queue.writeBuffer(this.alloc.paramsBuffer, 0, this.params);
    this.frame++;
  }

  /** Re-arm seeding without reallocating (e.g. slot switched to a sim shader). */
  resetFrame(): void {
    this.frame = 0;
  }

  destroy(): void {
    if (this.alloc) {
      destroyQuietly([this.alloc.stateBuffer, this.alloc.indexBuffer, this.alloc.paramsBuffer]);
    }
    this.alloc = null;
    this.bindGroup = null;
    this.device = null;
  }
}
