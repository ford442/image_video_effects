// ═══════════════════════════════════════════════════════════════════
//  Electric Contours v2
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba, field-line-tracing,
//            equipotential-surfaces, dielectric-polarization, corona-discharge
//  Complexity: Very High
//  Chunks From: electric-contours.wgsl v1
//  Created: 2026-05-31
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luminance(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn potentialAt(uv: vec2<f32>, charges: vec4<f32>, mouseCharge: f32, mousePos: vec2<f32>) -> f32 {
  let c1 = uv - vec2<f32>(0.35, 0.5);
  let c2 = uv - vec2<f32>(0.65, 0.5);
  let c3 = uv - mousePos;
  let r1 = length(c1) + 0.001;
  let r2 = length(c2) + 0.001;
  let r3 = length(c3) + 0.001;
  return charges.x / r1 + charges.y / r2 + mouseCharge / r3;
}

fn fieldAt(uv: vec2<f32>, charges: vec4<f32>, mouseCharge: f32, mousePos: vec2<f32>) -> vec2<f32> {
  let eps = 0.005;
  let p0 = potentialAt(uv, charges, mouseCharge, mousePos);
  let px = potentialAt(uv + vec2<f32>(eps, 0.0), charges, mouseCharge, mousePos);
  let py = potentialAt(uv + vec2<f32>(0.0, eps), charges, mouseCharge, mousePos);
  return -vec2<f32>(px - p0, py - p0) / eps;
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

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let edge_threshold_base = u.zoom_params.x * 0.5;
  let glow_multiplier = mix(0.0, 2.0, u.zoom_params.y) * (1.0 + bass * 0.3);
  let field_density = u.zoom_params.z * (1.0 + (1.0 - depth) * 0.5);
  let audio_spark = u.zoom_params.w * (1.0 + mids * 0.5);

  let texel = 1.0 / resolution;
  let c00 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(-1.0, -1.0), 0.0).rgb);
  let c10 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(0.0, -1.0), 0.0).rgb);
  let c20 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(1.0, -1.0), 0.0).rgb);
  let c01 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(-1.0, 0.0), 0.0).rgb);
  let c21 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(1.0, 0.0), 0.0).rgb);
  let c02 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(-1.0, 1.0), 0.0).rgb);
  let c12 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(0.0, 1.0), 0.0).rgb);
  let c22 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(1.0, 1.0), 0.0).rgb);

  let sx = -1.0 * c00 - 2.0 * c10 - 1.0 * c20 + 1.0 * c02 + 2.0 * c12 + 1.0 * c22;
  let sy = -1.0 * c00 - 2.0 * c01 - 1.0 * c02 + 1.0 * c20 + 2.0 * c21 + 1.0 * c22;
  let edge = sqrt(sx * sx + sy * sy);

  let q1 = 0.5 + bass * 0.3;
  let q2 = -0.5 - bass * 0.2;
  let mouseCharge = select(0.0, 0.8 + bass * 0.4, u.zoom_config.w > 0.5);
  let charges = vec4<f32>(q1, q2, 0.0, 0.0);

  let pot = potentialAt(uv, charges, mouseCharge, mouse_uv);
  let eField = fieldAt(uv, charges, mouseCharge, mouse_uv);
  let fieldMag = length(eField);

  let equipotential = abs(sin(pot * field_density * 8.0));
  let fieldLine = abs(sin(atan2(eField.y, eField.x) * field_density * 5.0 + time * 2.0));

  let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse_uv * vec2<f32>(aspect, 1.0));
  let mouse_influence = smoothstep(0.5, 0.0, dist);

  let noise = hash12(uv * 50.0 + vec2<f32>(time * 2.0));
  let spark = smoothstep(0.9, 1.0, noise * mouse_influence * mix(0.0, 10.0, audio_spark));

  let base_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let color_a = vec3<f32>(0.1, 0.85, 1.0);
  let color_b = vec3<f32>(1.0, 0.15, 0.85);
  let dielectric = mix(vec3<f32>(0.8, 1.0, 0.6), vec3<f32>(1.0, 0.6, 0.4), mids);
  let mix_factor = 0.5 + 0.5 * sin(time * 3.0 + dist * 10.0 + bass * 2.0);
  let edge_color = mix(color_a, color_b, mix_factor);

  let final_edge = smoothstep(edge_threshold_base, edge_threshold_base + 0.3, edge);
  let field_contrib = (equipotential * 0.4 + fieldLine * 0.6) * fieldMag * 0.1;

  let plasma_glow = edge_color * glow_multiplier * (final_edge + field_contrib);
  let corona = vec3<f32>(1.0, 0.9, 0.7) * smoothstep(2.0, 6.0, fieldMag) * spark * 2.0;

  let result = mix(base_color.rgb * 0.2, plasma_glow + corona, clamp(final_edge + field_contrib * 0.5, 0.0, 1.0));
  let dielectric_shift = dielectric * field_contrib * 0.3 * depth;
  let glow = mouse_influence * 0.3 * edge_color * glow_multiplier;
  let final_rgb = result + glow + dielectric_shift;

  let bloom = corona * 0.5 + vec3<f32>(spark) * edge_color;
  let tonemapped = acesToneMap(final_rgb + bloom);

  let fieldLineDensity = clamp(fieldMag * 0.15 + final_edge * 0.5, 0.0, 1.0);
  let dielectricDisplacement = clamp(field_contrib * 2.0, 0.0, 1.0);
  let alpha = clamp(fieldLineDensity * dielectricDisplacement * depth + spark + mouse_influence * 0.15 + base_color.a * 0.2, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(tonemapped, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(tonemapped, alpha));
}
