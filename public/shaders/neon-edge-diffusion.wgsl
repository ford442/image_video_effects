// Neon Edge Diffusion - compute skeleton
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
  config: vec4<f32>,       // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>,  // x=zoomTime, y=mouseX, z=mouseY, w=unused
  zoom_params: vec4<f32>,  // x=param1, y=param2, z=param3, w=param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn edge_diffusion(@builtin(global_invocation_id) gid: vec3<u32>) {
  let coord = vec2<i32>(i32(gid.x), i32(gid.y));
  let center = textureLoad(readTexture, coord, 0).rgb;
  let left = textureLoad(readTexture, coord + vec2<i32>(-1, 0), 0).rgb;
  let right = textureLoad(readTexture, coord + vec2<i32>(1, 0), 0).rgb;
  let top = textureLoad(readTexture, coord + vec2<i32>(0, -1), 0).rgb;
  let bottom = textureLoad(readTexture, coord + vec2<i32>(0, 1), 0).rgb;
  let gx = length(right - left);
  let gy = length(bottom - top);
  let edge = sqrt(gx*gx + gy*gy);
  let light = vec4<f32>(edge * 10.0);
  textureStore(dataTextureA, coord, light);
}

@compute @workgroup_size(8, 8, 1)
fn diffuse_light(@builtin(global_invocation_id) gid: vec3<u32>) {
  let coord = vec2<i32>(i32(gid.x), i32(gid.y));
  let center = textureLoad(readTexture, vec2<i32>(i32(coord.x), i32(coord.y)), 0).r;
  let left = textureLoad(readTexture, vec2<i32>(i32(coord.x - 1), i32(coord.y)), 0).r;
  let right = textureLoad(readTexture, vec2<i32>(i32(coord.x + 1), i32(coord.y)), 0).r;
  let top = textureLoad(readTexture, vec2<i32>(i32(coord.x), i32(coord.y - 1)), 0).r;
  let bottom = textureLoad(readTexture, vec2<i32>(i32(coord.x), i32(coord.y + 1)), 0).r;
  let diffused = (center + left + right + top + bottom) * 0.2;
  let shift = diffused * 0.1;
  let color = vec3<f32>(diffused * (1.0 - shift), diffused * (1.0 - abs(shift - 0.5)), diffused * shift);
  textureStore(dataTextureB, coord, vec4<f32>(color, 1.0));
  textureStore(writeTexture, vec2<i32>(i32(gid.x), i32(gid.y)), vec4<f32>(color, 1.0));
}
