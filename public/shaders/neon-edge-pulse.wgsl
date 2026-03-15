// ═══════════════════════════════════════════════════════════════
//  Neon Edge Pulse - Pulsing Edges with Alpha Emission
//  Category: lighting-effects
//  Physics: Time-pulsing emissive edges with alpha occlusion
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

// Alpha calculation for emissive materials
fn calculateEmissiveAlpha(glowIntensity: f32, occlusionBalance: f32) -> f32 {
    let coreAlpha = 0.3 * glowIntensity;
    let glowAlpha = 0.0;
    return mix(glowAlpha, coreAlpha, clamp(glowIntensity, 0.0, 1.0) * occlusionBalance);
}

// Inverse square law for light falloff
fn inverseSquareFalloff(dist: f32, maxDist: f32) -> f32 {
    let d = max(dist, 0.001);
    return 1.0 / (1.0 + d * d * 5.0) * smoothstep(maxDist, 0.0, dist);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Params
    // x: edgeThreshold, y: pulseSpeed, z: glowIntensity, w: occlusionBalance
    let edgeThreshold = u.zoom_params.x;
    let pulseSpeed = u.zoom_params.y * 5.0;
    let glowIntensity = u.zoom_params.z * 5.0;
    let colorShift = 0.5;
    let occlusionBalance = u.zoom_params.w;

    // Mouse
    var mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Sobel Kernels
    let stepX = 1.0 / resolution.x;
    let stepY = 1.0 / resolution.y;

    let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -stepY), 0.0).rgb;
    let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, stepY), 0.0).rgb;
    let l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-stepX, 0.0), 0.0).rgb;
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(stepX, 0.0), 0.0).rgb;

    let gradX = r - l;
    let gradY = b - t;

    let edge = sqrt(gradX * gradX + gradY * gradY);
    let edgeMag = length(edge);

    // Pulse
    let pulse = (sin(time * pulseSpeed - dist * 10.0) + 1.0) * 0.5;

    // Emission calculation
    var emission = vec3<f32>(0.0);
    
    // Only apply neon if edge is strong enough
    if (edgeMag > edgeThreshold * 0.2) {
        // Neon color generation
        let hue = fract(time * 0.1 + colorShift + dist * 0.5);
        let neon = vec3<f32>(
            0.5 + 0.5 * cos(6.28318 * (hue + 0.0)),
            0.5 + 0.5 * cos(6.28318 * (hue + 0.33)),
            0.5 + 0.5 * cos(6.28318 * (hue + 0.67))
        );

        // Intensity increases near mouse (flashlight)
        let mouseFactor = 1.0 / (dist * 5.0 + 0.2);
        let falloff = inverseSquareFalloff(dist, 0.5);

        emission = neon * edgeMag * glowIntensity * pulse * mouseFactor * (1.0 + falloff);
    }

    // Calculate alpha based on emission intensity
    let glowStrength = length(emission);
    let finalAlpha = calculateEmissiveAlpha(glowStrength, occlusionBalance);

    // Output with emission alpha
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(emission, finalAlpha));
}
