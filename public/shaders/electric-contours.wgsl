// ═══════════════════════════════════════════════════════════════════
//  Electric Contours
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

fn luminance(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let mouse_uv = u.zoom_config.yz;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let edge_threshold_base = u.zoom_params.x * 0.5;
  let glow_multiplier = mix(0.0, 2.0, u.zoom_params.y) * (1.0 + bass * 0.3);
  let audio_spark = u.zoom_params.w * (1.0 + mids * 0.5);

  let texel = 1.0 / resolution;
  let c00 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(-1.0, -1.0), 0.0).rgb);
  let c10 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>( 0.0, -1.0), 0.0).rgb);
  let c20 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>( 1.0, -1.0), 0.0).rgb);
  let c01 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(-1.0,  0.0), 0.0).rgb);
  let c21 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>( 1.0,  0.0), 0.0).rgb);
  let c02 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(-1.0,  1.0), 0.0).rgb);
  let c12 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>( 0.0,  1.0), 0.0).rgb);
  let c22 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>( 1.0,  1.0), 0.0).rgb);

  let sx = -1.0 * c00 - 2.0 * c10 - 1.0 * c20 + 1.0 * c02 + 2.0 * c12 + 1.0 * c22;
  let sy = -1.0 * c00 - 2.0 * c01 - 1.0 * c02 + 1.0 * c20 + 2.0 * c21 + 1.0 * c22;
  let edge = sqrt(sx*sx + sy*sy);

  let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse_uv * vec2<f32>(aspect, 1.0));
  let mouse_influence = smoothstep(0.5, 0.0, dist);

  let noise = hash12(uv * 50.0 + vec2<f32>(time * 2.0));
  let spark = smoothstep(0.9, 1.0, noise * mouse_influence * mix(0.0, 10.0, audio_spark));

  let base_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let color_a = vec3<f32>(0.2, 0.8, 1.0);
  let color_b = vec3<f32>(1.0, 0.2, 0.8);
  let mix_factor = 0.5 + 0.5 * sin(time * 3.0 + dist * 10.0 + bass * 2.0);
  let edge_color = mix(color_a, color_b, mix_factor);

  let final_edge = smoothstep(edge_threshold_base, edge_threshold_base + 0.3, edge);
  let result = mix(base_color.rgb * 0.2, edge_color * glow_multiplier + vec3<f32>(spark), final_edge);
  let glow = mouse_influence * 0.3 * edge_color * glow_multiplier;
  let final_rgb = result + glow;

  let alpha = clamp(final_edge * 0.8 + spark + mouse_influence * 0.2 + base_color.a * 0.3, 0.0, 1.0);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, coord, vec4<f32>(final_rgb, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(final_rgb, alpha));
}
