// ═══════════════════════════════════════════════════════════════════════════════
//  Vortex Warp — Turbulent Rotational Deformation with Angular Dispersion
//  Category: distortion
//  Features: mouse-driven, held-drag, bounded-click-ripples, audio-reactive,
//            angular-chromatic-dispersion, temporal-smear, depth-aware,
//            upgraded-rgba, semantic-alpha, aces
//  Upgraded: 2026-08-23 (Batch 56 — Turbulent Vortex)
// ═══════════════════════════════════════════════════════════════════════════════
//  A rigid rotation field is only the carrier here. On top of it sit two
//  structures that make the swirl behave like a real fluid vortex:
//
//    1. Azimuthal turbulence — the swirl angle is perturbed by a summed set of
//       rotating lobes whose amplitudes come from the 8 FFT bands
//       (plasmaBuffer[1..8].x), so the vortex "flutters" per frequency band
//       instead of rotating as one rigid disc. 'Turbulence' (p4) was declared
//       in the shader JSON but never read before this upgrade — it is the gain.
//
//    2. Angular chromatic dispersion — R/G/B are fetched at slightly different
//       rotation angles rather than different radii. That is the correct
//       geometry for a rotational shear: the wavelength split fans out ALONG
//       the flow lines, giving the prism smear a spiral shape.
//
//  Interaction: the pointer is the vortex core; holding the button tightens and
//  accelerates it, and each click launches a bounded shock ring that adds a
//  counter-rotating pulse as it expands outward (capped at 50 ripples, ~2.4 s).
//  Previous-frame colour is read back exactly from dataTextureC and advected
//  along the local flow direction, which turns fast swirls into motion smear.
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
  zoom_params: vec4<f32>,  // x=Strength, y=Radius, z=SpiralTwist, w=Turbulence
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530717958647692;

