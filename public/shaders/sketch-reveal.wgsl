// ═══════════════════════════════════════════════════════════════════════════════
//  Sketch Reveal - Advanced Alpha with Edge-Preserve
//  Category: edge-detection
//  Alpha Mode: Edge-Preserve Alpha + Luminance Key
//  Features: advanced-alpha, sketch-effect, reveal
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
    edgeThreshold: f32
) -> f32 {
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let dR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let dL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let dU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0).r;
    let dD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, pixelSize.y), 0.0).r;
    
    let depthEdge = length(vec2<f32>(dR - dL, dU - dD));
    let edgeMask = smoothstep(edgeThreshold * 0.5, edgeThreshold, depthEdge);
    
    return mix(0.1, 1.0, edgeMask);
}

// Mode 6: Luminance Key Alpha
fn luminanceKeyAlpha(color: vec3<f32>, threshold: f32, softness: f32) -> f32 {
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    return smoothstep(threshold - softness, threshold + softness, luma);
}

// Combined sketch alpha
fn calculateSketchAlpha(
    uv: vec2<f32>,
    pixelSize: vec2<f32>,
    sketchIntensity: f32,
    params: vec4<f32>
) -> f32 {
    let edgeAlpha = edgePreserveAlpha(uv, pixelSize, params.x);
    let lumaAlpha = luminanceKeyAlpha(vec3<f32>(sketchIntensity), params.y, params.z);
    return clamp(edgeAlpha * lumaAlpha, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let pixelSize = 1.0 / resolution;
    let time = u.config.x;
    
    // Parameters
    let edgeThreshold = u.zoom_params.x * 0.1 + 0.02;
    let revealProgress = u.zoom_params.y;
    let lumaThreshold = u.zoom_params.z * 0.5;
    let softness = u.zoom_params.w * 0.2;
    
    // Sample with sobel for edge detection
    let stepX = pixelSize.x;
    let stepY = pixelSize.y;
    
    let t_c = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -stepY), 0.0).rgb;
    let m_l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-stepX, 0.0), 0.0).rgb;
    let m_c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let m_r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(stepX, 0.0), 0.0).rgb;
    let b_c = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, stepY), 0.0).rgb;
    
    let gx = -dot(m_l, vec3<f32>(0.299, 0.587, 0.114)) + dot(m_r, vec3<f32>(0.299, 0.587, 0.114));
    let gy = -dot(t_c, vec3<f32>(0.299, 0.587, 0.114)) + dot(b_c, vec3<f32>(0.299, 0.587, 0.114));
    let edgeStrength = sqrt(gx * gx + gy * gy);
    
    // Sketch effect: high contrast edges
    let sketchIntensity = smoothstep(edgeThreshold, edgeThreshold * 3.0, edgeStrength);
    
    // Reveal effect based on progress
    let revealMask = smoothstep(0.0, revealProgress, uv.x + sin(uv.y * 10.0 + time) * 0.05);
    
    // Paper color (off-white)
    let paperColor = vec3<f32>(0.95, 0.94, 0.92);
    
    // Pencil color
    let pencilColor = vec3<f32>(0.1, 0.1, 0.12);
    
    // Mix based on sketch intensity
    let sketchColor = mix(paperColor, pencilColor, sketchIntensity * revealMask);
    
    // ═══ ADVANCED ALPHA CALCULATION ═══
    let alpha = calculateSketchAlpha(uv, pixelSize, sketchIntensity, u.zoom_params);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(sketchColor, alpha));
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
