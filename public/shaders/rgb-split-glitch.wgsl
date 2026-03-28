// ═══════════════════════════════════════════════════════════════
//  RGB Split Glitch - Digital glitch effect with wavelength-dependent alpha
//  Category: retro-glitch
//  Features: mouse-driven, chromatic-dispersion, wavelength-alpha
//  
//  SCIENTIFIC MODEL:
//  - Dispersion affects both color position AND alpha per channel
//  - Beer-Lambert law: alpha = exp(-thickness * absorption)
//  - Red (650nm): lowest absorption, highest transmission
//  - Blue (450nm): highest absorption, lowest transmission
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

// ═══════════════════════════════════════════════════════════════
//  SPECTRAL PHYSICS CONSTANTS
// ═══════════════════════════════════════════════════════════════
const WAVELENGTH_RED:    f32 = 650.0;  // nm - longest wavelength
const WAVELENGTH_GREEN:  f32 = 550.0;  // nm
const WAVELENGTH_BLUE:   f32 = 450.0;  // nm - shortest wavelength

// Absorption coefficients (Beer-Lambert law)
// Red transmits better, blue scatters/absorbs more
const ABSORPTION_RED:    f32 = 0.3;
const ABSORPTION_GREEN:  f32 = 0.5;
const ABSORPTION_BLUE:   f32 = 0.8;

fn hash12(p: vec2<f32>) -> f32 {
    var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══════════════════════════════════════════════════════════════
//  WAVELENGTH-DEPENDENT ALPHA CALCULATION
//  Returns alpha for each channel based on dispersion thickness
// ═══════════════════════════════════════════════════════════════
fn calculateChannelAlpha(thickness: f32, wavelength: f32) -> f32 {
    // Adjust absorption by wavelength (shorter wavelength = more absorption)
    // Normalize wavelength to 0-1 range for weighting
    let lambda_norm = (800.0 - wavelength) / 400.0; // Blue=0.875, Red=0.375
    let absorption = mix(0.3, 1.0, lambda_norm);
    return exp(-thickness * absorption);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;

    // Parameters
    let splitDist = u.zoom_params.x * 0.1;
    let angleOffset = u.zoom_params.y * 6.28;
    let noiseAmt = u.zoom_params.z;
    let radius = 0.1 + (u.zoom_params.w * 0.5);

    let aspect = resolution.x / resolution.y;
    var mousePos = u.zoom_config.yz;
    let dist = distance(uv * vec2(aspect, 1.0), mousePos * vec2(aspect, 1.0));

    // Influence factor based on mouse distance
    let influence = smoothstep(radius, 0.0, dist);

    var offsetR = vec2<f32>(0.0);
    var offsetG = vec2<f32>(0.0);
    var offsetB = vec2<f32>(0.0);

    // Calculate dispersion thickness based on influence
    let dispersionThickness = influence * 2.0;

    if (influence > 0.001) {
        let t = u.config.x;

        // Jitter/Noise
        let noise = (hash12(uv * 100.0 + t) - 0.5) * noiseAmt * influence * 0.1;

        // Directional Split
        var dir = vec2<f32>(cos(angleOffset), sin(angleOffset));
        let shift = dir * splitDist * influence;

        offsetR = shift + vec2<f32>(noise);
        offsetG = -shift * 0.5;
        offsetB = -shift + vec2<f32>(-noise);
    }

    // Sample color channels at displaced positions
    let r = textureSampleLevel(readTexture, u_sampler, uv + offsetR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv + offsetG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv + offsetB, 0.0).b;

    // ═══════════════════════════════════════════════════════════════
    //  WAVELENGTH-DEPENDENT ALPHA
    // ═══════════════════════════════════════════════════════════════
    // Calculate per-channel alpha based on dispersion thickness
    let alphaR = calculateChannelAlpha(dispersionThickness, WAVELENGTH_RED);
    let alphaG = calculateChannelAlpha(dispersionThickness, WAVELENGTH_GREEN);
    let alphaB = calculateChannelAlpha(dispersionThickness, WAVELENGTH_BLUE);
    
    // Luminance-weighted final alpha (red contributes more to perceived brightness)
    let luminanceWeights = vec3<f32>(0.299, 0.587, 0.114);
    let finalAlpha = dot(vec3<f32>(alphaR, alphaG, alphaB), luminanceWeights);
    
    // Apply channel alphas to color (premultiplied style)
    let finalColor = vec3<f32>(
        r * alphaR,
        g * alphaG,
        b * alphaB
    );

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
