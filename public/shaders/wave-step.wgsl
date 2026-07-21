// Wave Tank — Pass 1: discrete Laplacian integration step
// Reads previous state from dataTextureC, writes integrated state to dataTextureA

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

fn laplacian3x3(uv: vec2<f32>, texelSize: vec2<f32>) -> f32 {
  let center = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
  let left = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(-1.0, 0.0) * texelSize, 0.0).r;
  let right = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(1.0, 0.0) * texelSize, 0.0).r;
  let up = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, -1.0) * texelSize, 0.0).r;
  let down = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, 1.0) * texelSize, 0.0).r;
  return left + right + up + down - 4.0 * center;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }

  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));

  let waveSpeed = mix(0.1, 0.5, u.zoom_params.x);
  let damping = mix(0.98, 0.999, u.zoom_params.y);
  let boundaryReflect = mix(0.0, 0.95, u.zoom_params.w);

  let state = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  var height = state.r;
  var velocity = state.g;
  let prevHeight = state.b;
  let phase = state.a;

  let laplacian = laplacian3x3(uv, texelSize);
  let c2 = waveSpeed * waveSpeed;
  velocity = (velocity + c2 * laplacian) * damping;
  height = height + velocity;

  let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  let edgeFade = smoothstep(0.0, 0.05, edgeDist);
  height = height * mix(1.0, edgeFade, 1.0 - boundaryReflect);
  velocity = velocity * mix(1.0, edgeFade, 1.0 - boundaryReflect);

  height = clamp(height, -2.0, 2.0);
  velocity = clamp(velocity, -1.0, 1.0);

  textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(height, velocity, prevHeight, phase));
}
