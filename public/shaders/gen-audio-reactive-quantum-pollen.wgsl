// ═══════════════════════════════════════════════════════════════════
//  gen-audio-reactive-quantum-pollen
//  Category: generative
//  Features: audio-reactive, mouse-driven, depth-aware, particle-field,
//            aces-tone-map, ign-dither, premultiplied-alpha
//  Complexity: Medium
//  Chunks From: warpedFBM, hue_preserve_clamp, bass_env, ign
//  Created: 2026-07-17
//  By: Kimi swarm (manual completion after kimi-cli timeout)
// ═══════════════════════════════════════════════════════════════════
//  Hundreds of luminous pollen grains in a dark field. Bass envelope
//  pulls grains into log-spiral galaxy clusters, mids drive harmonic
//  orbital motion + hue shift, treble fires scatter bursts. Mouse hold
//  attracts nearby grains. Depth fades background grains into haze.
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
  config: vec4<f32>,       // x=Time, y=delta_time, zw=resolution
  zoom_config: vec4<f32>,  // x=zoom, yz=mouse_uv, w=mouse_down
  zoom_params: vec4<f32>,  // xyzw = user params p1…p4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123); }
fn hash22(p: vec2<f32>) -> vec2<f32> { return vec2<f32>(hash21(p), hash21(p + vec2<f32>(17.0, 31.0))); }
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), w.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), w.x), w.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i = i + 1) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
    return s;
}
fn domainWarp(p: vec2<f32>, t: f32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t), 3), fbm(p + vec2<f32>(5.2, 1.3), 3));
    return p + 0.25 * q;
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 { return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715)))); }
fn huePreserveClamp(c: vec3<f32>, maxLum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    return c * min(1.0, maxLum / max(l, 1e-4));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
    let uv01 = vec2<f32>(pixel) / res;
    let uv = (vec2<f32>(pixel) - 0.5 * res) / min(res.x, res.y);
    let time = u.config.x;
    let mouseC = (u.zoom_config.yz * res - 0.5 * res) / min(res.x, res.y);
    let mouseDown = u.zoom_config.w > 0.5;
    let density = mix(0.4, 1.6, u.zoom_params.x);
    let glowSize = mix(0.5, 2.0, u.zoom_params.y);
    let orbitSpeed = mix(0.2, 1.5, u.zoom_params.z);
    let hueBase = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let prev = textureLoad(dataTextureC, pixel, 0);

    // bass_env / treble_env attack-release envelopes (tactic 9)
    let bassEnv = mix(prev.r, bass, select(0.06, 0.35, bass > prev.r));
    let trebEnv = mix(prev.g, treble, select(0.08, 0.50, treble > prev.g));

    // drifting galaxy cluster center + log-spiral arm frame
    let galaxyC = vec2<f32>(sin(time * 0.07), cos(time * 0.09)) * 0.22;
    // warped haze field
    let wp = domainWarp(uv * 3.0 + vec2<f32>(time * 0.05), time * 0.1);
    let haze = fbm(wp * 2.0, 4);

    // grain grid: one grain per cell, 3x3 neighborhood gather
    let cells = 14.0 * density;
    let g = uv * cells;
    let id = floor(g);
    var col = vec3<f32>(0.0);
    var dens = 0.0;
    for (var j = -1; j <= 1; j = j + 1) {
        for (var i = -1; i <= 1; i = i + 1) {
            let cid = id + vec2<f32>(f32(i), f32(j));
            let rnd = hash22(cid);
            var gp = (cid + 0.5 + (rnd - 0.5) * 0.8) / cells;
            // mids harmonic orbit
            let orbA = time * (0.3 + mids * 0.9) * orbitSpeed * (rnd.x + 0.5) + rnd.y * TAU;
            gp += vec2<f32>(cos(orbA), sin(orbA)) * (0.35 / cells) * (0.4 + rnd.y);
            // bass cluster: pull toward log-spiral arm around galaxyC
            let rel = gp - galaxyC;
            let rr = length(rel) + 1e-4;
            let arm = atan2(rel.y, rel.x) + log(rr + 0.05) * 3.0 - time * 0.4;
            let armPos = galaxyC + vec2<f32>(cos(arm), sin(arm)) * rr;
            gp = mix(gp, armPos, bassEnv * 0.55 * smoothstep(0.8, 0.1, rr));
            // treble scatter burst
            let burst = trebEnv * 0.12;
            gp += vec2<f32>(hash21(cid + 9.1) - 0.5, hash21(cid + 3.7) - 0.5) * burst;
            // mouse attractor
            if (mouseDown) {
                let md = length(gp - mouseC) + 1e-4;
                let pull = smoothstep(0.35, 0.0, md) * 0.85;
                gp = mix(gp, mouseC + (gp - mouseC) / md * 0.03, pull);
            }
            let d = length(uv - gp);
            let r = (0.004 + rnd.x * 0.004) * glowSize;
            let w = exp(-d * d / (r * r));
            let hue = fract(rnd.y + hueBase + mids * 0.25 + haze * 0.15);
            let c = clamp(vec3<f32>(abs(hue * 6.0 - 3.0) - 1.0, abs(hue * 6.0 - 2.0) - 1.0, abs(hue * 6.0 - 4.0) - 1.0),
                          vec3<f32>(0.0), vec3<f32>(1.0));
            col += c * w;
            dens += w;
        }
    }

    // dark field: faint camera passthrough + audio-breathing haze
    let video = textureSampleLevel(readTexture, u_sampler, uv01, 0.0).rgb;
    var bg = video * 0.05 + vec3<f32>(0.02, 0.015, 0.05) * haze * (0.5 + bassEnv);
    // treble auroral shimmer in the haze
    bg += vec3<f32>(0.1, 0.4, 0.5) * haze * trebEnv * 0.35;
    col += bg * 0.4;

    // tone map + dither stack
    var outColor = acesToneMap(huePreserveClamp(col * (1.0 + bassEnv * 0.5), 2.0));
    outColor = clamp(outColor + vec3<f32>((ign(vec2<f32>(pixel)) - 0.5) / 255.0), vec3<f32>(0.0), vec3<f32>(1.0));

    // alpha = grain density, background fades with depth (transmission haze)
    let alpha = clamp(dens * (1.0 - depth * 0.4) + haze * 0.1 * (1.0 - depth), 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(outColor * alpha, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(bassEnv, trebEnv, dens, alpha));
}
