// ═══════════════════════════════════════════════════════════════════
//  Anamorphic Flare
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, lens-flare, upgraded-rgba
//  Complexity: Medium
//  Chunks From: anamorphic-flare
//  Upgraded: 2026-09-11, 2026-11-09
//  Ideas: threshold-gated highlight streak; blue-line ghost; oval 2:1 anamorphic ghosts;
//         power-law glare tail (soft inverse-square, §12.2F); per-channel streak extent
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 6: Luminance Key Alpha
fn luminanceKeyAlpha(color: vec3<f32>, threshold: f32, softness: f32) -> f32 {
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    return smoothstep(threshold - softness, threshold + softness, luma);
}

// Mode 5: Effect Intensity Alpha
fn effectIntensityAlpha(intensity: f32, falloff: f32) -> f32 {
    return mix(0.3, 1.0, intensity * falloff);
}

// Combined flare alpha
fn calculateFlareAlpha(
    color: vec3<f32>,
    intensity: f32,
    params: vec4<f32>
) -> f32 {
    let lumaAlpha = luminanceKeyAlpha(color, params.y, params.z * 0.2);
    let effectAlpha = effectIntensityAlpha(intensity, params.x);
    return clamp(lumaAlpha * effectAlpha, 0.0, 1.0);
}

const PI: f32 = 3.14159265359;
const TWO_PI: f32 = 6.28318530718;

fn hexagonAperture(uv: vec2<f32>, size: f32, soft: f32) -> f32 {
    let r = length(uv);
    let angle = atan2(uv.y, uv.x);
    let sectorAngle = fract(angle / (PI / 3.0)) * (PI / 3.0) - PI / 6.0;
    let dist = r * cos(sectorAngle) / cos(PI / 6.0);
    return smoothstep(size + soft, size - soft, dist);
}

fn spectralDispersion(angle: f32, dispersion: f32) -> vec3<f32> {
    let redOffset = 1.0 - dispersion * 0.3;
    let greenOffset = 1.0;
    let blueOffset = 1.0 + dispersion * 0.5;
    return vec3<f32>(redOffset, greenOffset, blueOffset);
}

fn anamorphicStreak(uv: vec2<f32>, lightPos: vec2<f32>, streakLength: f32, width: f32, dispersion: f32) -> vec3<f32> {
    let toLight = uv - lightPos;
    let distX = abs(toLight.x);
    let distY = abs(toLight.y);
    // ── Idea 3: per-channel streak extent ───────────────────────────────
    // A dispersive element stretches each wavelength to a different length along the
    // streak: all channels agree at the core (blue-white) and the tail runs blue
    // (red shortest, blue longest). HEAD multiplied a blue tint by distance instead;
    // here the colour lives in the extent. A small baseline keeps it visible at Color Shift 0.
    let dd = 0.25 + dispersion;
    let ext = clamp(vec3<f32>(1.0 - 0.45 * dd, 1.0, 1.0 + 0.8 * dd), vec3<f32>(0.3), vec3<f32>(3.0));
    let hStreak = exp(-distX / (streakLength * ext)) * exp(-distY * 50.0 / width);
    let vStreak = exp(-distY / (streakLength * 0.1)) * exp(-distX * 100.0 / width);
    let streak = hStreak * 0.9 + vec3<f32>(vStreak * 0.1);
    let baseTint = vec3<f32>(0.5, 0.7, 1.0);
    return streak * baseTint;
}

// ── Idea 1: anamorphic ghosts are 2:1 ovals ───────────────────────────
// An anamorphic lens squeezes the image 2:1 horizontally, so its iris images (ghosts,
// bokeh) are hexagons stretched ×2 along x. HEAD drew round hexagons (spherical iris).
const ANAMORPHIC_SQUEEZE: f32 = 2.0;

