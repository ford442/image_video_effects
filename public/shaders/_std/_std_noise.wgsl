// ═══════════════════════════════════════════════════════════════════
//  _std/_std_noise.wgsl — value, gradient, simplex, worley, fbm family
//  @std-module noise
//  @std-version 1
//  @requires math, hash
//
//  Lattice noises hash the integer cell (hashCell*), so they are
//  identical across vendors. All fbm-style sums are normalised by their
//  total amplitude, so the documented range holds for any octave count
//  and gain. Octaves are clamped to [1, 12].
// ═══════════════════════════════════════════════════════════════════

/// Per-octave rotation for 2D fbm (decorrelates lattice axes; |det| = 1).
const STD_FBM_ROT2: mat2x2<f32> = mat2x2<f32>(0.8, 0.6, -0.6, 0.8);

/// Quintic fade 6t⁵ − 15t⁴ + 10t³ (C2-continuous).
/// @range [0, 1] for t in [0, 1]
/// @cost 5 mul
fn fade2(t: vec2<f32>) -> vec2<f32> {
  return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

/// Quintic fade, vec3.
/// @range [0, 1]
/// @cost 5 mul
fn fade3(t: vec3<f32>) -> vec3<f32> {
  return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

/// 2D value noise.
/// @range [0, 1]
/// @cost 4 hashCell21
fn valueNoise(p: vec2<f32>) -> f32 {
  let i = vec2<i32>(floor(p));
  let u = fade2(fract(p));
  let a = hashCell21(i);
  let b = hashCell21(i + vec2<i32>(1, 0));
  let c = hashCell21(i + vec2<i32>(0, 1));
  let d = hashCell21(i + vec2<i32>(1, 1));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/// 3D value noise.
/// @range [0, 1]
/// @cost 8 hashCell31
fn valueNoise3(p: vec3<f32>) -> f32 {
  let i = vec3<i32>(floor(p));
  let u = fade3(fract(p));
  let x00 = mix(hashCell31(i), hashCell31(i + vec3<i32>(1, 0, 0)), u.x);
  let x10 = mix(hashCell31(i + vec3<i32>(0, 1, 0)), hashCell31(i + vec3<i32>(1, 1, 0)), u.x);
  let x01 = mix(hashCell31(i + vec3<i32>(0, 0, 1)), hashCell31(i + vec3<i32>(1, 0, 1)), u.x);
  let x11 = mix(hashCell31(i + vec3<i32>(0, 1, 1)), hashCell31(i + vec3<i32>(1, 1, 1)), u.x);
  return mix(mix(x00, x10, u.y), mix(x01, x11, u.y), u.z);
}

/// Unit gradient for a 2D lattice cell.
/// @range unit vector
/// @cost 1 hashCell21, 1 sincos
fn gradDir2(c: vec2<i32>) -> vec2<f32> {
  let a = hashCell21(c) * TAU;
  return vec2<f32>(cos(a), sin(a));
}

/// Unit gradient for a 3D lattice cell (uniform on the sphere).
/// @range unit vector
/// @cost 1 hashCell33, 1 sincos, 1 sqrt
fn gradDir3(c: vec3<i32>) -> vec3<f32> {
  let h = hashCell33(c);
  let z = h.x * 2.0 - 1.0;
  let a = h.y * TAU;
  let r = sqrt(max(1.0 - z * z, 0.0));
  return vec3<f32>(r * cos(a), r * sin(a), z);
}

/// 2D gradient (Perlin) noise, scaled by √2 so the theoretical range is [-1, 1].
/// @range [-1, 1]
/// @cost 4 gradDir2
fn gradientNoise(p: vec2<f32>) -> f32 {
  let i = vec2<i32>(floor(p));
  let f = fract(p);
  let u = fade2(f);
  let a = dot(gradDir2(i), f);
  let b = dot(gradDir2(i + vec2<i32>(1, 0)), f - vec2<f32>(1.0, 0.0));
  let c = dot(gradDir2(i + vec2<i32>(0, 1)), f - vec2<f32>(0.0, 1.0));
  let d = dot(gradDir2(i + vec2<i32>(1, 1)), f - vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 1.41421356;
}

/// 3D gradient (Perlin) noise, scaled by 2/√3 so the theoretical range is [-1, 1].
/// @range [-1, 1]
/// @cost 8 gradDir3
fn gradientNoise3(p: vec3<f32>) -> f32 {
  let i = vec3<i32>(floor(p));
  let f = fract(p);
  let u = fade3(f);
  let n000 = dot(gradDir3(i), f);
  let n100 = dot(gradDir3(i + vec3<i32>(1, 0, 0)), f - vec3<f32>(1.0, 0.0, 0.0));
  let n010 = dot(gradDir3(i + vec3<i32>(0, 1, 0)), f - vec3<f32>(0.0, 1.0, 0.0));
  let n110 = dot(gradDir3(i + vec3<i32>(1, 1, 0)), f - vec3<f32>(1.0, 1.0, 0.0));
  let n001 = dot(gradDir3(i + vec3<i32>(0, 0, 1)), f - vec3<f32>(0.0, 0.0, 1.0));
  let n101 = dot(gradDir3(i + vec3<i32>(1, 0, 1)), f - vec3<f32>(1.0, 0.0, 1.0));
  let n011 = dot(gradDir3(i + vec3<i32>(0, 1, 1)), f - vec3<f32>(0.0, 1.0, 1.0));
  let n111 = dot(gradDir3(i + vec3<i32>(1, 1, 1)), f - vec3<f32>(1.0, 1.0, 1.0));
  let x0 = mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y);
  let x1 = mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y);
  return mix(x0, x1, u.z) * 1.15470054;
}

/// 2D simplex noise (3 corners; cheaper than gradientNoise at similar quality).
/// @range approximately [-1, 1]
/// @cost 3 gradDir2
fn simplex2(p: vec2<f32>) -> f32 {
  let K1 = 0.366025404; // (√3 − 1) / 2
  let K2 = 0.211324865; // (3 − √3) / 6
  let i = floor(p + (p.x + p.y) * K1);
  let a = p - i + (i.x + i.y) * K2;
  let o = select(vec2<f32>(0.0, 1.0), vec2<f32>(1.0, 0.0), a.x > a.y);
  let b = a - o + K2;
  let c = a - 1.0 + 2.0 * K2;
  let h = max(vec3<f32>(0.5) - vec3<f32>(dot(a, a), dot(b, b), dot(c, c)), vec3<f32>(0.0));
  let ic = vec2<i32>(i);
  let n = h * h * h * h * vec3<f32>(
    dot(a, gradDir2(ic)),
    dot(b, gradDir2(ic + vec2<i32>(o))),
    dot(c, gradDir2(ic + vec2<i32>(1, 1))));
  return dot(n, vec3<f32>(70.0));
}

/// 2D Worley (cellular) noise: (F1, F2) distances to the nearest two feature points.
/// @range F1 in [0, ~1.5], F2 ≥ F1
/// @cost 9 hashCell22
fn worley(p: vec2<f32>) -> vec2<f32> {
  let i = vec2<i32>(floor(p));
  let f = fract(p);
  var f1 = 8.0;
  var f2 = 8.0;
  for (var y = -1; y <= 1; y++) {
    for (var x = -1; x <= 1; x++) {
      let o = vec2<i32>(x, y);
      let r = vec2<f32>(o) + hashCell22(i + o) - f;
      let d = dot(r, r);
      if (d < f1) {
        f2 = f1;
        f1 = d;
      } else if (d < f2) {
        f2 = d;
      }
    }
  }
  return sqrt(vec2<f32>(f1, f2));
}

/// Fractal Brownian motion over 2D value noise.
/// Typical: fbm(p, 5, 2.0, 0.5).
/// @range [0, 1]
/// @cost octaves × valueNoise
fn fbm(p: vec2<f32>, octaves: i32, lacunarity: f32, gain: f32) -> f32 {
  var q = p;
  var amp = 1.0;
  var sum = 0.0;
  var norm = 0.0;
  let n = clamp(octaves, 1, 12);
  for (var i = 0; i < n; i++) {
    sum += amp * valueNoise(q);
    norm += amp;
    q = STD_FBM_ROT2 * q * lacunarity + vec2<f32>(17.13, 3.71);
    amp *= gain;
  }
  return sum / max(norm, 1e-6);
}

/// Fractal Brownian motion over 3D value noise.
/// @range [0, 1]
/// @cost octaves × valueNoise3
fn fbm3(p: vec3<f32>, octaves: i32, lacunarity: f32, gain: f32) -> f32 {
  var q = p;
  var amp = 1.0;
  var sum = 0.0;
  var norm = 0.0;
  let n = clamp(octaves, 1, 12);
  for (var i = 0; i < n; i++) {
    sum += amp * valueNoise3(q);
    norm += amp;
    q = q * lacunarity + vec3<f32>(17.13, 3.71, 9.27);
    amp *= gain;
  }
  return sum / max(norm, 1e-6);
}

/// Ridged multifractal: sharp creases where gradient noise crosses zero.
/// @range [0, 1]
/// @cost octaves × gradientNoise
fn ridged(p: vec2<f32>, octaves: i32, lacunarity: f32, gain: f32) -> f32 {
  var q = p;
  var amp = 1.0;
  var sum = 0.0;
  var norm = 0.0;
  let n = clamp(octaves, 1, 12);
  for (var i = 0; i < n; i++) {
    let s = 1.0 - min(abs(gradientNoise(q)), 1.0);
    sum += amp * s * s;
    norm += amp;
    q = STD_FBM_ROT2 * q * lacunarity + vec2<f32>(17.13, 3.71);
    amp *= gain;
  }
  return sum / max(norm, 1e-6);
}

/// Turbulence: fbm of |gradient noise| (billowy).
/// @range [0, 1]
/// @cost octaves × gradientNoise
fn turbulence(p: vec2<f32>, octaves: i32, lacunarity: f32, gain: f32) -> f32 {
  var q = p;
  var amp = 1.0;
  var sum = 0.0;
  var norm = 0.0;
  let n = clamp(octaves, 1, 12);
  for (var i = 0; i < n; i++) {
    sum += amp * min(abs(gradientNoise(q)), 1.0);
    norm += amp;
    q = STD_FBM_ROT2 * q * lacunarity + vec2<f32>(17.13, 3.71);
    amp *= gain;
  }
  return sum / max(norm, 1e-6);
}

/// One-level domain warp: p displaced by two decorrelated fbm fields.
/// @range p ± strength per axis
/// @cost 2 × fbm(octaves)
fn domainWarp(p: vec2<f32>, strength: f32, octaves: i32) -> vec2<f32> {
  let q = vec2<f32>(
    fbm(p, octaves, 2.0, 0.5),
    fbm(p + vec2<f32>(5.2, 1.3), octaves, 2.0, 0.5));
  return p + strength * (q * 2.0 - 1.0);
}
