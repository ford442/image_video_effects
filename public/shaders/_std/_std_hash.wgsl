// ═══════════════════════════════════════════════════════════════════
//  _std/_std_hash.wgsl — integer (PCG) hash family
//  @std-module hash
//  @std-version 1
//  @requires (none)
//
//  Naming: hashNM takes an N-component input and returns M components.
//  hash21 is vec2 → f32 (the catalog's majority meaning). Note that 256
//  catalog shaders define `hash12(vec2) -> f32`; under this convention
//  hash12 is f32 → vec2. Migration matches bodies, not names, so those
//  copies become legacy names rather than silently changing look.
//
//  Integer only: no sin()/fract() hashes, which differ across GPU
//  vendors. Float inputs are hashed by their IEEE bits (bitcast), so
//  results are identical on every conforming GPU. Consequence: 0.0 and
//  -0.0 hash differently; quantise first if that matters.
//
//  Core mixers: Jarzynski & Olano, "Hash Functions for GPU Rendering",
//  JCGT 2020 (pcg, pcg2d, pcg3d, pcg4d).
// ═══════════════════════════════════════════════════════════════════

/// PCG single-u32 hash.
/// @range full u32
/// @cost ~8 int ops
fn pcg(v: u32) -> u32 {
  let s = v * 747796405u + 2891336453u;
  let w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
  return (w >> 22u) ^ w;
}

/// PCG 2D → 2D u32 hash.
/// @range full u32 per component
/// @cost ~14 int ops
fn pcg2d(v_in: vec2<u32>) -> vec2<u32> {
  var v = v_in * 1664525u + 1013904223u;
  v.x += v.y * 1664525u;
  v.y += v.x * 1664525u;
  v = v ^ (v >> vec2<u32>(16u));
  v.x += v.y * 1664525u;
  v.y += v.x * 1664525u;
  v = v ^ (v >> vec2<u32>(16u));
  return v;
}

/// PCG 3D → 3D u32 hash.
/// @range full u32 per component
/// @cost ~20 int ops
fn pcg3d(v_in: vec3<u32>) -> vec3<u32> {
  var v = v_in * 1664525u + 1013904223u;
  v.x += v.y * v.z;
  v.y += v.z * v.x;
  v.z += v.x * v.y;
  v = v ^ (v >> vec3<u32>(16u));
  v.x += v.y * v.z;
  v.y += v.z * v.x;
  v.z += v.x * v.y;
  return v;
}

/// PCG 4D → 4D u32 hash.
/// @range full u32 per component
/// @cost ~26 int ops
fn pcg4d(v_in: vec4<u32>) -> vec4<u32> {
  var v = v_in * 1664525u + 1013904223u;
  v.x += v.y * v.w;
  v.y += v.z * v.x;
  v.z += v.x * v.y;
  v.w += v.y * v.z;
  v = v ^ (v >> vec4<u32>(16u));
  v.x += v.y * v.w;
  v.y += v.z * v.x;
  v.z += v.x * v.y;
  v.w += v.y * v.z;
  return v;
}

/// u32 → f32 in [0, 1) using the top 24 bits (exact in f32).
/// @range [0, 1)
/// @cost 2 ops
fn u32ToUnit(x: u32) -> f32 {
  return f32(x >> 8u) * (1.0 / 16777216.0);
}

/// f32 → f32 hash.
/// @range [0, 1)
/// @cost 1 pcg
fn hash11(p: f32) -> f32 {
  return u32ToUnit(pcg(bitcast<u32>(p)));
}

/// f32 → vec2 hash.
/// @range [0, 1)²
/// @cost 1 pcg2d
fn hash12(p: f32) -> vec2<f32> {
  let h = pcg2d(vec2<u32>(bitcast<u32>(p), 0x9e3779b9u));
  return vec2<f32>(u32ToUnit(h.x), u32ToUnit(h.y));
}

