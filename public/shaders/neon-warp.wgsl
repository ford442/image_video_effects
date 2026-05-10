// ═══════════════════════════════════════════════════════════════════════════════
//  Neon Warp - Advanced Alpha with Effect Intensity
//  Category: distortion
//  Alpha Mode: Effect Intensity Alpha + Luminance Key
//  Features: advanced-alpha, warp, neon, distortion
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=WarpAmount, y=WarpSpeed, z=Intensity, w=Softness
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 5: Effect Intensity Alpha
fn effectIntensityAlpha(
    originalUV: vec2<f32>,
    displacedUV: vec2<f32>,
    baseAlpha: f32,
    intensity: f32
) -> f32 {
    let displacement = length(displacedUV - originalUV);
    let displacementAlpha = smoothstep(0.0, 0.1, displacement);
    return baseAlpha * mix(0.5, 1.0, displacementAlpha * intensity);
}

// Mode 6: Luminance Key Alpha
fn luminanceKeyAlpha(color: vec3<f32>, threshold: f32, softness: f32) -> f32 {
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    return smoothstep(threshold - softness, threshold + softness, luma);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let audioBass = plasmaBuffer[0].x;
    let audioReactivity = 1.0 + audioBass * 0.5;
    
    let warpAmount = u.zoom_params.x * 0.2;
    let warpSpeed = u.zoom_params.y * 5.0;
    let intensity = u.zoom_params.z;
    let softness = u.zoom_params.w * 0.2;
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Warp effect
    let warp = vec2<f32>(
        sin(uv.y * 10.0 + time * warpSpeed * audioReactivity) * warpAmount,
        cos(uv.x * 10.0 + time * warpSpeed * audioReactivity) * warpAmount
    );
    
    let warpedUV = uv + warp;
    let sample = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    
    // Neon color based on warp
    let neonColor = vec3<f32>(
        0.5 + 0.5 * sin(length(warp) * 50.0 + time),
        0.5 + 0.5 * sin(length(warp) * 50.0 + time + 2.09),
        0.5 + 0.5 * sin(length(warp) * 50.0 + time + 4.18)
    );
    
    let finalColor = mix(sample.rgb, neonColor, length(warp) * 10.0 * intensity);
    
    let effectAlpha = effectIntensityAlpha(uv, warpedUV, sample.a, intensity);
    let lumaAlpha = luminanceKeyAlpha(finalColor, 0.1, softness);
    let alpha = effectAlpha * lumaAlpha;
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
