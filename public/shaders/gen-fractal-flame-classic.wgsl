// ═══════════════════════════════════════════════════════════════════
//  Classic Fractal Flame
//  Category: generative
//  Features: fractal, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10, 2026-11-15
//  Ideas: white-hot cores (per-channel log blend with luminance-ratio colour, Draves-style vibrancy); julia variation on a third pick band with a per-iteration branch flip; kept: log-density compression; spherical z/r² variation; colour-index averaging (each variation owns a colour coordinate, c <- (c + c_v)/2, indexes a warm flame gradient); two-layer tint (ring vs white-hot core by density fraction); rescue: orbit plateau black point (HEAD was a flat wall)
//  A packing: raw HDR display RGBA (ACES on writeTexture); unchanged
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// ── Rescue 1: orbit plateau ─────────────────────────────────────────
// The affine step is contractive and every pixel's orbit lands in the same compact attractor, so
// each iteration adds nearly the same ~0.02 of trap/core density to EVERY pixel: HEAD's accumulated
// density was a flat 0.5 ± 0.05 and the log-density display saturated to one orange colour (stdL 0.011).
// Three changes, all inside the existing accumulators: (a) the trap ring and the centre glow are
// narrower (12 → 24, 4.5 → 9 per unit r) so hitting them is a rare event with contrast; (b) a black
// point PLATEAU per unit of accumulated weight (Σ w) is subtracted — 0.006 is about the 1st–10th
// percentile of density per weight at 31–48 iterations and the 10th–30th at 12 iterations (numpy port
// over iterations 12..48 × variationMix 0..1); (c) DENS_GAIN restores exposure after the subtraction.
const PLATEAU: f32 = 0.006;
const DENS_GAIN: f32 = 1.5;
// zoom_params: x=Iterations, y=Variation Mix, z=Flame Zoom, w=Palette Cycle

