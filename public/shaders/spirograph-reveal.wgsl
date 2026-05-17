// ═══════════════════════════════════════════════════════════════════
//  Spirograph Reveal
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
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
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let aspect = resolution.x / resolution.y;
  let center = mouse;
  let p = (uv - center) * vec2<f32>(aspect, 1.0);

  let r = length(p);
  let a = atan2(p.y, p.x);

  let petals = 3.0 + floor(u.zoom_params.x * 12.0);
  let complexity = 1.0 + u.zoom_params.y * 10.0;
  let speed = u.zoom_params.z * 2.0 * (1.0 + bass * 0.2);
  let thickness = 0.05 + u.zoom_params.w * 0.45;

  let wave1 = sin(a * petals + time * speed);
  let wave2 = cos(a * petals * 2.0 - time * speed * 1.5);
  let wave3 = sin(r * 20.0 * complexity);
  let val = sin(r * 30.0 + wave1 * 5.0 + wave2 * 2.0) + wave3 * 0.5;
  let lineField = abs(val);
  let mask = 1.0 - smoothstep(0.0, thickness, lineField);

  let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let gray = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let paper = vec3<f32>(0.95, 0.9, 0.85) * (0.5 + 0.5 * gray);

  let fade = smoothstep(0.8, 0.3, r);
  let finalMask = mask * fade;

  let outColor = mix(paper, color.rgb, finalMask);
  let alpha = clamp(finalMask * color.a + (1.0 - finalMask) * 0.5 + mids * 0.1, 0.0, 1.0);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, coord, vec4<f32>(outColor, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(outColor, alpha));
}
