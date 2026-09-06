// ═══════════════════════════════════════════════════════════════════
//  PP Tone Map
//  Category: post-processing
//  Features: audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-06
//  Ideas: continuous algorithm mix; hue-preserving contrast
//  A packing: display RGBA (tone-mapped; no second ACES)
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
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn uncharted2Tonemap(x: vec3<f32>) -> vec3<f32> {
  let A = 0.15; let B = 0.50; let C = 0.10; let D = 0.20; let E = 0.02; let F = 0.30;
  let W = 11.2;
  let whiteScale = 1.0 / (((W * (A * W + C * B) + D * E) / (W * (A * W + B) + D * F)) - E / F);
  var c = ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F;
  c *= whiteScale;
  return clamp(c, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn reinhardToneMap(x: vec3<f32>) -> vec3<f32> {
  return x / (1.0 + x);
}

fn agxToneMap(x: vec3<f32>) -> vec3<f32> {
  let sigmoid = (x * (x * 0.8 + 0.1)) / (x * (x * 0.7 + 0.4) + 0.05);
  return clamp(sigmoid, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn applyExposure(color: vec3<f32>, exposure: f32) -> vec3<f32> {
  return color * pow(2.0, exposure);
}

fn applyContrastHue(color: vec3<f32>, contrast: f32) -> vec3<f32> {
  let l = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
  let newL = (l - 0.5) * contrast + 0.5;
  return color * (newL / max(l, 1e-4));
}

fn applySaturation(color: vec3<f32>, saturation: f32) -> vec3<f32> {
  let l = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
  return mix(vec3<f32>(l), color, saturation);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let bass = plasmaBuffer[0].x;

  let algorithm = clamp(u.zoom_params.x, 0.0, 1.0);
  let exposure = (u.zoom_params.y - 0.5) * 4.0 + bass * 0.15;
  let contrast = max(u.zoom_params.z * 2.0, 0.01);
  let saturation = u.zoom_params.w * 2.0;

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var color = applyExposure(src.rgb, exposure);

  let c0 = acesToneMap(color);
  let c1 = uncharted2Tonemap(color);
  let c2 = reinhardToneMap(color);
  let c3 = agxToneMap(color);
  let t = algorithm * 3.0;
  var ldr = mix(c0, c1, clamp(t, 0.0, 1.0));
  ldr = mix(ldr, c2, clamp(t - 1.0, 0.0, 1.0));
  ldr = mix(ldr, c3, clamp(t - 2.0, 0.0, 1.0));

  ldr = applyContrastHue(ldr, contrast);
  ldr = applySaturation(ldr, saturation);
  ldr = clamp(ldr, vec3<f32>(0.0), vec3<f32>(1.0));

  let rolloff = smoothstep(0.55, 1.0, dot(ldr, vec3<f32>(0.2126, 0.7152, 0.0722)));
  let alpha = clamp(src.a * 0.6 + rolloff * 0.4, 0.0, 1.0);
  let outCol = vec4<f32>(ldr, alpha);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
