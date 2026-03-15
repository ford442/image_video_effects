// ═══════════════════════════════════════════════════════════════
//  Edge Glow Mouse - Mouse-Driven Edge Glow with Alpha Emission
//  Category: lighting-effects
//  Physics: Mouse-proximity emissive edge glow with alpha occlusion
//  Alpha: Core edge = 0.3, Glow = 0.0 (additive)
// ═══════════════════════════════════════════════════════════════

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

fn getLuminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn sobel(uv: vec2<f32>, step: vec2<f32>) -> f32 {
    let t = getLuminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -step.y), 0.0).rgb);
    let b = getLuminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, step.y), 0.0).rgb);
    let l = getLuminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-step.x, 0.0), 0.0).rgb);
    let r = getLuminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(step.x, 0.0), 0.0).rgb);

    let gx = -l + r;
    let gy = -t + b;

    return sqrt(gx*gx + gy*gy);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    var p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

// Alpha calculation for emissive materials
fn calculateEmissiveAlpha(glowIntensity: f32, occlusionBalance: f32) -> f32 {
    let coreAlpha = 0.3 * glowIntensity;
    let glowAlpha = 0.0;
    return mix(glowAlpha, coreAlpha, clamp(glowIntensity, 0.0, 1.0) * occlusionBalance);
}

// Inverse square law for light falloff
fn inverseSquareFalloff(dist: f32, maxDist: f32) -> f32 {
    let d = max(dist, 0.001);
    return 1.0 / (1.0 + d * d * 4.0) * smoothstep(maxDist, 0.0, dist);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let step = 1.0 / resolution;

    // Params
    // x: threshold, y: glowRadius, z: intensity, w: occlusionBalance
    let threshold = u.zoom_params.x;
    let glowRadius = u.zoom_params.y;
    let intensity = u.zoom_params.z * 5.0;
    let colorSpeed = 0.5;
    let occlusionBalance = u.zoom_params.w;

    // Mouse
    var mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let aspectVec = vec2<f32>(aspect, 1.0);

    let dist = distance(uv * aspectVec, mouse * aspectVec);

    // Edge Detection
    let edgeVal = sobel(uv, step);
    let edge = smoothstep(threshold, threshold + 0.1, edgeVal);

    // Mouse Influence Mask - 1.0 at mouse, 0.0 at radius
    let mask = smoothstep(glowRadius, 0.0, dist);

    // Glow Color
    let hue = fract(u.config.x * colorSpeed + dist);
    let glowColor = hsv2rgb(vec3<f32>(hue, 1.0, 1.0));

    // Emission calculation with inverse square falloff
    let falloff = inverseSquareFalloff(dist, glowRadius * 1.5);
    let emission = glowColor * edge * intensity * mask * (1.0 + falloff * 2.0);

    // Calculate alpha based on emission intensity
    let glowStrength = length(emission);
    let finalAlpha = calculateEmissiveAlpha(glowStrength, occlusionBalance);

    // Output with emission alpha
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(emission, finalAlpha));

    // Passthrough Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
