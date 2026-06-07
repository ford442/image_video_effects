// ═══════════════════════════════════════════════════════════════════════════════
//  Hyper-Space Jump with Alpha Physics
//  Scientific: High-velocity radial streaking with relativistic light effects
//  
//  ALPHA PHYSICS:
//  - Velocity streaks accumulate alpha along motion path
//  - Brightness-weighted streaking affects opacity
//  - Blue-shift at edges due to relativistic motion
//  - Vignetting creates tunnel transparency
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn getLuma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

// Calculate velocity-based alpha for streaks
fn calculateStreakAlpha(
    sampleAlpha: f32,
    luma: f32,
    sampleIndex: f32,
    totalSamples: f32,
    decay: f32
) -> f32 {
    // Bright features streak more prominently
    let brightWeight = smoothstep(0.5, 1.0, luma);
    
    // Distance along streak affects opacity
    let streakFactor = 1.0 - (sampleIndex / totalSamples);
    
    // Decay reduces contribution
    let decayFactor = pow(decay, sampleIndex);
    
    return sampleAlpha * (0.1 + brightWeight * 2.0) * streakFactor * decayFactor;
}

// Calculate relativistic Doppler alpha shift
fn calculateRelativisticAlpha(
    baseAlpha: f32,
    dist: f32,
    strength: f32
) -> f32 {
    // Higher velocity = more time dilation = light accumulation
    let timeDilation = 1.0 + strength * (1.0 - smoothstep(0.0, 1.5, dist));
    
    // But also more scattering
    let scattering = strength * dist * 0.2;
    
    return clamp(baseAlpha * timeDilation - scattering, 0.3, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Parameters
    let strength = u.zoom_params.x * 0.1;
    let samples = 30;
    var center = u.zoom_config.yz;

    // Aspect ratio correction
    let aspect = resolution.x / resolution.y;
    let center_aspect = vec2<f32>(center.x * aspect, center.y);
    let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);

    var dir = uv_aspect - center_aspect;
    let dist = length(dir);
    let dir_norm = normalize(dir);
    let dir_uv = (uv - center);

    // Random jitter for "speed" effect
    let noise = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233)) + time) * 43758.5453);

    var color_acc = vec4<f32>(0.0);
    var alpha_acc = 0.0;
    var weight_acc = 0.0;

    let decay = 0.95;

    // Radial Blur Loop with alpha accumulation
    for (var i = 0; i < samples; i++) {
        let f = f32(i);
        let offset = dir_uv * (f / f32(samples)) * strength * dist * 10.0;
        let sample_uv = uv - offset;

        // Jitter sampling
        let jitter_offset = offset * (noise - 0.5) * 0.1;

        // Check bounds
        if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) {
            continue;
        }

        let s_color = textureSampleLevel(readTexture, u_sampler, sample_uv + jitter_offset, 0.0);

        // Chromatic Aberration on streaks
        let r = textureSampleLevel(readTexture, u_sampler, sample_uv + jitter_offset + dir_uv * 0.005 * f, 0.0).r;
        let b = textureSampleLevel(readTexture, u_sampler, sample_uv + jitter_offset - dir_uv * 0.005 * f, 0.0).b;
        let sample_color = vec4<f32>(r, s_color.g, b, s_color.a);

        // Calculate streak alpha
        let luma = getLuma(sample_color.rgb);
        let weight = pow(decay, f) * (0.1 + smoothstep(0.5, 1.0, luma) * 2.0);
        
        // Accumulate with alpha
        let streakAlpha = calculateStreakAlpha(s_color.a, luma, f, f32(samples), decay);

        color_acc = color_acc + sample_color * weight;
        alpha_acc = alpha_acc + streakAlpha * weight;
        weight_acc = weight_acc + weight;
    }

    let final_color = color_acc / weight_acc;
    let baseAlpha = alpha_acc / weight_acc;
    
    // Apply relativistic alpha effects
    let finalAlpha = calculateRelativisticAlpha(baseAlpha, dist, strength);

    // Add vignette/tunnel darkening
    let vignette = 1.0 - smoothstep(0.5, 1.5, dist);
    let outputRGB = mix(vec3<f32>(0.0), final_color.rgb, vignette);
    // Vignette reduces alpha at edges
    let vignetteAlpha = finalAlpha * vignette;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(outputRGB, vignetteAlpha));
    
    // Clear depth for hyper-space effect
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
