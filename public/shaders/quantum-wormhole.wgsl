// ═══════════════════════════════════════════════════════════════════
//  Quantum Wormhole — Batch 58C
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal
//  Complexity: High
//  Upgraded: 2026-08-23
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

const TAU: f32 = 6.28318530718;

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
  let K = vec4<f32>(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
  let p = mix(vec4<f32>(c.b, c.g, K.w, K.z), vec4<f32>(c.g, c.b, K.x, K.y), step(c.b, c.g));
  let q = mix(vec4<f32>(p.x, p.y, p.w, c.r), vec4<f32>(c.r, p.y, p.z, p.x), step(p.x, c.r));
  let d = q.x - min(q.w, q.y);
  let e = 1.0e-10;
  return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(vec3<f32>(c.x, c.x, c.x) + K.xyz) * 6.0 - K.www);
  return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn to4D(uv: vec2<f32>, time: f32, aim: vec2<f32>) -> vec4<f32> {
  var p = (uv - aim) * 2.0;
  var r = min(length(p), 0.999);
  let theta = time * 0.2;
  let h = sqrt(max(0.001, 1.0 - r * r));
  return vec4<f32>(p, h * cos(theta), h * sin(theta));
}

fn curlField(uv: vec2<f32>, texelSize: vec2<f32>) -> vec2<f32> {
  let Lu = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texelSize.y), 0.0).r;
  let Ld = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, texelSize.y), 0.0).r;
  let Ll = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texelSize.x, 0.0), 0.0).r;
  let Lr = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(texelSize.x, 0.0), 0.0).r;
  let grad = vec2<f32>(Lr - Ll, Ld - Lu);
  return vec2<f32>(-grad.y, grad.x);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let uv = vec2<f32>(gid.xy) / dims;
  let aspect = dims.x / max(dims.y, 1.0);
  let time = u.config.x;
  let texelSize = 1.0 / dims;
  let mouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

  let twistScale = u.zoom_params.x * 2.0 + 0.5;
  let flowStrength = u.zoom_params.y * 0.8 + 0.1;
  let trailLength = u.zoom_params.z * 0.05;
  let persistence = u.zoom_params.w * 0.15 + 0.8;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let burstIntensity = 0.25 + bass * 0.35;
  let voidThreshold = 0.25 - treble * 0.08;
  let rotationSpeed = 0.15 + mids * 0.25 + held * 0.15;
  let depthInf = 0.5 + (1.0 - smoothstep(0.0, 0.4, length((uv - mouse) * vec2<f32>(aspect, 1.0)))) * 0.35;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let p4 = to4D(uv, time * rotationSpeed, mouse);
  let phase = atan2(p4.w, p4.z);
  let vel = curlField(uv, texelSize) * flowStrength * (1.0 + held * 0.3);

  var hsv = rgb2hsv(src.rgb);
  hsv.x = fract(hsv.x + twistScale * phase / TAU + bass * 0.05);
  hsv.y = hsv.y * (1.0 + (1.0 - depth) * depthInf * 0.3);

  let oilSlick = 0.5 + 0.5 * cos(TAU * (vec3<f32>(phase * 0.3 + time * 0.2) + vec3<f32>(0.0, 0.33, 0.67)));
  var newRGB = hsv2rgb(hsv) * (0.85 + oilSlick * 0.15);

  let lum = max(max(src.r, src.g), src.b);
  let burstHue = fract(atan2(vel.y, vel.x) / TAU + mids * 0.1);
  let burst = hsv2rgb(vec3<f32>(burstHue, 1.0, max(0.0, lum - 1.0) * 2.0));
  newRGB = newRGB + burst * burstIntensity * select(0.0, 1.0, lum > 1.0);

  let voidFlip = select(0.0, 1.0, hsv.z < voidThreshold);
  newRGB = mix(newRGB, -newRGB, voidFlip);

  let helix = sin(atan2(uv.y - mouse.y, uv.x - mouse.x) * 5.0 + time * (1.5 + treble));
  let warpedUV = clamp(uv + vel * trailLength + vec2<f32>(helix, -helix) * 0.008 * held, vec2<f32>(0.0), vec2<f32>(1.0));
  let warpedPixel = clamp(vec2<i32>(warpedUV * dims), vec2<i32>(0), vec2<i32>(dims) - vec2<i32>(1));
  let warpedPrev = textureLoad(dataTextureC, warpedPixel, 0).rgb;

  var clickRing = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = max(time - ripple.z, 0.0);
    let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    clickRing += exp(-age * 1.8) * exp(-abs(rDist - age * 0.42) * 55.0);
  }

  let finalRGB = aces(mix(warpedPrev * persistence + newRGB * (1.0 - persistence), newRGB + oilSlick * clickRing * 0.25, clickRing * 0.4));
  let luma = dot(finalRGB, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(0.3 + luma * 0.5 + clickRing * 0.12, 0.15, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeTexture, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
