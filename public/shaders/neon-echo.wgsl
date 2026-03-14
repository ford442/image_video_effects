// ═══════════════════════════════════════════════════════════════
//  Neon Echo - Echo Trail Effect with Alpha Emission
//  Category: lighting-effects
//  Physics: Persistent echo trails with emissive decay
//  Alpha: Core echo = 0.3, Glow = 0.0 (additive)
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

// Helper for hue rotation
fn hueShift(color: vec3<f32>, shift: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cosAngle = cos(shift * 6.28318);
    return vec3<f32>(color * cosAngle + cross(k, color) * sin(shift * 6.28318) + k * dot(k, color) * (1.0 - cosAngle));
}

// Alpha calculation for emissive materials
fn calculateEmissiveAlpha(glowIntensity: f32, occlusionBalance: f32) -> f32 {
    let coreAlpha = 0.3 * glowIntensity;
    let glowAlpha = 0.0;
    return mix(glowAlpha, coreAlpha, clamp(glowIntensity, 0.0, 1.0) * occlusionBalance);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    // x: decay, y: threshold, z: hueParam, w: occlusionBalance
    let decay = u.zoom_params.x;
    let threshold = u.zoom_params.y;
    let hueParam = u.zoom_params.z;
    let occlusionBalance = u.zoom_params.w;

    // Current Frame
    let currentColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // History Frame (Previous state)
    let historyColor = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);

    // Calculate Luminance/Edge
    let luma = dot(currentColor.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Simple neighbor sampling for edge detection
    let offset = 1.0 / resolution;
    let left = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-offset.x, 0.0), 0.0);
    let right = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(offset.x, 0.0), 0.0);
    let up = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -offset.y), 0.0);
    let down = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, offset.y), 0.0);

    let edgeX = length(right.rgb - left.rgb);
    let edgeY = length(down.rgb - up.rgb);
    let edgeStrength = sqrt(edgeX * edgeX + edgeY * edgeY);

    // Determine if we should spawn a new "echo" pixel
    var newEcho = vec3<f32>(0.0);

    if (edgeStrength > threshold) {
        // Calculate dynamic color based on Mouse Pos and Time
        let mouseX = u.zoom_config.y;
        let mouseY = u.zoom_config.z;
        let distToMouse = distance(uv, vec2<f32>(mouseX, mouseY));

        // Base color cycles over time and space
        let baseHue = hueParam + u.config.x * 0.1 + distToMouse;
        let tint = hueShift(vec3<f32>(1.0, 0.0, 0.0), baseHue);

        newEcho = currentColor.rgb * tint * 3.0; // Boost brightness for HDR emission
    }

    // Combine history with decay
    let fadedHistory = historyColor.rgb * (1.0 - decay * 0.1);

    // Add new echo (use max to keep bright trails)
    let resultRGB = max(fadedHistory, newEcho);

    // Calculate alpha based on emission intensity
    let glowIntensity = length(resultRGB);
    let finalAlpha = calculateEmissiveAlpha(glowIntensity, occlusionBalance);

    let resultColor = vec4<f32>(resultRGB, max(historyColor.a * (1.0 - decay * 0.05), length(newEcho) * 0.5));

    // Write to history buffer for next frame
    textureStore(dataTextureA, global_id.xy, resultColor);

    // Write to display with emission alpha
    // Screen blend for glow effect
    let displayColor = resultRGB * 1.5; // Boost for HDR emission

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(displayColor, finalAlpha));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
