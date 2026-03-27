// ═══════════════════════════════════════════════════════════════════════════════
//  Holographic Prism - Advanced Alpha with Depth-Layered
//  Category: complex-multi-effect
//  Alpha Mode: Depth-Layered Alpha + Luminance Key
//  Features: advanced-alpha, holographic, prism-diffraction
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

// Mode 1: Depth-Layered Alpha
fn depthLayeredAlpha(color: vec3<f32>, uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    
    let depthAlpha = mix(0.3, 1.0, depth);
    let lumaAlpha = mix(0.4, 1.0, luma);
    
    return mix(lumaAlpha, depthAlpha, depthWeight);
}

// Mode 6: Luminance Key Alpha
fn luminanceKeyAlpha(color: vec3<f32>, threshold: f32, softness: f32) -> f32 {
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    return smoothstep(threshold - softness, threshold + softness, luma);
}

// Combined alpha
fn calculateHolographicAlpha(
    color: vec3<f32>,
    uv: vec2<f32>,
    params: vec4<f32>
) -> f32 {
    let depthAlpha = depthLayeredAlpha(color, uv, params.z);
    let lumaAlpha = luminanceKeyAlpha(color, params.y * 0.5, params.w * 0.2);
    return clamp(depthAlpha * lumaAlpha, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let prismAngle = u.zoom_params.x * 6.28;
    let dispersion = u.zoom_params.y;
    let depthWeight = u.zoom_params.z;
    let holographicIntensity = u.zoom_params.w;
    
    // Sample depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Prism diffraction
    let centered = uv - 0.5;
    let angle = atan2(centered.y, centered.x) + prismAngle;
    let dist = length(centered);
    
    // Rainbow dispersion
    let rainbowPhase = angle * 3.0 + time * 0.5;
    let rainbow = vec3<f32>(
        0.5 + 0.5 * sin(rainbowPhase),
        0.5 + 0.5 * sin(rainbowPhase + 2.09),
        0.5 + 0.5 * sin(rainbowPhase + 4.18)
    );
    
    // Chromatic aberration
    let rOffset = centered * (1.0 - dispersion * 0.1);
    let gOffset = centered;
    let bOffset = centered * (1.0 + dispersion * 0.1);
    
    let r = textureSampleLevel(readTexture, u_sampler, rOffset + 0.5, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gOffset + 0.5, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bOffset + 0.5, 0.0).b;
    
    let prismColor = vec3<f32>(r, g, b);
    
    // Holographic overlay
    let holographic = rainbow * holographicIntensity * (1.0 - dist * 2.0);
    let finalColor = mix(prismColor, holographic, holographicIntensity * 0.3);
    
    // ═══ ADVANCED ALPHA CALCULATION ═══
    let alpha = calculateHolographicAlpha(finalColor, uv, u.zoom_params);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    
    // Pass through depth
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
