// ═══════════════════════════════════════════════════════════════════
//  Pixel Scattering
//  Category: image
//  Features: mouse-driven, audio-reactive
//  Complexity: Medium
//  Chunks From: pixel-scattering.wgsl
//  Created: 2026-05-17
//  By: WGSL Upgrade Agent
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let baseRadius = u.zoom_params.x * 0.5 + 0.02;
  let radius = baseRadius * (1.0 + 0.1 * sin(time * 2.0));
  let strength = u.zoom_params.y * 0.2 * (1.0 + plasmaBuffer[0].x);
  let size = u.zoom_params.z;
  let randomness = u.zoom_params.w * (1.0 + plasmaBuffer[0].y);

  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let to_mouse = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(to_mouse);

  let interact = smoothstep(radius, 0.0, dist);
  var dir = normalize(to_mouse);
  dir = select(dir, vec2<f32>(1.0, 0.0), dist < 0.001);

  let noise = hash12(uv * 50.0 + time) - 0.5;
  let angle_jitter = noise * randomness * 3.0;
  let c = cos(angle_jitter);
  let s = sin(angle_jitter);
  let rot_dir = vec2<f32>(dir.x * c - dir.y * s, dir.x * s + dir.y * c);

  let clickBurst = select(1.0, 3.0, u.zoom_config.w > 0.5);
  let offset = -rot_dir * interact * strength * clickBurst;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthBoost = 1.0 + (1.0 - depth) * 0.5;
  let finalUV = uv + offset * depthBoost;

  let color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

  let alphaFade = mix(color.a, color.a * 0.5, interact);
  let sizeConcentration = mix(1.0, 0.3 + 0.7 * (1.0 - interact), size);
  let alpha = alphaFade * sizeConcentration;

  let glow = vec3<f32>(0.5 + rot_dir.x * 0.5, 0.3 + rot_dir.y * 0.3, 0.2) * interact * strength * 0.5;
  let finalColor = vec4<f32>(color.rgb + glow, alpha);

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), finalColor);
}
