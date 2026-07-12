// ═══════════════════════════════════════════════════════════════════
//  Thermal Vision
//  Category: artistic
//  Features: upgraded-rgba, thermal, color-remap, audio-reactive, depth-aware, aces-tone-map, ign-dither
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
fn sampleLuma(uv: vec2<f32>) -> f32 { return luma(textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb); }
fn thermal_gradient(t: f32) -> vec3<f32> {
    let c0 = mix(vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(0.0, 0.0, 1.0), clamp(t * 5.0, 0.0, 1.0));
    let c1 = mix(vec3<f32>(0.0, 0.0, 1.0), vec3<f32>(1.0, 0.0, 1.0), clamp((t - 0.2) * 5.0, 0.0, 1.0));
    let c2 = mix(vec3<f32>(1.0, 0.0, 1.0), vec3<f32>(1.0, 0.0, 0.0), clamp((t - 0.4) * 5.0, 0.0, 1.0));
    let c3 = mix(vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(1.0, 1.0, 0.0), clamp((t - 0.6) * 5.0, 0.0, 1.0));
    let c4 = mix(vec3<f32>(1.0, 1.0, 0.0), vec3<f32>(1.0, 1.0, 1.0), clamp((t - 0.8) * 5.0, 0.0, 1.0));
    var color = c0;
    color = mix(color, c1, step(0.2, t));
    color = mix(color, c2, step(0.4, t));
    color = mix(color, c3, step(0.6, t));
    color = mix(color, c4, step(0.8, t));
    return color;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
    let uv = vec2<f32>(pixel) / res;
    let time = u.config.x;
    let texel = 1.0 / res;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    let p1 = clamp(u.zoom_params.x, 0.0, 1.0);
    let p2 = clamp(u.zoom_params.y, 0.0, 1.0);
    let p3 = clamp(u.zoom_params.z, 0.0, 1.0);
    let p4 = clamp(u.zoom_params.w, 0.0, 1.0);

    let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureLoad(readDepthTexture, pixel, 0).r;

    let sensitivity = mix(0.5, 3.0, p1) * (1.0 + bass * 0.2);
    let colorRange = p2;
    let sensorNoise = p3 * (1.0 + mids * 0.25);
    let thermalBlur = p4;

    let l = sampleLuma(uv);
    let blurredLuma = mix(l, (l + sampleLuma(uv + vec2<f32>(texel.x, 0.0)) + sampleLuma(uv - vec2<f32>(texel.x, 0.0)) + sampleLuma(uv + vec2<f32>(0.0, texel.y)) + sampleLuma(uv - vec2<f32>(0.0, texel.y))) / 5.0, thermalBlur);
    let drift = 0.6 + treble * 1.6;
    let n = fbm(uv * res * 0.04 + vec2<f32>(time * drift, -time * drift * 0.6), 4) - 0.5;
    let heat = clamp((blurredLuma + n * sensorNoise) * sensitivity, 0.0, 1.0);
    let thermalColor = thermal_gradient(pow(heat, mix(1.5, 0.55, colorRange)));
    let hotspot = smoothstep(0.75, 1.0, heat) * (0.15 + treble * 0.1);
    var color = mix(base.rgb * 0.25, thermalColor, 0.85) + vec3<f32>(hotspot);

    let depthFade = exp(-depth * 1.5);
    color = acesToneMap(color * (1.0 + bass * 0.2) * depthFade);
    color += (ign(vec2<f32>(global_id.xy)) - 0.5) / 255.0;

    let alpha = clamp(base.a * 0.4 + heat * 0.4 + bass * 0.05, 0.1, 1.0);
    let outDepth = clamp(depth + heat * 0.04, 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
