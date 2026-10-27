// ═══════════════════════════════════════════════════════════════
//  RGB Ripple Waves - Phase-shifted RGB waves with wavelength-alpha
//  Features: mouse-driven, phase-dispersion, wavelength-dependent-alpha, audio-reactive, upgraded-rgba
//  Upgraded: 2026-10-26
//  Ideas: deep-water channel speed (§12.2D); Cauchy phase (§12.2F)
//  A packing: ACES display RGBA
//  Beer-Lambert alpha stays per wavelength (650 / 550 / 450 nm).
// ═══════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

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

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// n(λ) = 1 + B/λ², λ in µm, relative to red so the red wave stays the anchor.
fn cauchyPhase(dispersion: f32) -> vec3<f32> {
    let invL2 = vec3<f32>(1.0 / 0.4225, 1.0 / 0.3025, 1.0 / 0.2025);
    let n = vec3<f32>(1.0) + dispersion * invL2;
    return (n / n.x - vec3<f32>(1.0)) * 50.6;
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

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    // Parameters — mids tighten the wavefronts, bass drives the amplitude
    let frequency = 50.0 * (1.0 + mids * 0.4) * mix(0.2, 3.0, u.zoom_params.x);
    let speed = 5.0 * (1.0 + bass * 0.3) * mix(0.1, 2.0, u.zoom_params.y);
    let amplitude = 0.02 * exp(-dist * 2.0) * (1.0 + bass * 0.6) * mix(0.0, 3.0, u.zoom_params.z);

    // ── Idea 2: Cauchy phase (§12.2F) ───────────────────────────────
    // Channel phase is B in n = 1 + B/λ². Red stays put; blue runs farther
    // than a linear 0,1,2 step. At the default slider this is near the old offset.
    let phase = cauchyPhase(mix(0.0, 0.12, u.zoom_params.w));
    // ── Idea 1: deep-water channel speed (§12.2D) ───────────────────
    // c ∝ sqrt(λ). Green keeps the slider speed.
    let speedScale = vec3<f32>(sqrt(WAVELENGTH_RED / WAVELENGTH_GREEN), 1.0, sqrt(WAVELENGTH_BLUE / WAVELENGTH_GREEN));

    let wave_r = sin(dist * frequency - time * speed * speedScale.x + phase.x);
    let wave_g = sin(dist * frequency - time * speed * speedScale.y + phase.y);
    let wave_b = sin(dist * frequency - time * speed * speedScale.z + phase.z);

    let dir_aspect = (uv_aspect - mouse_aspect) / max(dist, 0.001);
    let dir_uv = vec2<f32>(dir_aspect.x / aspect, dir_aspect.y);
    let ampMask = select(0.0, 1.0, dist > 0.001);
    let displacement_r = dir_uv * wave_r * amplitude * ampMask;
    let displacement_g = dir_uv * wave_g * amplitude * ampMask;
    let displacement_b = dir_uv * wave_b * amplitude * ampMask;

    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + displacement_r, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clamp(uv + displacement_g, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv + displacement_b, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

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
    
    var finalColor = vec3<f32>(
        r * alphaR,
        g * alphaG,
        b * alphaB
    );

    // Bass lights the wave crests as travelling spectral rings
    let crest = pow(max(0.0, wave_g), 8.0) * exp(-dist * 2.0);
    finalColor = finalColor + vec3<f32>(0.4, 0.7, 1.0) * crest * bass * 0.6;

    let outAlpha = clamp(finalAlpha + crest * bass * 0.3, 0.0, 1.0);
    let outColor = vec4<f32>(aces(max(finalColor, vec3<f32>(0.0))), outAlpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), outColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), outColor);

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
