// ═══════════════════════════════════════════════════════════════════
//  _std/_std_color.wgsl — transfer functions, HSV/HSL, OKLab/OKLCH,
//                         blackbody, cosine palettes, luminance
//  @std-module color
//  @std-version 1
//  @requires math
//
//  "linear" means linear-light Rec.709/sRGB primaries. Hue is in turns
//  ([0, 1)) for HSV/HSL and radians for OKLCH.
// ═══════════════════════════════════════════════════════════════════

/// Rec.709 relative luminance of linear RGB.
/// @range ≥ 0 for non-negative input
/// @cost 1 dot
fn luminance(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

/// sRGB-encoded → linear (exact piecewise curve). Negative input clamps to 0.
/// @range [0, ∞)
/// @cost 3 pow
fn srgbToLinear(c: vec3<f32>) -> vec3<f32> {
  let x = max(c, vec3<f32>(0.0));
  return select(pow((x + 0.055) / 1.055, vec3<f32>(2.4)), x / 12.92, x <= vec3<f32>(0.04045));
}

/// Linear → sRGB-encoded (exact piecewise curve). Negative input clamps to 0.
/// @range [0, ∞)
/// @cost 3 pow
fn linearToSrgb(c: vec3<f32>) -> vec3<f32> {
  let x = max(c, vec3<f32>(0.0));
  return select(1.055 * pow(x, vec3<f32>(1.0 / 2.4)) - 0.055, x * 12.92, x <= vec3<f32>(0.0031308));
}

/// RGB → HSV (branchless, Hocevar). h in turns.
/// @range h, s, v in [0, 1] for RGB in [0, 1]
/// @cost ~20 ALU
fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
  let K = vec4<f32>(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
  let p = mix(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), step(c.b, c.g));
  let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));
  let d = q.x - min(q.w, q.y);
  let e = 1e-10;
  return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

/// HSV → RGB. h in turns (wraps).
/// @range [0, v]
/// @cost ~12 ALU
fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let p = abs(fract(vec3<f32>(c.x) + vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
  return c.z * mix(vec3<f32>(1.0), clamp(p - 1.0, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

/// HSL → RGB. h in turns (wraps).
/// @range [0, 1] for s, l in [0, 1]
/// @cost ~12 ALU
fn hsl2rgb(c: vec3<f32>) -> vec3<f32> {
  let k = clamp(abs(fract(vec3<f32>(c.x) + vec3<f32>(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0,
    vec3<f32>(0.0), vec3<f32>(1.0));
  return c.z + c.y * (k - 0.5) * (1.0 - abs(2.0 * c.z - 1.0));
}

/// RGB → HSL. h in turns.
/// @range [0, 1] for RGB in [0, 1]
/// @cost rgb2hsv + ~6 ALU
fn rgb2hsl(c: vec3<f32>) -> vec3<f32> {
  let hsv = rgb2hsv(c);
  let l = hsv.z * (1.0 - hsv.y * 0.5);
  let m = min(l, 1.0 - l);
  let s = select((hsv.z - l) / m, 0.0, m < 1e-6);
  return vec3<f32>(hsv.x, s, l);
}

/// Linear sRGB → OKLab (Ottosson 2020). L ≈ [0, 1].
/// @range L [0, 1], a/b ≈ [-0.4, 0.4] for in-gamut input
/// @cost 3 cbrt, 18 mul
fn linearToOklab(c: vec3<f32>) -> vec3<f32> {
  let l = cbrt(0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b);
  let m = cbrt(0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b);
  let s = cbrt(0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b);
  return vec3<f32>(
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s);
}

/// OKLab → linear sRGB. Out-of-gamut results are not clipped.
/// @range unclipped
/// @cost 18 mul, 3 cube
fn oklabToLinear(lab: vec3<f32>) -> vec3<f32> {
  let l_ = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z;
  let m_ = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z;
  let s_ = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z;
  let l = l_ * l_ * l_;
  let m = m_ * m_ * m_;
  let s = s_ * s_ * s_;
  return vec3<f32>(
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
}

/// OKLab → OKLCH (L, chroma, hue radians).
/// @range h in (-π, π]
/// @cost 1 sqrt, 1 atan2
fn oklabToOklch(lab: vec3<f32>) -> vec3<f32> {
  return vec3<f32>(lab.x, length(lab.yz), atan2(lab.z, lab.y));
}

/// OKLCH → OKLab.
/// @cost 1 sincos
fn oklchToOklab(lch: vec3<f32>) -> vec3<f32> {
  return vec3<f32>(lch.x, lch.y * cos(lch.z), lch.y * sin(lch.z));
}

/// Blackbody colour for a temperature in kelvin (Helland fit), linear RGB, max channel 1.
/// @range [0, 1], kelvin clamped to [1000, 40000]
/// @cost 2 pow, 2 log, srgbToLinear
fn blackbody(kelvin: f32) -> vec3<f32> {
  let k = clamp(kelvin, 1000.0, 40000.0) / 100.0;
  let hi = max(k - 60.0, 1e-3);
  let r = select(1.29293618606 * pow(hi, -0.1332047592), 1.0, k <= 66.0);
  let g = select(1.12989086089 * pow(hi, -0.0755148492), 0.39008157876 * log(k) - 0.63184144378, k <= 66.0);
  let b = select(select(0.54320678911 * log(max(k - 10.0, 1e-3)) - 1.19625408914, 0.0, k <= 19.0), 1.0, k >= 66.0);
  return srgbToLinear(clamp(vec3<f32>(r, g, b), vec3<f32>(0.0), vec3<f32>(1.0)));
}

/// Cosine palette a + b·cos(2π(c·t + d)) (Quilez).
/// @range a ± b
/// @cost 3 cos
fn cosinePalette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(TAU * (c * t + d));
}
