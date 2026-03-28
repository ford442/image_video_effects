// ═══════════════════════════════════════════════════════════════
//  RGB Topology - Contour visualization with RGB parallax and wavelength-alpha
//  Category: artistic
//  Features: contour-lines, depth-parallax, wavelength-dependent-alpha
//
//  SCIENTIFIC MODEL:
//  - Dispersion parallax affects both position AND alpha per channel
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
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mouse = u.zoom_config.yz;

    // Params
    let density = mix(10.0, 100.0, u.zoom_params.x);
    let parallax = u.zoom_params.y * 0.1;
    let lineThickness = u.zoom_params.z * 0.2 + 0.05;
    let glow = u.zoom_params.w;

    // Parallax logic - Mouse determines view angle
    let tilt = (mouse - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0) * parallax;

    // Offsets - R closest, B furthest
    let offsetR = tilt * 1.0;
    let offsetG = tilt * 0.5;
    let offsetB = tilt * 0.0;

    let rVal = textureSampleLevel(readTexture, u_sampler, uv + offsetR, 0.0).r;
    let gVal = textureSampleLevel(readTexture, u_sampler, uv + offsetG, 0.0).g;
    let bVal = textureSampleLevel(readTexture, u_sampler, uv + offsetB, 0.0).b;

    // Generate contours
    let rLine = smoothstep(lineThickness, 0.0, abs(sin(rVal * density + u.config.x)));
    let gLine = smoothstep(lineThickness, 0.0, abs(sin(gVal * density + u.config.x * 1.1)));
    let bLine = smoothstep(lineThickness, 0.0, abs(sin(bVal * density + u.config.x * 0.9)));

    // Composite
    var finalColor = vec3<f32>(0.0);

    finalColor += vec3<f32>(rLine, 0.0, 0.0);
    finalColor += vec3<f32>(0.0, gLine, 0.0);
    finalColor += vec3<f32>(0.0, 0.0, bLine);

    // Add glow
    if (glow > 0.0) {
        finalColor += vec3<f32>(rVal, 0.0, 0.0) * glow * 0.5;
        finalColor += vec3<f32>(0.0, gVal, 0.0) * glow * 0.5;
        finalColor += vec3<f32>(0.0, 0.0, bVal) * glow * 0.5;
    }

    // Background dimming
    finalColor += vec3<f32>(0.05);

    // ═══════════════════════════════════════════════════════════════
    //  WAVELENGTH-DEPENDENT ALPHA
    //  Thickness derived from parallax amount
    // ═══════════════════════════════════════════════════════════════
    let parallaxLength = length(tilt);
    let dispersionThickness = parallaxLength * 15.0;
    
    let alphaR = calculateChannelAlpha(dispersionThickness, WAVELENGTH_RED);
    let alphaG = calculateChannelAlpha(dispersionThickness, WAVELENGTH_GREEN);
    let alphaB = calculateChannelAlpha(dispersionThickness, WAVELENGTH_BLUE);
    
    let luminanceWeights = vec3<f32>(0.299, 0.587, 0.114);
    let finalAlpha = dot(vec3<f32>(alphaR, alphaG, alphaB), luminanceWeights);
    
    let alphaModulatedColor = vec3<f32>(
        finalColor.r * alphaR,
        finalColor.g * alphaG,
        finalColor.b * alphaB
    );

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(alphaModulatedColor, finalAlpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
