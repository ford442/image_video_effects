// ═══════════════════════════════════════════════════════════════
//  Neon Edge Radar - Radar Sweep with Alpha Emission
//  Category: lighting-effects
//  Physics: Rotating radar beam with emissive edge detection
//  Alpha: Core beam = 0.3, Glow = 0.0 (additive)
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Parameters
    // x: beamSpeed, y: beamWidth, z: edgeThreshold, w: occlusionBalance
    let beamSpeed = u.zoom_params.x * 3.0;
    let beamWidth = u.zoom_params.y;
    let edgeThreshold = u.zoom_params.z;
    let occlusionBalance = u.zoom_params.w;

    // Mouse position
    var mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let aspectCorrection = vec2<f32>(aspect, 1.0);

    // --- Edge Detection (Sobel-like) ---
    let texel = 1.0 / resolution;
    let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).rgb;
    let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).rgb;
    let l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).rgb;
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).rgb;

    // Calculate gradients
    let gradX = length(r - l);
    let gradY = length(b - t);
    let edgeStrength = sqrt(gradX * gradX + gradY * gradY);

    // Apply threshold
    let threshold = 0.05 + (1.0 - edgeThreshold) * 0.5;
    let isEdge = smoothstep(threshold, threshold + 0.1, edgeStrength);

    // --- Radar Beam Logic ---
    let diff = (uv - mousePos) * aspectCorrection;
    let dist = length(diff);
    let angle = atan2(diff.y, diff.x);

    // Rotating beam angle
    let beamAngle = (time * beamSpeed * 2.0) % 6.28318;
    var currentAngle = angle;
    if (currentAngle < 0.0) { currentAngle = currentAngle + 6.28318; }

    var targetAngle = beamAngle;
    if (targetAngle < 0.0) { targetAngle = targetAngle + 6.28318; }

    // Calculate angular distance
    var angleDiff = abs(currentAngle - targetAngle);
    if (angleDiff > 3.14159) { angleDiff = 6.28318 - angleDiff; }

    // Beam intensity based on angle difference
    let width = 0.1 + beamWidth * 0.5;
    let beam = 1.0 - smoothstep(0.0, width, angleDiff);

    // Add a "scanline" pulse effect radiating out
    let ring = fract(dist * 5.0 - time * beamSpeed);
    let ringIntensity = smoothstep(0.8, 1.0, ring) * 0.5;

    // --- Compose Emission ---
    // Neon edge color (cyan/magenta mix based on angle)
    let neonColor = vec3<f32>(
        0.5 + 0.5 * sin(angle + time),
        0.8,
        0.5 + 0.5 * cos(angle - time)
    );

    // Apply beam to edges for emission
    let totalLight = beam + ringIntensity;
    var emission = vec3<f32>(0.0);
    
    if (isEdge > 0.1) {
        emission = neonColor * isEdge * totalLight * 3.0; // HDR boost
    }

    // Also light up the beam itself slightly
    emission += neonColor * beam * 0.2;

    // Calculate alpha based on emission intensity
    let glowIntensity = length(emission);
    let finalAlpha = calculateEmissiveAlpha(glowIntensity, occlusionBalance);

    // Output with emission alpha
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(emission, finalAlpha));

    // Clear depth
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
