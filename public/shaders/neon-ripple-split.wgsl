// ═══════════════════════════════════════════════════════════════════
//  Neon Ripple Split
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba, semantic-alpha
//  Complexity: Medium
//  Upgraded: 2026-10-05
//  Ideas: crest RGB split along the shear axis; neon seam lines at shear zero crossings (alpha = max(displacement, seam))
//  A packing: linear pre-ACES RGBA (12% feedback, exact C load); (0,0) = bass env + sentinel -7 in .w
// ═══════════════════════════════════════════════════════════════════
//  A sine shear runs down the screen and displaces the image in x; pink
//  neon and a spectral tint light up where the displacement peaks. Hold the
//  mouse for a gravity well, click for ripples.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Shear Amount, y=Ripple Speed, z=Glow Intensity, w=Frequency (spatial, mix(8,40,w))

const TAU: f32 = 6.28318530717958647692;
const STATE_SENTINEL: f32 = -7.0;

// ═══ Audio envelope (smooth attack/release) ═══
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

// ═══ Gravity well (mouse attraction) ═══
fn gravityWell(pos: vec2<f32>, wellPos: vec2<f32>, strength: f32) -> vec2<f32> {
    let d = wellPos - pos;
    let dist2 = dot(d, d) + 0.01;
    return (d / max(length(d), 1e-4)) * strength / dist2;
}

// ═══ Tent alpha curve ═══
fn tentAlpha(x: f32) -> f32 {
    return smoothstep(0.0, 0.4, x) * (1.0 - smoothstep(0.4, 1.0, x));
}

