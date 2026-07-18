// ═══════════════════════════════════════════════════════════════════
//  gen-audio-reactive-spiral-galaxy
//  Category: generative
//  Features: audio-reactive, mouse-driven, depth-aware, spiral-galaxy
//  Complexity: Medium
//  Chunks From: logSpiral, hue_preserve_clamp, bass_env, ign
//  Created: 2026-07-17
//  By: weekly swarm Batch 13
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
fn starGlow(uv: vec2<f32>, c: vec2<f32>, r: f32, i: f32) -> f32 {
    let d = length(uv - c);
    return exp(-d * d / (r * r * 0.4)) * i;
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
    let bassEnv = mix(prevEnv, bass, 0.08);
    extraBuffer[0] = bassEnv;

    let mouse = (u.zoom_config.yz - vec2<f32>(0.5)) * 2.0;
    let orbit = time * (0.12 + mids * 0.25 + p3 * 0.2);
    let tightness = 0.18 + bassEnv * (0.22 + p1 * 0.15);
    let arms = 2.0 + floor(mix(2.0, 5.0, p2));

    var p = uv - mouse * 0.15;
    let r = length(p);
    let a = atan2(p.y, p.x) + orbit;

    var col = vec3<f32>(0.008, 0.01, 0.02);
    var density = 0.0;

    // galactic core
    let core = exp(-r * r / (0.04 + bassEnv * 0.03));
    col += vec3<f32>(1.0, 0.85, 0.55) * core * (1.2 + bassEnv);
    density += core * 1.5;

    // spiral arm stars
    for (var i = 0; i < 96; i++) {
        let fi = f32(i);
        let h = hash22(vec2<f32>(fi, fi * 0.37));
        let arm = floor(h.x * arms);
        let armPhase = arm / arms * TAU;
        let spiral = a - armPhase - log(max(r, 0.02)) / tightness;
        let band = exp(-spiral * spiral * (18.0 - bassEnv * 6.0));
        let radial = smoothstep(0.75, 0.05, abs(r - (0.08 + h.y * 0.55)));
        let starMask = band * radial;
        if (starMask < 0.01) { continue; }

        let jitter = (hash22(vec2<f32>(fi, time * 0.1)) - 0.5) * (0.02 + treble * 0.04);
        let pos = vec2<f32>(cos(a + armPhase), sin(a + armPhase)) * (r + jitter.x) + jitter;
        let size = 0.002 + h.y * 0.004 + treble * 0.002;
        let glow = starGlow(uv, pos, size, starMask);
        let temp = mix(vec3<f32>(0.5, 0.7, 1.0), vec3<f32>(1.0, 0.75, 0.45), h.x);
        col += temp * glow * (0.8 + mids * 0.5);
        density += glow;
    }

    // dust lane
    let dust = smoothstep(0.35, 0.0, abs(sin(a * arms - log(r + 0.05) * 3.0))) * exp(-r * 1.8);
    col *= 1.0 - dust * 0.35;

    // treble supernova sparks
    let spark = step(0.992 - treble * 0.02, hash21(uv * 120.0 + time)) * treble;
    col += vec3<f32>(1.0, 0.9, 0.7) * spark * 0.6;

    let prev = textureSampleLevel(dataTextureC, u_sampler, uv01, 0.0).rgb;
    col = mix(prev * (0.9 - p4 * 0.08), col, 0.22 + p4 * 0.18 + bass * 0.1);
    textureStore(dataTextureA, pixel, vec4<f32>(col, bassEnv));

    let depthFade = mix(1.0, 0.5, depth);
    col *= depthFade;
    col = hue_preserve_clamp(col, 1.25);
    col = aces(col * (0.85 + bassEnv * 0.3));
    col += vec3<f32>((ign(vec2<f32>(pixel)) - 0.5) / 255.0);

    var alpha = clamp(density * (0.9 + bassEnv * 0.35) * (1.0 - depth * 0.35), 0.1, 0.95);
    textureStore(writeTexture, pixel, vec4<f32>(col * alpha, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
