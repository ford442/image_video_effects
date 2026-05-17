// ═══════════════════════════════════════════════════════════════════
//  Contour Flow
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Low
//  Upgraded: 2026-05-17
// ═══════════════════════════════════════════════════════════════════

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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let flowSpeed = u.zoom_params.x * 5.0 * (1.0 + bass * 0.3);
  let flowLength = u.zoom_params.y * 0.05;
  let mouseRadius = u.zoom_params.z * 0.5 + 0.01;
  let edgeDetect = u.zoom_params.w * 5.0;
  let mouse = u.zoom_config.yz;

  let texel = vec2<f32>(1.0) / resolution;
  let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).r;
  let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;
  let l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).r;
  let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;

  let gradX = r - l;
  let gradY = b - t;
  let flowDir = normalize(vec2<f32>(-gradY, gradX) + vec2<f32>(0.0001));
  let gradMag = length(vec2<f32>(gradX, gradY));

  let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);
  let mouseFactor = smoothstep(mouseRadius, 0.0, dist);

  let wave = sin(uv.x * 10.0 + uv.y * 10.0 + time * flowSpeed);
  let strength = (gradMag * edgeDetect + 0.2) * mouseFactor * flowLength;
  let offset = flowDir * strength * wave;

  let color = textureSampleLevel(readTexture, u_sampler, clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let highlight = length(offset) * 10.0;
  let final_rgb = color.rgb + vec3<f32>(highlight * 0.1 * (1.0 + mids));

  let alpha = clamp(color.a + highlight * 0.2 + mouseFactor * 0.2, 0.0, 1.0);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, coord, vec4<f32>(final_rgb, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(final_rgb, alpha));
}
