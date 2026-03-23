// ═══════════════════════════════════════════════════════════════════════════════
//  Neon Ripple Split - Advanced Alpha with Effect Intensity
//  Category: distortion
//  Alpha Mode: Effect Intensity Alpha + Luminance Key
//  Features: advanced-alpha, ripple, split, neon
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    let splitAmount = u.zoom_params.x * 0.1;
    let rippleSpeed = u.zoom_params.y * 5.0;
    let intensity = u.zoom_params.z * 2.0;
    let splitCount = u.zoom_params.w * 5.0 + 2.0;
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Ripple split effect
    let ripple = sin(uv.y * 20.0 - time * rippleSpeed) * splitAmount;
    
    // RGB split based on ripple
    let rUV = uv + vec2<f32>(ripple * splitCount, 0.0);
    let gUV = uv;
    let bUV = uv - vec2<f32>(ripple * splitCount, 0.0);
    
    let r = textureSampleLevel(readTexture, u_sampler, clamp(rUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clamp(gUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(bUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    
    let splitColor = vec3<f32>(r, g, b);
    
    // Neon glow on split
    let neon = vec3<f32>(1.0, 0.5, 0.8) * abs(ripple) * 10.0 * intensity;
    let finalColor = splitColor + neon;
    
    let alpha = effectIntensityAlpha(uv, rUV, 1.0, intensity);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
