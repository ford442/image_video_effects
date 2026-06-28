// ═══════════════════════════════════════════════════════════════════
//  Quantum Aether-Origami — Algorithmist Upgrade
//  Category: generative
//  Features: generative, mouse-driven, audio-reactive, raymarched,
//            depth-aware, upgraded-rgba, KIFS, FBM, domain-warping,
//            curl-noise, thin-film, Fresnel-Schlick, temporal
//  Complexity: Very High
//  Upgraded: 2026-06-28
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Fold Complexity, y=Crease Glow, z=Audio Reactivity, w=Interference Shift
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;
const PHI: f32 = 1.618033988749895;

fn rot(a: f32) -> mat2x2<f32> { let s = sin(a); let c = cos(a); return mat2x2<f32>(c, -s, s, c); }

fn hash1(p: vec3<f32>) -> f32 { return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453); }

fn vnoise(p: vec3<f32>) -> f32 {
    let i = floor(p); let f = fract(p); let s = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash1(i), hash1(i + vec3<f32>(1.0, 0.0, 0.0)), s.x),
                   mix(hash1(i + vec3<f32>(0.0, 1.0, 0.0)), hash1(i + vec3<f32>(1.0, 1.0, 0.0)), s.x), s.y),
               mix(mix(hash1(i + vec3<f32>(0.0, 0.0, 1.0)), hash1(i + vec3<f32>(1.0, 0.0, 1.0)), s.x),
                   mix(hash1(i + vec3<f32>(0.0, 1.0, 1.0)), hash1(i + vec3<f32>(1.0, 1.0, 1.0)), s.x), s.y), s.z);
}

fn fbm(p: vec3<f32>, oct: i32) -> f32 {
    var v = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < 6; i++) { if (i >= oct) { break; } v += a * vnoise(p * f); f *= 2.0; a *= 0.5; }
    return v;
}

fn domainWarp(p: vec3<f32>, t: f32) -> vec3<f32> {
    return p + vec3<f32>(fbm(p + vec3<f32>(0.0, 0.0, t), 3), fbm(p + vec3<f32>(5.2, 1.3, t), 3), fbm(p + vec3<f32>(1.7, 9.2, t), 3)) * 0.4;
}

fn curl(p: vec3<f32>, t: f32) -> vec3<f32> {
    let e = 0.01;
    let n1 = vnoise(p + vec3<f32>(e, 0.0, 0.0) + t); let n2 = vnoise(p - vec3<f32>(e, 0.0, 0.0) + t);
    let n3 = vnoise(p + vec3<f32>(0.0, e, 0.0) + t); let n4 = vnoise(p - vec3<f32>(0.0, e, 0.0) + t);
    let n5 = vnoise(p + vec3<f32>(0.0, 0.0, e) + t); let n6 = vnoise(p - vec3<f32>(0.0, 0.0, e) + t);
    let dx = (n1 - n2) / (2.0 * e); let dy = (n3 - n4) / (2.0 * e); let dz = (n5 - n6) / (2.0 * e);
    return vec3<f32>(dy - dz, dz - dx, dx - dy);
}

fn fold(p: vec3<f32>, normal: vec3<f32>, d: f32) -> vec3<f32> { let t = dot(p, normal) - d; return p - 2.0 * min(0.0, t) * normal; }
fn smin(a: f32, b: f32, k: f32) -> f32 { let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0); return mix(b, a, h) - k * h * (1.0 - h); }
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 { let d = abs(p) - b; return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, vec3<f32>(0.0))); }
fn sdSphere(p: vec3<f32>, r: f32) -> f32 { return length(p) - r; }

