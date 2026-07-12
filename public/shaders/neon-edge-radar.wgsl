// ═══════════════════════════════════════════════════════════════════
//  Neon Edge Radar
//  Category: interactive-mouse
//  Features: upgraded-rgba, radar-sweep, edge-detection, mouse-driven, audio-reactive, aces-tone-map, ign-dither, depth-aware
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
fn luma(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722)); }
fn edgeMetric(uv: vec2<f32>, ps: vec2<f32>) -> f32 {
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let dx = vec2<f32>(ps.x, 0.0); let dy = vec2<f32>(0.0, ps.y);
    let dR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + dx, 0.0).r;
    let dL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - dx, 0.0).r;
    let dU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + dy, 0.0).r;
    let dD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - dy, 0.0).r;
    let depthEdge = length(vec2<f32>(dR - dL, dU - dD));
    let lR = luma(textureSampleLevel(readTexture, u_sampler, uv + dx, 0.0).rgb);
    let lL = luma(textureSampleLevel(readTexture, u_sampler, uv - dx, 0.0).rgb);
    let lU = luma(textureSampleLevel(readTexture, u_sampler, uv + dy, 0.0).rgb);
    let lD = luma(textureSampleLevel(readTexture, u_sampler, uv - dy, 0.0).rgb);
    let lumaEdge = length(vec2<f32>(lR - lL, lU - lD));
    return smoothstep(0.02, 0.25, lumaEdge + depthEdge * 2.0);
}
fn neonSpectrum(t: f32) -> vec3<f32> { return 0.5 + 0.5 * cos(vec3<f32>(t, t + 2.094, t + 4.189)); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
    let uv = vec2<f32>(pixel) / res;
    let ps = 1.0 / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mouse = u.zoom_config.yz;

    let p1 = clamp(u.zoom_params.x, 0.0, 1.0);
    let p2 = clamp(u.zoom_params.y, 0.0, 1.0);
    let p3 = clamp(u.zoom_params.z, 0.0, 1.0);
    let p4 = clamp(u.zoom_params.w, 0.0, 1.0);

    let threshold = mix(0.02, 0.3, p1);
    let radarSpeed = p2 * 2.0 * (1.0 + bass * 0.5);
    let sweepWidth = mix(0.05, 0.5, p3);
    let intensity = p4 * 3.0;

    let centered = uv - mix(vec2<f32>(0.5), mouse, 0.6);
    let angle = atan2(centered.y, centered.x);
    let sweepAngle = fract(time * radarSpeed) * TAU - PI;
    let diff = abs(fract((angle - sweepAngle) / TAU + 0.5) - 0.5) * TAU;
    let sweep = exp(-diff * diff / (sweepWidth * sweepWidth));

    let edgeRaw = edgeMetric(uv, ps);
    let edge = smoothstep(threshold, threshold + 0.05, edgeRaw);
    let hue = time * 0.3 + bass * 0.5 + fbm(uv * 3.0 + time * 0.1, 3) * 0.4;
    let neon = neonSpectrum(hue) * intensity;
    let emission = neon * edge * sweep;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let energy = edge * sweep * intensity;
    let alpha = clamp(energy * (0.6 + depth * 0.4), 0.0, 0.98);

    var color = acesToneMap(emission * (1.0 + bass));
    color += (ign(vec2<f32>(global_id.xy)) - 0.5) / 255.0;

    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
