// ═══════════════════════════════════════════════════════════════════════════════
//  Neon Edge Radar - Advanced Alpha with Edge-Preserve
//  Category: edge-detection
//  Alpha Mode: Edge-Preserve Alpha + Effect Intensity
//  Features: advanced-alpha, radar-sweep, edge-detection
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
fn edgePreserveAlpha(uv: vec2<f32>, pixelSize: vec2<f32>, edgeThreshold: f32) -> f32 {
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let dR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let dL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let dU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0).r;
    let dD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, pixelSize.y), 0.0).r;
    let depthEdge = length(vec2<f32>(dR - dL, dU - dD));
    let edgeMask = smoothstep(edgeThreshold * 0.5, edgeThreshold, depthEdge);
    return mix(0.2, 1.0, edgeMask);
}

// Mode 5: Effect Intensity Alpha
fn effectIntensityAlpha(intensity: f32, falloff: f32) -> f32 {
    return mix(0.3, 1.0, intensity * falloff);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let pixelSize = 1.0 / resolution;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.zoom_config.x;
    let audioBass = audioOverall * 1.5;
    let audioReactivity = 1.0 + audioOverall * 0.3;
    
    let edgeThreshold = u.zoom_params.x * 0.1 + 0.02;
    let radarSpeed = u.zoom_params.y * 2.0;
    let sweepWidth = u.zoom_params.z * 0.3;
    let intensity = u.zoom_params.w * 2.0;
    
    // Radar sweep angle
    let centered = uv - 0.5;
    let angle = atan2(centered.y, centered.x);
    let sweepAngle = fract(time * radarSpeed * audioReactivity) * 6.28 - 3.14;
    let angleDiff = abs(angle - sweepAngle);
    let sweep = exp(-angleDiff * angleDiff / (sweepWidth * sweepWidth));
    
    // Edge detection
    let l = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).rgb;
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).rgb;
    let edge = length(r - l);
    
    // Neon color
    let neonColor = vec3<f32>(0.0, 1.0, 0.5);
    let emission = neonColor * edge * sweep * intensity;
    
    let edgeAlpha = edgePreserveAlpha(uv, pixelSize, edgeThreshold);
    let effectAlpha = effectIntensityAlpha(sweep * edge, intensity);
    let alpha = clamp(edgeAlpha * effectAlpha, 0.0, 1.0);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(emission, alpha));
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
