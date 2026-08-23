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

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture:    texture_2d<f32>;
@group(0) @binding(2) var writeTexture:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture:   texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
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

@compute @workgroup_size(16, 16, 1)
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
    let dir = distVec / max(dist, 1e-5);
    let time = u.config.x;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let held = select(0.0, 1.0, click > 0.5);
    let squeeze = held * exp(-dist * 8.0) * (0.015 + strength * 0.4);

    // Chromatic Aberration
    var irisShell = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        irisShell += exp(-age * 1.8) * exp(-abs(length((uv - event.xy) * vec2<f32>(aspect, 1.0)) - age * 0.36) * 65.0);
    }
    let caustic = sin(dist * (35.0 + focusRad * 90.0) - time * (1.0 + audio.y * 4.0)) * amount;
    let rOffset = dir * (amount * strength + squeeze + irisShell * 0.008);
    let bOffset = -dir * (amount * strength + squeeze + irisShell * 0.008);
    let gOffset = vec2<f32>(0.0);

    let blurRadius = blurAmt * amount * (0.002 + audio.x * 0.006);
    let tangent = vec2<f32>(-dir.y, dir.x);
    let r = (textureSampleLevel(readTexture, u_sampler, clamp(uv + rOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r +
      textureSampleLevel(readTexture, u_sampler, clamp(uv + rOffset + tangent * blurRadius, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r +
      textureSampleLevel(readTexture, u_sampler, clamp(uv + rOffset - tangent * blurRadius, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r) / 3.0;
    let g = (textureSampleLevel(readTexture, u_sampler, clamp(uv + gOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g +
      textureSampleLevel(readTexture, u_sampler, clamp(uv + tangent * blurRadius, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g +
      textureSampleLevel(readTexture, u_sampler, clamp(uv - tangent * blurRadius, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g) / 3.0;
    let b = (textureSampleLevel(readTexture, u_sampler, clamp(uv + bOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b +
      textureSampleLevel(readTexture, u_sampler, clamp(uv + bOffset + tangent * blurRadius, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b +
      textureSampleLevel(readTexture, u_sampler, clamp(uv + bOffset - tangent * blurRadius, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b) / 3.0;

    // Vignette
    let vig = 1.0 - amount * 0.3;

    var color = vec3<f32>(r, g, b) * vig;
    color += (0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + caustic * 4.0 + time)) * (abs(caustic) * 0.10 + irisShell * 0.24);

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

    textureStore(writeTexture, gid.xy, vec4<f32>(finalColor, finalAlpha));
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
