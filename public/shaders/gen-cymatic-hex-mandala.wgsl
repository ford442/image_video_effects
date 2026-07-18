// ═══════════════════════════════════════════════════════════════════
//  gen-cymatic-hex-mandala
//  Category: generative
//  Features: audio-reactive, mouse-driven, depth-aware, cymatic-hex
//  Complexity: Medium
//  Chunks From: hexGrid, standingWave, bass_env, ign
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

const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
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
fn hexCoords(p: vec2<f32>) -> vec3<f32> {
    let q = vec2<f32>(p.x * 2.0 / 3.0, (-p.x / 3.0 + p.y) * 1.1547005);
    let r = floor(q);
    let f = fract(q);
    let alt = step(f.y, f.x);
    let id = r + vec2<f32>(alt, 1.0 - alt);
    let local = f - vec2<f32>(alt, 1.0 - alt);
    let edge = max(abs(local.x), abs(local.y * 0.8660254 + local.x * 0.5));
    return vec3<f32>(id.x, id.y, edge);
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

    let mouse = (u.zoom_config.yz - vec2<f32>(0.5)) * 1.5;
    let ruv = uv - mouse * 0.15;
    let scale = mix(5.0, 11.0, p1);
    let hex = hexCoords(ruv * scale);
    let cellId = vec2<f32>(hex.x, hex.y);
    let edge = smoothstep(0.42, 0.38, hex.z);

    let dist = length(ruv);
    let freq = 3.0 + mids * 5.0 + p2 * 4.0;
    let wave = sin(dist * freq * TAU - time * (1.2 + p3 * 1.5)) * (0.35 + bassEnv * 0.45);
    let ring = abs(wave) * exp(-dist * (1.2 - bassEnv * 0.3));
    let nodeSpark = hash21(cellId + fract(time * 0.2)) * treble * edge;

    let hue = fract(atan2(ruv.y, ruv.x) / TAU + 0.5 + mids * 0.25 + time * 0.02);
    var col = vec3<f32>(0.01, 0.015, 0.025);
    let palette = mix(vec3<f32>(0.2, 0.75, 1.0), vec3<f32>(1.0, 0.45, 0.85), hue);
    col += palette * ring * (0.55 + p3 * 0.35);
    col += vec3<f32>(0.9, 0.95, 1.0) * edge * (0.15 + mids * 0.2);
    col += vec3<f32>(1.0, 0.98, 0.75) * nodeSpark * 0.8;

    let prev = textureSampleLevel(dataTextureC, u_sampler, uv01, 0.0).rgb;
    col = mix(prev * (0.9 - p4 * 0.1), col, 0.28 + p4 * 0.18);
    textureStore(dataTextureA, pixel, vec4<f32>(col, bassEnv));

    col *= mix(1.0, 0.55, depth);
    col = hue_preserve_clamp(col, 1.2);
    col = aces(col * (0.92 + bassEnv * 0.22));
    col += vec3<f32>((ign(vec2<f32>(pixel)) - 0.5) / 255.0);

    let density = ring * 0.6 + edge * 0.25 + nodeSpark * 0.15;
    let alpha = clamp(density * (0.55 + bassEnv * 0.35) * (1.0 - depth * 0.35), 0.1, 0.92);
    textureStore(writeTexture, pixel, vec4<f32>(col * alpha, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
