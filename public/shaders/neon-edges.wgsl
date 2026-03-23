// ═══════════════════════════════════════════════════════════════════════════════
//  Neon Edges - Advanced Alpha with Edge-Preserve
//  Category: edge-detection
//  Alpha Mode: Edge-Preserve Alpha
//  Features: advanced-alpha, edge-detection, neon-glow
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

// Mode 2: Edge-Preserve Alpha
fn edgePreserveAlpha(
    uv: vec2<f32>,
    pixelSize: vec2<f32>,
    edgeThreshold: f32,
    colorSensitivity: f32
) -> f32 {
    // Depth edge detection
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let dR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let dL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let dU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0).r;
    let dD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, pixelSize.y), 0.0).r;
    
    let depthEdge = length(vec2<f32>(dR - dL, dU - dD));
    
    // Color edge detection
    let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let cR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).rgb;
    let cL = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).rgb;
    let colorEdge = length(cR - cL) + length(c - cR) + length(c - cL);
    
    // Combine edges
    let totalEdge = depthEdge * 2.0 + colorEdge * colorSensitivity;
    
    // Edge = opaque, smooth = transparent
    let edgeMask = smoothstep(edgeThreshold * 0.5, edgeThreshold, totalEdge);
    return mix(0.2, 1.0, edgeMask);
}

// Mode 6: Luminance Key Alpha for glow
fn luminanceKeyAlpha(color: vec3<f32>, threshold: f32, softness: f32) -> f32 {
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    return smoothstep(threshold - softness, threshold + softness, luma);
}

// Combined alpha for neon edges
fn calculateNeonAlpha(
    color: vec3<f32>,
    uv: vec2<f32>,
    pixelSize: vec2<f32>,
    params: vec4<f32>
) -> f32 {
    // params.x = edge threshold
    // params.y = luminance threshold
    // params.z = softness
    
    let edgeAlpha = edgePreserveAlpha(uv, pixelSize, params.x, 2.0);
    let lumaAlpha = luminanceKeyAlpha(color, params.y, params.z);
    
    // Combine: edges are always visible, but luminance controls intensity
    return clamp(edgeAlpha * (0.5 + 0.5 * lumaAlpha), 0.0, 1.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let pixelSize = 1.0 / resolution;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.zoom_config.x;
    let audioBass = audioOverall * 1.5;
    let audioReactivity = 1.0 + audioOverall * 0.3;
    
    // Parameters
    let edgeThreshold = u.zoom_params.x * 0.1 + 0.02;
    let glowIntensity = u.zoom_params.y * 3.0;
    let lumaThreshold = u.zoom_params.z;
    let softness = u.zoom_params.w * 0.1;
    
    // Sobel edge detection
    let stepX = pixelSize.x;
    let stepY = pixelSize.y;
    
    let t_l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-stepX, -stepY), 0.0).rgb;
    let t_c = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -stepY), 0.0).rgb;
    let t_r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(stepX, -stepY), 0.0).rgb;
    let m_l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-stepX, 0.0), 0.0).rgb;
    let m_r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(stepX, 0.0), 0.0).rgb;
    let b_l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-stepX, stepY), 0.0).rgb;
    let b_c = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, stepY), 0.0).rgb;
    let b_r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(stepX, stepY), 0.0).rgb;
    
    // Calculate luminance
    fn luma(c: vec3<f32>) -> f32 {
        return dot(c, vec3<f32>(0.299, 0.587, 0.114));
    }
    
    let gx = -1.0 * luma(t_l) - 2.0 * luma(m_l) - 1.0 * luma(b_l) +
              1.0 * luma(t_r) + 2.0 * luma(m_r) + 1.0 * luma(b_r);
    
    let gy = -1.0 * luma(t_l) - 2.0 * luma(t_c) - 1.0 * luma(t_r) +
              1.0 * luma(b_l) + 2.0 * luma(b_c) + 1.0 * luma(b_r);
    
    let edgeStrength = sqrt(gx * gx + gy * gy);
    
    // Neon color with time variation
    let neonColor = vec3<f32>(
        0.5 + 0.5 * sin(time + 0.0),
        0.5 + 0.5 * sin(time + 2.09),
        0.5 + 0.5 * sin(time + 4.18)
    );
    
    // Apply edge strength to neon
    var emission = vec3<f32>(0.0);
    if (edgeStrength > 0.02) {
        let edge = smoothstep(0.02, 0.2, edgeStrength);
        emission = neonColor * edge * glowIntensity;
    }
    
    // ═══ ADVANCED ALPHA CALCULATION ═══
    let alpha = calculateNeonAlpha(emission, uv, pixelSize, u.zoom_params);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(emission, alpha));
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
