// ═══════════════════════════════════════════════════════════════════
//  Holographic Shatter
//  Category: image
//  Features: advanced-alpha, holographic, shatter, glass, mouse-driven, audio-reactive
//  Complexity: High
//  Upgraded: 2026-05-23
//  upgraded-rgba
// ═══════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=ShatterAmount, y=HolographicIntensity, z=DepthWeight, w=ShardCount
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;

    let shatterAmount = clamp(u.zoom_params.x * (1.0 + bass * 0.4), 0.0, 1.0);
    let holographicIntensity = u.zoom_params.y;
    let depthWeight = u.zoom_params.z;
    let shardCount = u.zoom_params.w * 50.0 + 10.0;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Mouse-centered impact: shards farther from mouse displaced more (impact radial wave)
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let dM = distance(uv, mouse);
    let impact = (0.4 + mouseDown * 0.6) * smoothstep(0.0, 0.6, dM);

    // Shatter grid
    let gridUV = uv * shardCount;
    let shardId = floor(gridUV);
    let shardUv = fract(gridUV);

    // Per-shard random radial flight direction (mouse repels)
    let shardRand = rand(shardId);
    let shardCenter = (shardId + 0.5) / shardCount;
    let flightDir = normalize(shardCenter - mouse + vec2<f32>(1e-4));
    let offset = flightDir * shatterAmount * impact * (0.4 + shardRand * 0.6);

    let warpedUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
    let sample = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Shard edge glow (pseudo-cracked-glass refraction)
    let edgeDist = min(min(shardUv.x, 1.0 - shardUv.x), min(shardUv.y, 1.0 - shardUv.y));
    let edgeGlow = smoothstep(0.1, 0.0, edgeDist);

    // Iridescent holographic + plasma palette per shard
    let phase = time + shardRand * TAU + depth * PI;
    let holographic = 0.5 + 0.5 * sin(vec3<f32>(phase, phase + 2.094, phase + 4.188));
    let palIdx = u32(clamp((shardRand + time * 0.05) * 255.0, 0.0, 255.0));
    let palette = plasmaBuffer[palIdx % 256u].rgb;
    let foil = mix(holographic, holographic * (0.6 + palette * 0.7), 0.4);

    let finalColor = mix(sample.rgb, foil, edgeGlow * holographicIntensity);
    let effectIntensity = edgeGlow * holographicIntensity + shatterAmount * 0.5;
    let finalAlpha = mix(baseColor.a, 1.0, clamp(effectIntensity * 0.7, 0.0, 1.0));
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0, 0, 1));
}
