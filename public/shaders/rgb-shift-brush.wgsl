// ═══════════════════════════════════════════════════════════════
//  RGB Shift Brush - Feedback-based RGB displacement with wavelength-alpha
//  Category: artistic
//  Features: feedback, brush-dispersion, wavelength-dependent-alpha
//
//  SCIENTIFIC MODEL:
//  - Dispersion shift affects both position AND alpha per channel
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
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.zoom_config.x;
    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Params
    let shiftAmount = u.zoom_params.x * 0.1;
    let brushSize = mix(0.01, 0.2, u.zoom_params.y);
    let decay = mix(0.9, 0.995, u.zoom_params.z);
    let hueShift = u.zoom_params.w;

    // 1. Update Feedback Mask
    let prevVal = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

    // Calculate Brush Influence
    let aspect = resolution.x / resolution.y;
    let dVec = (uv - mouse) * vec2(aspect, 1.0);
    let dist = length(dVec);
    let brush = smoothstep(brushSize, brushSize * 0.5, dist);

    // New mask value
    let newVal = min(1.0, prevVal * decay + brush);

    // Write to DataTextureA for next frame
    textureStore(dataTextureA, global_id.xy, vec4(newVal, 0.0, 0.0, 1.0));

    // 2. Render Effect
    let shift = shiftAmount * newVal;

    // Shift direction based on time
    let angle = time * 2.0;
    var dir = vec2(cos(angle), sin(angle));

    let r_uv = uv + dir * shift;
    let b_uv = uv - dir * shift;

    var r = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    var b = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;

    // Optional Hue Shift on the trail
    if (hueShift > 0.0) {
        if (newVal > 0.1) {
           r = mix(r, 1.0 - r, hueShift * newVal);
           b = mix(b, 1.0 - b, hueShift * newVal);
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  WAVELENGTH-DEPENDENT ALPHA
    //  Thickness derived from shift amount and mask value
    // ═══════════════════════════════════════════════════════════════
    let dispersionThickness = shift * 10.0 + newVal * 2.0;
    
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

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4(finalColor, finalAlpha));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
