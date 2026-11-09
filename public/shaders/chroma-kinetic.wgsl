// ═══════════════════════════════════════════════════════════════════
//  Chroma Kinetic
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, velocity-chromatic, directional-smear, upgraded-rgba
//  Complexity: High
//  Chunks From: chroma-kinetic, bass_env, temporal-feedback
//  Created: 2026-05-10
//  Upgraded: 2026-08-02, 2026-11-09
//  Ideas: motion-aligned lead/lag (the sprung centre's real velocity drives R-lead / B-lag and the smear, so the fringe follows the cursor's travel); Cauchy spectral fringe (five wavelength taps placed by n(λ)=A+B/λ², §12.2F Cauchy dispersion, calibrated to HEAD's R/B anchors). Rescued: the scratch-buffer spring never persisted (flick bonus was dead) — the sprung centre now lives in two A texels; dead per-sector FFT voices (spectrum bins above index 0 are never uploaded) removed.
//  A packing: RGBA before ACES (HEAD), C not read as colour. Texels (0,0) = (sprung centre.xy, centre velocity.xy) and (1,0) = (fract(lastTime), 0, 0, 0.7371 sentinel) are STATE, not pixels (top-left corner, invisible).
//  Notes: critically-damped sprung effect centre (omega 10), flick-speed strength bonus,
//         click kinetic bursts (ripples), bass/mids/treble smear mix.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Strength, y=Radius, z=LumaInfluence, w=Rotation

const SENT: f32 = 0.7371;

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.4 + mids * 0.15;
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

