// ─────────────────────────────────────────────────────────────────────────────
//  Recursion Mirror Vortex
//  Category: EFFECT
//  Complexity: HIGH
//  Visual concept: Nested fractal-like mirrors fold the image into itself at
//    precise "singularity" points, creating infinite-hallway illusions that
//    remain spatially coherent and visually non-noisy.
//  Mathematical approach: Iterated Möbius-like fold maps applied k times to UV
//    coordinates; each iteration scales/reflects around a dynamic center;
//    depth used to modulate fold intensity; mouse steers singularity origin.
// ─────────────────────────────────────────────────────────────────────────────
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
    config:      vec4<f32>, // x=Time, y=ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>, // x=unused, y=MouseX, z=MouseY, w=unused
    zoom_params: vec4<f32>, // x=FoldDepth(1-6), y=FoldRadius, z=VortexSpeed, w=MirrorBlend
    ripples: array<vec4<f32>, 50>,
};

// ─────────────────────────────────────────────────────────────────────────────
//  Complex multiply: treat vec2 as complex number
// ─────────────────────────────────────────────────────────────────────────────
fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Complex division
// ─────────────────────────────────────────────────────────────────────────────
fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let denom = dot(b, b);
    return vec2<f32>(dot(a, b), a.y * b.x - a.x * b.y) / max(denom, 1e-9);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Möbius-inspired fold: z → (z - c) / (|z - c|² · r + 1) + c
