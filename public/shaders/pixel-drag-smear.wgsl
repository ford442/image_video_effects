// ═══════════════════════════════════════════════════════════════════
//  Pixel Drag Smear
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal
//  Complexity: Medium
//  Chunks From: pixel-drag-smear.wgsl
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
  var pp = fract(p * vec2(0.1031, 0.1030));
  pp = pp + dot(pp, pp.yx + 33.33);
  return fract((pp.x + pp.y) * pp.x);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash12(i);
  let b = hash12(i + vec2(1.0, 0.0));
  let c = hash12(i + vec2(0.0, 1.0));
  let d = hash12(i + vec2(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

fn lumaMix(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
  let lumaA = dot(a, vec3(0.299, 0.587, 0.114));
  let lumaB = dot(b, vec3(0.299, 0.587, 0.114));
  let deltaL = lumaB - lumaA;
  let adjust = 1.0 + deltaL * t * 0.3;
  return mix(a, b, t) * adjust;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;

  let brushRadius = mix(0.01, 0.25, u.zoom_params.x);
  let decay = mix(0.8, 0.99, u.zoom_params.z);
  let audioBass = plasmaBuffer[0].x;
  let baseStrength = mix(0.1, 2.0, u.zoom_params.y);
  let clickBoost = select(0.0, 1.5, u.zoom_config.w > 0.5);
  let strength = (baseStrength + audioBass * 0.8 + clickBoost) * 0.5;

  let mouse = u.zoom_config.yz;
  let dist = distance(uv * vec2(aspect, 1.0), mouse * vec2(aspect, 1.0));

  let toMouse = uv - mouse;
  let dir = select(normalize(toMouse), vec2(0.0), length(toMouse) < 0.0001);
  let influence = (1.0 - smoothstep(0.0, brushRadius, dist)) * strength;

  let jitter = (valueNoise(uv * 12.0 + u.config.x) - 0.5) * 0.04;
  let curlAngle = valueNoise(uv * 8.0 + u.config.x * 0.5) * 6.28318;
  let curlDir = vec2(cos(curlAngle), sin(curlAngle));
  let curlDisp = curlDir * influence * 0.03;

  let offset = dir * influence * 0.05 + jitter + curlDisp;

  let historyColor = textureSampleLevel(dataTextureC, u_sampler, uv - offset, 0.0);
  let videoColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let smearWeight = select(0.0, 0.9, influence > 0.001);
  let baseMix = mix(videoColor.rgb, historyColor.rgb, decay);
  let smearMix = mix(baseMix, historyColor.rgb, smearWeight);
  let blended = lumaMix(baseMix, smearMix, influence);

  let velocity = length(offset) * 20.0;
  let warmTint = vec3(1.08, 1.02, 0.92);
  let coolTint = vec3(0.92, 0.98, 1.06);
  let tint = mix(warmTint, coolTint, clamp(velocity, 0.0, 1.0));
  let tinted = blended * tint;

  let toneMapped = acesToneMap(tinted);

  let alphaBoost = influence * 0.6;
  let finalAlpha = mix(videoColor.a, clamp(videoColor.a + alphaBoost, 0.0, 1.0), smoothstep(0.0, 0.005, influence));

  let finalColor = vec4(toneMapped, finalAlpha);

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
  textureStore(dataTextureA, global_id.xy, finalColor);
  textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
