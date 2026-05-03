// ═══════════════════════════════════════════════════════════════════
//  Scanline Wave - Sine wave distortion with HDR bloom & atmosphere
//  Category: interactive-mouse
//  Features: mouse-driven, upgraded-rgba, depth-aware
//  Upgraded: 2026-05-03
//  By: Visualist
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

fn srgb_to_linear(c: vec3<f32>) -> vec3<f32> {
  return pow(c, vec3<f32>(2.2));
}

fn linear_to_srgb(c: vec3<f32>) -> vec3<f32> {
  return pow(c, vec3<f32>(1.0 / 2.2));
}

fn aces_tone_map(c: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let cc = 2.43; let d = 0.59; let e = 0.14;
  return clamp((c * (a * c + b)) / (c * (cc * c + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;

  let freq = mix(10.0, 200.0, u.zoom_params.x);
  let amp = u.zoom_params.y * 0.1;
  let speed = (u.zoom_params.z - 0.5) * 20.0;
  let mouse_influence = u.zoom_params.w;

  let wave = sin(uv.y * freq + time * speed) * amp *
             mix(1.0, smoothstep(0.5, 0.0, abs(uv.y - mousePos.y)), step(0.001, mouse_influence));

  let finalUV = vec2<f32>(uv.x + wave, uv.y);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  var col = srgb_to_linear(textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).rgb);

  let waveGlow = abs(wave) / (amp + 0.001);
  col *= 1.0 + waveGlow * 2.0;

  let fogColor = vec3<f32>(0.05, 0.07, 0.12);
  let fogFactor = exp(-depth * 2.5);
  col = mix(fogColor, col, fogFactor);

  let luma = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
  let warmTint = vec3<f32>(1.08, 0.95, 0.82);
  col = mix(col, col * warmTint, smoothstep(0.4, 1.2, luma) * 0.35);

  col = aces_tone_map(col);
  col = linear_to_srgb(col);

  let bloomWeight = pow(max(0.0, luma - 0.5), 2.0) * 2.5;
  textureStore(writeTexture, coord, vec4<f32>(col, bloomWeight));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
