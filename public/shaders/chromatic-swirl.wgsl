// ═══════════════════════════════════════════════════════════════
//  Chromatic Swirl - Rotational chromatic aberration with wavelength-alpha
//  Category: distortion
//  Features: swirl-rotation, chromatic-dispersion, wavelength-dependent-alpha
//
//  SCIENTIFIC MODEL:
//  - Swirl rotation creates dispersion that affects both position AND alpha
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.zoom_config.x;
    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Params
    let swirlStrength = 5.0 + u.zoom_params.x * 10.0;
    let radius = 0.3 + u.zoom_params.y * 0.5;
    let aberration = 0.02 + u.zoom_params.z * 0.05;
    let animate = u.zoom_params.w;

    let aspect = resolution.x / resolution.y;
    var center = mouse;
    if (mouse.x < 0.0) {
        center = vec2<f32>(0.5, 0.5);
    }

    let dVec = uv - center;
    let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

    // Calculate Swirl Angle
    var angle = 0.0;
    if (dist < radius) {
        let percent = (radius - dist) / radius;
        angle = percent * percent * swirlStrength;
        if (animate > 0.5) {
            angle += sin(time) * 2.0 * percent;
        }
        if (mouseDown > 0.5) {
            angle *= 2.0;
        }
    }

    // Rotate UV
    let sinA = sin(angle);
    let cosA = cos(angle);
    let offset = uv - center;
    let x_corr = offset.x * aspect;
    let y_corr = offset.y;

    let rotatedX = x_corr * cosA - y_corr * sinA;
    let rotatedY = x_corr * sinA + y_corr * cosA;

    let finalUV_center = vec2<f32>(rotatedX / aspect, rotatedY) + center;

    // Chromatic Aberration
    var dir = normalize(finalUV_center - center);

    let uvR = finalUV_center + dir * aberration * dist;
    let uvG = finalUV_center;
    let uvB = finalUV_center - dir * aberration * dist;

    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    // ═══════════════════════════════════════════════════════════════
    //  WAVELENGTH-DEPENDENT ALPHA
    //  Thickness derived from swirl angle and aberration
    // ═══════════════════════════════════════════════════════════════
    let swirlThickness = angle * 0.5 + aberration * dist * 10.0;
    let dispersionThickness = swirlThickness;
    
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
}
