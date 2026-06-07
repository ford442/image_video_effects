// ═══════════════════════════════════════════════════════════════════
//  Temporal Decay Multiresolution
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, temporal, history-ring, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-23
//  Requires: binding 13 (historyTexture — HISTORY_DEPTH=8 ring buffer)
//  Created: 2026-05-23
//  By: Copilot
//
//  Sibling of sim-decay-system-rgba. Maps the four output channels
//  to four distinct temporal timescales pulled from the history ring:
//    R = fast   (avg of ages 1–2): recent flickers and fast motion
//    G = medium (avg of ages 4–5): medium-speed movement
//    B = slow   (age 7):           slow drift and near-static regions
//    A = ultra  (avg of all 7):    scene-level accumulated luminance
//  Per-channel decay constants let each timescale fade independently.
//  Stacks cleanly behind sim-decay-system-rgba in slot 0 → slot 1.
//
//  zoom_params layout:
//    x = fast-decay  rate (0→0.82, 1→0.97, default 0.5→0.895)
//    y = medium-decay rate (0→0.88, 1→0.98, default 0.5→0.93)
//    z = slow-decay   rate (0→0.93, 1→0.99, default 0.5→0.96)
//    w = blend with original (0→full multiRes, 1→original, default 0.3)
//
//  extraBuffer layout:
//    [0]=bass  [1]=mid  [2]=treble  [3]=reserved  [4]=historyHead
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
@group(0) @binding(13) var historyTexture: texture_2d_array<f32>;

struct Uniforms {
  config: vec4<f32>,      // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>, // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>, // x=fastDecay, y=medDecay, z=slowDecay, w=origBlend
  ripples: array<vec4<f32>, 50>,
};

const HISTORY_DEPTH: u32 = 8u;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res   = vec2<f32>(u.config.z, u.config.w);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  // Per-channel decay rates; bass lengthens the fast-decay trail on beats
  let decayFast   = clamp(0.82 + u.zoom_params.x * 0.15 + bass * 0.05, 0.0, 0.999);
  let decayMedium = clamp(0.88 + u.zoom_params.y * 0.10 + mids * 0.02, 0.0, 0.999);
  let decaySlow   = 0.93 + u.zoom_params.z * 0.06;
  let origBlend   = u.zoom_params.w;

  let historyHead = u32(extraBuffer[4]);
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // ── Fast timescale (R): average of ages 1–2 ──────────────────────────────
  let l1 = (historyHead + HISTORY_DEPTH - 1u) % HISTORY_DEPTH;
  let l2 = (historyHead + HISTORY_DEPTH - 2u) % HISTORY_DEPTH;
  let h1 = textureSampleLevel(historyTexture, u_sampler, uv, i32(l1), 0.0);
  let h2 = textureSampleLevel(historyTexture, u_sampler, uv, i32(l2), 0.0);
  let fastAvg = (h1 + h2) * 0.5;

  // ── Medium timescale (G): average of ages 4–5 ────────────────────────────
  let l4 = (historyHead + HISTORY_DEPTH - 4u) % HISTORY_DEPTH;
  let l5 = (historyHead + HISTORY_DEPTH - 5u) % HISTORY_DEPTH;
  let h4 = textureSampleLevel(historyTexture, u_sampler, uv, i32(l4), 0.0);
  let h5 = textureSampleLevel(historyTexture, u_sampler, uv, i32(l5), 0.0);
  let medAvg = (h4 + h5) * 0.5;

  // ── Slow timescale (B): age 7 (oldest reliable frame) ────────────────────
  let l7 = (historyHead + HISTORY_DEPTH - 7u) % HISTORY_DEPTH;
  let h7 = textureSampleLevel(historyTexture, u_sampler, uv, i32(l7), 0.0);

  // ── Ultra-slow timescale: full average of all 7 stored frames ────────────
  var ultraSum = vec4<f32>(0.0);
  for (var age: u32 = 1u; age <= 7u; age = age + 1u) {
    let l = (historyHead + HISTORY_DEPTH - age) % HISTORY_DEPTH;
    ultraSum += textureSampleLevel(historyTexture, u_sampler, uv, i32(l), 0.0);
  }
  let ultraAvg = ultraSum / 7.0;

  // ── Per-channel max(current, decayed_history) ─────────────────────────────
  let r = max(current.r, fastAvg.r   * decayFast);
  let g = max(current.g, medAvg.g    * decayMedium);
  let b = max(current.b, h7.b        * decaySlow);
  // Alpha channel encodes ultra-slow luminance (useful for downstream slots)
  let a = (ultraAvg.r + ultraAvg.g + ultraAvg.b) / 3.0;

  let multiRes = vec4<f32>(r, g, b, a);
  let output   = mix(multiRes, current, origBlend);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, output);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, output);
}
