// ═══════════════════════════════════════════════════════════════════
//  gen-fractal-lightning-canvas
//  Category: generative
//  Features: audio-reactive, mouse-driven, depth-aware, fractal-lightning
//  Complexity: Medium
//  Chunks From: lichtenbergBranch, domainWarp, blackbodyGlow, ign
//  Created: 2026-07-17
//  By: weekly swarm Batch 14
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

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(17.0, 31.0)));
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < 4; i++) {
        s += a * valueNoise(p * f); f *= 2.0; a *= 0.5;
    }
    return s;
}
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}
fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    let s = min(1.0, max_lum / max(l, 1e-4));
    return c * s;
}
fn branchBolt(uv: vec2<f32>, seed: vec2<f32>, branches: f32, jitter: f32, t: f32) -> f32 {
    let d = uv - seed;
    let r = length(d);
    let a = atan2(d.y, d.x);
    let w = fbm(d * 4.0 + t * 0.2) * jitter * 2.5;
    let dend = fbm(vec2<f32>(a * branches + w, r * 7.0 + t * 0.1));
    let core = smoothstep(0.14, 0.0, r);
    let fil = smoothstep(0.52, 0.42, dend) * smoothstep(0.65, 0.0, r);
    return max(core, fil);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
    let uv01 = vec2<f32>(pixel) / res;
    let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let p1 = clamp(u.zoom_params.x, 0.0, 1.0);
    let p2 = clamp(u.zoom_params.y, 0.0, 1.0);
    let p3 = clamp(u.zoom_params.z, 0.0, 1.0);
    let p4 = clamp(u.zoom_params.w, 0.0, 1.0);

    let prevEnv = extraBuffer[0];
    let bassEnv = mix(prevEnv, bass, 0.1);
    extraBuffer[0] = bassEnv;

    let mouse = (u.zoom_config.yz - vec2<f32>(0.5)) * 1.6;
    let warp = fbm(uv * 2.0 + time * 0.08) * (0.04 + treble * 0.08);
    let wuv = uv + vec2<f32>(warp, warp * 0.6) + mouse * 0.08;

    let prev = textureSampleLevel(dataTextureC, u_sampler, uv01, 0.0).r;
    var energy = 0.0;
    let branches = mix(10.0, 22.0, p1);
    let jitter = 0.25 + p2 * 0.55 + treble * 0.35;
    let seedCount = i32(mix(2.0, 5.0, bassEnv * (0.5 + p3)));

    for (var i = 0; i < seedCount; i++) {
        let fi = f32(i);
        let baseSeed = hash22(vec2<f32>(fi, floor(time * (0.4 + bassEnv * 0.3))));
        let seed = baseSeed * 0.7 + vec2<f32>(sin(time * 0.2 + fi), cos(time * 0.17 + fi * 1.3)) * 0.12;
        energy = max(energy, branchBolt(wuv, seed, branches, jitter, time + fi));
    }

    if (length(mouse) < 1.2) {
        energy = max(energy, branchBolt(wuv, mouse * 0.45 + vec2<f32>(0.0, 0.2), branches * 1.2, jitter, time) * 0.85);
    }

    let strike = smoothstep(0.82, 1.0, sin(time * (2.0 + mids * 3.0) + bassEnv * 4.0) * 0.5 + 0.5);
    if (strike > 0.0) {
        let strikeSeed = hash22(vec2<f32>(floor(time * 3.0), 1.0));
        energy = max(energy, branchBolt(wuv, strikeSeed, branches * 1.4, jitter * 1.2, time) * strike);
    }

    energy = smoothstep(0.0, 1.0 / mix(0.6, 1.8, mids), energy);
    energy = max(energy, prev * mix(0.65, 0.94, p4));

    var col = vec3<f32>(0.01, 0.015, 0.03);
    let cool = vec3<f32>(0.35, 0.55, 1.0);
    let hot = vec3<f32>(0.85, 0.95, 1.0);
    let core = vec3<f32>(1.0, 0.98, 0.9);
    let hotMask = smoothstep(0.55, 1.0, energy);
    let warmMask = smoothstep(0.2, 0.55, energy);
    col += mix(cool, hot, warmMask) * energy * 0.9;
    col += core * hotMask * hotMask * (1.2 + treble * 1.5);
    col += vec3<f32>(1.0) * hash21(vec2<f32>(pixel) + fract(time * 25.0)) * treble * hotMask * 0.6;

    col *= mix(1.0, 0.55, depth);
    col = hue_preserve_clamp(col, 1.3);
    col = aces(col * (0.9 + bassEnv * 0.25 + p2 * 0.15));
    col += vec3<f32>((ign(vec2<f32>(pixel)) - 0.5) / 255.0);

    let alpha = clamp(energy * (0.65 + bassEnv * 0.3) * (1.0 - depth * 0.35), 0.08, 0.95);
    textureStore(writeTexture, pixel, vec4<f32>(col * alpha, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(energy, 0.0, 0.0, 0.0));
    textureStore(writeDepthTexture, pixel, vec4<f32>(energy * 0.45 + depth * 0.2, 0.0, 0.0, 0.0));
}
