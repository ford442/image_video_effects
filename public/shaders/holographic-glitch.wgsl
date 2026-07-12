// ═══════════════════════════════════════════════════════════════════
//  Holographic Glitch
//  Category: retro-glitch
//  Features: upgraded-rgba, holographic, glitch, chromatic-aberration,
//            scanlines, audio-reactive, aces-tone-map, ign-dither,
//            depth-aware, temporal-feedback, fresnel-rim, split-tone,
//            film-grain, hue-preserve-clamp
//  Complexity: Medium
//  Upgraded: 2026-07-12 (retry)
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
  config: vec4<f32>,       // .x = time, .y = delta_time, .zw = resolution
  zoom_config: vec4<f32>,  // .x = zoom, .yz = mouse_uv, .w = mouse_down
  zoom_params: vec4<f32>,  // .xyzw = user params p1..p4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123); }
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p); let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x), mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 { var s = 0.0; var a = 0.5; var f = 1.0; for (var i = 0; i < oct; i = i + 1) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; } return s; }
fn acesToneMap(x: vec3<f32>) -> vec3<f32> { return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0)); }
fn ign(p: vec2<f32>) -> f32 { return fract(52.9829181 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715)))); }
fn luma(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722)); }
fn chromaticAberration(uv: vec2<f32>, amount: f32) -> vec3<f32> {
    let center = vec2<f32>(0.5);
    let delta = uv - center;
    let lenSq = max(dot(delta, delta), 0.000001);
    let dir = delta * inverseSqrt(lenSq);
    let offset = dir * max(amount, 0.0);
    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - offset * 0.6, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    return vec3<f32>(r, g, b);
}

// Split-tone the image: cool cyan in shadows and warm amber in highlights.
fn splitTone(c: vec3<f32>, shadows: vec3<f32>, highlights: vec3<f32>, strength: f32) -> vec3<f32> {
    let y = luma(c);
    let mask = smoothstep(0.25, 0.7, y);
    let tint = mix(shadows, highlights, mask);
    return mix(c, c * tint, strength);
}

// Fresnel rim brightens the viewport edges like a worn holographic plate.
fn fresnelRim(uv: vec2<f32>, bias: f32, power: f32) -> f32 {
    let d = distance(uv, vec2<f32>(0.5));
    let f = 1.0 - pow(clamp(d * 2.0, 0.0, 1.0), power);
    return bias + (1.0 - bias) * f;
}

// Coarse film-grain overlay for a retro analog feel.
fn filmGrain(uv: vec2<f32>, time: f32, strength: f32) -> f32 {
    return (hash21(uv * 1234.5 + time * 37.0) - 0.5) * strength;
}

// Keep saturated highlights from clipping to white while preserving hue.
fn huePreserveClamp(c: vec3<f32>) -> vec3<f32> {
    let mx = max(max(c.r, c.g), c.b);
    return c / max(mx, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
    let uv = vec2<f32>(pixel) / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let p1 = clamp(u.zoom_params.x, 0.0, 1.0);
    let p2 = clamp(u.zoom_params.y, 0.0, 1.0);
    let p3 = clamp(u.zoom_params.z, 0.0, 1.0);
    let p4 = clamp(u.zoom_params.w, 0.0, 1.0);

    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let prev = textureLoad(dataTextureC, pixel, 0);

    let block = floor(uv.y * 40.0);
    let seed = hash21(vec2<f32>(block, floor(time * 8.0 * (1.0 + bass))));
    let trigger = step(seed, p1);
    let offset = (hash21(vec2<f32>(time, block)) - 0.5) * p1 * 0.08 * trigger;
    let warpedUV = clamp(uv + vec2<f32>(offset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let ca = chromaticAberration(warpedUV, p3 * 0.006 * (1.0 + bass) + depth * 0.002);
    let holo = (0.5 + 0.5 * cos(vec3<f32>(time + uv.x * 6.0, time + uv.x * 6.0 + 2.094, time + uv.x * 6.0 + 4.189))) * p2;
    let scan = sin(uv.y * res.y * 0.7 + time * (1.0 + p4 * 9.0) * (1.0 + treble)) * 0.07;
    let flick = 1.0 - p4 * 0.35 * hash21(uv + time);
    let rim = fresnelRim(uv, 0.08, 2.2) * p2 * (0.4 + bass * 0.4);

    var color = mix(ca, holo + scan + rim, p2 * flick);
    color = splitTone(color, vec3<f32>(0.65, 0.95, 1.05), vec3<f32>(1.15, 0.92, 0.68), p4 * 0.45);
    color = acesToneMap(color * (0.9 + mids * 0.25));
    color += (ign(vec2<f32>(global_id.xy)) - 0.5) / 255.0;
    color += filmGrain(uv, time, p1 * 0.03);
    color = huePreserveClamp(color);

    let depthAlpha = mix(0.35, 0.95, depth);
    let alpha = clamp(luma(color) * 0.8 * (1.0 + p2) * depthAlpha, 0.1, 0.98);
    let trail = mix(prev.rgb * (0.94 - p4 * 0.04), color, 0.25 + bass * 0.1);

    textureStore(writeTexture, pixel, vec4<f32>(trail, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(trail, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
