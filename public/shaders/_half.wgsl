// ═══════════════════════════════════════════════════════════════════
//  _half.wgsl — half-precision helpers (capability tier 2, #1512)
//
//  Use it with:
//      // @requires f16
//      #include "_prelude.wgsl"
//      #include "_half.wgsl"
//
//  The math below is written in the aliases hf / hv2 / hv3 / hv4. As
//  written they are f32: valid on every device, and what naga, the WASM
//  backend and the catalog gates see. When a shader carries the
//  `// @requires f16` header and the device was granted `shader-f16`, the
//  TS renderer compiles the f16 variant instead: it prepends `enable f16;`
//  and rewrites the four alias lines to f16 types (src/renderer/wgslF16.ts).
//  Without the feature the same shader simply runs in f32.
//
//  Rules for code in this file (and for shaders using the aliases):
//   - no `h` literal suffix (1.0h does not exist in f32): write hf(1.0);
//   - hash in integers, never a sin() hash in half precision: f16 has an
//     11-bit mantissa, so fract(sin(x) * 43758.5) is only noise in f32;
//   - keep half-precision operands small (|x| < ~2000; f16 tops at 65504):
//     lattice coordinates and uv stay f32, fractions and colours go half.
//
//  Bundled into the app (src/wasm/bridge/wgslLibraries.ts) like
//  _prelude.wgsl, so a shader served from storage resolves it offline.
// ═══════════════════════════════════════════════════════════════════

alias hf = f32;
alias hv2 = vec2<f32>;
alias hv3 = vec3<f32>;
alias hv4 = vec4<f32>;

/// PCG integer hash (u32 → u32).
fn h_pcg(v: u32) -> u32 {
  let state = v * 747796405u + 2891336453u;
  let word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
  return (word >> 22u) ^ word;
}

/// Hash of an integer lattice point to [0, 1), hashed in integers, returned in half.
fn h_hash21(p: vec2<i32>) -> hf {
  let h = h_pcg(bitcast<u32>(p.x) ^ h_pcg(bitcast<u32>(p.y)));
  return hf(f32(h >> 8u) * (1.0 / 16777216.0));
}

/// Value noise in [0, 1): the lattice stays f32 / i32, the interpolation is half.
fn h_valueNoise(p: vec2<f32>) -> hf {
  let i = vec2<i32>(floor(p));
  let f = hv2(fract(p));
  let u = f * f * (hv2(3.0) - hf(2.0) * f);
  let a = h_hash21(i);
  let b = h_hash21(i + vec2<i32>(1, 0));
  let c = h_hash21(i + vec2<i32>(0, 1));
  let d = h_hash21(i + vec2<i32>(1, 1));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/// Fractal value noise in [0, 1); at most 8 octaves.
fn h_fbm(p: vec2<f32>, octaves: i32) -> hf {
  var sum = hf(0.0);
  var amp = hf(0.5);
  var norm = hf(0.0);
  var q = p;
  for (var o = 0; o < min(octaves, 8); o = o + 1) {
    sum = sum + amp * h_valueNoise(q);
    norm = norm + amp;
    amp = amp * hf(0.5);
    q = q * 2.03 + vec2<f32>(17.0, 31.0);
  }
  return sum / max(norm, hf(0.001));
}

/// Rec. 709 luma.
fn h_luma(c: hv3) -> hf {
  return dot(c, hv3(0.2126, 0.7152, 0.0722));
}

/// HSV (all 0..1) to RGB, branchless.
fn h_hsv2rgb(c: hv3) -> hv3 {
  let k = hv3(1.0, 2.0 / 3.0, 1.0 / 3.0);
  let p = abs(fract(hv3(c.x) + k) * hf(6.0) - hv3(3.0));
  return c.z * mix(hv3(1.0), clamp(p - hv3(1.0), hv3(0.0), hv3(1.0)), c.y);
}

/// sRGB transfer function to linear (exact piecewise form).
fn h_srgbToLinear(c: hv3) -> hv3 {
  let lo = c / hf(12.92);
  let hi = pow((c + hv3(0.055)) / hf(1.055), hv3(2.4));
  return select(hi, lo, c <= hv3(0.04045));
}

/// Linear to the sRGB transfer function (exact piecewise form).
fn h_linearToSrgb(c: hv3) -> hv3 {
  let lo = c * hf(12.92);
  let hi = hf(1.055) * pow(max(c, hv3(0.0)), hv3(1.0 / 2.4)) - hv3(0.055);
  return select(hi, lo, c <= hv3(0.0031308));
}
