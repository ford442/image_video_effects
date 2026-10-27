// ═══════════════════════════════════════════════════════════════════
//  _half.wgsl — half-precision helper library (#1512, shader-f16)
//
//  Use it from a shader that opts in with a header line:
//      // @requires f16
//      #include "_prelude.wgsl"
//      #include "_half.wgsl"
//
//  As shipped every alias below is f32, so this is plain f32 WGSL that
//  compiles everywhere and passes the naga gates. On a device with the
//  `shader-f16` feature the renderer rewrites ONLY these alias lines to
//  f16 and prepends `enable f16;` (src/renderer/wgslF16.ts). Write the
//  math against hf / hf2 / hf3 / hf4 and use unsuffixed literals (they
//  are abstract floats and fit both precisions); convert with hf(x).
//
//  Keep inputs in a small range: f16 has ~3 decimal digits and a max of
//  65504. Hashes here take integer cell coordinates (u32 hashing, then a
//  conversion), so their quality does not depend on the float width.
//
//  Careful: these names (hf*, *_h) must not clash with the shader's own.
// ═══════════════════════════════════════════════════════════════════

alias hf = f32;
alias hf2 = vec2<f32>;
alias hf3 = vec3<f32>;
alias hf4 = vec4<f32>;

// ── colour ──────────────────────────────────────────────────────────

/** Rec. 709 luma of linear RGB. */
fn luma_h(c: hf3) -> hf {
    return dot(c, hf3(0.2126, 0.7152, 0.0722));
}

/** Saturation around luma: s = 0 grey, 1 unchanged, > 1 boosted. */
fn saturate_h(c: hf3, s: hf) -> hf3 {
    return mix(hf3(luma_h(c)), c, s);
}

/** sRGB transfer (piecewise) → linear, per channel. */
fn srgb_to_linear_h(c: hf3) -> hf3 {
    let lo = c / 12.92;
    let hi = pow((c + 0.055) / 1.055, hf3(2.4));
    return select(hi, lo, c <= hf3(0.04045));
}

/** Linear → sRGB transfer (piecewise), per channel. */
fn linear_to_srgb_h(c: hf3) -> hf3 {
    let x = max(c, hf3(0.0));
    let lo = x * 12.92;
    let hi = 1.055 * pow(x, hf3(1.0 / 2.4)) - 0.055;
    return select(hi, lo, x <= hf3(0.0031308));
}

/** Hue rotation in RGB (radians) about the grey axis. */
fn hue_rotate_h(c: hf3, angle: hf) -> hf3 {
    let k = hf3(0.57735);
    let cosA = cos(angle);
    return c * cosA + cross(k, c) * sin(angle) + k * dot(k, c) * (1.0 - cosA);
}

/** Reinhard tonemap on luma, keeping hue. */
fn reinhard_h(c: hf3) -> hf3 {
    let l = luma_h(c);
    return c / (1.0 + l);
}

// ── hash / noise ────────────────────────────────────────────────────

/** PCG-style 2D integer hash. */
fn pcg2_h(v: vec2<u32>) -> u32 {
    var x = v.x * 1664525u + 1013904223u + v.y * 747796405u;
    x = ((x >> ((x >> 28u) + 4u)) ^ x) * 277803737u;
    return (x >> 22u) ^ x;
}

/** Cell hash in [0, 1): integer cell in, half-precision value out. */
fn hash21_h(cell: vec2<i32>) -> hf {
    return hf(f32(pcg2_h(bitcast<vec2<u32>>(cell)) >> 8u) / 16777216.0);
}

/** Smooth value noise over integer cells; p in cells (keep |p| modest). */
fn value_noise_h(p: vec2<f32>) -> hf {
    let i = vec2<i32>(floor(p));
    let f = hf2(fract(p));
    let u = f * f * (3.0 - 2.0 * f);
    let a = hash21_h(i);
    let b = hash21_h(i + vec2<i32>(1, 0));
    let c = hash21_h(i + vec2<i32>(0, 1));
    let d = hash21_h(i + vec2<i32>(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/** Four-octave fBm of value_noise_h, in [0, 1). */
fn fbm4_h(p: vec2<f32>) -> hf {
    var sum: hf = 0.0;
    var amp: hf = 0.5;
    var q = p;
    for (var o = 0; o < 4; o = o + 1) {
        sum = sum + amp * value_noise_h(q);
        q = q * 2.03 + vec2<f32>(17.0, 31.0);
        amp = amp * 0.5;
    }
    return sum / 0.9375;
}
