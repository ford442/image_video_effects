// ═══════════════════════════════════════════════════════════════════
//  Torus Knot Rainbow — Algorithmist Upgrade
//  Category: generative
//  Features: audio-reactive, temporal-feedback, analytic-sdf-tube,
//            smooth-union-capsules, multi-orbit-julia-trap,
//            fbm-domain-warp, psychedelic-halo, depth-output, aces-tone-map
//  Complexity: High
//  Created: 2026-05-23
//  Upgraded: 2026-06-29
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const SEGMENTS: i32 = 128;
const JULIA_ITERS: i32 = 32;

// ── Hash & noise ──────────────────────────────────────────────────
fn hashf(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453);
}

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        sum += amp * valueNoise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return sum;
}

fn domainWarp(p: vec2<f32>, strength: f32, octaves: i32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p, octaves), fbm(p + vec2<f32>(5.2, 1.3), octaves));
    return p + strength * q;
}

// ── Color utilities ───────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let c = hsv.z * hsv.y;
    let h = hsv.x * 6.0;
    let x = c * (1.0 - abs(fract(h / 2.0) * 2.0 - 1.0));
    let m = hsv.z - c;
    var rgb: vec3<f32>;
    if (h < 1.0)       { rgb = vec3<f32>(c, x, 0.0); }
    else if (h < 2.0)  { rgb = vec3<f32>(x, c, 0.0); }
    else if (h < 3.0)  { rgb = vec3<f32>(0.0, c, x); }
    else if (h < 4.0)  { rgb = vec3<f32>(0.0, x, c); }
    else if (h < 5.0)  { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(m);
}

