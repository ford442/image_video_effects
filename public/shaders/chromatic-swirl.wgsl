// ═══════════════════════════════════════════════════════════════════
//  Chromatic Swirl
//  Category: distortion
//  Features: mouse-driven, audio-reactive, rich-chromatic-aberration, volumetric-swirl, depth-falloff, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-08, 2026-11-20
//  Ideas: angular chromatic (R/G/B at different swirl angles); animate as continuous spin; Cauchy radial lateral colour (§12.2F); Rayleigh in-scatter of the absorbed light (§12.2F)
//  A packing: telemetry (dist/radius, angle, aberration, alpha)
// ═══════════════════════════════════════════════════════════════════

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

// ─────────────────────────────────────────────────────────────────────────────
// ACES Tone Mapping
// ─────────────────────────────────────────────────────────────────────────────
fn aces_tonemap(color: vec3<f32>) -> vec3<f32> {
    let m1 = mat3x3<f32>(
        0.59719, 0.07600, 0.02840,
        0.35458, 0.90834, 0.13383,
        0.04823, 0.01566, 0.83777
    );
    let m2 = mat3x3<f32>(
        1.60475, -0.10208, -0.00327,
        -0.53108,  1.10813, -0.07276,
        -0.07367, -0.00605,  1.07602
    );
    let v = m1 * color;
    let a = v * (v + 0.0245786) - 0.000090537;
    let b = v * (0.983729 * v + 0.4329510) + 0.238081;
    return clamp(m2 * (a / b), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.zoom_config.x;
    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    // Params
    let swirlStrength = (5.0 + u.zoom_params.x * 10.0) * (1.0 + bass * 0.25);
    let radius = 0.3 + u.zoom_params.y * 0.5;
    let aberration = 0.02 + u.zoom_params.z * 0.05 + treble * 0.02;
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
    var percent = 0.0;
    if (dist < radius) {
        percent = (radius - dist) / radius;
        angle = percent * percent * swirlStrength;
        // Animate as continuous spin when the toggle is on (not a sin pulse).
        angle += select(0.0, time * (1.4 + mids) * percent, animate > 0.5);
        if (mouseDown > 0.5) {
            angle *= 2.0;
        }
    }

    let swirlSpeed = 1.0 + mids * 1.8;
    let extraTwist = sin(time * swirlSpeed + dist * 18.0) * (0.3 + treble * 0.6);
    let baseAngle = angle + extraTwist;

    let offset = uv - center;
    let x_corr = offset.x * aspect;
    let y_corr = offset.y;
    let angR = baseAngle * (1.0 + aberration * 2.8);
    let angG = baseAngle;
    let angB = baseAngle * (1.0 - aberration * 2.2);

    // ── Idea 1: Cauchy radial lateral colour (§12.2F) ───────────────
    // n(λ) = A + B/λ²: a wavelength-dependent medium also magnifies each channel
    // differently, on top of the per-channel swirl angle. λ in µm from the
    // WAVELENGTH_* constants this file already owns; strength rides `aberration`.
    // R is sampled nearer the pointer (larger image), B farther (smaller image).
    let lamUm = vec3<f32>(WAVELENGTH_RED, WAVELENGTH_GREEN, WAVELENGTH_BLUE) * 0.001;
    let invLam2 = vec3<f32>(1.0) / (lamUm * lamUm);
    let cauchyScale = vec3<f32>(1.0) + aberration * 0.25 * (invLam2 - vec3<f32>(invLam2.y));
    let xyR = vec2<f32>(x_corr, y_corr) * cauchyScale.x;
    let xyG = vec2<f32>(x_corr, y_corr) * cauchyScale.y;
    let xyB = vec2<f32>(x_corr, y_corr) * cauchyScale.z;
    let uvR = clamp(vec2<f32>(
        (xyR.x * cos(angR) - xyR.y * sin(angR)) / aspect,
        xyR.x * sin(angR) + xyR.y * cos(angR)
    ) + center, vec2<f32>(0.001), vec2<f32>(0.999));
    let uvG = clamp(vec2<f32>(
        (xyG.x * cos(angG) - xyG.y * sin(angG)) / aspect,
        xyG.x * sin(angG) + xyG.y * cos(angG)
    ) + center, vec2<f32>(0.001), vec2<f32>(0.999));
    let uvB = clamp(vec2<f32>(
        (xyB.x * cos(angB) - xyB.y * sin(angB)) / aspect,
        xyB.x * sin(angB) + xyB.y * cos(angB)
    ) + center, vec2<f32>(0.001), vec2<f32>(0.999));

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
    
    // === Visual Flourish: Rich atmospheric color + depth ===
    let transmit = vec3<f32>(alphaR, alphaG, alphaB);

    // ── Idea 2: Rayleigh in-scatter of the absorbed light (§12.2F) ──
    // Beer–Lambert above only removes energy (the thick core goes dead black).
    // A turbid medium re-emits a fraction ω of what it extinguishes, with a
    // λ⁻⁴ spectrum, so (1 − T) becomes a blue-weighted haze, never more than
    // ω of the removed light. Spectrum is luminance-normalised.
    let rayleigh = pow(vec3<f32>(WAVELENGTH_GREEN) / vec3<f32>(WAVELENGTH_RED, WAVELENGTH_GREEN, WAVELENGTH_BLUE), vec3<f32>(4.0));
    let rayleighTint = rayleigh / dot(rayleigh, luminanceWeights);
    let srcLuma = dot(vec3<f32>(r, g, b), luminanceWeights);
    let inScatter = (vec3<f32>(1.0) - transmit) * (0.18 * srcLuma) * rayleighTint;

    let baseCol = vec3<f32>(r, g, b) * transmit + inScatter;
    
    // Audio-reactive color temperature and saturation
    let warm = bass * 0.18;
    let cool = treble * 0.14;
    let col = baseCol * vec3<f32>(1.0 + warm, 1.0 - warm * 0.4 + cool * 0.15, 1.0 + cool);

    // Subtle volumetric swirl glow
    let swirlGlow = smoothstep(0.4, 2.0, abs(angle)) * 0.09;
    let finalCol = col + vec3<f32>(0.12, 0.1, 0.22) * swirlGlow * (0.4 + mids * 0.6);

    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, uvG, 0.0).r + dist * 0.05, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(aces_tonemap(finalCol), finalAlpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(dist / max(radius, 0.0001), angle / 12.0, aberration, finalAlpha));
}
