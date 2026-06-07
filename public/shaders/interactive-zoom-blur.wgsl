// ═══════════════════════════════════════════════════════════════════
//  Interactive Zoom Blur
//  Category: image
//  Features: mouse-centered, chromatic-aberration, dithered-sampling, audio-reactive,
//            temporal-blur-trail, chromatic-radial-streaks, depth-blur-attenuation
//  Complexity: Medium
//  Upgraded: 2026-05-31
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

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn hash11(p: f32) -> f32 {
    return fract(sin(p * 12.9898) * 43758.5453);
}

fn bayer(x: i32, y: i32) -> f32 {
    let matrix = array<f32, 16>(
        0.0, 0.5, 0.125, 0.625,
        0.75, 0.25, 0.875, 0.375,
        0.1875, 0.6875, 0.0625, 0.5625,
        0.9375, 0.4375, 0.8125, 0.3125
    );
    return matrix[(y % 4) * 4 + (x % 4)];
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let center = u.zoom_config.yz;
    let strength = u.zoom_params.x * (1.0 + bass * 0.25);
    let chromatic = u.zoom_params.y;
    let sampleCount = u.zoom_params.z;
    let depthAttenuation = u.zoom_params.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let dir = uv - center;
    let dist = length(dir);
    let dirNorm = normalize(dir + vec2<f32>(1e-4));

    // Depth-scaled blur attenuation: deeper pixels blur less
    let attenuatedStrength = strength * (1.0 - depth * depthAttenuation);

    let samples = i32(sampleCount * 30.0 + 5.0);
    let dither = bayer(i32(global_id.x), i32(global_id.y)) / f32(samples);

    // Chromatic radial streak separation
    let rSpread = chromatic * 0.008 * (1.0 + treble * 0.3);
    let gSpread = chromatic * 0.008;
    let bSpread = chromatic * 0.008 * (1.0 - bass * 0.2);

    var rAcc = vec3<f32>(0.0);
    var gAcc = vec3<f32>(0.0);
    var bAcc = vec3<f32>(0.0);

    for (var i: i32 = 0; i < samples; i = i + 1) {
        let t = (f32(i) + dither) / f32(samples);
        let rT = t + rSpread * t;
        let gT = t;
        let bT = t - bSpread * t;
        rAcc += textureSampleLevel(readTexture, u_sampler, clamp(center + dir * (1.0 + rT * attenuatedStrength), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        gAcc += textureSampleLevel(readTexture, u_sampler, clamp(center + dir * (1.0 + gT * attenuatedStrength), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        bAcc += textureSampleLevel(readTexture, u_sampler, clamp(center + dir * (1.0 + bT * attenuatedStrength), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    }
    let invSamples = 1.0 / f32(samples);
    rAcc *= invSamples;
    gAcc *= invSamples;
    bAcc *= invSamples;

    var color = vec3<f32>(rAcc.r, gAcc.g, bAcc.b);

    // Temporal blur trail persistence
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let trail = mix(color, prev * 0.88, 0.05 + mids * 0.02);
    color = mix(color, trail, 0.3);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let effectBlend = smoothstep(0.0, 1.0, dist * attenuatedStrength);
    color = mix(baseColor.rgb, color, effectBlend);

    let alpha = mix(baseColor.a, 1.0, effectBlend * 0.5);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0, 0, 1));
}
