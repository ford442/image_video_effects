// ═══════════════════════════════════════════════════════════════════════════════
//  Edge Glow Mouse - Advanced Alpha with Edge-Preserve
//  Category: edge-detection
//  Alpha Mode: Edge-Preserve Alpha + Depth-Layered
//  Features: advanced-alpha, mouse-interactive, edge-glow
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
    
    return mix(0.2, 1.0, edgeMask);
}

// Mode 1: Depth-Layered Alpha
fn depthLayeredAlpha(uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthAlpha = mix(0.4, 1.0, depth);
    return mix(1.0, depthAlpha, depthWeight);
}

// Combined alpha
fn calculateAdvancedAlpha(
    uv: vec2<f32>,
    pixelSize: vec2<f32>,
    mouseDist: f32,
    glowRadius: f32,
    params: vec4<f32>
) -> f32 {
    let edgeAlpha = edgePreserveAlpha(uv, pixelSize, params.x);
    let depthAlpha = depthLayeredAlpha(uv, params.z);
    
    // Mouse proximity increases alpha
    let mouseAlpha = 1.0 - smoothstep(0.0, glowRadius, mouseDist);
    
    return clamp(edgeAlpha * depthAlpha * mix(0.5, 1.0, mouseAlpha), 0.0, 1.0);
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
    
    // Parameters
    let edgeThreshold = u.zoom_params.x * 0.1 + 0.02;
    let glowRadius = u.zoom_params.y * 0.3 + 0.05;
    let depthWeight = u.zoom_params.z;
    let glowIntensity = u.zoom_params.w * 3.0;
    
    let mousePos = u.zoom_config.yz;
    let mouseDist = distance(uv, mousePos);
    
    // Sample with offset for edge detection
    let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let cR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).rgb;
    let cL = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).rgb;
    let cU = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0).rgb;
    let cD = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, pixelSize.y), 0.0).rgb;
    
    let colorEdge = length(cR - cL) + length(cU - cD);
    
    // Mouse glow falloff
    let glowFalloff = 1.0 - smoothstep(0.0, glowRadius, mouseDist);
    
    // Edge glow color
    let edgeGlow = vec3<f32>(
        0.5 + 0.5 * sin(time * 2.0),
        0.5 + 0.5 * sin(time * 2.0 + 2.09),
        0.5 + 0.5 * sin(time * 2.0 + 4.18)
    ) * colorEdge * glowIntensity * glowFalloff;
    
    // ═══ ADVANCED ALPHA CALCULATION ═══
    let alpha = calculateAdvancedAlpha(uv, pixelSize, mouseDist, glowRadius, u.zoom_params);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(edgeGlow, alpha));
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