fn ghostElement(uv: vec2<f32>, lightPos: vec2<f32>, offset: vec2<f32>, size: f32, intensity: f32, aspectVec: vec2<f32>) -> vec3<f32> {
    let center = vec2<f32>(0.5, 0.5);
    let ghostPos = center + (center - lightPos) * offset * 2.0 + offset;
    // aspect-corrected, then squeezed: the ghost is a circle-of-the-lens drawn as a 2:1 oval
    let dv = (uv - ghostPos) * aspectVec * vec2<f32>(1.0 / ANAMORPHIC_SQUEEZE, 1.0);
    let dist = length(dv);
    // soft rim: a ghost is an out-of-focus iris image, not a cut-out
    let hex = hexagonAperture(dv / size, 0.8, 0.12);
    let falloff = exp(-dist * dist * 8.0 / size);
    let ghostTint = vec3<f32>(1.0, 0.95, 0.9);
    return hex * falloff * intensity * ghostTint;
}

fn volumetricRays(uv: vec2<f32>, lightPos: vec2<f32>, intensity: f32) -> f32 {
    let toLight = lightPos - uv;
    let angle = atan2(toLight.y, toLight.x);
    let dist = length(toLight);
    // ── Rescue R3: pow(sin(..), 4.0) has a possibly NEGATIVE base (undefined → NaN on real GPUs);
    // sin⁴ written as a product is identical for every valid input.
    let rs = sin(angle * 12.0 + dist * 20.0);
    let rs2 = rs * rs;
    let rayPattern = rs2 * rs2;
    let radialFalloff = 1.0 / (1.0 + dist * 3.0);
    return rayPattern * radialFalloff * intensity * 0.3;
}

fn centralGlow(uv: vec2<f32>, lightPos: vec2<f32>, size: f32) -> vec3<f32> {
    let dist = length(uv - lightPos);
    let core = exp(-dist * 15.0 / size);
    let corona = exp(-dist * 5.0 / size) * 0.3;
    let glowTint = vec3<f32>(0.8, 0.9, 1.0);
    return (core + corona) * glowTint;
}

