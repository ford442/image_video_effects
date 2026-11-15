// ═══════════════════════════════════════════════════════════════════
//  _std/_std_tonemap.wgsl — ACES, AgX, Reinhard, HDR passthrough
//  @std-module tonemap
//  @std-version 1
//  @requires (none)
//
//  Every operator clamps its input to ≥ 0 first. The catalog's private
//  ACES fit maps negative input to bright output (aces(-0.18) ≈ 0.68
//  before clamping); here aces(x < 0) == 0. All operators take and return
//  linear RGB.
// ═══════════════════════════════════════════════════════════════════

/// ACES filmic fit (Narkowicz 2015), input clamped to ≥ 0.
/// @range [0, 1]
/// @cost ~8 ALU
fn aces(x_in: vec3<f32>) -> vec3<f32> {
  let x = max(x_in, vec3<f32>(0.0));
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

/// Reinhard x / (1 + x).
/// @range [0, 1)
/// @cost 1 div
fn reinhard(x_in: vec3<f32>) -> vec3<f32> {
  let x = max(x_in, vec3<f32>(0.0));
  return x / (1.0 + x);
}

/// Extended Reinhard on luminance with a white point; preserves hue.
/// @range [0, 1] for luminance ≤ white
/// @cost ~10 ALU
fn reinhardExtended(x_in: vec3<f32>, white: f32) -> vec3<f32> {
  let x = max(x_in, vec3<f32>(0.0));
  let l = dot(x, vec3<f32>(0.2126, 0.7152, 0.0722));
  let w2 = max(white * white, 1e-6);
  let lo = l * (1.0 + l / w2) / (1.0 + l);
  return x * select(lo / l, 0.0, l < 1e-8);
}

/// AgX sigmoid approximation (6th-order polynomial, Wrensch 2023).
/// @range ≈ [0, 1] for t in [0, 1]
/// @cost 12 mul
fn agxContrast(t: vec3<f32>) -> vec3<f32> {
  let x2 = t * t;
  let x4 = x2 * x2;
  return 15.5 * x4 * x2 - 40.14 * x4 * t + 31.96 * x4 - 6.868 * x2 * t + 0.4298 * x2 + 0.1191 * t - 0.00232;
}

/// AgX base tonemap, input clamped to ≥ 0, output linear (inverse inset + 2.2 EOTF applied).
/// @range [0, 1]
/// @cost 2 mat3, 3 log2, 3 pow
fn agx(x_in: vec3<f32>) -> vec3<f32> {
  let inset = mat3x3<f32>(
    0.842479062253094, 0.0423282422610123, 0.0423756549057051,
    0.0784335999999992, 0.878468636469772, 0.0784336,
    0.0792237451477643, 0.0791661274605434, 0.879142973793104);
  let outset = mat3x3<f32>(
    1.19687900512017, -0.0528968517574562, -0.0529716355144438,
    -0.0980208811401368, 1.15190312990417, -0.0980434501171241,
    -0.0990297440797205, -0.0989611768448433, 1.15107367264116);
  let minEv = -12.47393;
  let maxEv = 4.026069;
  let v = inset * max(x_in, vec3<f32>(0.0));
  let ev = clamp(log2(max(v, vec3<f32>(1e-10))), vec3<f32>(minEv), vec3<f32>(maxEv));
  let curve = agxContrast((ev - minEv) / (maxEv - minEv));
  return clamp(pow(max(outset * curve, vec3<f32>(0.0)), vec3<f32>(2.2)), vec3<f32>(0.0), vec3<f32>(1.0));
}

/// HDR passthrough for the rgba16float canvas: no curve, negatives removed.
/// @range [0, ∞)
/// @cost 1 max
fn hdrPassthrough(x: vec3<f32>) -> vec3<f32> {
  return max(x, vec3<f32>(0.0));
}

/// Exposure in stops: x · 2^ev.
/// @range unbounded
/// @cost 1 exp2
fn exposure(x: vec3<f32>, ev: f32) -> vec3<f32> {
  return x * exp2(ev);
}
