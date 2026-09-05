// ═══════════════════════════════════════════════════════════════════
//  Liquid Viscous — Navier-Stokes with Local Jacobi Projection
//  Category: image
//  Features: mouse-driven, held-drag, bounded-click-ripples, audio-reactive,
//            per-band-fft, vorticity-confinement, stencil-vorticity,
//            midpoint-advection, anisotropic-streamline-diffusion,
//            Reynolds-transition, local-jacobi-pressure, depth-aware, upgraded-rgba,
//            semantic-alpha, aces
//  Complexity: Very High
//  Scientific: 2D incompressible Navier-Stokes with vorticity confinement,
//              turbulence cascade, semi-Lagrangian advection and dye roll-up
//  Upgraded: 2026-08-23 (Batch 58B — Liquid)
// ═══════════════════════════════════════════════════════════════════
//  A carries SIM STATE (rg = velocity, b = dye, a = pressure); it is read back
//  next frame as dataTextureC. Display RGBA goes to writeTexture only —
//  overwriting A with colour would destroy the simulation.
//
//  THREE BUGS FIXED IN THIS PASS
//
//  1. Dead pressure solve. The old loop was:
//
//         for (iter = 0; iter < 4; iter++) {
//             pressure = (pL + pR + pU + pD - divergence) * 0.25;
//         }
//
//     pL/pR/pU/pD were loop-invariant, so all four iterations produced exactly
//     the same number — three were pure cost. The solve now relaxes the centre
//     AND its four neighbours together against a frozen outer ring, so each
//     sweep actually propagates pressure.
//
//  2. Frame-quantised vortices. Audio vortex centres were seeded from
//     `floor(time * 0.7)`, so they teleported to new positions ~0.7 s apart
//     instead of moving. They now drift along continuous Lissajous paths, the
//     class of fix earlier batches applied to time-hashed motion.
//
//  3. Filtered reads of dataTextureC. State was fetched through the FILTERING
//     sampler; dataTextureC is rgba32float and `float32-filterable` is only
//     requested when the adapter offers it (src/renderer/webgpu/device.ts), so
//     the read is invalid on devices without the feature. All state now comes
//     from exact textureLoad, bilinear by hand where advection needs sub-pixel.
//
//  Two new structures: vorticity at the centre and its four neighbours is now
//  derived from ONE shared Manhattan-radius-2 stencil (the old code called
//  vorticityAt() five times, each doing four filtered samples — 20 samples for
//  one confinement gradient), and dye is injected per FFT band so each bin
//  stains its own region of the fluid.
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Viscosity, y=Confinement, z=Injection, w=HueShift
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530717958647692;
const PRESSURE_ALPHA: f32 = 0.25;

fn clampUV(uv: vec2<f32>) -> vec2<f32> {
  return clamp(uv, vec2<f32>(0.001), vec2<f32>(0.999));
}

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
  let len2 = dot(v, v);
  if (len2 < 1e-8) { return vec2<f32>(0.0, 0.0); }
  return v * inverseSqrt(len2);
}