fn map(p: vec3<f32>) -> f32 {
    let audio = plasmaBuffer[0].x * u.zoom_params.z;
    let mids = plasmaBuffer[0].y * u.zoom_params.z;
    let treble = plasmaBuffer[0].z * u.zoom_params.z;
    let t = u.config.x * 0.2 + audio * 0.5;
    let iters = i32(u.zoom_params.x);
    var q = p;
    // Add curl noise aether flow
    q += curl(q * 0.3, t * 0.3) * 0.15;
    // Domain-warped fold parameters
    let warp = domainWarp(q * 0.2 + vec3<f32>(0.0, 0.0, t * 0.1), t * 0.2);
    let n1 = normalize(vec3<f32>(1.0, 1.0, 0.0) + warp * 0.3);
    let n2 = normalize(vec3<f32>(0.0, 1.0, 1.0) + warp * 0.3);
    let n3 = normalize(vec3<f32>(1.0, 0.0, 1.0) + warp * 0.3);
    let n4 = normalize(vec3<f32>(1.0, 1.0, 1.0));
    let n5 = normalize(vec3<f32>(-1.0, 1.0, 0.5));
    var scale = 1.0;
    for (var i = 0; i < 10; i++) {
        if (i >= iters) { break; }
        q = fold(q, n1, 0.1 * sin(t + warp.x));
        q = fold(q, n2, 0.1 * cos(t * 0.8 + warp.y));
        q = fold(q, n3, 0.05 + mids * 0.02);
        q = fold(q, n4, 0.03 + treble * 0.01);
        q = fold(q, n5, 0.04 * sin(t * 1.5));
        let xy = rot(0.5 + audio * 0.1) * vec2<f32>(q.x, q.y); q.x = xy.x; q.y = xy.y;
        let yz = rot(0.3 + mids * 0.05) * vec2<f32>(q.y, q.z); q.y = yz.x; q.z = yz.y;
        let xz = rot(0.2 + treble * 0.1) * vec2<f32>(q.x, q.z); q.x = xz.x; q.z = xz.y;
        q = abs(q) - vec3<f32>(0.2, 0.2, 0.2);
        scale *= 1.2; q *= 1.2;
    }
    // Base thin-box with FBM surface detail
    let base = sdBox(q, vec3<f32>(1.0, 1.0, 0.05)) - 0.01;
    let sphere = sdSphere(q, 0.8 + audio * 0.1);
    return smin(base / scale, sphere / scale, 0.1) + fbm(domainWarp(q * 0.5, t * 0.5), 3) * 0.02;
}

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.5, 0.5, 0.5) + vec3<f32>(0.5, 0.5, 0.5) * cos(TAU * (vec3<f32>(1.0, 1.0, 1.0) * t + vec3<f32>(0.263, 0.416, 0.557)));
}

fn fresnel(cosTheta: f32, f0: vec3<f32>) -> vec3<f32> { return f0 + (vec3<f32>(1.0) - f0) * pow(1.0 - cosTheta, 5.0); }

fn softShadow(ro: vec3<f32>, rd: vec3<f32>, mint: f32, maxt: f32, k: f32) -> f32 {
    var res = 1.0; var t = mint;
    for (var i = 0; i < 24; i++) {
        let h = map(ro + rd * t);
        if (h < 0.001) { return 0.0; }
        res = min(res, k * h / t);
        t += clamp(h, 0.01, 0.5);
        if (t > maxt) { break; }
    }
    return clamp(res, 0.0, 1.0);
}

fn ambientOcclusion(p: vec3<f32>, n: vec3<f32>) -> f32 {
    var occ = 0.0; var scale = 1.0;
    for (var i = 0; i < 5; i++) {
        let h = 0.01 + 0.12 * f32(i) / 4.0;
        let d = map(p + n * h);
        occ += (h - d) * scale;
        scale *= 0.5;
    }
    return clamp(1.0 - 3.0 * occ, 0.0, 1.0);
}

