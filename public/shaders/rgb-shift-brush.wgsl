// ═══════════════════════════════════════════════════════════════
//  RGB Shift Brush - Feedback-based RGB displacement with spectral alpha
//  Category: artistic
//  Features: feedback, brush-dispersion, wavelength-dependent-alpha
//
//  STYLIZED SPECTRAL MODEL:
//  - Dispersion shifts position and maps trail thickness to channel alpha
//  - Named wavelength bands provide a stable artistic color ordering
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
//  SPECTRAL BAND CONSTANTS
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
    let time = u.config.x;
    var mouse = u.zoom_config.yz;
    let held = step(0.5, u.zoom_config.w);
    let audio = plasmaBuffer[0].xyz;

    // Params
    let shiftAmount = u.zoom_params.x * 0.1;
    let brushSize = mix(0.01, 0.2, u.zoom_params.y);
    let decay = mix(0.9, 0.995, u.zoom_params.z);
    let hueShift = u.zoom_params.w;

    let spectralRunner = pow(max(0.0, sin((uv.x + uv.y * 0.31) * 52.0 - time * (15.0 + audio.y * 7.0))), 14.0);
    let ribbonRunner = pow(max(0.0, sin((uv.y - uv.x * 0.18) * 64.0 - time * (20.0 + audio.z * 8.0))), 18.0);
    let feedbackFlow = vec2<f32>(cos(time * 1.7), sin(time * 1.3)) * shiftAmount * 0.08 * (0.25 + spectralRunner);
    let historyCoord = clamp(vec2<i32>((uv - feedbackFlow) * resolution), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));

    // 1. Update Feedback Mask using exact prior-state texels.
    let prevVal = textureLoad(dataTextureC, historyCoord, 0).r;

    // Calculate Brush Influence
    let aspect = resolution.x / resolution.y;
    let dVec = (uv - mouse) * vec2(aspect, 1.0);
    let dist = length(dVec);
    let brush = smoothstep(brushSize, brushSize * 0.5, dist) * mix(0.12, 1.0, held);

    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var rippleIndex: u32 = 0u; rippleIndex < rippleCount; rippleIndex = rippleIndex + 1u) {
        let ripple = u.ripples[rippleIndex];
        let rippleAge = max(time - ripple.z, 0.0);
        let front = abs(distance(uv, ripple.xy) - rippleAge * (0.22 + audio.x * 0.12));
        clickFront += exp(-front * 125.0) * exp(-rippleAge * 1.6);
    }

    // New mask value
    let newVal = clamp(prevVal * decay + brush + clickFront * 0.35 + ribbonRunner * audio.z * 0.025, 0.0, 1.0);

    // Write to DataTextureA for next frame
    textureStore(dataTextureA, global_id.xy, vec4(newVal, 0.0, 0.0, 1.0));

    // 2. Render Effect
    let shift = shiftAmount * newVal * (1.0 + audio.x * 0.35 + spectralRunner * 0.25);

    // Shift direction based on time
    let angle = time * (2.0 + audio.y * 1.4) + ribbonRunner * 0.45;
    var dir = vec2(cos(angle), sin(angle));

    let r_uv = clamp(uv + dir * shift, vec2<f32>(0.0), vec2<f32>(1.0));
    let b_uv = clamp(uv - dir * shift, vec2<f32>(0.0), vec2<f32>(1.0));

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
    
    let finalColor = clamp(vec3<f32>(
        r * alphaR,
        g * alphaG,
        b * alphaB
    ) + vec3<f32>(0.18, 0.48, 1.0) * spectralRunner * audio.y * 0.08 +
        vec3<f32>(1.0, 0.22, 0.55) * clickFront * 0.08,
        vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4(finalColor, finalAlpha));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
