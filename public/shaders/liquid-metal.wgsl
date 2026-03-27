// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Metal - Advanced Alpha with Physical Transmittance
//  Category: distortion
//  Alpha Mode: Effect Intensity Alpha + Physical Transmittance
//  Features: advanced-alpha, liquid, metallic, reflection
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

// Fresnel
fn fresnel(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.zoom_config.x;
    let audioBass = audioOverall * 1.5;
    let audioReactivity = 1.0 + audioOverall * 0.3;
    
    let rippleSpeed = u.zoom_params.x;
    let rippleIntensity = u.zoom_params.y * 0.1;
    let metallic = u.zoom_params.z;
    let roughness = u.zoom_params.w;
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Liquid ripples
    let ripple = sin(length(uv - 0.5) * 20.0 - time * rippleSpeed * audioReactivity) * rippleIntensity;
    let warpedUV = uv + vec2<f32>(ripple);
    
    let sample = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    
    // Metallic reflection
    let viewDir = normalize(uv - 0.5);
    let normal = normalize(vec2<f32>(ripple * 10.0, 0.01));
    let cosTheta = max(dot(viewDir, normal), 0.0);
    let F0 = mix(0.04, 0.9, metallic);
    let reflectivity = fresnel(cosTheta, F0);
    
    let metalColor = mix(sample.rgb, vec3<f32>(0.8, 0.85, 0.9), reflectivity * metallic);
    
    let alpha = effectIntensityAlpha(uv, warpedUV, sample.a, rippleIntensity * 10.0);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(metalColor, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