fn hash12(p: vec2<f32>) -> f32 {
  let h = sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123;
  return fract(h);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  let a = hash12(i);
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

fn curlNoise(p: vec2<f32>) -> vec2<f32> {
  let e = 0.05;
  let dx = valueNoise(p + vec2<f32>(e, 0.0)) - valueNoise(p - vec2<f32>(e, 0.0));
  let dy = valueNoise(p + vec2<f32>(0.0, e)) - valueNoise(p - vec2<f32>(0.0, e));
  return safeNormalize(vec2<f32>(dy, -dx));
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(vec3<f32>(c.x) + k.xyz) * 6.0 - vec3<f32>(k.www));
  return c.z * mix(vec3<f32>(k.x), clamp(p - vec3<f32>(k.x), vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// Exact float32 state fetch with hand-rolled bilinear — dataTextureC must never
// go through the filtering sampler.
fn stateBilinear(p: vec2<f32>, dims: vec2<i32>) -> vec4<f32> {
  let maxC = dims - vec2<i32>(1);
  let f = fract(p);
  let i0 = vec2<i32>(floor(p));
  let s00 = textureLoad(dataTextureC, clamp(i0,                     vec2<i32>(0), maxC), 0);
  let s10 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(1, 0), vec2<i32>(0), maxC), 0);
  let s01 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(0, 1), vec2<i32>(0), maxC), 0);
  let s11 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(1, 1), vec2<i32>(0), maxC), 0);
  return mix(mix(s00, s10, f.x), mix(s01, s11, f.x), f.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dimsI = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dimsI.x) || global_id.y >= u32(dimsI.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let maxC = dimsI - vec2<i32>(1);
  let resolution = vec2<f32>(dimsI);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let texel = 1.0 / resolution;
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let viscosity = clamp(u.zoom_params.x, 0.001, 1.0);
  let confinement = max(u.zoom_params.y, 0.0);
  let injectionScale = 0.35 + 1.65 * clamp(u.zoom_params.z, 0.0, 1.0);
  let hueShift = u.zoom_params.w;
  let dt = 0.55;

  // ── One shared Manhattan-radius-2 stencil (13 exact loads) ────────────────
  // Everything below — divergence, vorticity at five points, the pressure ring
  // — is derived from these. The old code re-sampled for each quantity.
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

  let invDx = 1.0 / (2.0 * texel.x);
  let invDy = 1.0 / (2.0 * texel.y);

  // ── Structure 1: vorticity at five points from the shared stencil ─────────
  let omega  = (cE.y  - cW.y)  * invDx - (cN.x  - cS.x)  * invDy;
  let omegaE = (cEE.y - c00.y) * invDx - (cNE.x - cSE.x) * invDy;
  let omegaW = (c00.y - cWW.y) * invDx - (cNW.x - cSW.x) * invDy;
  let omegaN = (cNE.y - cNW.y) * invDx - (cNN.x - c00.x) * invDy;
  let omegaS = (cSE.y - cSW.y) * invDx - (c00.x - cSS.x) * invDy;

  // ── Second-order semi-Lagrangian advection ────────────────────────────────
  // Re-evaluating velocity at the midpoint materially reduces orbital phase
  // error compared with the former single Euler backtrace.
  let midpointPx = clampUV(uv - c00.rg * (0.5 * dt)) * resolution;
  let midpointState = stateBilinear(midpointPx, dimsI);
  let departurePx = clampUV(uv - midpointState.rg * dt) * resolution;
  let advectedState = stateBilinear(departurePx, dimsI);
  let streamline = safeNormalize(midpointState.rg);
  let normalLine = vec2<f32>(-streamline.y, streamline.x);
  let alongA = stateBilinear(departurePx + streamline * 1.5, dimsI);
  let alongB = stateBilinear(departurePx - streamline * 1.5, dimsI);
  let acrossA = stateBilinear(departurePx + normalLine * 1.25, dimsI);
  let acrossB = stateBilinear(departurePx - normalLine * 1.25, dimsI);
  let alongMean = 0.5 * (alongA + alongB);
  let acrossMean = 0.5 * (acrossA + acrossB);
  // Thick fluid diffuses along streamlines more readily than across shear
  // layers, retaining the fine rolled edges of dye tendrils.
  var velocity = mix(advectedState.rg, alongMean.rg, viscosity * 0.14);
  velocity = mix(velocity, acrossMean.rg, viscosity * 0.035);
  var dye = mix(advectedState.b, alongMean.b, viscosity * 0.10);
  dye = mix(dye, acrossMean.b, viscosity * 0.02) * exp(-viscosity * 0.025);
  let reynolds = length(midpointState.rg) * min(resolution.x, resolution.y)
               * 0.08 / max(viscosity, 0.015);
  let turbulentTransition = smoothstep(0.35, 3.5, reynolds);

  // ── Vorticity confinement ─────────────────────────────────────────────────
  let eta = safeNormalize(vec2<f32>(abs(omegaE) - abs(omegaW), abs(omegaS) - abs(omegaN)));
  let confinementForce = vec2<f32>(eta.y, -eta.x)
                       * clamp(omega, -40.0, 40.0) * confinement * 0.00003;

  // ── Turbulence cascade ────────────────────────────────────────────────────
  var cascadeForce = vec2<f32>(0.0, 0.0);
  cascadeForce += curlNoise(uv * 3.0  + vec2<f32>( time * 0.07, -time * 0.03)) * (0.00025 + 0.0018 * bass);
  cascadeForce += curlNoise(uv * 8.0  + vec2<f32>(-time * 0.11,  time * 0.05)) * (0.00018 + 0.0011 * mids);
  cascadeForce += curlNoise(uv * 18.0 + vec2<f32>( time * 0.19,  time * 0.13)) * (0.00012 + 0.0010 * treble);
  cascadeForce *= injectionScale * (1.15 - 0.65 * viscosity)
                * mix(0.35, 1.35, turbulentTransition);

  // ── Pointer ───────────────────────────────────────────────────────────────
  let mouse = u.zoom_config.yz;
  let mouseDown = clamp(u.zoom_config.w, 0.0, 1.0);
  let toMouse = (uv - mouse) * aspectVec;
  let mouseDist = length(toMouse);
  let mouseEnvelope = exp(-mouseDist * 22.0) * mouseDown;
  let mouseCurl = safeNormalize(vec2<f32>(-toMouse.y, toMouse.x))
                * mouseEnvelope * (0.0015 + 0.0075 * treble);

  // ── Bounded click ripples ─────────────────────────────────────────────────
  var rippleForce = vec2<f32>(0.0, 0.0);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age < 0.0 || age > 4.0) { continue; }
    let delta = (uv - ripple.xy) * aspectVec;
    let r = length(delta);
    let ring = sin(r * 42.0 - age * 7.0) * exp(-r * 11.0 - age * 0.8);
    rippleForce += safeNormalize(vec2<f32>(-delta.y, delta.x)) * ring * (0.0006 + 0.0030 * bass);
    dye += exp(-r * 18.0 - age * 1.2) * (0.04 + 0.12 * bass);
  }

  // ── Continuously drifting audio vortices (was floor(time*0.7) teleporting) ─
  var audioVortices = vec2<f32>(0.0, 0.0);
  for (var j: i32 = 0; j < 3; j = j + 1) {
    let jf = f32(j);
    let phase = time * (0.11 + jf * 0.037);
    let center = vec2<f32>(0.5 + 0.34 * sin(phase * TAU * 0.31 + jf * 2.1),
                           0.5 + 0.30 * cos(phase * TAU * 0.23 + jf * 1.3));
    let delta = (uv - center) * aspectVec;
    let r = length(delta);
    let envelope = exp(-r * (10.0 + jf * 3.0));
    audioVortices += safeNormalize(vec2<f32>(-delta.y, delta.x))
                   * envelope * bass * (0.0014 + jf * 0.0005);
  }

  // ── Structure 2: per-band FFT dye injection ───────────────────────────────
  // Eight emitters on slow orbits, each stained by its own spectrum bin, so the
  // fluid picks up colour band by band instead of one global dye level.
  for (var b: u32 = 0u; b < 8u; b = b + 1u) {
    let fb = f32(b);
    let energy = plasmaBuffer[b + 1u].x;
    let ang = time * (0.05 + fb * 0.017) + fb * 0.7853981634;
    let src = vec2<f32>(0.5 + 0.36 * cos(ang), 0.5 + 0.32 * sin(ang * 1.27));
    let d = length((uv - src) * aspectVec);
    dye += exp(-d * (16.0 + fb * 2.0)) * energy * 0.06 * injectionScale;
  }

  velocity += (confinementForce + cascadeForce + mouseCurl + rippleForce + audioVortices) * dt;
  velocity *= 1.0 / (1.0 + 10.0 * viscosity * dt);

  // ── Local Jacobi pressure projection (the fixed solve) ────────────────────
  let divC = (cE.x  - cW.x)  * invDx + (cN.y  - cS.y)  * invDy;
  let divE = (cEE.x - c00.x) * invDx + (cNE.y - cSE.y) * invDy;
  let divW = (c00.x - cWW.x) * invDx + (cNW.y - cSW.y) * invDy;
  let divN = (cNE.x - cNW.x) * invDx + (cNN.y - c00.y) * invDy;
  let divS = (cSE.x - cSW.x) * invDx + (c00.y - cSS.y) * invDy;
  let duDx = (cE.x - cW.x) * invDx;
  let dvDy = (cN.y - cS.y) * invDy;
  let duDy = (cN.x - cS.x) * invDy;
  let dvDx = (cE.y - cW.y) * invDx;
  let extensionalStrain = sqrt((duDx - dvDy) * (duDx - dvDy)
                             + (duDy + dvDx) * (duDy + dvDx));

  // Frozen outer ring = Dirichlet boundary for the local solve.
  let pEE = cEE.a; let pWW = cWW.a; let pNN = cNN.a; let pSS = cSS.a;
  let pNE = cNE.a; let pNW = cNW.a; let pSE = cSE.a; let pSW = cSW.a;

  var pC = c00.a;
  var pE = cE.a;
  var pW = cW.a;
  var pN = cN.a;
  var pS = cS.a;

  for (var iter: i32 = 0; iter < 4; iter = iter + 1) {
    let nC = (pE + pW + pN + pS - divC) * PRESSURE_ALPHA;
    let nE = (pEE + pC + pNE + pSE - divE) * PRESSURE_ALPHA;
    let nW = (pC + pWW + pNW + pSW - divW) * PRESSURE_ALPHA;
    let nN = (pNE + pNW + pNN + pC - divN) * PRESSURE_ALPHA;
    let nS = (pSE + pSW + pC + pSS - divS) * PRESSURE_ALPHA;
    pC = nC; pE = nE; pW = nW; pN = nN; pS = nS;
  }
  let pressure = pC;
  velocity -= vec2<f32>((pE - pW) * invDx, (pN - pS) * invDy) * 0.0004;

  // ── Shading ───────────────────────────────────────────────────────────────
  let advectedColor = textureSampleLevel(readTexture, u_sampler, clampUV(uv + velocity * 0.35), 0.0);
  let sourceDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clampUV(uv + velocity * 0.2), 0.0).r;
  let luma = dot(advectedColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  dye = clamp(mix(dye, luma, 0.05) + mouseEnvelope * 0.18 + bass * 0.06 + abs(omega) * 0.0004, 0.0, 1.0);

  let vorticityVisual = clamp(abs(omega) * 0.02, 0.0, 1.0);
  let hue = fract(0.58 + hueShift * 0.25 + dye * 0.22 + vorticityVisual * 0.30
                  + treble * 0.08 + sin(time * 0.13) * 0.04);
  let saturation = clamp(0.55 + 0.25 * dye + 0.35 * vorticityVisual + 0.15 * mids, 0.0, 1.0);
  let value = clamp(0.35 + 0.55 * dye + 0.45 * vorticityVisual + 0.20 * luma, 0.0, 1.0);
  let iridescent = hsv2rgb(vec3<f32>(hue, saturation, value));
  let shearHighlight = smoothstep(0.5, 18.0, extensionalStrain)
                     * mix(0.35, 1.0, turbulentTransition);
  let rollupGlow = vec3<f32>(0.20, 0.10, 0.32) * vorticityVisual
                 + vec3<f32>(0.10, 0.18, 0.28) * dye
                 + vec3<f32>(0.55, 0.72, 0.95) * shearHighlight * (0.08 + 0.18 * treble);
  let blend = clamp(0.32 + 0.45 * dye + 0.28 * vorticityVisual, 0.0, 1.0);
  let finalColor = acesFilm(mix(advectedColor.rgb, iridescent + rollupGlow, blend));

  // ── Semantic alpha: dye load and roll-up are the substance ────────────────
  let alpha = clamp(mix(advectedColor.a, 1.0, clamp(dye * 0.8 + vorticityVisual * 0.5, 0.0, 1.0))
                    * 0.9 + 0.1, 0.0, 1.0);
  let depthProxy = clamp(max(sourceDepth * 0.65, vorticityVisual * 0.9 + dye * 0.2), 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
  // A carries SIM STATE, not display colour.
  textureStore(dataTextureA, coord, vec4<f32>(velocity, dye, pressure));
  textureStore(dataTextureB, coord, vec4<f32>(vorticityVisual,
                                              clamp(abs(divC) * 0.01, 0.0, 1.0),
                                              clamp(length(velocity) * 90.0, 0.0, 1.0), turbulentTransition));
  textureStore(writeDepthTexture, coord, vec4<f32>(depthProxy, 0.0, 0.0, 1.0));
}