//  Creates smooth inward mirror toward center c with radius r
// ─────────────────────────────────────────────────────────────────────────────
fn mobiusFold(z: vec2<f32>, c: vec2<f32>, r: f32) -> vec2<f32> {
    let d   = z - c;
    let d2  = dot(d, d);
    let inv = d / max(d2 * r + 0.001, 0.001);
    return c + mix(d, inv, 0.9);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Rotate 2-D vector
// ─────────────────────────────────────────────────────────────────────────────
fn rot2(v: vec2<f32>, a: f32) -> vec2<f32> {
    let s = sin(a); let c = cos(a);
    return vec2<f32>(c * v.x - s * v.y, s * v.x + c * v.y);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Vortex twist: spirally map UV around center
// ─────────────────────────────────────────────────────────────────────────────
fn vortexTwist(uv: vec2<f32>, center: vec2<f32>, strength: f32) -> vec2<f32> {
    let d   = uv - center;
    let len = length(d);
    let ang = strength / (len * 8.0 + 1.0);
    return center + rot2(d, ang);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Ripple accumulation
// ─────────────────────────────────────────────────────────────────────────────
fn rippleDisp(uv: vec2<f32>, t: f32, cnt: u32) -> vec2<f32> {
    var d = vec2<f32>(0.0);
    for (var i: u32 = 0u; i < cnt; i++) {
        let r   = u.ripples[i];
        let age = t - r.z;
        if (age < 0.0 || age > 3.5) { continue; }
        let dist = distance(uv, r.xy);
        let wave = sin(dist * 35.0 - age * 7.0) * exp(-dist * 6.0) * exp(-age * 1.5);
        if (dist > 0.001) {
            d += normalize(uv - r.xy) * wave * (1.0 - age / 3.5) * 0.01;
        }
    }
    return d;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Box fold: reflect z into [-1,1] box — Mandelbox-style
// ─────────────────────────────────────────────────────────────────────────────
fn boxFold(z: vec2<f32>, limit: f32) -> vec2<f32> {
    return clamp(z, vec2<f32>(-limit), vec2<f32>(limit)) * 2.0 - z;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Sphere fold: if |z| < r, scale z by (R/r)²; if |z| < R, scale by 1/|z|²
// ─────────────────────────────────────────────────────────────────────────────
fn sphereFold(z: vec2<f32>, minR: f32, fixedR: f32) -> vec2<f32> {
    let r2 = dot(z, z);
    if (r2 < minR * minR) {
        let s = fixedR * fixedR / (minR * minR);
        return z * s;
    } else if (r2 < fixedR * fixedR) {
        return z * (fixedR * fixedR / r2);
    }
    return z;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Chromatic vignette: center-weighted color darkening
// ─────────────────────────────────────────────────────────────────────────────
fn chromaticVignette(uv: vec2<f32>, center: vec2<f32>, power: f32) -> vec3<f32> {
    let d = length(uv - center);
    let v = pow(max(1.0 - d * 1.5, 0.0), power);
    return vec3<f32>(v * 0.95, v * 0.97, v);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Luminance
// ─────────────────────────────────────────────────────────────────────────────
fn luma_rmv(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Smooth hash noise
// ─────────────────────────────────────────────────────────────────────────────
fn h2_rmv(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(127.1, 311.7));
    q += dot(q, q + 19.19);
    return fract(q.x * q.y);
}
fn vnoise_rmv(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p); let u = f*f*(3.0-2.0*f);
    return mix(mix(h2_rmv(i),h2_rmv(i+vec2<f32>(1,0)),u.x),mix(h2_rmv(i+vec2<f32>(0,1)),h2_rmv(i+vec2<f32>(1,1)),u.x),u.y);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Reflection glow at mirror seams
// ─────────────────────────────────────────────────────────────────────────────
fn seamGlow(origUV: vec2<f32>, foldedUV: vec2<f32>, t: f32) -> vec3<f32> {
    let diff = length(origUV - foldedUV);
    let glow = exp(-diff * 12.0) * 0.4;
    let hue  = fract(diff * 3.0 + t * 0.1);
    let c    = 6.0 * hue;
    let x    = 1.0 - abs(fract(c * 0.5) * 2.0 - 1.0);
    var rgb  = vec3<f32>(0.0);
    if      (c < 1.0) { rgb = vec3<f32>(1.0, x, 0.0); }
    else if (c < 2.0) { rgb = vec3<f32>(x, 1.0, 0.0); }
    else if (c < 3.0) { rgb = vec3<f32>(0.0, 1.0, x); }
    else if (c < 4.0) { rgb = vec3<f32>(0.0, x, 1.0); }
    else if (c < 5.0) { rgb = vec3<f32>(x, 0.0, 1.0); }
    else               { rgb = vec3<f32>(1.0, 0.0, x); }
    return rgb * glow;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res    = u.config.zw;
    var uv     = vec2<f32>(gid.xy) / res;
    let t      = u.config.x;
    let mouse  = u.zoom_config.yz; // normalized 0-1

    // Parameters
    let foldDepth   = i32(u.zoom_params.x * 5.0 + 1.5);  // 1 – 6 iterations
    let foldRadius  = u.zoom_params.y * 2.0 + 0.3;        // 0.3 – 2.3
    let vortSpeed   = u.zoom_params.z * 2.0 - 1.0;        // -1 – 1
    let mirrorBlend = u.zoom_params.w;                      // 0 – 1

    // Singularity center: mouse-driven, gently animated
    let cx = mouse.x * 0.6 + 0.2 + sin(t * 0.13) * 0.05;
    let cy = mouse.y * 0.6 + 0.2 + cos(t * 0.17) * 0.05;
    let center = vec2<f32>(cx, cy);

    // ── Vortex warp (global) ──────────────────────────────────────────────
    let vortStrength = sin(t * 0.3) * vortSpeed * 0.4;
    var wUV = vortexTwist(uv, center, vortStrength);

    // ── Iterative Möbius folds ────────────────────────────────────────────
    for (var k = 0; k < foldDepth; k++) {
        let r_k   = foldRadius * pow(0.65, f32(k));           // shrink per iteration
        let angle = t * 0.08 * f32(k + 1) * sign(vortSpeed);
        let c_k   = center + rot2(vec2<f32>(r_k * 0.3, 0.0), angle);
        wUV = mobiusFold(wUV, c_k, 1.0 / (r_k * r_k + 0.01));
        // Mirror fold: flip if outside [0,1]² after each step
        wUV = abs(fract(wUV * 0.5) * 2.0 - 1.0) * 0.5 + center * (1.0 - pow(0.7, f32(k + 1)));
    }

    // ── Ripple displacement ───────────────────────────────────────────────
    wUV += rippleDisp(uv, t, u32(u.config.y));

    // ── Sample original and folded ────────────────────────────────────────
    let foldedUV = clamp(wUV, vec2<f32>(0.0), vec2<f32>(1.0));
    let colOrig  = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let colFold  = textureSampleLevel(readTexture, u_sampler, foldedUV, 0.0);

    // ── Depth-based blend: near objects fold more ─────────────────────────
    let depth   = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let blend   = mirrorBlend * (0.4 + depth * 0.6);

    // ── Vortex edge darkening for depth ───────────────────────────────────
    let edgeDist = length(uv - center);
    let vignette = smoothstep(0.0, 0.35, edgeDist) * (1.0 - smoothstep(0.35, 0.7, edgeDist));

    let outColor = mix(colOrig, colFold, blend) * (0.7 + vignette * 0.5);

    // ── Box+sphere fold for extra recursive complexity ─────────────────────
    var zMandelbox = foldedUV * 2.0 - 1.0;
    for (var k2 = 0; k2 < 3; k2++) {
        zMandelbox = boxFold(zMandelbox, 1.0);
        zMandelbox = sphereFold(zMandelbox, 0.4, 0.9);
        zMandelbox = zMandelbox * 1.5 + (foldedUV * 2.0 - 1.0);
    }
    let mandelboxUV = clamp((zMandelbox * 0.5 + 0.5), vec2<f32>(0.0), vec2<f32>(1.0));
    let mbCol = textureSampleLevel(readTexture, u_sampler, mandelboxUV, 0.0);
    let mbBlend = smoothstep(0.3, 0.7, mirrorBlend) * depth * 0.25;

    // ── Seam glow where folds meet ────────────────────────────────────────
    let sGlow = seamGlow(uv, foldedUV, t);

    // ── Chromatic vignette ────────────────────────────────────────────────
    let vign  = chromaticVignette(uv, center, 2.0 + mirrorBlend * 2.0);

    // ── Noise-based micro-detail on mirrors ───────────────────────────────
    let microNoise = (vnoise_rmv(foldedUV * 50.0 + t * 0.3) - 0.5) * 0.02;
    let microCol   = textureSampleLevel(readTexture, u_sampler,
        clamp(foldedUV + microNoise, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    let finalMirror = vec4<f32>(
        clamp((outColor.rgb + mbCol.rgb * mbBlend + sGlow) * vign + microCol.rgb * 0.05,
              vec3<f32>(0.0), vec3<f32>(1.0)), 1.0);

    // ── Final depth-aware luminance pass ──────────────────────────────────
    // Boost near-depth regions slightly to accentuate recursive fold depth
    let depthLift = 1.0 + depth * 0.08;
    let liftedMirror = vec4<f32>(clamp(finalMirror.rgb * depthLift, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0);

    textureStore(writeTexture, gid.xy, liftedMirror);
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
