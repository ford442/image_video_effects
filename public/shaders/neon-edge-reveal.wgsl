// ═══════════════════════════════════════════════════════════════
//  Neon Edge Reveal - Flashlight Reveal with Alpha Emission
//  Category: lighting-effects
//  Physics: Mouse-revealed emissive edges with alpha occlusion
//  Alpha: Core edge = 0.3, Glow = 0.0 (additive)
// ═══════════════════════════════════════════════════════════════

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

fn getLuminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

// Alpha calculation for emissive materials
fn calculateEmissiveAlpha(glowIntensity: f32, occlusionBalance: f32) -> f32 {
    let coreAlpha = 0.3 * glowIntensity;
    let glowAlpha = 0.0;
    return mix(glowAlpha, coreAlpha, clamp(glowIntensity, 0.0, 1.0) * occlusionBalance);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.zoom_config.x;
    let audioBass = audioOverall * 1.5;
    let audioReactivity = 1.0 + audioOverall * 0.3;

    // Params
    // x: revealRadius, y: edgeBoost, z: glowIntensity, w: occlusionBalance
    let revealRadius = 0.2 + u.zoom_params.x * 0.3;
    let edgeBoost = u.zoom_params.y * 2.0;
    let glowIntensity = u.zoom_params.z * 2.0;
    let occlusionBalance = u.zoom_params.w;

    // Sobel kernels
    let stepX = 1.0 / resolution.x;
    let stepY = 1.0 / resolution.y;

    let t_l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-stepX, -stepY), 0.0).rgb;
    let t_c = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -stepY), 0.0).rgb;
    let t_r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(stepX, -stepY), 0.0).rgb;
    let m_l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-stepX, 0.0), 0.0).rgb;
    let m_r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(stepX, 0.0), 0.0).rgb;
    let b_l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-stepX, stepY), 0.0).rgb;
    let b_c = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, stepY), 0.0).rgb;
    let b_r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(stepX, stepY), 0.0).rgb;

    // Use luminance for edge detection
    let gx = -1.0 * getLuminance(t_l) - 2.0 * getLuminance(m_l) - 1.0 * getLuminance(b_l) +
              1.0 * getLuminance(t_r) + 2.0 * getLuminance(m_r) + 1.0 * getLuminance(b_r);

    let gy = -1.0 * getLuminance(t_l) - 2.0 * getLuminance(t_c) - 1.0 * getLuminance(t_r) +
              1.0 * getLuminance(b_l) + 2.0 * getLuminance(b_c) + 1.0 * getLuminance(b_r);

    let edgeStrength = sqrt(gx * gx + gy * gy);

    // Mouse interaction: "Flashlight"
    var mousePos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let aspect = resolution.x / resolution.y;

    // Correct distance for aspect ratio
    let distToMouse = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mousePos.x * aspect, mousePos.y));

    // Reveal falloff
    let revealFalloff = 1.0 - smoothstep(0.0, revealRadius, distToMouse);

    // Neon color cycling
    let neonColor1 = vec3<f32>(1.0, 0.0, 0.8);
    let neonColor2 = vec3<f32>(0.0, 1.0, 1.0);
    let mixFactor = 0.5 + 0.5 * sin(time * 2.0 * audioReactivity + uv.x * 3.0);
    let neonColor = mix(neonColor1, neonColor2, mixFactor);

    // Emission calculation
    var emission = vec3<f32>(0.0);
    
    if (edgeStrength > 0.05) {
        // Boost edge
        let edge = smoothstep(0.05, 0.3, edgeStrength);

        // Intensity depends on mouse proximity
        let glow = 0.3 + 2.0 * revealFalloff;

        emission = neonColor * glow * edge * edgeBoost * 2.0;
    }

    // Calculate alpha based on emission intensity
    let glowStrength = length(emission);
    let finalAlpha = calculateEmissiveAlpha(glowStrength, occlusionBalance);

    // Output with emission alpha
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(emission, finalAlpha));
}
