// ═══════════════════════════════════════════════════════════════
//  RGB Ripple Waves - Phase-shifted RGB waves with wavelength-alpha
//  Category: distortion
//  Features: mouse-driven, phase-dispersion, wavelength-dependent-alpha
//
//  SCIENTIFIC MODEL:
//  - Dispersion affects both wave phase AND alpha per channel
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
const WAVELENGTH_RED:    f32 = 650.0;  // nm
const WAVELENGTH_GREEN:  f32 = 550.0;  // nm
const WAVELENGTH_BLUE:   f32 = 450.0;  // nm

// ═══════════════════════════════════════════════════════════════
//  WAVELENGTH-DEPENDENT ALPHA
// ═══════════════════════════════════════════════════════════════
fn calculateChannelAlpha(thickness: f32, wavelength: f32) -> f32 {
    let lambda_norm = (800.0 - wavelength) / 400.0;
    let absorption = mix(0.3, 1.0, lambda_norm);
    return exp(-thickness * absorption);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / resolution;
    var mouse = u.zoom_config.yz;
    let time = u.config.x;

    // Correct aspect ratio for distance calculation
    let aspect = resolution.x / resolution.y;
    let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);
    let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);

    let dist = distance(uv_aspect, mouse_aspect);

    // Parameters
    let frequency = 50.0;
    let speed = 5.0;
    let amplitude = 0.02 * exp(-dist * 2.0);

    // Phase shifts for RGB (simulating chromatic dispersion)
    let phase_r = 0.0;
    let phase_g = 1.0;
    let phase_b = 2.0;

    // Calculate waves
    let wave_r = sin(dist * frequency - time * speed + phase_r);
    let wave_g = sin(dist * frequency - time * speed + phase_g);
    let wave_b = sin(dist * frequency - time * speed + phase_b);

    // Displace UVs
    var displacement_r = vec2<f32>(0.0);
    var displacement_g = vec2<f32>(0.0);
    var displacement_b = vec2<f32>(0.0);

    if (dist > 0.001) {
        let dir_aspect = normalize(uv_aspect - mouse_aspect);
        let dir_uv = vec2<f32>(dir_aspect.x / aspect, dir_aspect.y);

        displacement_r = dir_uv * wave_r * amplitude;
        displacement_g = dir_uv * wave_g * amplitude;
        displacement_b = dir_uv * wave_b * amplitude;
    }

    let r = textureSampleLevel(readTexture, u_sampler, uv + displacement_r, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv + displacement_g, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv + displacement_b, 0.0).b;

    // ═══════════════════════════════════════════════════════════════
    //  WAVELENGTH-DEPENDENT ALPHA
    //  Thickness derived from wave displacement magnitude
    // ═══════════════════════════════════════════════════════════════
    let displacementMag = length(displacement_r) + length(displacement_g) + length(displacement_b);
    let dispersionThickness = displacementMag * 50.0 + exp(-dist * 2.0) * 1.5;
    
    let alphaR = calculateChannelAlpha(dispersionThickness, WAVELENGTH_RED);
    let alphaG = calculateChannelAlpha(dispersionThickness, WAVELENGTH_GREEN);
    let alphaB = calculateChannelAlpha(dispersionThickness, WAVELENGTH_BLUE);
    
    let luminanceWeights = vec3<f32>(0.299, 0.587, 0.114);
    let finalAlpha = dot(vec3<f32>(alphaR, alphaG, alphaB), luminanceWeights);
    
    let finalColor = vec3<f32>(
        r * alphaR,
        g * alphaG,
        b * alphaB
    );

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