/// f32 → vec3 hash.
/// @range [0, 1)³
/// @cost 1 pcg3d
fn hash13(p: f32) -> vec3<f32> {
  let h = pcg3d(vec3<u32>(bitcast<u32>(p), 0x9e3779b9u, 0x85ebca6bu));
  return vec3<f32>(u32ToUnit(h.x), u32ToUnit(h.y), u32ToUnit(h.z));
}

/// vec2 → f32 hash.
/// @range [0, 1)
/// @cost 1 pcg2d
fn hash21(p: vec2<f32>) -> f32 {
  return u32ToUnit(pcg2d(bitcast<vec2<u32>>(p)).x);
}

/// vec2 → vec2 hash.
/// @range [0, 1)²
/// @cost 1 pcg2d
fn hash22(p: vec2<f32>) -> vec2<f32> {
  let h = pcg2d(bitcast<vec2<u32>>(p));
  return vec2<f32>(u32ToUnit(h.x), u32ToUnit(h.y));
}

/// vec2 → vec3 hash.
/// @range [0, 1)³
/// @cost 1 pcg3d
fn hash23(p: vec2<f32>) -> vec3<f32> {
  let b = bitcast<vec2<u32>>(p);
  let h = pcg3d(vec3<u32>(b, 0x9e3779b9u));
  return vec3<f32>(u32ToUnit(h.x), u32ToUnit(h.y), u32ToUnit(h.z));
}

/// vec3 → f32 hash.
/// @range [0, 1)
/// @cost 1 pcg3d
fn hash31(p: vec3<f32>) -> f32 {
  return u32ToUnit(pcg3d(bitcast<vec3<u32>>(p)).x);
}

/// vec3 → vec2 hash.
/// @range [0, 1)²
/// @cost 1 pcg3d
fn hash32(p: vec3<f32>) -> vec2<f32> {
  let h = pcg3d(bitcast<vec3<u32>>(p));
  return vec2<f32>(u32ToUnit(h.x), u32ToUnit(h.y));
}

/// vec3 → vec3 hash.
/// @range [0, 1)³
/// @cost 1 pcg3d
fn hash33(p: vec3<f32>) -> vec3<f32> {
  let h = pcg3d(bitcast<vec3<u32>>(p));
  return vec3<f32>(u32ToUnit(h.x), u32ToUnit(h.y), u32ToUnit(h.z));
}

/// vec4 → f32 hash.
/// @range [0, 1)
/// @cost 1 pcg4d
fn hash41(p: vec4<f32>) -> f32 {
  return u32ToUnit(pcg4d(bitcast<vec4<u32>>(p)).x);
}

/// Integer lattice cell → f32. Use for noise lattices (hash the cell, not its float bits).
/// @range [0, 1)
/// @cost 1 pcg2d
fn hashCell21(c: vec2<i32>) -> f32 {
  return u32ToUnit(pcg2d(bitcast<vec2<u32>>(c)).x);
}

/// Integer lattice cell → vec2.
/// @range [0, 1)²
/// @cost 1 pcg2d
fn hashCell22(c: vec2<i32>) -> vec2<f32> {
  let h = pcg2d(bitcast<vec2<u32>>(c));
  return vec2<f32>(u32ToUnit(h.x), u32ToUnit(h.y));
}

/// Integer lattice cell (3D) → f32.
/// @range [0, 1)
/// @cost 1 pcg3d
fn hashCell31(c: vec3<i32>) -> f32 {
  return u32ToUnit(pcg3d(bitcast<vec3<u32>>(c)).x);
}

/// Integer lattice cell (3D) → vec3.
/// @range [0, 1)³
/// @cost 1 pcg3d
fn hashCell33(c: vec3<i32>) -> vec3<f32> {
  let h = pcg3d(bitcast<vec3<u32>>(c));
  return vec3<f32>(u32ToUnit(h.x), u32ToUnit(h.y), u32ToUnit(h.z));
}
