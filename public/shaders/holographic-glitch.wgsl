// ═══════════════════════════════════════════════════════════════════════════════
//  Holographic Glitch - Advanced Alpha with Depth-Layered
//  Category: complex-multi-effect
//  Alpha Mode: Depth-Layered Alpha + Luminance Key
//  Features: advanced-alpha, holographic, glitch, digital
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

// Random
fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.zoom_config.x;
    let audioBass = audioOverall * 1.5;
    let audioReactivity = 1.0 + audioOverall * 0.3;
    
    let glitchAmount = u.zoom_params.x;
    let holographicIntensity = u.zoom_params.y;
    let depthWeight = u.zoom_params.z;
    let scanSpeed = u.zoom_params.w * 10.0;
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Glitch offset
    let block = floor(uv.y * 20.0);
    let noise = rand(vec2<f32>(block, floor(time * 10.0 * audioReactivity)));
    var glitchOffset = vec2<f32>(0.0);
    if (noise < glitchAmount) {
        glitchOffset.x = (rand(vec2<f32>(time)) - 0.5) * glitchAmount * 0.2;
    }
    
    let warpedUV = uv + glitchOffset;
    let sample = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    
    // Holographic rainbow
    let scanline = sin(uv.y * 800.0 + time * scanSpeed * audioReactivity) * 0.1;
    let holographic = vec3<f32>(
        0.5 + 0.5 * sin(time + uv.x * 5.0),
        0.5 + 0.5 * sin(time + uv.x * 5.0 + 2.09),
        0.5 + 0.5 * sin(time + uv.x * 5.0 + 4.18)
    ) * holographicIntensity;
    
    let finalColor = mix(sample.rgb, holographic + scanline, holographicIntensity);
    
    let depthAlpha = depthLayeredAlpha(finalColor, uv, depthWeight);
    let lumaAlpha = luminanceKeyAlpha(finalColor, 0.1, 0.05);
    let alpha = clamp(depthAlpha * lumaAlpha, 0.0, 1.0);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