// ── ACES filmic tone map (Narkowicz fit) ─────────────────────────────────────
fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// Rotate a UV offset (already aspect-corrected) by `angle`.
fn rotate2(v: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

// ── Azimuthal turbulence ─────────────────────────────────────────────────────
// Eight counter-rotating lobes, one per FFT band. Lobe k has k+2 arms and
// drifts at its own rate, so the sum never repeats over a musical phrase.
fn azimuthalTurbulence(theta: f32, radialT: f32, time: f32) -> f32 {
    var sum = 0.0;
    for (var k = 0u; k < 8u; k = k + 1u) {
        let band = plasmaBuffer[k + 1u].x;
        let arms = f32(k) + 2.0;
        let drift = time * (0.35 + f32(k) * 0.11) * select(1.0, -1.0, (k & 1u) == 1u);
        sum += sin(theta * arms + drift + radialT * 3.0) * band / arms;
    }
    return sum;
}

// Base rotation distortion magnitude — drives the alpha physics below.
fn calculateRotationalDistortion(percent: f32, strength: f32, twist: f32, dist: f32) -> f32 {
    let rotationDistortion = abs(strength) * percent * percent;
    let spiralDistortion = abs(twist) * percent * dist;
    return rotationDistortion + spiralDistortion * 0.1;
}

// Physical alpha for rotational warping: centrifugal pressure gradient minus
// scattering loss through the sheared medium.
fn calculateRotationalAlpha(baseAlpha: f32, distortionMag: f32, percent: f32) -> f32 {
    let pressureAlpha = mix(0.9, 0.6, percent);
    let scatteringLoss = distortionMag * 0.3;
    return clamp(baseAlpha * pressureAlpha - scatteringLoss, 0.4, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(dims);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    // ── Audio ────────────────────────────────────────────────────────────────
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Params (held pointer tightens the core and spins it faster) ──────────
    let held = step(0.5, u.zoom_config.w);
    let strength = (u.zoom_params.x - 0.5) * 10.0 * (1.0 + bass * 0.45 + held * 0.35);
    let radius = (u.zoom_params.y * 0.5 + 0.05) * (1.0 - held * 0.22);
    let twist = u.zoom_params.z * 10.0 * (1.0 + mids * 0.3);
    let turbGain = u.zoom_params.w;

    let center = u.zoom_config.yz;
    let diff = uv - center;
    let diffAspect = diff * vec2<f32>(aspect, 1.0);
    let dist = length(diffAspect);
    let theta = atan2(diffAspect.y, diffAspect.x);

    // ── Bounded click shock rings ────────────────────────────────────────────
    // Each click emits an outward front; where the front passes it injects a
    // short counter-rotating kick, so clicks read as pressure waves rather than
    // as a second permanent vortex.
    var shockAngle = 0.0;
    var shockGlow = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 2.4) {
            let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
            let front = rDist - age * 0.55;
            let band = exp(-front * front * 260.0) * exp(-age * 1.4);
            shockAngle -= band * 1.6;
            shockGlow += band;
        }
    }
    shockGlow = min(shockGlow, 1.5);

    // ── Swirl field ──────────────────────────────────────────────────────────
    // Inside the vortex radius the swirl is rigid rotation + spiral + turbulence.
    // Outside it, only the click shock rings twist the frame. The rotation is
    // applied through one path either way, so the three colour channels below
    // always agree on the base angle.
    let inside = step(dist, radius);
    let percent = select(0.0, (radius - dist) / radius, dist < radius);
    let weight = percent * percent;

    let rigid = weight * strength;
    let spiral = twist * weight * dist;

    // Structure 1: azimuthal turbulence, banded by the FFT.
    let turb = azimuthalTurbulence(theta, percent, time) * turbGain * 2.2 * weight;

    let totalAngle = rigid + spiral + turb + shockAngle;
    let distortionMag = (calculateRotationalDistortion(percent, strength, twist, dist)
                        + abs(turb) * 0.6) * inside + abs(shockAngle) * 0.4;

    let rotatedDiff = rotate2(diffAspect, totalAngle);
    let finalUV = center + vec2<f32>(rotatedDiff.x / aspect, rotatedDiff.y);

    // Tangential flow direction at this pixel — used for the temporal smear.
    let flowDir = normalize(vec2<f32>(-diffAspect.y, diffAspect.x) + vec2<f32>(1e-6))
                * clamp(abs(totalAngle) * max(percent, shockGlow * 0.5) * 0.02, 0.0, 0.02);

    // ── Structure 2: angular chromatic dispersion ────────────────────────────
    // The wavelength split is a rotation delta, not a radial one, so the fringe
    // follows the flow lines of the vortex.
    let dispersion = (0.012 + treble * 0.03)
                   * max(percent, shockGlow * 0.4)
                   * clamp(abs(totalAngle), 0.0, 3.0);
    let dR = rotate2(diffAspect, totalAngle + dispersion);
    let dB = rotate2(diffAspect, totalAngle - dispersion);
    let uvR = center + vec2<f32>(dR.x / aspect, dR.y);
    let uvB = center + vec2<f32>(dB.x / aspect, dB.y);

    let sR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0);
    let sG = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);
    let sB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0);
    var color = vec3<f32>(sR.r, sG.g, sB.b);

    // ── Temporal smear: previous frame advected along the flow ───────────────
    let prevCoord = clamp(coord - vec2<i32>(flowDir * resolution),
                          vec2<i32>(0), dims - vec2<i32>(1));
    let prev = textureLoad(dataTextureC, prevCoord, 0);
    let smear = clamp(max(percent, shockGlow * 0.5) * (0.28 + abs(totalAngle) * 0.06), 0.0, 0.62);
    color = mix(color, max(color, prev.rgb * 0.97), smear);

    // Shock fronts glow with a warm rim so the click reads even on dark frames.
    color += vec3<f32>(1.0, 0.72, 0.45) * shockGlow * (0.35 + bass * 0.5);

    color = acesFilm(color);

    // ── Alpha physics ────────────────────────────────────────────────────────
    let finalAlpha = clamp(
        calculateRotationalAlpha(sG.a, distortionMag, percent) + shockGlow * 0.15,
        0.0, 1.0);
    let outColor = vec4<f32>(color, finalAlpha);

    textureStore(writeTexture, coord, outColor);
    textureStore(dataTextureA, coord, outColor);

    // Depth: rotational shear creates depth uncertainty proportional to distortion.
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthMod = 1.0 + distortionMag * 0.05;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth * depthMod, 0.0, 0.0, 0.0));
}
