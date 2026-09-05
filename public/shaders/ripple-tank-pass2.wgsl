// Ripple Tank — Codex (e) graph node 3: capillary dispersion and foam gather.
// Replaces the legacy coarse-grid scratch path with local A/C refinement.
// Reads exact bounded C state and writes only A.

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn stateAt(pixel: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC,
    clamp(pixel, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let dims = vec2<i32>(res);
  let state = stateAt(pixel, dims);
  let left = stateAt(pixel + vec2<i32>(-1, 0), dims);
  let right = stateAt(pixel + vec2<i32>(1, 0), dims);
  let top = stateAt(pixel + vec2<i32>(0, -1), dims);
  let bottom = stateAt(pixel + vec2<i32>(0, 1), dims);
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

  let curvature = left.r + right.r + top.r + bottom.r - 4.0 * state.r;
  let velocityCurvature = left.g + right.g + top.g + bottom.g - 4.0 * state.g;
  let surfaceTension = mix(0.006, 0.035, u.zoom_params.x) *
    (1.0 + audio.z * 0.35);
  let velocity = clamp(state.g - curvature * surfaceTension +
    velocityCurvature * 0.004, -0.8, 0.8);
  let foamNeighbor = (left.b + right.b + top.b + bottom.b) * 0.25;
  let foam = clamp(mix(state.b, foamNeighbor, 0.12) +
    abs(curvature) * (0.08 + audio.y * 0.06), 0.0, 1.5);

  textureStore(dataTextureA, pixel,
    vec4<f32>(state.r, velocity, foam, state.a));
}
