// ═══════════════════════════════════════════════════════════════════
//  VHS Tracking
//  Category: retro-glitch
//  Features: vhs-tracking, chromatic-noise, tape-warp, scan-lines
//  Complexity: Medium
//  Created: 2026-05-31
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

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash1(n: f32) -> f32 {
    return fract(sin(n * 43758.5453) * 127.1);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let trackingIntensity = u.zoom_params.x;
    let chromaticNoise = u.zoom_params.y * 0.06;
    let warpAmount = u.zoom_params.z;
    let staticAmount = u.zoom_params.w;

    // VHS tape warp: sinusoidal vertical distortion
    let warpPhase = uv.y * 8.0 + time * 3.0;
    let trackingWarp = sin(warpPhase) * warpAmount * 0.02 * trackingIntensity;

    // Occasional tracking glitch bands
    let bandNoise = hash1(floor(uv.y * 40.0) + floor(time * 6.0) * 73.0);
    let bandOffset = select(0.0, (bandNoise - 0.5) * trackingIntensity * 0.06, bandNoise > 0.93);

    // Horizontal jitter
    let jitterSeed = floor(time * 30.0);
    let jitter = (hash1(jitterSeed) - 0.5) * trackingIntensity * 0.005;

    var displacedUV = uv;
    displacedUV.x += trackingWarp + bandOffset + jitter;

    // Vertical tracking roll (periodic full-frame shift)
    let rollPhase = fract(time * 0.15);
    let rollOffset = smoothstep(0.85, 1.0, rollPhase) * trackingIntensity * 0.3;
    displacedUV.y += rollOffset;
    displacedUV.y = fract(displacedUV.y);

    // VHS chromatic aberration (stronger than modern lens)
    let rUv = clamp(displacedUV + vec2<f32>(chromaticNoise * trackingIntensity, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let gUv = displacedUV;
    let bUv = clamp(displacedUV - vec2<f32>(chromaticNoise * trackingIntensity, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    var r = textureSampleLevel(readTexture, u_sampler, rUv, 0.0).r;
    var g = textureSampleLevel(readTexture, u_sampler, gUv, 0.0).g;
    var b = textureSampleLevel(readTexture, u_sampler, bUv, 0.0).b;

    // VHS color bleeding (horizontal smear on saturated areas)
    let bleedAmount = chromaticNoise * 0.03 * trackingIntensity;
    for (var i: i32 = 1; i <= 4; i = i + 1) {
        let offset = f32(i) * bleedAmount;
        let weight = 0.15 / f32(i);
        r += textureSampleLevel(readTexture, u_sampler, clamp(rUv + vec2<f32>(offset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r * weight;
        b += textureSampleLevel(readTexture, u_sampler, clamp(bUv - vec2<f32>(offset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b * weight;
    }

    var color = vec3<f32>(r, g, b);

    // VHS scanlines
    let scanLine = sin(uv.y * resolution.y * 0.5) * 0.5 + 0.5;
    color *= mix(1.0, scanLine * 0.3 + 0.7, trackingIntensity * 0.6);

    // VHS static noise
    let staticNoise = hash(uv * resolution + fract(time * 43.0) * 100.0) - 0.5;
    color += staticNoise * staticAmount * trackingIntensity * 0.2;

    // VHS saturation boost (characteristic oversaturated look)
    let luminance = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    color = mix(vec3<f32>(luminance), color, 1.0 + trackingIntensity * 0.4);

    // Occasional dropout (snow band)
    let dropoutSeed = hash1(floor(uv.y * 100.0) + floor(time * 4.0) * 91.0);
    if (dropoutSeed > 0.98) {
        let snow = hash(uv * 50.0 + time);
        color = mix(color, vec3<f32>(snow), 0.7);
    }

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
