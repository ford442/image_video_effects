// ═══════════════════════════════════════════════════════════════════
//  Liquid Displacement — Semi-Lagrangian Fluid with Local Jacobi Solve
//  Category: liquid-effects
//  Features: mouse-driven, held-drag, spring-damper-pointer,
//            bounded-click-ripples, audio-reactive, per-band-fft,
//            local-jacobi-pressure, chromatic-aberration, depth-aware,
//            upgraded-rgba, semantic-alpha, aces
//  Complexity: High
//  Upgraded: 2026-08-23 (Batch 58B — Liquid)
// ═══════════════════════════════════════════════════════════════════
//  A real Eulerian fluid: velocity + pressure live in dataTextureA (rg = velocity
//  encoded to [0,1], b = pressure), read back next frame through dataTextureC
//  with exact textureLoad. Note that A carries SIM STATE here, not display RGBA —
//  the display goes to writeTexture only. Overwriting A with colour would destroy
//  the simulation.
//
//  TWO BUGS FIXED IN THIS PASS
//
//  1. Dead pressure solve. The old loop was:
//
//         for (i = 1; i < pressureIters; i++) {
//             let pLeft = textureLoad(dataTextureC, leftCoord, 0).b;   // ...
//             pressure = (pLeft + pRight + pDown + pUp - divergence) * 0.25;
//         }
//
//     Every iteration re-read the SAME four unchanging neighbours from last
//     frame's texture and recomputed an identical value, so iterations 2..N were
//     pure cost. The 'Pressure Iterations' slider was therefore inert — the
//     dead-slider auditor passes it because zoom_params.y *is* read, but nothing
//     downstream could see the difference. This version loads a Manhattan-radius-2
//     stencil (13 taps) once, computes divergence at the centre AND its four
//     direct neighbours, then relaxes those five pressure values against a frozen
//     outer ring. Each sweep now genuinely propagates information, so the slider
//     controls real convergence.
//
//  2. Mouse smuggled through pixel (0,0). The previous mouse position was stashed
//     in the b/a channels of dataTextureA at texel (0,0) and read back by every
//     pixel — which corrupted the velocity/pressure state at that texel and made
//     the whole field depend on one arbitrary corner sample. The smoothed pointer
//     and its velocity now live in extraBuffer[133..136], written by invocation
//     (0,0) only, which is the engine's designated scratch range.
//
//  New structures: click ripples inject divergence impulses into the velocity
//  field (bounded, capped at 50), and the turbulence injection is banded across
//  the eight FFT bins instead of a single fixed swirl.
// ═══════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,              // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,         // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,         // x=Viscosity, y=PressureIterations, z=FlowSpeed, w=Turbidity
  ripples: array<vec4<f32>, 50>,
};

const DT: f32 = 0.016;
const DISSIPATION: f32 = 0.995;
const PRESSURE_ALPHA: f32 = 0.25;
const TAU: f32 = 6.28318530717958647692;

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

fn calculateFlowAlpha(flowMagnitude: f32, pressure: f32, turbidity: f32, viewDotNormal: f32) -> f32 {
  let fresnel = schlickFresnel(max(0.0, viewDotNormal), 0.02);
  let flowThickness = flowMagnitude * 0.5 + abs(pressure) * 0.3 + 0.1;
  let absorption = exp(-flowThickness * (1.0 + turbidity * 3.0) * 1.5);
  return clamp(mix(0.4, 0.9, absorption) * (1.0 - fresnel * 0.4), 0.0, 1.0);
}

