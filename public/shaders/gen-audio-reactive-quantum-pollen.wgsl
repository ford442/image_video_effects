// ═══════════════════════════════════════════════════════════════════
//  gen-audio-reactive-quantum-pollen
//  Category: generative
//  Features: audio-reactive, mouse-driven, depth-aware, particle-field
//  Complexity: Medium
//  Chunks From: warpedFBM, hue_preserve_clamp, bass_env, ign
//  Created: 2026-07-17
//  By: Kimi Code CLI (weekly swarm)
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

const TAU: f32 = 6.28318530718;

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
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i++) {
        s += a * valueNoise(p * f); f *= 2.0; a *= 0.5;
    }
    return s;
}
fn domainWarp(p: vec2<f32>, t: f32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p + vec2(0.0, t), 3), fbm(p + vec2(5.2, 1.3), 3));
    return p + 0.25 * q;
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
fn grainGlow(uv: vec2<f32>, c: vec2<f32>, r: f32, i: f32) -> f32 {
    let d = length(uv - c);
    return exp(-d * d / (r * r * 0.35)) * i;
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

    let cluster = smoothstep(0.25, 0.85, bassEnv) * (0.35 + p1 * 0.65);
    let scatter = treble * (0.8 + p2 * 0.6);
    let orbit = 0.35 + mids * (0.9 + p3 * 1.2);
    let mouse = (u.zoom_config.yz - vec2<f32>(0.5)) * 2.0;
    let attract = select(vec2<f32>(0.0), mouse, u.zoom_config.w > 0.5);

    let galaxyCenters = array<vec2<f32>, 3>(
        vec2<f32>(-0.35, 0.15), vec2<f32>(0.3, -0.2), vec2<f32>(0.0, 0.35));
    var col = vec3<f32>(0.01, 0.012, 0.02);
    var density = 0.0;

    for (var g = 0; g < 72; g++) {
        let gi = f32(g);
        let seed = vec2<f32>(floor(gi * 0.17), floor(gi * 0.31));
        let h = hash22(seed + vec2<f32>(gi * 0.07, gi * 0.13));
        let hub = galaxyCenters[i32(g) % 3];
        let spiral = hub + vec2<f32>(cos(gi * 0.42 + time * orbit), sin(gi * 0.42 + time * orbit)) * (0.08 + h.y * 0.22);
        let free = (h - 0.5) * (1.6 + scatter * 1.4);
        var pos = mix(free, spiral, cluster);
        pos += attract * (0.25 + bassEnv * 0.35) * exp(-length(uv - mouse) * 2.5);
        pos += (hash22(seed + vec2<f32>(time * 0.2)) - 0.5) * scatter * 0.35;
        pos = domainWarp(pos + time * 0.05, time * 0.12);

        let size = 0.003 + h.x * 0.004 + bassEnv * 0.002;
        let glow = grainGlow(uv, pos, size, 0.7 + mids * 0.5);
        let hue = fract(h.x + mids * 0.35 + gi * 0.03);
        let pollen = mix(
            mix(vec3<f32>(0.35, 0.85, 1.0), vec3<f32>(1.0, 0.55, 0.85), hue),
            vec3<f32>(1.0, 0.95, 0.7),
            treble * 0.4);
        col += pollen * glow;
        density += glow;
    }

    let field = fbm(domainWarp(uv * 2.2 + time * 0.08, time * 0.1), 4);
    col += vec3<f32>(0.08, 0.12, 0.18) * field * (0.15 + mids * 0.2);
    density += field * 0.08;

    let prev = textureSampleLevel(dataTextureC, u_sampler, uv01, 0.0).rgb;
    col = mix(prev * (0.88 - p4 * 0.08), col, 0.28 + p4 * 0.2 + bass * 0.12);
    textureStore(dataTextureA, pixel, vec4<f32>(col, bassEnv));

    let depthFade = mix(1.0, 0.45, depth);
    col *= depthFade;
    col = hue_preserve_clamp(col, 1.2);
    col = aces(col * (0.9 + bassEnv * 0.25));
    col += vec3<f32>((ign(vec2<f32>(pixel)) - 0.5) / 255.0);

    var alpha = clamp(density * (1.1 + bassEnv * 0.4) * (1.0 - depth * 0.4), 0.08, 0.95);
    alpha = mix(alpha, alpha * 0.65, scatter * 0.35);
    textureStore(writeTexture, pixel, vec4<f32>(col * alpha, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
