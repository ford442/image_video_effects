// ═══════════════════════════════════════════════════════════════════
//  _std/_std_math.wgsl — constants, safe math, remaps, complex, polar
//  @std-module math
//  @std-version 1
//  @requires (none)
//
//  Shader standard library (docs/SHADER_STDLIB.md). Pure functions, no
//  bindings. `saturate` is a WGSL builtin and is deliberately not defined.
// ═══════════════════════════════════════════════════════════════════

/// π.
const PI: f32 = 3.14159265358979;
/// 2π.
const TAU: f32 = 6.28318530717959;
/// π / 2.
const HALF_PI: f32 = 1.57079632679490;
/// 1 / π.
const INV_PI: f32 = 0.31830988618379;
/// Golden ratio φ.
const PHI: f32 = 1.61803398874989;

/// pow that never NaNs: sign(x)·|x|^e. pow(negative, e) is undefined in WGSL.
/// @range sign-preserving, finite for finite input
/// @cost 1 pow
fn safePow(x: f32, e: f32) -> f32 {
  return sign(x) * pow(abs(x), e);
}

/// Component-wise safePow on vec3.
/// @range sign-preserving
/// @cost 3 pow
fn safePow3(x: vec3<f32>, e: f32) -> vec3<f32> {
  return sign(x) * pow(abs(x), vec3<f32>(e));
}

/// Real cube root, defined for negative input.
/// @range (-∞, ∞)
/// @cost 1 pow
fn cbrt(x: f32) -> f32 {
  return sign(x) * pow(abs(x), 1.0 / 3.0);
}

/// Linear remap of x from [inLo, inHi] to [outLo, outHi]; unclamped.
/// inLo == inHi is guarded (returns outLo).
/// @range unbounded
/// @cost 1 div
fn remap(x: f32, inLo: f32, inHi: f32, outLo: f32, outHi: f32) -> f32 {
  let d = inHi - inLo;
  let t = select((x - inLo) / d, 0.0, abs(d) < 1e-20);
  return outLo + (outHi - outLo) * t;
}

/// remap with t clamped to [0, 1].
/// @range [min(outLo,outHi), max(outLo,outHi)]
/// @cost 1 div
fn remapClamped(x: f32, inLo: f32, inHi: f32, outLo: f32, outHi: f32) -> f32 {
  let d = inHi - inLo;
  let t = saturate(select((x - inLo) / d, 0.0, abs(d) < 1e-20));
  return outLo + (outHi - outLo) * t;
}

/// Division that returns `fallback` when |b| is ~0.
/// @range unbounded
/// @cost 1 div
fn safeDiv(a: f32, b: f32, fallback: f32) -> f32 {
  return select(a / b, fallback, abs(b) < 1e-20);
}

/// Complex multiply, (a.x + i a.y)(b.x + i b.y).
/// @cost 4 mul
fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

/// Complex divide a / b; b == 0 returns 0.
/// @cost 1 div
fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  let d = dot(b, b);
  return select(vec2<f32>(a.x * b.x + a.y * b.y, a.y * b.x - a.x * b.y) / d, vec2<f32>(0.0), d < 1e-30);
}

/// Complex exponential e^z.
/// @cost 1 exp, 1 sincos
fn cexp(z: vec2<f32>) -> vec2<f32> {
  return exp(z.x) * vec2<f32>(cos(z.y), sin(z.y));
}

/// Cartesian → polar (r, θ), θ in (-π, π].
/// @cost 1 sqrt, 1 atan2
fn toPolar(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(length(p), atan2(p.y, p.x));
}

/// Polar (r, θ) → cartesian.
/// @cost 1 sincos
fn fromPolar(rt: vec2<f32>) -> vec2<f32> {
  return rt.x * vec2<f32>(cos(rt.y), sin(rt.y));
}