// Spectral tint for mix-based color variation.
fn wavelengthToRGB(offset: f32) -> vec3<f32> {
    let t = fract(offset);
    let r = smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(0.5, 0.8, t));
    let g = smoothstep(0.2, 0.5, t) * (1.0 - smoothstep(0.7, 1.0, t));
    let b = smoothstep(0.5, 0.8, t) * (1.0 - smoothstep(0.9, 1.0, t) + smoothstep(0.0, 0.2, t));
    return vec3<f32>(r, g, b);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn safeRGB(v: vec3<f32>) -> vec3<f32> {
    return clamp(select(vec3<f32>(0.0), v, v == v), vec3<f32>(0.0), vec3<f32>(16.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;
    let bass = plasmaBuffer[0].x;

    // ─── Audio envelope with attack/release, persisted in the (0,0) state texel ───
    // FIX: every pixel reads the env from C(0,0); valid only behind the sentinel.
    let stateRaw = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    let stateOk = stateRaw.w == STATE_SENTINEL && stateRaw.r == stateRaw.r;
    let prevEnv = select(0.0, clamp(stateRaw.r, 0.0, 4.0), stateOk);
    let env = bass_env(prevEnv, bass, 0.8, 0.15);

    // ─── Parameters ───
    let splitAmount = u.zoom_params.x * 0.1 * (1.0 + env * 0.3);
    let rippleSpeed = u.zoom_params.y * 5.0;
    let intensity   = u.zoom_params.z * 2.0;
    // FIX: w is the spatial frequency of the shear (default 0.5 → 20, HEAD's
    // constant) and no longer multiplies the amplitude.
    let frequency   = mix(8.0, 32.0, u.zoom_params.w);

    // Mouse X modulates ripple speed, Mouse Y drives spectral phase
    let mouseSpeedMod = 1.0 + mousePos.x * 0.5;
    let effectiveRippleSpeed = rippleSpeed * mouseSpeedMod;
    let mouseTintPhase = mousePos.y * TAU * 0.5;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ─── Gravity well attracts ripples when mouse is clicked ───
    let wellStrength = select(0.0, 0.05, isMouseDown) * (1.0 + env * 0.5);
    let gWell = gravityWell(uv, mousePos, wellStrength);
    let gravityOffset = gWell * 0.02;

    // ─── Ripple system integration ───
    var rippleSum = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time - rStart;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = distance(uv, rPos);
            let rWave = sin(rDist * 40.0 - rElapsed * 8.0) * exp(-rElapsed * 1.5);
            rippleSum = rippleSum + rWave * (1.0 - smoothstep(0.0, 0.3, rDist));
        }
    }

    // ─── Single smooth displacement field (NO per-channel UVs) ───
    let shearPhase = uv.y * frequency - time * effectiveRippleSpeed;
    let shearWave = sin(shearPhase);
    let baseRipple = shearWave * splitAmount;
    let dx = (baseRipple + rippleSum) * (1.0 + depth * 0.5);
    let smoothOffset = vec2<f32>(dx, 0.0) + gravityOffset;
    let displacedUV = clamp(uv + smoothOffset, vec2<f32>(0.0), vec2<f32>(1.0));

    // ── Idea 1: crest RGB split — at the crests of the shear (|sin| → 1) the
    // R and B channels sample ±dx*0.15 apart along the shear (x) axis, G stays
    // on the unified UV. Zero at the zero crossings, so flat regions stay clean.
    let crest = smoothstep(0.45, 1.0, abs(shearWave));
    let splitOff = vec2<f32>(dx * 0.15 * crest, 0.0);
    let sampleG = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;
    let sampleR = textureSampleLevel(readTexture, u_sampler, clamp(displacedUV + splitOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let sampleB = textureSampleLevel(readTexture, u_sampler, clamp(displacedUV - splitOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let baseColor = vec3<f32>(sampleR, sampleG.g, sampleB);

    // ─── Temporal feedback via dataTextureC (exact load; C holds linear colour) ───
    let displacementMagnitude = length(smoothOffset);
    let prevColor = safeRGB(textureLoad(dataTextureC, coord, 0).rgb);
    let feedbackMix = tentAlpha(displacementMagnitude * 2.0) * 0.12;
    let feedbackColor = mix(baseColor, prevColor, feedbackMix);

    // ─── Spectral tint via mix(), NOT per-channel sampling ───
    let wavelengthOffset = uv.x * 2.0 + time * 0.3 + abs(dx) * 10.0 + mouseTintPhase;
    let spectralTint = wavelengthToRGB(wavelengthOffset);
    let tintStrength = tentAlpha(abs(dx) * 5.0) * intensity * 0.5;
    let tintedColor = mix(feedbackColor, feedbackColor * spectralTint * 1.5, tintStrength);

    // Neon emission proportional to displacement magnitude
    let absRipple = abs(baseRipple) + abs(rippleSum) * 0.5;
    let neon = vec3<f32>(1.0, 0.5, 0.8) * absRipple * 10.0 * intensity;

    // ── Idea 2: neon seam lines — a thin horizontal seam where the shear
    // crosses zero (|sin| < ~0.12 → ~6 px at 1080p for frequency 20), lit in
    // the pink neon mixed with the spectral tint and pumped by the bass env.
    let seam = pow(1.0 - smoothstep(0.0, 0.12, abs(shearWave)), 2.0);
    let seamColor = mix(vec3<f32>(1.0, 0.5, 0.8), spectralTint * 1.5, 0.5) * seam * intensity * (0.5 + env * 0.6) * 0.8;
    let finalColor = tintedColor + neon + seamColor;

    // ─── Alpha = max(ripple displacement * bass pulse + neon emission, seam) ───
    let bassPulse = 0.3 + env * 0.7;
    let neonAlpha = absRipple * 0.4 * intensity;
    let seamAlpha = seam * clamp(intensity, 0.0, 1.0) * 0.9;
    let alpha = clamp(max(displacementMagnitude * bassPulse * 10.0 + neonAlpha, seamAlpha), 0.0, 1.0);

    let display = acesToneMap(max(finalColor, vec3<f32>(0.0)));
    textureStore(writeTexture, coord, vec4<f32>(display, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));

    // Persist env at (0,0) (single writer, sentinel in .w); linear colour everywhere else
    if (coord.x == 0 && coord.y == 0) {
        textureStore(dataTextureA, coord, vec4<f32>(env, 0.0, 0.0, STATE_SENTINEL));
    } else {
        textureStore(dataTextureA, coord, vec4<f32>(max(finalColor, vec3<f32>(0.0)), alpha));
    }
}
