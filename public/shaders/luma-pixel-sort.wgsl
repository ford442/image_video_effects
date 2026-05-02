// ═══════════════════════════════════════════════════════════════════
//  Luma Pixel Sort
//  Category: artistic
//  Features: mouse-driven, hdr-ready
//  Complexity: Low
//  Chunks From: original luma-pixel-sort
//  Created: 2026-05-02
//  By: Optimizer
// ═══════════════════════════════════════════════════════════════════
//  Pipeline Notes:
//    • Slot: works in any chained/parallel slot
//    • HDR: outputs unclamped RGBA; tone-map downstream if needed
//    • Samples: 1–2 per pixel depending on local luminance
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// ── Named Constants ───────────────────────────────────────────────
const LUMA_WEIGHTS: vec3<f32> = vec3<f32>(0.299, 0.587, 0.114);
const HASH_A: vec2<f32> = vec2<f32>(12.9898, 78.233);
const HASH_B: f32 = 43758.5453;
const MOUSE_BAND: f32 = 0.2;
const MOUSE_INFLUENCE_MAX: f32 = 0.2;
const NOISE_AMP: f32 = 0.1;
const MAX_STRENGTH: f32 = 0.5;

// ── Helper: fast scalar hash ──────────────────────────────────────
fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, HASH_A)) * HASH_B);
}

// ── Helper: mouse band influence (branchless) ─────────────────────
fn mouseInfluence(uv: vec2<f32>, mousePos: vec2<f32>) -> f32 {
  let dy = abs(uv.y - mousePos.y);
  let inBand = step(dy, MOUSE_BAND);
  return inBand * (1.0 - dy / MOUSE_BAND);
}

// ── Helper: compute displaced UV ──────────────────────────────────
fn displacedUV(
  uv: vec2<f32>,
  luma: f32,
  threshold: f32,
  strength: f32,
  dirMix: f32,
  glitch: f32,
  time: f32
) -> vec2<f32> {
  let shift = max(luma - threshold, 0.0) * strength;

  // Early-out: no displacement and negligible glitch
  if (shift < 0.0001 && glitch < 0.001) {
    return uv;
  }

  let noise = hash12(vec2<f32>(uv.y, time)) * glitch * NOISE_AMP;
  let offsetLen = shift + noise;

  // Branchless direction selection: 0=vertical, 1=horizontal
  let isHoriz = step(0.5, dirMix);
  let offset = vec2<f32>(
    isHoriz * offsetLen,
    (1.0 - isHoriz) * offsetLen
  );

  return clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;

  // Read tunables from uniform params
  let threshold = u.zoom_params.x;
  let strength = u.zoom_params.y * MAX_STRENGTH;
  let dirMix = u.zoom_params.z;
  let glitch = u.zoom_params.w;

  // Single sample for luminance test
  let srcColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = dot(srcColor.rgb, LUMA_WEIGHTS);

  // Dynamic threshold modulated by mouse Y proximity
  let mInf = mouseInfluence(uv, mousePos);
  let localThreshold = threshold - mInf * MOUSE_INFLUENCE_MAX;

  // Compute displaced read coordinate
  let sampleUV = displacedUV(uv, luma, localThreshold, strength, dirMix, glitch, time);

  // Second sample only when displacement is non-zero;
  // branch is data-dependent (not uniform) so GPU predication is efficient
  var outColor: vec4<f32>;
  if (all(sampleUV == uv)) {
    outColor = srcColor;
  } else {
    outColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
  }

  // HDR-ready: no clamping, preserve alpha for downstream tone mapping
  textureStore(writeTexture, vec2<i32>(global_id.xy), outColor);
}