// ── Idea 2: Cauchy spectral fringe (§12.2F) ─────────────────────────────────
// n(λ) = A + B/λ² spaces the colours non-linearly: blue bends much more than red per nm.
// Five wavelength taps (660/600/550/500/450 nm) sit at their Cauchy fractions along the
// lead→lag segment, f = (1/λ² − 1/λ_R²)/(1/λ_B² − 1/λ_R²), then re-centred so the R channel's
// weighted centroid is HEAD's −lead and the B channel's is HEAD's +lag (G lands at its Cauchy
// position, −0.35 instead of the old arbitrary −0.5). Each channel integrates the taps with
// its own spectral response (weights sum to 1), so the three ghost copies of HEAD become a
// continuous rainbow fringe. At zero velocity every tap is the same pixel and the image is
// returned unchanged.
fn spectralFringe(uv: vec2<f32>, lead: vec2<f32>, lag: vec2<f32>) -> vec3<f32> {
  let span = lead + lag;                       // offset(f) = −lead + f·span
  let o0 = -lead + span * (-0.190);            // 660 nm
  let o1 = -lead + span * (0.037);             // 600 nm
  let o2 = -lead + span * (0.286);             // 550 nm
  let o3 = -lead + span * (0.613);             // 500 nm
  let o4 = -lead + span * (1.055);             // 450 nm
  let s0 = textureSampleLevel(readTexture, u_sampler, clamp(uv + o0, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let s1 = textureSampleLevel(readTexture, u_sampler, clamp(uv + o1, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let s2 = textureSampleLevel(readTexture, u_sampler, clamp(uv + o2, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let s3 = textureSampleLevel(readTexture, u_sampler, clamp(uv + o3, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let s4 = textureSampleLevel(readTexture, u_sampler, clamp(uv + o4, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let r = 0.265 * s0.r + 0.645 * s1.r + 0.089 * s2.r + 0.001 * s3.r;
  let g = 0.091 * s1.g + 0.726 * s2.g + 0.182 * s3.g + 0.001 * s4.g;
  let b = 0.124 * s3.b + 0.876 * s4.b;
  return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let mousePos = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));   // raw cursor = spring TARGET

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthMod = mix(0.5, 1.5, depth);

    // ── Sprung effect centre, persisted in two A texels ─────────────
    // HEAD kept this spring in the extra scratch buffer, which is re-uploaded zeroed every frame, so
    // it never persisted (centre = raw cursor, velocity always 0). Texel (0,0) = (pos.xy, vel.xy),
    // texel (1,0) = (fract(lastTime), 0, 0, SENT). Every thread integrates the same critically
    // damped step (omega 10) from the stored state; the sentinel guards the first frame / inherited C.
    // fract(time) keeps the stored time exact on rgba16float tiers.
    let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    let st1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
    let stateOk = abs(st1.w - SENT) < 0.001;
    var center = select(mousePos, st0.xy, stateOk);
    var centerVel = select(vec2<f32>(0.0), st0.zw, stateOk);
    let springDt = select(0.016, clamp(fract(time - st1.x), 0.001, 0.05), stateOk);
    let omega = 10.0;
    centerVel += ((mousePos - center) * (omega * omega) - centerVel * (2.0 * omega)) * springDt;
    center += centerVel * springDt;
    // f16 rest-snap (see cyber-ripples-coupled): a spring stored in rgba16float stalls ~2e-3 short of the
    // cursor with a residual velocity that never decays; settle exactly once near and slow.
    let settled = all(abs(mousePos - center) < vec2<f32>(0.004)) && length(centerVel) < 0.06;
    center = select(center, mousePos, settled);
    centerVel = select(centerVel, vec2<f32>(0.0), settled);

    // Kinetic flick bonus: fast cursor flicks smear harder (alive now: centerVel is real).
    let springSpeed = length(centerVel);
    var strength = u.zoom_params.x * 0.1 * bass_env(bass, mids) * depthMod;
    strength *= 1.0 + min(springSpeed * 3.0, 0.4);
    let radius = u.zoom_params.y;
    let lumaInf = u.zoom_params.z;
    let rotation = u.zoom_params.w * 6.28318;

    let diff = uv - center;
    let diffAspect = diff * vec2<f32>(aspect, 1.0);
    let dist = length(diffAspect);
    let dir = diffAspect / max(dist, 0.001);

    let c = cos(rotation);
    let s = sin(rotation);
    let rotDir = vec2<f32>(dir.x * c - dir.y * s, dir.x * s + dir.y * c);
    let uvOffsetDir = vec2<f32>(rotDir.x / max(aspect, 0.001), rotDir.y);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(baseColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let falloff = smoothstep(max(radius, 0.001), 0.0, dist);
    let modFactor = max(0.0, 1.0 + (luma - 0.5) * lumaInf * 2.0);

    // Velocity chromatic aberration: R leads, B lags based on motion direction
    var velocity = uvOffsetDir * strength * falloff * modFactor;

    // ── Idea 1: motion-aligned lead/lag ─────────────────────────────
    // The centre's real velocity (uv/s) is an exposure-length offset along the direction of
    // travel: R leads and B lags along it, and the smear below trails behind it. It is zero at
    // an idle cursor, so the idle look is HEAD's radial fringe. Direction Rot turns only the
    // radial field; the motion stays true to the cursor's travel.
    // 0.16 * Strength: equals the previous 0.03 + 0.1*Strength at the 0.5 default, but now goes to zero
    // with the slider (the constant base kept the fringe and a saturating alpha alive at Strength 0).
    var motion = centerVel * (0.16 * u.zoom_params.x);
    motion = motion * min(1.0, 0.12 / max(length(motion), 1e-5));
    velocity += motion * falloff * modFactor;

    // ── Click kinetic bursts ────────────────────────────────────────
    // Each live ripple fires a decaying directional smear pulse at its
    // click point: exp(-rippleAge * 2.0) boost, aspect-corrected ~0.25
    // radius, direction radial from the click, ~1.2s lifetime.
    let rippleTotal = min(u32(u.config.y), 50u);
    for (var ri: u32 = 0u; ri < rippleTotal; ri = ri + 1u) {
        let ripple = u.ripples[ri];
        let rippleAge = time - ripple.z;
        if (rippleAge >= 0.0 && rippleAge <= 1.2) {
            let toRipple = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let rippleDist = length(toRipple);
            let pulse = exp(-rippleAge * 2.0) * smoothstep(0.25, 0.0, rippleDist);
            let radialDir = toRipple / max(rippleDist, 0.001);
            let burstDir = vec2<f32>(radialDir.x / max(aspect, 0.001), radialDir.y);
            velocity += burstDir * pulse * strength * 2.0;
        }
    }

    let leadAmount = velocity * (1.0 + bass * 0.5);
    let lagAmount = velocity * (1.0 + mids * 0.3);

    let fringe = spectralFringe(uv, leadAmount, lagAmount);

    // Directional smear: sample along velocity vector for motion trails
    let smearSamples = 3;
    var smearR = 0.0;
    var smearG = 0.0;
    var smearB = 0.0;
    for (var i = 1; i <= smearSamples; i = i + 1) {
        let t = f32(i) / f32(smearSamples);
        let smearUV = clamp(uv + velocity * t * 2.0, vec2<f32>(0.0), vec2<f32>(1.0));
        let smearColor = textureSampleLevel(readTexture, u_sampler, smearUV, 0.0);
        smearR = smearR + smearColor.r * (1.0 - t);
        smearG = smearG + smearColor.g * (1.0 - t);
        smearB = smearB + smearColor.b * (1.0 - t);
    }
    smearR = smearR / f32(smearSamples);
    smearG = smearG / f32(smearSamples);
    smearB = smearB / f32(smearSamples);

    // Audio mix of the smear (HEAD's per-sector FFT voices read spectrum bins above index 0, which
    // are never uploaded, so they were always 0 and are gone).
    let finalR = mix(fringe.r, smearR, bass * 0.3);
    let finalG = mix(fringe.g, smearG, mids * 0.2);
    let finalB = mix(fringe.b, smearB, treble * 0.2);
    let color = vec3<f32>(finalR, finalG, finalB);

    // Audio split: bass shifts hue globally, mids add glow
    let dispersion = length(velocity) / max(strength, 0.001);
    let alpha = clamp(falloff * modFactor * 0.6 + dispersion * 0.3 + 0.1 + treble * 0.05, 0.0, 1.0);

    let finalRGBA = vec4<f32>(color, alpha);

    // State texels carry the sprung centre instead of pixels (C is not read as colour here).
    var aOut = finalRGBA;
    if (global_id.y == 0u && global_id.x == 0u) { aOut = vec4<f32>(center, centerVel); }
    if (global_id.y == 0u && global_id.x == 1u) { aOut = vec4<f32>(fract(time), 0.0, 0.0, SENT); }

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(aces_tonemap(finalRGBA.rgb), finalRGBA.a));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), aOut);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
