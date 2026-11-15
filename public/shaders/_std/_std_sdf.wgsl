// ═══════════════════════════════════════════════════════════════════
//  _std/_std_sdf.wgsl — signed distance primitives and operators
//  @std-module sdf
//  @std-version 1
//  @requires (none)
//
//  Exact distances unless noted. WGSL has no function pointers, so
//  normal estimation is split: evaluate your map at
//  p + sdfTetraOffset(i, eps) for i = 0..3 and pass the four distances
//  to sdfNormalTetra.
// ═══════════════════════════════════════════════════════════════════

/// 2D rotation matrix; rot2(a) * v rotates v counter-clockwise by a radians.
/// @cost 1 sincos
fn rot2(a: f32) -> mat2x2<f32> {
  let c = cos(a);
  let s = sin(a);
  return mat2x2<f32>(c, s, -s, c);
}

/// Circle of radius r.
/// @cost 1 length
fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
  return length(p) - r;
}

/// Axis-aligned box with half-extents b.
/// @cost ~8 ALU
fn sdBox2(p: vec2<f32>, b: vec2<f32>) -> f32 {
  let d = abs(p) - b;
  return length(max(d, vec2<f32>(0.0))) + min(max(d.x, d.y), 0.0);
}

/// Line segment a–b (unsigned distance).
/// @cost ~10 ALU
fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-12), 0.0, 1.0);
  return length(pa - ba * h);
}

/// Sphere of radius r.
/// @cost 1 length
fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
  return length(p) - r;
}

/// Box with half-extents b.
/// @cost ~10 ALU
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
  let q = abs(p) - b;
  return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

/// Box with half-extents b and edge radius r.
/// @cost sdBox
fn sdRoundBox(p: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
  return sdBox(p, b - vec3<f32>(r)) - r;
}

/// Torus in the XZ plane; t = (major radius, minor radius).
/// @cost 2 length
fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
  let q = vec2<f32>(length(p.xz) - t.x, p.y);
  return length(q) - t.y;
}

/// Capsule from a to b with radius r.
/// @cost ~12 ALU
fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-12), 0.0, 1.0);
  return length(pa - ba * h) - r;
}

/// Plane with unit normal n at offset h.
/// @cost 1 dot
fn sdPlane(p: vec3<f32>, n: vec3<f32>, h: f32) -> f32 {
  return dot(p, n) + h;
}

/// Polynomial smooth minimum with blend radius k (k ≤ 0 → min).
/// @cost ~6 ALU
fn smin(a: f32, b: f32, k: f32) -> f32 {
  let kk = max(k, 1e-6);
  let h = max(kk - abs(a - b), 0.0) / kk;
  return min(a, b) - h * h * kk * 0.25;
}

/// Polynomial smooth maximum with blend radius k.
/// @cost smin
fn smax(a: f32, b: f32, k: f32) -> f32 {
  return -smin(-a, -b, k);
}

/// Infinite repetition: fold p into the cell centred on the origin.
/// @range each axis in [-period/2, period/2]
/// @cost 2 div
fn opRep2(p: vec2<f32>, period: vec2<f32>) -> vec2<f32> {
  return p - period * round(p / period);
}

/// Infinite repetition, 3D.
/// @cost 3 div
fn opRep3(p: vec3<f32>, period: vec3<f32>) -> vec3<f32> {
  return p - period * round(p / period);
}

/// Tetrahedral sample offset i (0..3) scaled by eps, for sdfNormalTetra.
/// @cost select chain
fn sdfTetraOffset(i: i32, eps: f32) -> vec3<f32> {
  var k = vec3<f32>(1.0, 1.0, 1.0);
  if (i == 0) {
    k = vec3<f32>(1.0, -1.0, -1.0);
  } else if (i == 1) {
    k = vec3<f32>(-1.0, -1.0, 1.0);
  } else if (i == 2) {
    k = vec3<f32>(-1.0, 1.0, -1.0);
  }
  return k * eps;
}

/// Surface normal from four distances sampled at p + sdfTetraOffset(0..3, eps).
/// @range unit vector (zero vector if all distances are equal)
/// @cost 1 normalize
fn sdfNormalTetra(d0: f32, d1: f32, d2: f32, d3: f32) -> vec3<f32> {
  let n = vec3<f32>(1.0, -1.0, -1.0) * d0 + vec3<f32>(-1.0, -1.0, 1.0) * d1
    + vec3<f32>(-1.0, 1.0, -1.0) * d2 + vec3<f32>(1.0, 1.0, 1.0) * d3;
  let l = length(n);
  return select(n / l, vec3<f32>(0.0), l < 1e-20);
}
