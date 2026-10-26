/**
 * simHash.ts
 *
 * Optional spatial hash for the @group(1) sim ring (bind_group1.json
 * `spatialHash`, binding 3 `simHash`). One u32 buffer: `cellCount` cell heads,
 * then one `next` link per agent. The frame planner rebuilds it with a head
 * reset plus one scatter compute pass before the first node that reads it:
 *
 *     next[i] = atomicExchange(head[cell(xy_i)], i)
 *
 * so a reader walks a cell's agents by following `next` from the head, with a
 * hard visit cap. Everything here is TypeScript-only; the C++ backend refuses
 * @group(1) shaders before LoadShader.
 */

import bindGroup1Contract from '../../contracts/bind_group1.json';

const spatialHash = bindGroup1Contract.spatialHash;

export const SIM_HASH_BINDING = spatialHash.binding;
/** Cells per row and column over the working-size domain. */
export const SIM_HASH_GRID = spatialHash.gridWidth;
export const SIM_HASH_CELL_COUNT = spatialHash.cellCount;
/** u32 index of agent 0's `next` link inside simHash. */
export const SIM_HASH_NEXT_OFFSET = spatialHash.nextOffset;
/** Head value of an empty cell. */
export const SIM_HASH_EMPTY = spatialHash.emptyHead;
export const SIM_HASH_HEAD_BYTES = SIM_HASH_CELL_COUNT * 4;
export const SIM_HASH_WORKGROUP_SIZE_X = spatialHash.build.workgroupSize[0] as number;
/** { res: vec2<f32>, stateCount: u32, pad: u32 } — internal to the scatter pass, not author-visible. */
export const SIM_HASH_PARAMS_BYTES = 16;

/** simHash holds the heads plus one link per allocated agent. */
export function simHashBufferBytes(stateCount: number): number {
  return (SIM_HASH_NEXT_OFFSET + stateCount) * 4;
}

/** Heads pre-filled with the empty sentinel (clearBuffer can only zero-fill). */
export function emptyHeads(): Uint32Array<ArrayBuffer> {
  return new Uint32Array(new ArrayBuffer(SIM_HASH_HEAD_BYTES)).fill(SIM_HASH_EMPTY);
}

/** The scatter pass: reads simState, writes simHash. Its own bind group, never an author's. */
export function simHashBuildWgsl(): string {
  return /* wgsl */ `
struct HashParams {
  res: vec2<f32>,
  stateCount: u32,
  pad: u32,
};

@group(0) @binding(0) var<storage, read> simState: array<vec4<f32>>;
@group(0) @binding(1) var<storage, read_write> simHash: array<atomic<u32>>;
@group(0) @binding(2) var<uniform> hp: HashParams;

const HASH_GRID: u32 = ${SIM_HASH_GRID}u;
const HASH_NEXT: u32 = ${SIM_HASH_NEXT_OFFSET}u;

@compute @workgroup_size(${SIM_HASH_WORKGROUP_SIZE_X}, 1, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let i = gid.x;
  if (i >= hp.stateCount) { return; }
  let p = simState[i].xy;
  // Dead agents park outside the domain; NaN fails every comparison.
  if (!(p.x >= 0.0 && p.y >= 0.0 && p.x < hp.res.x && p.y < hp.res.y)) { return; }
  let g = f32(HASH_GRID);
  let c = vec2<u32>(clamp(p / hp.res * g, vec2<f32>(0.0), vec2<f32>(g - 1.0)));
  let prev = atomicExchange(&simHash[c.y * HASH_GRID + c.x], i);
  atomicStore(&simHash[HASH_NEXT + i], prev);
}
`;
}

/** Mirrors the scatter shader's bindings: simState (read), simHash (write), params. */
export function createSimHashBuildBindGroupLayout(device: GPUDevice): GPUBindGroupLayout {
  const V = GPUShaderStage.COMPUTE;
  return device.createBindGroupLayout({
    label: 'simHashBuildBGL',
    entries: [
      { binding: 0, visibility: V, buffer: { type: 'read-only-storage' } },
      { binding: 1, visibility: V, buffer: { type: 'storage' } },
      { binding: 2, visibility: V, buffer: { type: 'uniform' } },
    ],
  });
}

export interface SimHashBuildResources {
  bindGroupLayout: GPUBindGroupLayout;
  pipeline: GPUComputePipeline;
}

/** Compile the scatter pass. Small and static, so it is created synchronously with the layout. */
export function createSimHashBuildResources(device: GPUDevice): SimHashBuildResources {
  const bindGroupLayout = createSimHashBuildBindGroupLayout(device);
  const module = device.createShaderModule({ label: 'simHashBuild', code: simHashBuildWgsl() });
  const pipeline = device.createComputePipeline({
    label: 'simHashBuild',
    layout: device.createPipelineLayout({
      label: 'simHashBuildPL',
      bindGroupLayouts: [bindGroupLayout],
    }),
    compute: { module, entryPoint: 'main' },
  });
  return { bindGroupLayout, pipeline };
}
