// ═══════════════════════════════════════════════════════════════════
//  Thermal Touch
//  Category: image
//  Features: mouse-driven, audio-reactive
//  Complexity: Medium
//  Created: 2026-05-17
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

fn hash21(p: vec2<f32>) -> f32 {
  let q = fract(p * vec2(123.34, 456.21));
  return fract(dot(q, vec2(12.9898, 78.233)));
}

fn get_thermal_color(val: f32) -> vec3<f32> {
  let v = clamp(val, 0.0, 1.0);
  let s1 = smoothstep(0.0, 0.25, v);
  let s2 = smoothstep(0.25, 0.5, v);
  let s3 = smoothstep(0.5, 0.75, v);
  let s4 = smoothstep(0.75, 1.0, v);
  var c = mix(vec3(0.0, 0.0, 0.5), vec3(0.0, 1.0, 1.0), s1);
  c = mix(c, vec3(0.0, 1.0, 0.0), s2);
  c = mix(c, vec3(1.0, 1.0, 0.0), s3);
  c = mix(c, vec3(1.0, 0.0, 0.0), s4);
  return c;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let time = u.config.x;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let clickBoost = select(1.0, 1.5, u.zoom_config.w > 0.5);

  let heatIntensity = mix(0.1, 2.0, u.zoom_params.x) * (1.0 + bass * 0.4);
  let radius = mix(0.05, 0.5, u.zoom_params.y) * clickBoost;
  let ambientTemp = u.zoom_params.z;
  let colorMode = u.zoom_params.w;

  let mousePos = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let distVec = (uv - mousePos) * vec2(aspect, 1.0);
  let dist = length(distVec);

  let pulse = sin(time * (2.0 + bass * 6.0)) * 0.5 + 0.5;
  let mouseHeat = (1.0 - smoothstep(0.0, radius, dist)) * heatIntensity * (0.8 + pulse * 0.2);
  let shimmer = hash21(uv * 200.0 + time * (2.0 + mids * 10.0)) * 0.04 * (1.0 + mids * 2.0);

  let texColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));

  var heat = luminance + mouseHeat + shimmer;
  heat = mix(heat, ambientTemp, 0.3 * select(0.0, 1.0, ambientTemp > 0.0));

  var finalColor = get_thermal_color(heat);
  finalColor = mix(finalColor, texColor.rgb, 0.5 * select(0.0, 1.0, colorMode > 0.5));

  let alpha = clamp(mix(0.5, 1.0, clamp(heat, 0.0, 1.0)) * (1.0 + mouseHeat * 0.5), 0.0, 1.0);
  let outAlpha = mix(alpha, texColor.a, select(0.0, 1.0, colorMode > 0.5));

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4(finalColor, outAlpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4(finalColor, outAlpha));
}