fn spectralFold(foldDepth: f32, time: f32, audio: f32) -> vec3<f32> {
    let phase = foldDepth * TAU * 2.0 + time * 0.3 + audio * 0.5;
    return vec3<f32>(
        0.5 + 0.5 * cos(phase + 0.0),
        0.5 + 0.5 * cos(phase + 2.094),
        0.5 + 0.5 * cos(phase + 4.189)
    );
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let d = map(p); let e = vec2<f32>(0.001, 0.0);
    return normalize(d - vec3<f32>(map(p - e.xyy), map(p - e.yxy), map(p - e.yyx)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let texSize = textureDimensions(writeTexture);
    let uv = vec2<f32>(id.xy) / vec2<f32>(texSize);
    if (id.x >= texSize.x || id.y >= texSize.y) { return; }
    let res = vec2<f32>(texSize);
    let centered_uv = (vec2<f32>(id.xy) - 0.5 * res) / res.y;
    // Mouse Y-flip: screen-top (zoom_config.z=0) = +Y/up
    let mouse = (vec2<f32>(u.zoom_config.y, 0.5 - u.zoom_config.z) * res - 0.5 * res) / res.y;
    let mouse_dist = length(centered_uv - mouse);
    let fold_factor = smoothstep(0.0, 0.5, mouse_dist);
    let ro = vec3<f32>(0.0, 0.0, -3.0); let rd = normalize(vec3<f32>(centered_uv, 1.0));
    let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
    var t = 0.0; var p = ro; var hit = false; var min_dist = 999.0;
    for (var i = 0; i < 100; i++) {
        p = ro + rd * t;
        let orig_d = map(p);
        let flat_d = p.z;
        let d = mix(flat_d, orig_d, fold_factor);
        min_dist = min(min_dist, d);
        if (abs(d) < 0.001) { hit = true; break; }
        if (t > 15.0) { break; }
        t += d;
    }
    var color = vec4<f32>(0.0);
    if (hit) {
        let e = vec2<f32>(0.001, 0.0);
        let d_p = mix(p.z, map(p), fold_factor);
        let n = normalize(vec3<f32>(
            mix(p.z, map(p + vec3<f32>(e.x, e.y, e.y)), fold_factor) - d_p,
            mix(p.z, map(p + vec3<f32>(e.y, e.x, e.y)), fold_factor) - d_p,
            mix(p.z + e.x, map(p + vec3<f32>(e.y, e.y, e.x)), fold_factor) - d_p
        ));
        let v = -rd;
        let view_angle = max(dot(n, v), 0.0);
        let shift = u.zoom_params.w * u.config.x * 0.1 + treble * 0.5;
        // Multi-band thin-film interference
        let if1 = palette(view_angle * 2.0 + shift);
        let if2 = palette(view_angle * 3.0 + shift + 0.3) * 0.5;
        let interference = if1 + if2;
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let shadow = softShadow(p + n * 0.01, l, 0.02, 5.0, 8.0);
        let ao = ambientOcclusion(p, n);
        let ambient = vec3<f32>(0.02, 0.02, 0.05);
        let base_col = ambient + diff * interference * shadow * ao;
        // Spectral fold coloring based on iteration depth
        let foldCol = spectralFold(min_dist * 10.0, u.config.x, bass) * 0.15 * u.zoom_params.y;
        // Fresnel rim lighting
        let f0 = vec3<f32>(0.04, 0.03, 0.02);
        let fres = fresnel(view_angle, f0);
        let rim = fres * (0.5 + bass * 0.5) * palette(shift + 0.5);
        // Edge glow with audio pulse
        let edge_glow = smoothstep(0.05, 0.0, min_dist);
        let audio_pulse = 1.0 + u.config.y * u.zoom_params.z;
        let emissive = vec3<f32>(1.0, 0.8, 0.2) * edge_glow * u.zoom_params.y * audio_pulse;
        let lum = dot(base_col + emissive + rim + foldCol, vec3<f32>(0.299, 0.587, 0.114));
        color = vec4<f32>(base_col + emissive + rim + foldCol, clamp(lum * 1.2 + 0.15, 0.05, 0.98));
    } else {
        let bg_glow = 0.1 / max(length(centered_uv), 0.01);
        let bgCol = vec3<f32>(0.05, 0.0, 0.1) * bg_glow;
        color = vec4<f32>(bgCol, clamp(dot(bgCol, vec3<f32>(0.299, 0.587, 0.114)) * 1.5, 0.05, 0.6));
    }
    // Fog with Beer-Lambert attenuation
    let fog = 1.0 - exp(-0.05 * t);
    color = mix(color, vec4<f32>(0.0, 0.0, 0.02, color.a), fog);
    // Temporal feedback via dataTextureC
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    color = mix(color, vec4<f32>(prev.rgb * 0.95, prev.a * 0.95), 0.02 + bass * 0.015);
    // Curl-noise aether drift on background
    if (!hit) {
        let drift = curl(vec3<f32>(uv * 3.0, u.config.x * 0.1), u.config.x * 0.2);
        color.rgb += vec3<f32>(0.02, 0.01, 0.03) * drift.z * (0.5 + mids * 0.5);
    }
    textureStore(writeTexture, id.xy, color);
    let d_uv = clamp(vec2<f32>(id.xy) / vec2<f32>(u.config.z, u.config.w), vec2<f32>(0.0), vec2<f32>(1.0));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, d_uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(id.xy), color);
}
