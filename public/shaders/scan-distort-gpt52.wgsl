// ═══ Scan Distort Matrix gpt52 (Optimized) ═══════════════════════
//  Category: distortion
//  Features: glitch, animated, depth-aware, upgraded-rgba, audio-reactive
//  Complexity: High
//  Upgrades: 16x16 workgroups, canonical math, branchless band mixing,
//            textureLoad depth, cleaner HDR scan pipeline

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Canonical math ────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0;
  var a = 0.5;
  var f = 1.0;
  for (var i: i32 = 0; i < oct; i = i + 1) {
    s = s + a * valueNoise(p * f);
    f = f * 2.0;
    a = a * 0.5;
  }
  return s;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn toLinear(c: vec3<f32>) -> vec3<f32> {
  return pow(c, vec3<f32>(2.2));
}

fn toSrgb(c: vec3<f32>) -> vec3<f32> {
  return pow(c, vec3<f32>(1.0 / 2.2));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let time = u.config.x;

  // Params
  let scanIntensity = u.zoom_params.x;
  let bandSplit = u.zoom_params.y;
  let fbmScale = u.zoom_params.z;
  let chromaticMix = u.zoom_params.w;

  // Audio + depth
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  // Barrel distortion
  let aspect = res.x / res.y;
  let centered = (uv01 - 0.5) * vec2<f32>(aspect, 1.0);
  let radius = length(centered);
  let bend = mix(0.0, 0.18, bandSplit);
  var warped = uv01 + centered * (radius * radius) * bend;

  // FBM-perturbed scan lines
  let fbmPerturb = fbm(vec2<f32>(warped.y * fbmScale * 5.0, time * 0.3), 4) * 0.02 * fbmScale;
  let lines = mix(200.0, 1400.0, scanIntensity);
  let glitch = scanIntensity * 0.08;
  let roll = time * mix(0.2, 2.5, chromaticMix);
  let linePhase = (warped.y + roll + fbmPerturb) * lines;
  let scan = sin(linePhase) * 0.5 + 0.5;
  let scanBoost = 0.65 + 0.75 * scan;

  // Branchless 3-band weights
  let bandT = uv01.y * 3.0;
  let b1 = saturate(1.0 - abs(bandT - 0.5));
  let b2 = saturate(1.0 - abs(bandT - 1.5));
  let b3 = saturate(1.0 - abs(bandT - 2.5));

  // Audio-driven band distortion
  let bandDistort = (1.0 + mids * 3.0) * (1.0 + bass * 0.6);
  let lineId = floor(warped.y * lines * 0.05);
  let jit1 = (hash21(vec2<f32>(lineId, floor(time * 24.0))) - 0.5) * glitch * bandDistort;
  let jit2 = (hash21(vec2<f32>(lineId + 100.0, floor(time * 18.0))) - 0.5) * glitch * bandDistort * 1.5;
  let jit3 = (hash21(vec2<f32>(lineId + 200.0, floor(time * 30.0))) - 0.5) * glitch * bandDistort * 0.7;

  let blockId = floor(warped.y * 30.0);
  let blockNoise = hash21(vec2<f32>(blockId, floor(time * 12.0)));
  let blockJitter = (blockNoise - 0.5) * glitch * step(blockNoise, scanIntensity * 0.6);
  let totalOffset = vec2<f32>(jit1 * b1 + jit2 * b2 + jit3 * b3 + blockJitter, 0.0);

  // Chromatic tear
  let aberr = (scanIntensity * 0.01 + 0.002) * (1.0 + treble * 1.5);
  let r = textureSampleLevel(readTexture, u_sampler, warped + totalOffset + vec2<f32>(aberr, 0.0), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, warped + totalOffset, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, warped + totalOffset - vec2<f32>(aberr, 0.0), 0.0).b;

  // HDR scan processing
  var color = toLinear(vec3<f32>(r, g, b)) * scanBoost;

  // Film grain
  let grain = (hash21(uv01 * res + time) - 0.5) * 0.03
            + (hash21(uv01 * res * 1.3 - time * 0.7) - 0.5) * 0.015;
  color = color + vec3<f32>(grain) * scanIntensity;

  // Depth haze
  let fogAmount = smoothstep(0.0, 1.0, depth * 0.5 + radius * 0.35) * 0.4;
  let fogColor = vec3<f32>(0.08, 0.06, 0.04);
  color = mix(color, fogColor * 1.5, fogAmount);

  // Split-tone: cool shadows / warm highlights
  let lum = luma(color);
  let shadowTint = vec3<f32>(0.6, 0.75, 1.0);
  let highlightTint = vec3<f32>(1.15, 0.95, 0.7);
  let shadowMask = 1.0 - smoothstep(0.0, 0.25, lum);
  let highlightMask = smoothstep(0.5, 1.0, lum);
  color = color * mix(vec3<f32>(1.0), shadowTint, shadowMask * 0.3);
  color = color * mix(vec3<f32>(1.0), highlightTint, highlightMask * 0.25);

  // Rim glow + vignette
  let rim = pow(radius * 1.6, 3.0);
  color = color + vec3<f32>(1.0, 0.85, 0.5) * rim * 0.6 * (1.0 - bandSplit * 0.3);
  let vignette = 1.0 - smoothstep(0.4, 1.2, radius);
  color = color * (0.55 + 0.45 * vignette);

  // ACES tone map
  color = acesToneMap(color);

  // Semantic alpha
  let effectStrength = scanIntensity + bandDistort * 0.3 + length(totalOffset) * 10.0;
  let alpha = saturate(effectStrength);

  textureStore(writeTexture, pixel, vec4<f32>(toSrgb(color), alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
