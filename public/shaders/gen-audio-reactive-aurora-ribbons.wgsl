// ═══════════════════════════════════════════════════════════════════
//  gen-audio-reactive-aurora-ribbons
//  Category: generative
//  Features: audio-reactive, mouse-driven, depth-aware, aurora-ribbons
//  Complexity: Medium
//  Chunks From: domainWarp, ribbonSDF, hue_preserve_clamp, bass_env, ign
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

const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
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
fn auroraPalette(t: f32) -> vec3<f32> {
    let hue = fract(t);
    return mix(
        mix(vec3<f32>(0.1, 0.9, 0.55), vec3<f32>(0.2, 0.55, 1.0), smoothstep(0.0, 0.5, hue)),
        mix(vec3<f32>(0.75, 0.25, 1.0), vec3<f32>(1.0, 0.45, 0.75), smoothstep(0.5, 1.0, hue)),
        step(0.5, hue)
    );
}
fn ribbonField(uv: vec2<f32>, t: f32, amp: f32, freq: f32, phase: f32) -> f32 {
    let warp = fbm(uv * 1.5 + vec2<f32>(t * 0.05, 0.0), 3) * 0.35;
    let x = uv.x + warp;
    let wave = sin(x * freq + t * 0.8 + phase) * amp;
    let curtain = exp(-abs(uv.y - wave) * (8.0 + amp * 6.0));
    let shimmer = pow(valueNoise(uv * vec2<f32>(24.0, 6.0) + vec2<f32>(t * 0.4, phase)), 2.0);
    return curtain * (0.55 + shimmer * 0.45);
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
    let bassEnv = mix(prevEnv, bass, 0.09);
    extraBuffer[0] = bassEnv;

    let mouse = (u.zoom_config.yz - vec2<f32>(0.5)) * 1.8;
    let sky = vec3<f32>(0.01, 0.015, 0.03) * (1.0 - depth * 0.35);
    var col = sky;
    var density = 0.0;

    let ribbonCount = i32(mix(3.0, 7.0, p2));
    let baseAmp = 0.08 + bassEnv * (0.18 + p1 * 0.12);
    let baseFreq = 2.0 + mids * 3.0 + p3 * 2.5;

    for (var i = 0; i < ribbonCount; i++) {
        let fi = f32(i);
        let phase = fi * 1.7 + time * 0.15;
        let offset = (fi - f32(ribbonCount) * 0.5) * 0.22 + mouse.y * 0.15;
        let ruv = uv + vec2<f32>(mouse.x * 0.12, offset);
        let field = ribbonField(ruv, time + fi * 0.3, baseAmp, baseFreq + fi * 0.4, phase);
        let hue = fi * 0.11 + mids * 0.35 + time * 0.04 + p1 * 0.2;
        let ribbonCol = auroraPalette(hue) * (0.7 + treble * 0.5);
        col += ribbonCol * field * (0.85 + bassEnv * 0.35);
        density += field;
    }

    let spark = hash21(vec2<f32>(pixel) + fract(time * 30.0)) * treble * density * 0.8;
    col += vec3<f32>(0.9, 0.98, 1.0) * spark;

    let prev = textureSampleLevel(dataTextureC, u_sampler, uv01, 0.0).rgb;
    col = mix(prev * (0.9 - p4 * 0.08), col, 0.28 + p4 * 0.18);
    textureStore(dataTextureA, pixel, vec4<f32>(col, bassEnv));

    col *= mix(1.0, 0.6, depth);
    col = hue_preserve_clamp(col, 1.25);
    col = aces(col * (0.95 + bassEnv * 0.2));
    col += vec3<f32>((ign(vec2<f32>(pixel)) - 0.5) / 255.0);

    let alpha = clamp(density * (0.55 + bassEnv * 0.35) * (1.0 - depth * 0.3), 0.1, 0.92);
    textureStore(writeTexture, pixel, vec4<f32>(col * alpha, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
