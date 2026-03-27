// ═══════════════════════════════════════════════════════════════════════════════
//  Neon Pulse - Advanced Alpha with Luminance Key
//  Category: glow/light-effects
//  Alpha Mode: Luminance Key Alpha + Depth-Layered
//  Features: advanced-alpha, pulsing-glow, rhythm-reactive
// ═══════════════════════════════════════════════════════════════════════════════

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

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 6: Luminance Key Alpha
fn luminanceKeyAlpha(color: vec3<f32>, threshold: f32, softness: f32) -> f32 {
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    return smoothstep(threshold - softness, threshold + softness, luma);
}

// Mode 1: Depth-Layered Alpha
fn depthLayeredAlpha(uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthAlpha = mix(0.4, 1.0, depth);
    return mix(1.0, depthAlpha, depthWeight);
}

// Combined alpha
fn calculatePulseAlpha(
    color: vec3<f32>,
    uv: vec2<f32>,
    pulseIntensity: f32,
    params: vec4<f32>
) -> f32 {
    let lumaAlpha = luminanceKeyAlpha(color, params.y, params.z * 0.2);
    let depthAlpha = depthLayeredAlpha(uv, params.z);
    return clamp(lumaAlpha * depthAlpha * pulseIntensity, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.zoom_config.x;
    let audioBass = audioOverall * 1.5;
    let audioReactivity = 1.0 + audioOverall * 0.3;
    
    // Parameters
    let pulseSpeed = u.zoom_params.x * 10.0;
    let pulseIntensity = u.zoom_params.y;
    let lumaThreshold = u.zoom_params.z * 0.5;
    let depthWeight = u.zoom_params.w;
    
    // Pulse wave
    let pulse = 0.5 + 0.5 * sin(time * pulseSpeed * audioReactivity);
    
    // Grid of neon pulses
    let gridUV = uv * 10.0;
    let gridCell = floor(gridUV);
    let gridFrac = fract(gridUV);
    
    // Distance from cell center
    let cellCenter = 0.5;
    let distFromCenter = length(gridFrac - vec2<f32>(cellCenter));
    
    // Pulse radius
    let pulseRadius = 0.3 + pulse * 0.2;
    let cellPulse = smoothstep(pulseRadius, 0.0, distFromCenter);
    
    // Neon color per cell
    let cellHash = fract(sin(dot(gridCell, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let neonColor = vec3<f32>(
        0.5 + 0.5 * sin(cellHash * 6.28),
        0.5 + 0.5 * sin(cellHash * 6.28 + 2.09),
        0.5 + 0.5 * sin(cellHash * 6.28 + 4.18)
    );
    
    let finalColor = neonColor * cellPulse * pulseIntensity;
    
    // ═══ ADVANCED ALPHA CALCULATION ═══
    let alpha = calculatePulseAlpha(finalColor, uv, cellPulse * pulseIntensity, u.zoom_params);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