// ── Idea 2: power-law glare tail (soft inverse-square, §12.2F) ──────────
// Real veiling glare falls off as ~1/(r²+r0²), not exponentially; HEAD's glow is two
// exponentials that end abruptly. The long exp() factor only bounds the tail to the frame.
// uvA / lightA are aspect-corrected so the veil is round on any canvas.
fn glareTail(uvA: vec2<f32>, lightA: vec2<f32>, r0: f32) -> vec3<f32> {
    let d = uvA - lightA;
    let d2 = dot(d, d);
    let inv = (r0 * r0) / (d2 + r0 * r0);
    return inv * exp(-sqrt(d2) * 2.0) * vec3<f32>(0.8, 0.9, 1.0);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let lightPos = u.zoom_config.yz;
    let time = u.config.x;
    // ── Rescue R1: aspect-correct the radial terms ────────────────────────
    // HEAD measured glow / rays / starburst / halo / ghost shapes in raw uv, so on 16:9 they
    // were ellipses. The streak and blue line stay in uv (their length is a fraction of the
    // frame width by design). Identical at aspect 1.
    let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
    let uvA = uv * aspectVec;
    let lightA = lightPos * aspectVec;
    let hasAudio = arrayLength(&plasmaBuffer) > 0u;
    let bass = select(0.0, plasmaBuffer[0].x, hasAudio);
    let treble = select(0.0, plasmaBuffer[0].z, hasAudio);

    // JSON: width, intensity, color, threshold
    let streakLength = u.zoom_params.x * 0.8 + 0.05;
    let flareIntensity = u.zoom_params.y * 3.0;
    let dispersion = u.zoom_params.z * 2.0;
    let threshold = u.zoom_params.w;

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let lightSrc = textureSampleLevel(readTexture, u_sampler, clamp(lightPos, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let lightLuma = dot(lightSrc.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let highlightGate = smoothstep(threshold, threshold + 0.18, lightLuma);

    var flareColor = vec3<f32>(0.0);
    let streak = anamorphicStreak(uv, lightPos, streakLength, 2.0, dispersion);
    flareColor += streak * flareIntensity * highlightGate;

    let blueLine = anamorphicStreak(uv, lightPos + vec2<f32>(0.0, 0.018), streakLength * 0.85, 1.4, dispersion * 0.4);
    flareColor += blueLine * vec3<f32>(0.25, 0.55, 1.0) * flareIntensity * 0.55 * highlightGate;

    let ghostCount = i32(clamp(1.0 + highlightGate * 4.0, 1.0, 5.0));
    for (var i: i32 = 0; i < ghostCount; i++) {
        let fi = f32(i);
        let ghostOffset = vec2<f32>(
            sin(fi * 1.3 + time * 0.1) * 0.15 + fi * 0.08,
            cos(fi * 0.7) * 0.1 + fi * 0.05
        );
        let ghostSize = 0.08 - fi * 0.01;
        // ghosts are now whole oval discs (R2) instead of slivers, so they carry ~half HEAD's per-ghost gain
        let ghostIntensity = (0.4 - fi * 0.06) * 0.55 * flareIntensity * highlightGate;
        let ghost = ghostElement(uv, lightPos, ghostOffset, ghostSize, ghostIntensity, aspectVec);
        // ── Rescue R2: the outer aperture was centred WITHOUT the `+ ghostOffset` that
        // ghostElement uses, so the product of the two hexes was a clipped sliver /
        // parallelogram, not a ghost. Both apertures now share the ghost centre; the outer one
        // (1.5·size vs the disc's 0.8·size) only bounds the disc. Same aspect + 2:1 squeeze (Idea 1).
        let ghostCentre = vec2<f32>(0.5) + (vec2<f32>(0.5) - lightPos) * ghostOffset * 2.0 + ghostOffset;
        let toGhost = (uv - ghostCentre) * aspectVec * vec2<f32>(1.0 / ANAMORPHIC_SQUEEZE, 1.0);
        let hexPattern = hexagonAperture(toGhost / max(ghostSize * 3.0, 0.001), 0.5, 0.01);
        let ghostDist = length(toGhost);
        let ghostDispersion = spectralDispersion(ghostDist * 10.0, dispersion * 0.5);
        flareColor += ghost * hexPattern * ghostDispersion;
    }

    let glow = centralGlow(uvA, lightA, 0.15);
    flareColor += glow * flareIntensity * 0.8 * highlightGate;
    // ── Idea 2: power-law glare tail (soft inverse-square) ──────────────
    flareColor += glareTail(uvA, lightA, 0.06) * flareIntensity * 0.5 * highlightGate;
    let rays = volumetricRays(uvA, lightA, flareIntensity);
    flareColor += vec3<f32>(rays * 0.5, rays * 0.6, rays * 0.8) * highlightGate;
    let toLight = uvA - lightA;
    let angle = atan2(toLight.y, toLight.x);
    let dist = length(toLight);
    let starburst = pow(abs(sin(angle * 6.0)), 20.0) * exp(-dist * 3.0);
    flareColor += vec3<f32>(starburst * 0.3 * flareIntensity) * highlightGate;
    let haloDist = abs(dist - 0.25);
    let haloIntensity = exp(-haloDist * 100.0) * dispersion * 0.5;
    let rainbowPhase = angle * 3.0;
    let rainbow = vec3<f32>(
        (sin(rainbowPhase) + 1.0) * 0.5,
        (sin(rainbowPhase + TWO_PI / 3.0) + 1.0) * 0.5,
        (sin(rainbowPhase + 2.0 * TWO_PI / 3.0) + 1.0) * 0.5
    );
    flareColor += rainbow * haloIntensity * flareIntensity * 0.2 * highlightGate;
    flareColor *= 1.0 + bass * 0.2 + treble * 0.1;

    let mapped = aces(baseColor.rgb + flareColor);
    let alpha = calculateFlareAlpha(flareColor, flareIntensity, u.zoom_params) * baseColor.a;
    let display = vec4<f32>(mapped, max(baseColor.a, alpha));

    textureStore(writeTexture, vec2<i32>(global_id.xy), display);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), display);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