fn rot(a: f32) -> mat2x2<f32> {
    let c = cos(a); let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.5) + vec3<f32>(0.5) * cos(6.28318 * (vec3<f32>(t) + vec3<f32>(0.0, 0.10, 0.24)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
    if (gid.x >= dims.x || gid.y >= dims.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let res = vec2<f32>(dims);
    let uv = (vec2<f32>(gid.xy) + vec2<f32>(0.5)) / res;
    let aspect = res.x / max(res.y, 1.0);
    var p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;

    let iterationCount = i32(12.0 + clamp(u.zoom_params.x, 0.0, 1.0) * 36.0);
    let variationMix = clamp(u.zoom_params.y, 0.0, 1.0);
    let flameZoom = mix(0.75, 2.2, clamp(u.zoom_params.z, 0.0, 1.0));
    let paletteCycle = clamp(u.zoom_params.w, 0.0, 1.0);
    let mouse = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
    let held = clamp(u.zoom_config.w, 0.0, 1.0);
    p = p * flameZoom - mouse * held * 0.22;

    var z = p;
    var density = 0.0;
    var edgeTrap = 0.0;
    var hueMoment = 0.0;   // Σ w·f·c : colour-index moment (HEAD: Σ f·i, a near-constant hue)
    var coreAcc = 0.0;     // the centre-glow share of `density`, for the two-layer tint
    var wsum = 0.0;        // Σ w : the plateau scale
    var ci = 0.5;          // running colour index
    for (var i = 0; i < 48; i++) {
        if (i >= iterationCount) { break; }
        let fi = f32(i);
        let r = max(length(z), 0.001);
        let theta = atan2(z.y, z.x);
        let swirl = vec2<f32>(z.x * sin(r * r) - z.y * cos(r * r),
                              z.x * cos(r * r) + z.y * sin(r * r));
        let horseshoe = vec2<f32>((z.x - z.y) * (z.x + z.y), 2.0 * z.x * z.y) / r;
        let polar = vec2<f32>(theta / 3.14159265, r - 1.0);
        let spherical = z / (r * r);
        let firstMix = mix(swirl, horseshoe, variationMix);
        let wPolar = 0.22 + audio.y * 0.12;
        var varied = mix(firstMix, polar, wPolar);
        let pick = fract(fi * 0.37 + 0.11);
        let wSph = select(0.0, 0.55 + audio.z * 0.12, pick > 0.72);
        varied = mix(varied, spherical, wSph);
        // Idea 2 - julia variation: sqrt(r) * (cos, sin)(theta/2 + branch * pi), branch flips per iteration
        let branch = select(0.0, 3.14159265, ((u32(i) * 5u + 1u) & 2u) != 0u);
        let sr = sqrt(r);
        let julia = sr * vec2<f32>(cos(theta * 0.5 + branch), sin(theta * 0.5 + branch));
        let wJul = select(0.0, 0.3 + audio.y * 0.1, pick > 0.40 && pick < 0.58);
        varied = mix(varied, julia, wJul);
        // ── Idea 3: colour-index averaging (native — the flame's own colouring) ──
        // A fractal flame colours a point by a running colour coordinate that each transform pulls
        // toward its own constant: c <- (c + c_v) / 2. Here every variation owns a colour coordinate
        // that is a function of what it actually did (swirl rotation r², horseshoe fold angle, polar
        // angle, spherical inversion radius, julia branch), blended with the SAME weights that blend
        // the variations themselves, so colour records the chain of folds the orbit went through.
        let cSwirl = fract(r * r * 0.159155);
        let cHorse = 0.5 + z.x * z.y / (r * r);          // 0.5 + 0.5·sin 2θ without the trig
        let cPolar = 0.5 + theta * 0.159155;
        let cSph = r / (1.0 + r);
        let cJul = 0.5 + 0.5 * julia.y / sr;             // sin(θ/2 + branch), already in julia
        var cv = mix(mix(cSwirl, cHorse, variationMix), cPolar, wPolar);
        cv = mix(cv, cSph, wSph);
        cv = mix(cv, cJul, wJul);
        ci = 0.5 * (ci + cv);
        let affine = rot(0.38 + sin(time * 0.12) * 0.07) * varied * (0.62 + audio.x * 0.035);
        z = affine + vec2<f32>(-0.12 + sin(fi * 2.1) * 0.025, 0.16);
        let w = 1.0 / (1.0 + fi * 0.025);
        let trap = exp(-abs(length(z) - 0.48) * (24.0 + audio.z * 16.0));
        let center = exp(-length(z) * 9.0);
        density += (trap * 0.08 + center * 0.06) * w;
        coreAcc += center * 0.06 * w;
        wsum += w;
        edgeTrap += exp(-abs(z.x) * 26.0) * exp(-abs(z.y) * 2.0) * 0.018;
        hueMoment += (trap * 0.08 + center * 0.06) * w * ci;
    }

    var clickFlame = 0.0;
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age > 0.0 && age < 3.0) {
            let center = (ripple.xy * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
            clickFlame += exp(-abs(distance(p / flameZoom, center) - age * 0.22) * 72.0) * exp(-age * 1.45);
        }
    }

    // Rescue 1 applied: remove the plateau (black point scales with the weight sum), restore exposure.
    let denseBase = max(density - PLATEAU * wsum, 0.0) * DENS_GAIN;
    let denseTot = denseBase + edgeTrap;
    let logDensity = log(1.0 + denseTot * 8.0);
    let flame = min(logDensity, 5.0);
    // Idea 3 (cont.): the density-weighted mean colour index drives hue and the warm flame gradient.
    let ciMean = hueMoment / max(density, 0.001);
    let hue = ciMean * 0.6 + time * (0.015 + paletteCycle * 0.06) + audio.y * 0.12;
    let classicWarm = vec3<f32>(1.3, 0.18, 0.015);
    // warm gradient: ci 0 → deep red, 0.5 → HEAD's classicWarm, 1 → gold (classicWarm is the mid-point, so
    // a flat ci reproduces HEAD's colour)
    let deepRed = vec3<f32>(1.3, 0.04, 0.008);
    let gold = vec3<f32>(1.3, 0.55, 0.05);
    let warmGrad = mix(mix(deepRed, classicWarm, clamp(ciMean * 2.0, 0.0, 1.0)), gold, clamp(ciMean * 2.0 - 1.0, 0.0, 1.0));
    let spectral = palette(hue);
    // ── Idea 4: two-layer tint (final-transform bloom) ─────────────────
    // HEAD fused the ring trap and the centre glow into one density with one tint. Keep the single
    // density, but tint it by WHERE it came from: ring share carries the flame gradient/spectral,
    // the centre-glow share burns white-hot.
    let coreFrac = smoothstep(0.30, 0.75, coreAcc / max(density, 0.001)) * smoothstep(0.05, 0.45, denseTot);
    let coreTint = vec3<f32>(1.3, 0.95, 0.55);
    let tint = mix(mix(warmGrad, spectral, paletteCycle * 0.72), coreTint, coreFrac);
    let perChannel = log(vec3<f32>(1.0) + tint * denseTot * 8.0);
    let vibrantCol = mix(perChannel, tint * flame, 0.65) + vec3<f32>(1.0, 0.82, 0.55) * smoothstep(2.0, 4.2, flame) * 0.5;
    // Idea 1 - vibrancy (above): per-channel log lets dense cores burn white-hot, luminance-ratio colour keeps hue
    var hdrColor = vec3<f32>(0.006, 0.002, 0.008) + vibrantCol * (1.1 + audio.x * 0.8);
    hdrColor += vec3<f32>(1.2, 0.65 + audio.y * 0.25, 0.08 + audio.z * 0.25) * edgeTrap * 1.4;
    hdrColor += vec3<f32>(1.0, 0.28, 0.08 + audio.z * 0.35) * clickFlame * 0.38;
    let history = textureLoad(dataTextureC, coord, 0);
    hdrColor = clamp(mix(hdrColor, history.rgb, 0.05 + audio.x * 0.065), vec3<f32>(0.0), vec3<f32>(8.0));
    let mapped = acesToneMap(hdrColor);
    // coverage: HEAD's 0.46 was calibrated to the flat plateau flame (~1.6); the black point lowers `flame`, so the same coverage needs 0.8
    let alpha = clamp(flame * 0.8 + edgeTrap * 0.2 + clickFlame * 0.1, 0.02, 0.98);
    let depth = clamp(logDensity * 0.28 + edgeTrap * 0.12, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(mapped, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, alpha));
}
