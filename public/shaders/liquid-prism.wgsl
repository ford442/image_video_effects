// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Prism — Cauchy-Dispersion Ripple Glass
//  Category: distortion
//  Features: mouse-driven, held-drag, bounded-click-ripples, audio-reactive,
//            per-band-fft, cauchy-dispersion, fresnel, caustic-fronts,
//            temporal-afterglow, depth-aware, upgraded-rgba, semantic-alpha, aces
//  Upgraded: 2026-08-23 (Batch 58B — Liquid)
// ═══════════════════════════════════════════════════════════════════════════════
//  FIXED IN THIS PASS — dead audio. The shader previously read
//
//      let audioOverall = u.config.y;
//
//  and drove every "audio" term from it. `config.y` is the RIPPLE COUNT, not an
//  audio level (docs/BINDING_CONTRACT.md, do-not-reintroduce list — the
//  recurring dead-audio bug of batches 15-19). The practical effect was that
//  the prism only "reacted to music" in proportion to how many click ripples
//  happened to be alive, and sat completely inert otherwise. Audio now comes
//  from plasmaBuffer[0].xyz with per-band detail from plasmaBuffer[1..8].
//
//  Two structures on top of the original single ripple:
//
//    1. Cauchy dispersion — the refractive index is evaluated per wavelength
//       with the Cauchy relation n(λ) = A + B/λ², and the sample offset for
//       each channel is scaled by its own n. The previous code faked this by
//       multiplying the red channel up and the blue channel down by a constant,
//       which splits the channels but gets the ORDER of the spread wrong: real
//       glass bends blue hardest. The fringe now fans the correct way and its
//       width tracks the physical index spread.
//
//    2. Bounded click caustics — each click emits an expanding wavefront that
//       both displaces the sample and deposits a caustic ridge where the front
//       focuses, capped at 50 ripples and ~2.6 s of life.
// ═══════════════════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Strength, y=Frequency, z=Speed, w=Aberration
  ripples: array<vec4<f32>, 50>,
};

// Cauchy coefficients for a dense flint-like glass. n = A + B / lambda^2,
// lambda in micrometres — B is what actually produces the spread.
const CAUCHY_A: f32 = 1.62;
const CAUCHY_B: f32 = 0.0132;
const LAMBDA_R: f32 = 0.650;
const LAMBDA_G: f32 = 0.532;
const LAMBDA_B: f32 = 0.450;

fn cauchyIndex(lambdaUm: f32) -> f32 {
    return CAUCHY_A + CAUCHY_B / (lambdaUm * lambdaUm);
}

fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
    let m = clamp(1.0 - cosTheta, 0.0, 1.0);
    let m2 = m * m;
    return F0 + (1.0 - F0) * m2 * m2 * m;
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// Glass thickness gate: more bending = thicker path = less transmission.
fn calculatePrismAlpha(distortionMag: f32, viewDotNormal: f32, baseTransparency: f32) -> f32 {
    let fresnel = schlickFresnel(max(0.0, viewDotNormal), 0.04);
    let thicknessFactor = smoothstep(0.0, 0.1, distortionMag);
    let baseAlpha = mix(0.3, 0.85, baseTransparency);
    return clamp(baseAlpha * (1.0 - thicknessFactor * 0.3) * (1.0 - fresnel * 0.25), 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimsI = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dimsI.x) || global_id.y >= u32(dimsI.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(dimsI);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;

    // ── Real audio (was u.config.y) ──────────────────────────────────────────
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Radial FFT banding: the ripple front is sliced into 8 annuli, each
    // driven by its own bin, so the wave carries spectral structure outward.
    let mousePos = u.zoom_config.yz;
    let held = step(0.5, u.zoom_config.w);
    let diff = uv - mousePos;
    let distVec = diff * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let bandIdx = u32(clamp(dist * 8.0, 0.0, 7.999));
    let band = plasmaBuffer[bandIdx + 1u].x;

    // ── Params ───────────────────────────────────────────────────────────────
    let strength = u.zoom_params.x * 0.1 * (1.0 + bass * 0.6 + held * 0.35);
    let frequency = (u.zoom_params.y * 20.0 + 5.0) * (1.0 + mids * 0.3 + band * 0.4);
    let speed = u.zoom_params.z * 5.0 * (1.0 + bass * 0.2);
    let aberration = u.zoom_params.w * 0.05 * (1.0 + treble * 0.4);
    let baseTransparency = u.zoom_params.w;

    // ── Pointer ripple ───────────────────────────────────────────────────────
    let wavePhase = dist * frequency - time * speed;
    let wave = sin(wavePhase);
    let decay = 1.0 / (1.0 + dist * 5.0);
    let dir = normalize(diff + vec2<f32>(0.0001, 0.0001));
    var displace = dir * wave * strength * decay;

    // ── Structure 2: bounded click caustic fronts ────────────────────────────
    var causticRidge = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 2.6) {
            let rDelta = (uv - rp.xy) * vec2<f32>(aspect, 1.0);
            let rDist = max(length(rDelta), 1e-4);
            let front = rDist - age * 0.5;
            let envelope = exp(-front * front * 120.0) * exp(-age * 1.3);
            let rDir = rDelta / rDist;
            displace += vec2<f32>(rDir.x / aspect, rDir.y) * sin(front * 60.0)
                      * envelope * strength * 2.2;
            // A caustic is where the wavefront folds — brightest at the crest.
            causticRidge += envelope * envelope * (1.0 + bass * 0.8);
        }
    }
    causticRidge = min(causticRidge, 2.0);

    // ── Structure 1: Cauchy dispersion ───────────────────────────────────────
    // Offset per channel scales with that channel's refractive index, so blue
    // (highest n) bends hardest — the physical ordering the old constant
    // R-up/B-down fudge had backwards.
    let nR = cauchyIndex(LAMBDA_R);
    let nG = cauchyIndex(LAMBDA_G);
    let nB = cauchyIndex(LAMBDA_B);
    let nMid = nG;
    let spread = 1.0 + aberration * 8.0;

    let rUV = uv + displace * (1.0 + (nR - nMid) * spread);
    let gUV = uv + displace;
    let bUV = uv + displace * (1.0 + (nB - nMid) * spread);

    let sR = textureSampleLevel(readTexture, u_sampler, rUV, 0.0);
    let sG = textureSampleLevel(readTexture, u_sampler, gUV, 0.0);
    let sB = textureSampleLevel(readTexture, u_sampler, bUV, 0.0);
    var color = vec3<f32>(sR.r, sG.g, sB.b);

    // Prism highlight at the wave crests, plus the click caustics.
    let highlight = smoothstep(0.8, 1.0, wave) * decay * strength * 10.0 * (1.0 + bass);
    color += vec3<f32>(0.15, 0.18, 0.2) * highlight;
    color += vec3<f32>(1.0, 0.92, 0.78) * causticRidge * 0.5;

    // Dispersion tint: the index spread itself colours the glass edge.
    let indexSpread = (nB - nR) * spread;
    color += vec3<f32>(0.10, 0.06, 0.22) * indexSpread * length(displace) * 60.0;

    // ── Surface normal / Fresnel ─────────────────────────────────────────────
    let distortionMag = length(displace);
    let normal = normalize(vec3<f32>(-displace.x * 50.0, -displace.y * 50.0, 1.0));
    let viewDotNormal = normal.z;

    // ── Temporal afterglow (exact load, no filtering of rgba32float) ─────────
    let prev = textureLoad(dataTextureC, coord, 0);
    color = max(color, prev.rgb * (0.80 + treble * 0.06));

    color = acesFilm(color);

    let alpha = clamp(
        calculatePrismAlpha(distortionMag, viewDotNormal, baseTransparency)
        + causticRidge * 0.2,
        0.0, 1.0);
    let outColor = vec4<f32>(color, alpha);

    textureStore(writeTexture, coord, outColor);
    textureStore(dataTextureA, coord, outColor);

    // Depth: the glass sits proud of the plate where it bends most.
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord,
                 vec4<f32>(clamp(depth * (1.0 - distortionMag * 2.0), 0.0, 1.0), 0.0, 0.0, 0.0));
}
