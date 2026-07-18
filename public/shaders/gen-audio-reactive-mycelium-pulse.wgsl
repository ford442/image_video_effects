// ═══════════════════════════════════════════════════════════════════
//  gen-audio-reactive-mycelium-pulse
//  Category: generative
//  Features: audio-reactive, mouse-driven, depth-aware, mycelium-network
//  Complexity: Medium
//  Chunks From: voronoiEdges, domainWarp, bass_env, ign
//  Created: 2026-07-17
//  By: weekly swarm Batch 15
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
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(19.0, 37.0)));
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
fn voronoiEdges(p: vec2<f32>) -> vec2<f32> {
    let n = floor(p);
    let f = fract(p);
    var md = 8.0;
    var md2 = 8.0;
    for (var j = -1; j <= 1; j++) {
        for (var i = -1; i <= 1; i++) {
            let g = vec2<f32>(f32(i), f32(j));
            let o = hash22(n + g);
            let r = g + o - f;
            let d = dot(r, r);
            if (d < md) { md2 = md; md = d; }
            else if (d < md2) { md2 = d; }
        }
    }
    return vec2<f32>(sqrt(md), sqrt(md2) - sqrt(md));
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
    let warp = fbm(uv * 1.8 + time * 0.05, 3) * (0.06 + treble * 0.1);
    var p = uv + mouse * 0.12 + vec2<f32>(warp, warp * 0.7);
    let scale = mix(4.0, 9.0, p1) * (1.0 + bassEnv * 0.25);
    let v = voronoiEdges(p * scale + vec2<f32>(time * 0.03, 0.0));
    let edge = smoothstep(0.02 + mids * 0.02, 0.0, v.y);
    let node = exp(-v.x * (12.0 - bassEnv * 4.0));

    let hue = fract(length(uv) * 0.4 + mids * 0.35 + time * 0.03);
    var col = vec3<f32>(0.01, 0.02, 0.03);
    let hyphae = mix(vec3<f32>(0.15, 0.85, 0.45), vec3<f32>(0.55, 0.25, 1.0), hue);
    col += hyphae * edge * (0.7 + p2 * 0.5);
    col += vec3<f32>(0.35, 1.0, 0.65) * node * (0.25 + bassEnv * 0.45);
    col += vec3<f32>(1.0, 0.95, 0.7) * hash21(vec2<f32>(pixel) + fract(time * 18.0)) * treble * edge * 0.5;

    let prev = textureSampleLevel(dataTextureC, u_sampler, uv01, 0.0).rgb;
    col = mix(prev * (0.88 - p4 * 0.08), col, 0.3 + p3 * 0.2);
    textureStore(dataTextureA, pixel, vec4<f32>(col, bassEnv));

    col *= mix(1.0, 0.58, depth);
    col = hue_preserve_clamp(col, 1.2);
    col = aces(col * (0.9 + bassEnv * 0.25));
    col += vec3<f32>((ign(vec2<f32>(pixel)) - 0.5) / 255.0);

    let density = edge * (0.55 + node * 0.45);
    let alpha = clamp(density * (0.6 + bassEnv * 0.35) * (1.0 - depth * 0.35), 0.1, 0.92);
    textureStore(writeTexture, pixel, vec4<f32>(col * alpha, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