fn psychedelicPalette(t: f32) -> vec3<f32> {
    let hue = fract(t);
    let saturation = clamp(0.72 + 0.28 * sin(TAU * (t * 0.137 + 0.19)), 0.45, 1.0);
    let value = 1.0 + 0.18 * sin(TAU * (t * 0.071 + 0.43));
    let rgb = clamp(abs(fract(vec3<f32>(hue) + vec3<f32>(0.0, 0.6666667, 0.3333333)) * 6.0 - vec3<f32>(3.0)) - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));
    let smoothRgb = rgb * rgb * (vec3<f32>(3.0) - 2.0 * rgb);
    return mix(vec3<f32>(value), smoothRgb * value, saturation);
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// ── Geometry helpers ──────────────────────────────────────────────
fn rot2(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn rotX(v: vec3<f32>, a: f32) -> vec3<f32> {
    let c = cos(a);
    let s = sin(a);
    return vec3<f32>(v.x, c * v.y - s * v.z, s * v.y + c * v.z);
}

fn rotY(v: vec3<f32>, a: f32) -> vec3<f32> {
    let c = cos(a);
    let s = sin(a);
    return vec3<f32>(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

fn torusKnotPoint(t: f32, pWind: f32, qWind: f32, R: f32, r: f32) -> vec3<f32> {
    let phi = t * pWind;
    let theta = t * qWind;
    let x = (R + r * cos(theta)) * cos(phi);
    let y = (R + r * cos(theta)) * sin(phi);
    let z = r * sin(theta);
    return vec3<f32>(x, y, z);
}

fn project(pt: vec3<f32>, camDist: f32) -> vec2<f32> {
    let w = 1.0 / (camDist - pt.z);
    return pt.xy * w;
}

// ── Fractal: multi-orbit Julia trap ───────────────────────────────
fn juliaOrbitTrap(z0: vec2<f32>, c: vec2<f32>) -> f32 {
    var z = z0;
    var acc = 0.0;
    for (var i: i32 = 0; i < JULIA_ITERS; i = i + 1) {
        let x = z.x * z.x - z.y * z.y + c.x;
        let y = 2.0 * z.x * z.y + c.y;
        z = vec2<f32>(x, y);

        let d1 = length(z - vec2<f32>(0.3, 0.0));
        let d2 = length(z - vec2<f32>(-0.5, 0.2));
        let d3 = length(z - vec2<f32>(0.0, 0.55));
        let minTrap = min(min(d1, d2), d3);

        acc += exp(-minTrap * 5.0);
        if (dot(z, z) > 16.0) { break; }
    }
    return acc / f32(JULIA_ITERS);
}

// ═══════════════════════════════════════════════════════════════════
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = u.config.zw;
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let p1 = u.zoom_params.x;
    let p2 = u.zoom_params.y;
    let p3 = u.zoom_params.z;
    let p4 = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depthIn = textureLoad(readDepthTexture, pixel, 0).r;
    let prev = textureLoad(dataTextureC, pixel, 0);

    // ── Parameter mapping ──────────────────────────────────────────
    let spinSpeed = mix(0.05, 1.8, p1);
    let pWind = floor(mix(2.0, 7.0, p2));
    let qWind = floor(mix(3.0, 8.0, p3));
    let baseRad = mix(0.045, 0.012, p4);
    let smoothK = mix(0.12, 0.035, p4);

    // ── Screen-space setup ─────────────────────────────────────────
    let aspect = res.x / max(res.y, 1.0);
    var p2d = uv * vec2<f32>(aspect, 1.0) * 2.8;

    let rot = time * spinSpeed * 0.25 + mouse.x * TAU;
    p2d = rot2(rot) * p2d;

    // Audio-driven wind modulation preserves the original soul
    let qAudio = qWind + bass * 1.2;
    let R = 0.72;
    let r = 0.30;
    let cam = 4.0 + (0.5 - mouse.y) * 2.0;
    let tumble = time * spinSpeed * 0.08;

    // Organic domain warp for tube modulation and background
    let warp = domainWarp(uv * 3.0 + vec2<f32>(time * 0.07, -time * 0.05), 0.35, 3);

    // ── Analytic torus-knot SDF (smooth union of capsules) ─────────
    var dMin = 1e5;
    var halo = 0.0;
    var bestT = 0.0;
    var bestD = 1e5;
    let invN = 1.0 / f32(SEGMENTS);

    for (var i: i32 = 0; i < SEGMENTS; i = i + 1) {
        let t0 = f32(i) * invN * TAU;
        let t1 = f32(i + 1) * invN * TAU;

        let a = torusKnotPoint(t0, pWind, qAudio, R, r);
        let b = torusKnotPoint(t1, pWind, qAudio, R, r);

        // Gentle 3D tumble for parallax
        let pa = project(rotY(rotX(a, tumble * 0.7), tumble), cam);
        let pb = project(rotY(rotX(b, tumble * 0.7), tumble), cam);

        let dseg = sdSegment(p2d, pa, pb);

        // Harmonic tube-radius modulation
        let rad = baseRad * (1.0 + 0.22 * sin(t0 * 5.0 - time * 0.4) + 0.12 * bass);

        // Smooth-min union creates a continuous analytic tube
        dMin = smin(dMin, dseg - rad, smoothK);

        // Layered halo for glow and depth
        halo += exp(-dseg * (12.0 + treble * 8.0)) * (1.0 + mids * 0.5);

        // Branchless closest-segment tracking for color mapping
        let closer = dseg < bestD;
        bestD = select(bestD, dseg, closer);
        bestT = select(bestT, f32(i) * invN, closer);
    }

    // ── Fractal orbit trap in the halo field ───────────────────────
    let jCoord = p2d * (2.0 + bass) + warp * 0.5;
    let jc = vec2<f32>(cos(time * 0.13) * 0.55, sin(time * 0.17) * 0.38) + (mouse - 0.5) * 0.4;
    let jTrap = juliaOrbitTrap(jCoord, jc);

    // ── Knot color (rainbow along arc + fractal iridescence) ───────
    let hue = fract(bestT + time * spinSpeed * 0.08 + treble * 0.12 + jTrap * 0.15);
    let sat = clamp(0.78 + mids * 0.2 + jTrap * 0.25, 0.0, 1.0);
    var knotCol = hsv2rgb(vec3<f32>(hue, sat, 1.0));

    let haloCol = psychedelicPalette(bestT * 3.0 + time * 0.06 + jTrap);
    let field = exp(-max(dMin, 0.0) * (8.0 + treble * 6.0));
    knotCol = mix(knotCol, haloCol, clamp(jTrap * 2.0 + field * 0.3, 0.0, 0.55));

    // ── Domain-warped background ───────────────────────────────────
    let bgP = domainWarp(uv * 2.5 + vec2<f32>(time * 0.04, time * 0.03), 0.5, 4);
    let bgNoise = fbm(bgP + warp * 0.3, 4);
    let bgCol = psychedelicPalette(bgNoise + time * 0.03 + bass * 0.1);
    let bgMask = smoothstep(0.25, 0.8, field);

    var col = mix(bgCol * 0.25, knotCol, field);
    col = col + bgCol * 0.05 * (1.0 - bgMask);
    col = col + haloCol * halo * 0.03;

    // ── Temporal feedback ──────────────────────────────────────────
    let decay = 0.96 - p4 * 0.025;
    let trailW = 0.25 + bass * 0.12;
    col = mix(prev.rgb * decay, col, trailW);

    // ── Chromatic shift (generative, no readTexture dependency) ─────
    let angle = atan2(uv01.y - 0.5, uv01.x - 0.5);
    let caStr = 0.025 * (1.0 + bass) + depthIn * 0.01;
    col = vec3<f32>(
        col.r * (1.0 + cos(angle) * caStr),
        col.g,
        col.b * (1.0 - sin(angle) * caStr * 0.5)
    );

    // ── Tone map + semantic alpha ──────────────────────────────────
    col = acesToneMap(col * (0.95 + mids * 0.15));
    let alpha = clamp(luma(col) * 1.4 + field * 0.4 + bass * 0.05, 0.15, 0.95);

    // ── Depth output ───────────────────────────────────────────────
    let depth = clamp(field * 0.85 + halo * 0.04 + depthIn * 0.1, 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));
}
