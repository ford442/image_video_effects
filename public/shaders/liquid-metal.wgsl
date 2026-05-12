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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=RippleSpeed, y=RippleIntensity, z=Metallic, w=Roughness
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

// Fresnel
fn fresnel(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let audioBass = plasmaBuffer[0].x;
    let audioReactivity = 1.0 + audioBass * 0.5;

    let rippleSpeed = u.zoom_params.x;
    let rippleIntensity = u.zoom_params.y * 0.1 * (1.0 + audioBass * 0.3);
    let metallic = u.zoom_params.z;
    let roughness = u.zoom_params.w;
    let mouse = u.zoom_config.yz;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Mouse-centered + center radial ripples — adds tactile interaction
    let dCenter = length(uv - 0.5);
    let dMouse = length(uv - mouse);
    let r1 = sin(dCenter * 20.0 - time * rippleSpeed * audioReactivity) * rippleIntensity;
    let r2 = sin(dMouse * 28.0 - time * rippleSpeed * audioReactivity * 1.3) * rippleIntensity * 0.7;
    let ripple = r1 + r2;
    let warpedUV = clamp(uv + vec2<f32>(ripple), vec2<f32>(0.0), vec2<f32>(1.0));

    let sample = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);

    // Metallic reflection (Fresnel) — anisotropic by ripple gradient
    let viewDir = normalize(uv - 0.5);
    let normal = normalize(vec2<f32>(ripple * 10.0, 0.01));
    let cosTheta = max(dot(viewDir, normal), 0.0);
    let F0 = mix(0.04, 0.9, metallic);
    let reflectivity = fresnel(cosTheta, F0);

    // Iridescent metal tint (palette-mapped by reflection angle, modulates roughness brushed look)
    let palIdx = u32(clamp((cosTheta + time * 0.05) * 255.0, 0.0, 255.0));
    let irid = plasmaBuffer[palIdx % 256u].rgb;
    let baseMetal = mix(vec3<f32>(0.8, 0.85, 0.9), irid, 0.4 * (1.0 - roughness));
    let metalColor = mix(sample.rgb, baseMetal, reflectivity * metallic);

    let alpha = effectIntensityAlpha(uv, warpedUV, sample.a, rippleIntensity * 10.0);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(metalColor, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
