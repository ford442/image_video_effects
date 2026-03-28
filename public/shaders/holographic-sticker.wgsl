// ═══════════════════════════════════════════════════════════════════════════════
//  Holographic Sticker - Advanced Alpha with Depth-Layered
//  Category: complex-multi-effect
//  Alpha Mode: Depth-Layered Alpha + Luminance Key
//  Features: advanced-alpha, holographic, sticker-effect
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
    let depthAlpha = mix(0.4, 1.0, depth);
    let lumaAlpha = mix(0.5, 1.0, luma);
    return mix(lumaAlpha, depthAlpha, depthWeight);
}

// Mode 6: Luminance Key Alpha
fn luminanceKeyAlpha(color: vec3<f32>, threshold: f32, softness: f32) -> f32 {
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    return smoothstep(threshold - softness, threshold + softness, luma);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    let holographicIntensity = u.zoom_params.x;
    let colorShift = u.zoom_params.y;
    let depthWeight = u.zoom_params.z;
    let stickerShape = u.zoom_params.w;
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    
    // Holographic rainbow effect
    let angle = atan2(uv.y - 0.5, uv.x - 0.5);
    let rainbow = vec3<f32>(
        0.5 + 0.5 * sin(angle * 3.0 + colorShift * 6.28 + time * 0.5),
        0.5 + 0.5 * sin(angle * 3.0 + colorShift * 6.28 + time * 0.5 + 2.09),
        0.5 + 0.5 * sin(angle * 3.0 + colorShift * 6.28 + time * 0.5 + 4.18)
    );
    
    // Sticker edge shape
    let distFromCenter = length(uv - 0.5);
    let edgeGlow = smoothstep(stickerShape, stickerShape - 0.05, distFromCenter);
    
    let holographicColor = mix(baseSample.rgb, rainbow, holographicIntensity * edgeGlow);
    
    let depthAlpha = depthLayeredAlpha(holographicColor, uv, depthWeight);
    let lumaAlpha = luminanceKeyAlpha(holographicColor, 0.1, 0.05);
    let alpha = clamp(depthAlpha * lumaAlpha * edgeGlow, 0.0, 1.0);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(holographicColor, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
