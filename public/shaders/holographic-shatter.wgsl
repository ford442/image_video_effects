// ═══════════════════════════════════════════════════════════════════════════════
//  Holographic Shatter - Advanced Alpha with Depth-Layered
//  Category: complex-multi-effect
//  Alpha Mode: Depth-Layered Alpha + Effect Intensity
//  Features: advanced-alpha, holographic, shatter, glass
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

// Random
fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    let shatterAmount = u.zoom_params.x;
    let holographicIntensity = u.zoom_params.y;
    let depthWeight = u.zoom_params.z;
    let shardCount = u.zoom_params.w * 50.0 + 10.0;
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Shatter grid
    let gridUV = uv * shardCount;
    let shardId = floor(gridUV);
    let shardUv = fract(gridUV);
    
    // Random offset per shard
    let shardRand = rand(shardId);
    let offset = vec2<f32>(rand(shardId + 1.0), rand(shardId + 2.0)) * shatterAmount;
    
    let warpedUV = uv + offset * smoothstep(0.5, 1.0, shatterAmount);
    let sample = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    
    // Holographic edge
    let edgeDist = min(min(shardUv.x, 1.0 - shardUv.x), min(shardUv.y, 1.0 - shardUv.y));
    let edgeGlow = smoothstep(0.1, 0.0, edgeDist);
    
    let holographic = vec3<f32>(
        0.5 + 0.5 * sin(time + shardRand * 6.28),
        0.5 + 0.5 * sin(time + shardRand * 6.28 + 2.09),
        0.5 + 0.5 * sin(time + shardRand * 6.28 + 4.18)
    );
    
    let finalColor = mix(sample.rgb, holographic, edgeGlow * holographicIntensity);
    let alpha = depthLayeredAlpha(finalColor, uv, depthWeight) * (0.8 + edgeGlow * 0.2);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