fn calculateFlowColor(baseColor: vec3<f32>, velocity: vec2<f32>, pressure: f32, turbidity: f32) -> vec3<f32> {
  let velMag = length(velocity);
  let flowDepth = velMag * 0.3 + abs(pressure) * 0.2;
  let absorption = vec3<f32>(
      exp(-flowDepth * (1.0 + turbidity)),
      exp(-flowDepth * (0.9 + turbidity * 0.9)),
      exp(-flowDepth * (0.8 + turbidity * 0.8))
  );
  let flowTint = vec3<f32>(0.0, 0.05, 0.1) * velMag * 2.0;
  return baseColor * absorption + vec3<f32>(0.0, flowTint.g, flowTint.b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let texSize = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(texSize.x) || global_id.y >= u32(texSize.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(texSize);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let maxC = texSize - vec2<i32>(1);
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    // ── Audio ────────────────────────────────────────────────────────────────
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Params ───────────────────────────────────────────────────────────────
    let viscosity = max(u.zoom_params.x * 0.01, 0.0001);
    let pressureIters = i32(clamp(u.zoom_params.y * 20.0, 1.0, 20.0));
    let flowSpeed = u.zoom_params.z * 2.0 * (1.0 + bass * 0.4);
    let turbidity = u.zoom_params.w * (1.0 + bass * 0.2);

    // ── Spring-damped pointer in extraBuffer[133..136] ───────────────────────
    // (Replaces the previous mouse-in-texel-(0,0) hack.)
    let rawMouse = u.zoom_config.yz;
    if (global_id.x == 0u && global_id.y == 0u) {
        var sm = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        if (sm.x == 0.0 && sm.y == 0.0) { sm = rawMouse; }
        let k = 1.0 - exp(-11.0 * DT);
        let next = sm + (rawMouse - sm) * k;
        var sv = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        sv = mix(sv, (next - sm) / DT, 0.3);
        extraBuffer[133] = next.x;
        extraBuffer[134] = next.y;
        extraBuffer[135] = sv.x;
        extraBuffer[136] = sv.y;
    }
    let mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    let mouseVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    let mouseDown = u.zoom_config.w > 0.5;

    // ── Load the Manhattan-radius-2 stencil once (13 taps) ───────────────────
    // rg = velocity (encoded), b = pressure. Every derivative below reuses these.
    let c00 = textureLoad(dataTextureC, coord, 0);
    let cE  = textureLoad(dataTextureC, clamp(coord + vec2<i32>( 1,  0), vec2<i32>(0), maxC), 0);
    let cW  = textureLoad(dataTextureC, clamp(coord + vec2<i32>(-1,  0), vec2<i32>(0), maxC), 0);
    let cN  = textureLoad(dataTextureC, clamp(coord + vec2<i32>( 0,  1), vec2<i32>(0), maxC), 0);
    let cS  = textureLoad(dataTextureC, clamp(coord + vec2<i32>( 0, -1), vec2<i32>(0), maxC), 0);
    let cEE = textureLoad(dataTextureC, clamp(coord + vec2<i32>( 2,  0), vec2<i32>(0), maxC), 0);
    let cWW = textureLoad(dataTextureC, clamp(coord + vec2<i32>(-2,  0), vec2<i32>(0), maxC), 0);
    let cNN = textureLoad(dataTextureC, clamp(coord + vec2<i32>( 0,  2), vec2<i32>(0), maxC), 0);
    let cSS = textureLoad(dataTextureC, clamp(coord + vec2<i32>( 0, -2), vec2<i32>(0), maxC), 0);
    let cNE = textureLoad(dataTextureC, clamp(coord + vec2<i32>( 1,  1), vec2<i32>(0), maxC), 0);
    let cNW = textureLoad(dataTextureC, clamp(coord + vec2<i32>(-1,  1), vec2<i32>(0), maxC), 0);
    let cSE = textureLoad(dataTextureC, clamp(coord + vec2<i32>( 1, -1), vec2<i32>(0), maxC), 0);
    let cSW = textureLoad(dataTextureC, clamp(coord + vec2<i32>(-1, -1), vec2<i32>(0), maxC), 0);

    let vC  = c00.rg * 2.0 - 1.0;
    let vE  = cE.rg  * 2.0 - 1.0;
    let vW  = cW.rg  * 2.0 - 1.0;
    let vN  = cN.rg  * 2.0 - 1.0;
    let vS  = cS.rg  * 2.0 - 1.0;
    let vEE = cEE.rg * 2.0 - 1.0;
    let vWW = cWW.rg * 2.0 - 1.0;
    let vNN = cNN.rg * 2.0 - 1.0;
    let vSS = cSS.rg * 2.0 - 1.0;
    let vNE = cNE.rg * 2.0 - 1.0;
    let vNW = cNW.rg * 2.0 - 1.0;
    let vSE = cSE.rg * 2.0 - 1.0;
    let vSW = cSW.rg * 2.0 - 1.0;

    var velocity = vC;

    // ── 1. Semi-Lagrangian advection (manual bilinear, exact loads) ──────────
    let dt = DT * flowSpeed;
    let backPos = uv - velocity * dt;
    let sampleCoord = backPos * resolution;
    let fcoord = fract(sampleCoord);
    let icoord = vec2<i32>(floor(sampleCoord));
    let s00 = textureLoad(dataTextureC, clamp(icoord,                      vec2<i32>(0), maxC), 0).rg * 2.0 - 1.0;
    let s10 = textureLoad(dataTextureC, clamp(icoord + vec2<i32>(1, 0), vec2<i32>(0), maxC), 0).rg * 2.0 - 1.0;
    let s01 = textureLoad(dataTextureC, clamp(icoord + vec2<i32>(0, 1), vec2<i32>(0), maxC), 0).rg * 2.0 - 1.0;
    let s11 = textureLoad(dataTextureC, clamp(icoord + vec2<i32>(1, 1), vec2<i32>(0), maxC), 0).rg * 2.0 - 1.0;
    velocity = mix(mix(s00, s10, fcoord.x), mix(s01, s11, fcoord.x), fcoord.y);

    // ── 2. Pointer injection using the smoothed pointer velocity ─────────────
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let mouseRadius = 0.15;
    if (dist < mouseRadius) {
        let mouseForce = smoothstep(mouseRadius, 0.0, dist);
        if (mouseDown) {
            velocity += clamp(mouseVel * 0.6, vec2<f32>(-6.0), vec2<f32>(6.0)) * mouseForce * 2.0;
        } else {
            velocity += normalize(distVec + vec2<f32>(1e-6)) * 0.5 * mouseForce * 0.3;
        }
    }

    // ── 3. Bounded click impulses ────────────────────────────────────────────
    // Each click drives an outward radial front — a divergence impulse the
    // pressure solve then has to work against, which is what makes it read as
    // a real splash rather than a painted ring.
    var splash = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 2.4) {
            let d = (uv - rp.xy) * vec2<f32>(aspect, 1.0);
            let r = max(length(d), 1e-4);
            let front = r - age * 0.5;
            let env = exp(-front * front * 150.0) * exp(-age * 1.5);
            velocity += (d / r) * env * (1.6 + bass * 1.8);
            splash += env;
        }
    }
    splash = min(splash, 1.5);

    // ── 4. Viscosity (Laplacian diffusion) ───────────────────────────────────
    let laplacian = vW + vE + vN + vS - 4.0 * velocity;
    velocity += laplacian * viscosity;

    // ── 5. FFT-banded turbulence injection ───────────────────────────────────
    // Eight curl cells, one per bin, instead of a single fixed swirl.
    var turb = vec2<f32>(0.0);
    for (var b: u32 = 0u; b < 8u; b = b + 1u) {
        let fb = f32(b);
        let energy = plasmaBuffer[b + 1u].x;
        let k = 3.0 + fb * 2.5;
        let drift = time * (0.08 + fb * 0.03) * select(1.0, -1.0, (b & 1u) == 1u);
        let p = uv * k + vec2<f32>(drift, drift * 0.7);
        turb += vec2<f32>(sin(p.y * TAU) * cos(p.x * TAU * 0.68),
                          -cos(p.x * TAU) * sin(p.y * TAU * 0.68))
              * (0.25 + energy * 1.5) / (1.0 + fb * 0.4);
    }
    velocity += turb * turbidity * 0.002 * (1.0 + mids * 0.5);

    // ── 6. Local Jacobi pressure projection (the fixed solve) ────────────────
    // Divergence at the centre and its four direct neighbours, all from the
    // stencil already in registers.
    let divC = (vE.x  - vW.x)  * 0.5 + (vN.y  - vS.y)  * 0.5;
    let divE = (vEE.x - vC.x)  * 0.5 + (vNE.y - vSE.y) * 0.5;
    let divW = (vC.x  - vWW.x) * 0.5 + (vNW.y - vSW.y) * 0.5;
    let divN = (vNE.x - vNW.x) * 0.5 + (vNN.y - vC.y)  * 0.5;
    let divS = (vSE.x - vSW.x) * 0.5 + (vC.y  - vSS.y) * 0.5;

    // Frozen outer ring acts as the Dirichlet boundary for the local solve.
    let pEE = cEE.b; let pWW = cWW.b; let pNN = cNN.b; let pSS = cSS.b;
    let pNE = cNE.b; let pNW = cNW.b; let pSE = cSE.b; let pSW = cSW.b;

    var pC = c00.b;
    var pE = cE.b;
    var pW = cW.b;
    var pN = cN.b;
    var pS = cS.b;

    for (var iter: i32 = 0; iter < pressureIters; iter = iter + 1) {
        // Interior five relax against each other and the frozen ring — this is
        // what the old loop failed to do.
        let nC = (pE + pW + pN + pS - divC) * PRESSURE_ALPHA;
        let nE = (pEE + pC + pNE + pSE - divE) * PRESSURE_ALPHA;
        let nW = (pC + pWW + pNW + pSW - divW) * PRESSURE_ALPHA;
        let nN = (pNE + pNW + pNN + pC - divN) * PRESSURE_ALPHA;
        let nS = (pSE + pSW + pC + pSS - divS) * PRESSURE_ALPHA;
        pC = nC; pE = nE; pW = nW; pN = nN; pS = nS;
    }
    let pressure = pC;

    // Subtract the pressure gradient — velocity is now near divergence-free.
    velocity -= vec2<f32>((pE - pW) * 0.5, (pN - pS) * 0.5);
    velocity *= DISSIPATION;
    velocity = clamp(velocity, vec2<f32>(-5.0), vec2<f32>(5.0));

    // ── 7. Store sim state (A carries STATE, not display colour) ─────────────
    let encodedVel = velocity * 0.5 + 0.5;
    textureStore(dataTextureA, coord, vec4<f32>(encodedVel, pressure, 1.0));

    // ── 8. Displace the plate ────────────────────────────────────────────────
    let displacementStrength = 0.02 + u.zoom_params.x * 0.03;
    let clampedUV = clamp(uv - velocity * displacementStrength, vec2<f32>(0.001), vec2<f32>(0.999));

    let velMag = length(velocity);
    let chromaticOffset = velMag * 0.002 * u.zoom_params.z * (1.0 + treble * 0.8);
    let flowDir = normalize(velocity + vec2<f32>(1e-6));
    let baseSample = textureSampleLevel(readTexture, u_sampler, clampedUV, 0.0);
    let r = textureSampleLevel(readTexture, u_sampler, clampedUV + flowDir * chromaticOffset, 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, clampedUV - flowDir * chromaticOffset, 0.0).b;
    let baseColor = vec3<f32>(r, baseSample.g, b);

    // ── 9. Shade ─────────────────────────────────────────────────────────────
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clampedUV, 0.0).r;
    let velNormal = normalize(vec3<f32>(-velocity, 0.5));
    var flowColor = calculateFlowColor(baseColor, velocity, pressure, turbidity);
    flowColor += vec3<f32>(0.35, 0.65, 1.0) * splash * 0.45;
    flowColor += vec3<f32>(0.15, 0.25, 0.4) * clamp(abs(pressure) * 2.0, 0.0, 1.0);
    flowColor = acesFilm(flowColor);

    // ── 10. Semantic alpha ───────────────────────────────────────────────────
    let physAlpha = calculateFlowAlpha(velMag, pressure, turbidity, velNormal.z);
    let effectIntensity = clamp(velMag + splash * 0.6, 0.0, 1.0);
    let finalAlpha = clamp(mix(baseSample.a * physAlpha, 1.0, effectIntensity * 0.7), 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(flowColor, finalAlpha));
    // B carries diagnostics: |velocity|, pressure, divergence, splash.
    textureStore(dataTextureB, coord, vec4<f32>(clamp(velMag, 0.0, 1.0),
                                                clamp(pressure * 0.5 + 0.5, 0.0, 1.0),
                                                clamp(abs(divC), 0.0, 1.0),
                                                clamp(splash, 0.0, 1.0)));
    textureStore(writeDepthTexture, coord,
                 vec4<f32>(clamp(depth - velMag * 0.02, 0.0, 1.0), 0.0, 0.0, 1.0));
}
