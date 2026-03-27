// ═══════════════════════════════════════════════════════════════════════════════
//  Gravity Well with Alpha Physics
//  Scientific: Gravitational lensing with pinch distortion and light scattering
//  
//  ALPHA PHYSICS:
//  - Pinch distortion creates radial compression/expansion
//  - Chromatic aberration separates channels = different alphas per channel
//  - Accretion disk glow adds emission alpha
//  - Event horizon creates absorption zone
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

// Calculate pinch distortion magnitude
fn calculatePinchDistortion(
    dist: f32,
    radius: f32,
    strength: f32,
    density: f32
) -> f32 {
    let distSurface = dist - radius;
    let falloff = 1.0 / (pow(distSurface, density) * 10.0 + 1.0);
    let pull = strength * falloff;
    return pull;
}

// Calculate alpha for pinch/gravity effect
fn calculatePinchAlpha(
    baseAlpha: f32,
    distortionMag: f32,
    aberration: f32,
    isInsideHorizon: bool
) -> f32 {
    if (isInsideHorizon) {
        // Event horizon absorbs all light
        return 1.0;
    }
    
    // Pinch in (compression) = higher density = more opaque
    // But also causes more light scattering
    let compressionFactor = 1.0 + distortionMag * 0.2;
    let scatteringLoss = distortionMag * 0.4;
    
    // Chromatic aberration causes channel separation
    let chromaticScatter = aberration * distortionMag * 0.5;
    
    return clamp(baseAlpha * compressionFactor - scatteringLoss - chromaticScatter, 0.4, 1.0);
}

// Calculate per-channel alpha for chromatic effects
fn calculateChromaticAlpha(
    baseAlpha: f32,
    distortionMag: f32,
    aberration: f32,
    channel: i32  // 0=R, 1=G, 2=B
) -> f32 {
    // Different channels experience different scattering
    let channelShift = vec3<f32>(-0.1, 0.0, 0.1); // R less, B more
    let shift = channelShift[channel];
    
    return clamp(baseAlpha - (distortionMag + shift) * aberration * 2.0, 0.3, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Parameters
    let strength = u.zoom_params.x;        // Distortion strength (0.0 - 1.0)
    let radius = u.zoom_params.y * 0.4;    // Event horizon size (0.0 - 0.4)
    let aberration = u.zoom_params.z;      // Chromatic aberration (0.0 - 0.1)
    let density = u.zoom_params.w;         // Falloff density (0.1 - 5.0)

    // Mouse Interaction (Center of Gravity Well)
    var mouse = u.zoom_config.yz;

    // Calculate vector from mouse to current pixel (aspect corrected)
    let d_vec_raw = uv - mouse;
    let d_vec_aspect = vec2<f32>(d_vec_raw.x * aspect, d_vec_raw.y);
    let dist = length(d_vec_aspect);

    var finalColor = vec3<f32>(0.0, 0.0, 0.0);
    var finalAlpha = 1.0;
    var distortionMag = 0.0;

    // Apply distortion if outside event horizon
    if (dist > radius) {
        // Calculate displacement
        let distSurface = dist - radius;
        let falloff = 1.0 / (pow(distSurface, density) * 10.0 + 1.0);
        let pull = strength * falloff;
        distortionMag = pull;

        var dir = normalize(d_vec_aspect);

        let shift_aspect = dir * pull * 0.1;
        let shift = vec2<f32>(shift_aspect.x / aspect, shift_aspect.y);

        let sample_uv_center = uv - shift;

        // Chromatic Aberration with per-channel alpha
        let uv_r = sample_uv_center + shift * aberration * 5.0;
        let uv_b = sample_uv_center - shift * aberration * 5.0;

        let sampleR = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0);
        let sampleG = textureSampleLevel(readTexture, u_sampler, sample_uv_center, 0.0);
        let sampleB = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0);

        // Calculate per-channel alphas
        let alphaR = calculateChromaticAlpha(sampleR.a, distortionMag, aberration, 0);
        let alphaG = calculateChromaticAlpha(sampleG.a, distortionMag, aberration, 1);
        let alphaB = calculateChromaticAlpha(sampleB.a, distortionMag, aberration, 2);

        finalColor = vec3<f32>(sampleR.r, sampleG.g, sampleB.b);
        finalAlpha = (alphaR + alphaG + alphaB) / 3.0;

        // Add accretion disk glow at the edge with emission alpha
        let glow = exp(-distSurface * 20.0) * strength;
        let glowColor = vec3<f32>(0.5, 0.2, 0.8) * glow;
        finalColor += glowColor;
        // Glow adds to alpha
        finalAlpha = min(finalAlpha + glow * 0.5, 1.0);

    } else {
        // Inside Event Horizon - Black with full absorption
        finalColor = vec3<f32>(0.0, 0.0, 0.0);
        finalAlpha = 1.0;
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));

    // Passthrough depth with distortion modification
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    // Pinch creates depth distortion
    let depthMod = 1.0 - distortionMag * 0.1;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth * depthMod, 0.0, 0.0, 0.0));
}
