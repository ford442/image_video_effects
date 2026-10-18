// sim ring fixture

#include "_prelude.wgsl"

struct SimParams { stateCount: u32, indexCount: u32, frame: u32, truncated: u32 };
@group(1) @binding(0) var<storage, read_write> simState: array<vec4<f32>>;
@group(1) @binding(2) var<uniform> simParams: SimParams;

@compute @workgroup_size(64, 1, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  if (gid.x >= simParams.stateCount) { return; }
  simState[gid.x] = simState[gid.x] * u.zoom_params.x;
}
