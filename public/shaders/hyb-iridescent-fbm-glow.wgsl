// ═══════════════════════════════════════════════════════════════════
//  hyb-iridescent-fbm-glow
//  Category: hybrid
//  Features: upgraded-rgba, fbm-noise, iridescence, image-glow, domain-warp, audio-reactive, aces-tone-map, ign-dither, depth-aware
//  Complexity: Medium
//  Upgraded: 2026-07-12
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
fn fbm(p: vec2<f32>, oct: i32) -> f32 { var s = 0.0; var a = 0.5; var f = 1.0; for (var i = 0; i < oct; i++) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; } return s; }
fn acesToneMap(x: vec3<f32>) -> vec3<f32> { return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0)); }
fn ign(p: vec2<f32>) -> f32 { return fract(52.9829181 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715)))); }
fn iridescence(theta: f32, shift: f32) -> vec3<f32> { let t = theta * 4.0 + shift; return 0.5 + 0.5 * cos(vec3<f32>(t, t + 2.094, t + 4.189)); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
    let uv = (vec2<f32>(pixel) + 0.5) / res;
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;

    let p1 = clamp(u.zoom_params.x, 0.0, 1.0);
    let p2 = clamp(u.zoom_params.y, 0.0, 1.0);
    let p3 = clamp(u.zoom_params.z, 0.0, 1.0);
    let p4 = clamp(u.zoom_params.w, 0.0, 1.0);

    let fbmScale = mix(1.5, 18.0, p1);
    let octaves = i32(mix(2.0, 7.0, p2));
    let shiftSpeed = mix(0.0, 3.0, p3);
    let glowMix = p4;

    let q = vec2<f32>(
        fbm(uv * fbmScale + vec2<f32>(time * 0.07 * (1.0 + bass * 0.3), 0.0), octaves),
        fbm(uv * fbmScale + vec2<f32>(5.2, 1.3 + time * 0.07), octaves)
    );
    let warped = uv * fbmScale + 4.0 * q + vec2<f32>(time * 0.05);
    let noise = fbm(warped, octaves);
    let ird = iridescence(noise, time * shiftSpeed);
    let glowLayer = ird * noise * noise;

    let depthFog = exp(-depth * 2.0);
    let glow = glowLayer * glowMix * (1.0 + bass * 0.5) * depthFog;
    var outRGB = mix(src.rgb, src.rgb + glow, glowMix);
    outRGB = acesToneMap(outRGB);
    outRGB += (ign(vec2<f32>(global_id.xy)) - 0.5) / 255.0;

    let energy = length(glow) * 0.5;
    let alpha = clamp(src.a + energy * (1.0 - depth * 0.3), 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(outRGB, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(outRGB, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
