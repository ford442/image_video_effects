// Ripple Tank — Codex (e) graph node 1: dispersive wave integration.
// A/C packing: height, velocity, foam energy, oscillator phase.
// Writes only A; B and extraBuffer are intentionally unused.

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

fn laplacian(pixel: vec2<i32>, dims: vec2<i32>) -> f32 {
  let center = stateAt(pixel, dims).r;
  var sum = -28.0 * center;
  sum += 4.0 * stateAt(pixel + vec2<i32>(1, 0), dims).r;
  sum += 4.0 * stateAt(pixel + vec2<i32>(-1, 0), dims).r;
  sum += 4.0 * stateAt(pixel + vec2<i32>(0, 1), dims).r;
  sum += 4.0 * stateAt(pixel + vec2<i32>(0, -1), dims).r;
  sum += 2.0 * stateAt(pixel + vec2<i32>(1, 1), dims).r;
  sum += 2.0 * stateAt(pixel + vec2<i32>(1, -1), dims).r;
  sum += 2.0 * stateAt(pixel + vec2<i32>(-1, 1), dims).r;
  sum += 2.0 * stateAt(pixel + vec2<i32>(-1, -1), dims).r;
  sum += stateAt(pixel + vec2<i32>(2, 0), dims).r;
  sum += stateAt(pixel + vec2<i32>(-2, 0), dims).r;
  sum += stateAt(pixel + vec2<i32>(0, 2), dims).r;
  sum += stateAt(pixel + vec2<i32>(0, -2), dims).r;
  return sum / 14.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let dims = vec2<i32>(res);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let state = stateAt(pixel, dims);
  let waveSpeed = mix(0.08, 0.45, u.zoom_params.x) * (1.0 + audio.y * 0.035);
  let damping = mix(0.975, 0.9995, u.zoom_params.y) - audio.z * 0.0008;
  let boundaryReflect = u.zoom_params.w;

  let curvature = laplacian(pixel, dims);
  var velocity = (state.g + waveSpeed * waveSpeed * curvature) * damping;
  var height = state.r + velocity;
  var foam = max(state.b * (0.965 + audio.x * 0.012), abs(curvature) * 0.32);

  let edgeDistance = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  let wall = mix(smoothstep(0.0, 0.06, edgeDistance), 1.0, boundaryReflect);
  height *= wall;
  velocity *= wall;
  foam *= mix(0.7, 1.0, wall);

  textureStore(dataTextureA, pixel, vec4<f32>(
    clamp(height, -1.5, 1.5),
    clamp(velocity, -0.8, 0.8),
    clamp(foam, 0.0, 1.5),
    state.a));
}
