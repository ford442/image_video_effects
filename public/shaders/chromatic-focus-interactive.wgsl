// ═══════════════════════════════════════════════════════════════════════════════
//  Chromatic Focus Interactive - DOF effect with wavelength-dependent alpha
//  Category: distortion
//  Features: depth-of-field, chromatic-aberration, wavelength-dependent-alpha
//
//  SCIENTIFIC MODEL:
//  - Focus-based dispersion affects both position AND alpha per channel
//  - Beer-Lambert law: alpha = exp(-thickness * absorption)
//  - Red (650nm): lowest absorption, highest transmission
//  - Blue (450nm): highest absorption, lowest transmission
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var feedbackOut: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var normalBuf:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var feedbackTex: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config:      vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples:     array<vec4<f32>, 50>,
};

// ═══════════════════════════════════════════════════════════════════════════════
//  SPECTRAL PHYSICS CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════
const WAVELENGTH_RED:    f32 = 650.0;  // nm
const WAVELENGTH_GREEN:  f32 = 550.0;  // nm
const WAVELENGTH_BLUE:   f32 = 450.0;  // nm

// ═══════════════════════════════════════════════════════════════════════════════
//  WAVELENGTH-DEPENDENT ALPHA
// ═══════════════════════════════════════════════════════════════════════════════
fn calculateChannelAlpha(thickness: f32, wavelength: f32) -> f32 {
    let lambda_norm = (800.0 - wavelength) / 400.0;
    let absorption = mix(0.3, 1.0, lambda_norm);
    return exp(-thickness * absorption);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    var uv = vec2<f32>(gid.xy) / dims;
    let aspect = dims.x / dims.y;

    // Params
    let strength = u.zoom_params.x * 0.05;
    let blurAmt = u.zoom_params.y;
    let focusRad = u.zoom_params.z;
    let hardness = u.zoom_params.w * 5.0 + 1.0;

    var mouse = u.zoom_config.yz;
    let click = u.zoom_config.w;

    // Focus point is mouse
    var center = mouse;
    let distVec = (uv - center) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Calculate blur/aberration amount based on distance from focus
    var amount = smoothstep(focusRad, focusRad + 0.5, dist);
    amount = pow(amount, 1.0 / hardness);

    // Direction for displacement
    var dir = normalize(distVec);

    // Chromatic Aberration
    let rOffset = dir * amount * strength;
    let bOffset = -dir * amount * strength;
    let gOffset = vec2<f32>(0.0);

    // Simple 3-tap sample for CA
    let r = textureSampleLevel(videoTex, videoSampler, uv + rOffset, 0.0).r;
    let g = textureSampleLevel(videoTex, videoSampler, uv + gOffset, 0.0).g;
    let b = textureSampleLevel(videoTex, videoSampler, uv + bOffset, 0.0).b;

    // Vignette
    let vig = 1.0 - amount * 0.3;

    var color = vec3<f32>(r, g, b) * vig;

    // Show focus ring if clicking
    if (click > 0.5) {
        let ring = abs(dist - focusRad);
        if (ring < 0.005) {
            color += vec3<f32>(0.5, 0.5, 0.5);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    //  WAVELENGTH-DEPENDENT ALPHA
    //  Thickness derived from focus blur amount
    // ═══════════════════════════════════════════════════════════════════════════════
    let blurThickness = amount * 5.0 + blurAmt * 2.0;
    let dispersionThickness = blurThickness;
    
    let alphaR = calculateChannelAlpha(dispersionThickness, WAVELENGTH_RED);
    let alphaG = calculateChannelAlpha(dispersionThickness, WAVELENGTH_GREEN);
    let alphaB = calculateChannelAlpha(dispersionThickness, WAVELENGTH_BLUE);
    
    let luminanceWeights = vec3<f32>(0.299, 0.587, 0.114);
    let finalAlpha = dot(vec3<f32>(alphaR, alphaG, alphaB), luminanceWeights);
    
    let finalColor = vec3<f32>(
        color.r * alphaR,
        color.g * alphaG,
        color.b * alphaB
    );

    textureStore(outTex, gid.xy, vec4<f32>(finalColor, finalAlpha));
    
    // Pass through depth
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    textureStore(outDepth, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
