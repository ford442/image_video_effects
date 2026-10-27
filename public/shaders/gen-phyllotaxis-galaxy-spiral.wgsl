// ═══════════════════════════════════════════════════════════════════
//  Phyllotaxis Galaxy Spiral
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10, 2026-10-25
//  Ideas: Sersic bulge and disk; dust lanes and HII knots; flat-curve shear; parastichy sheen; seed-scale bracts; meristem rim
//  A packing: ACES display RGBA in A
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: .x = Star Spread, .y = Star Size, .z = Disk Rotation, .w = Wave Density

const PHI: f32 = 2.39996323; // golden angle in radians
const TAU: f32 = 6.283185307;

fn hash11(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Native idea 1: unresolved starlight — Sersic (n=2) bulge plus an
// exponential disk whose surface brightness is lifted on density-wave crests.
fn diffuseStarlight(p: vec2<f32>, armCrest: f32, waveGain: f32) -> vec3<f32> {
  let r = length(p);
  let bulge = exp(-3.67 * sqrt(r / 0.25)) * 0.9;
  let disk = exp(-r / 0.38) * 0.07 * (1.0 + armCrest * 1.6 * waveGain);
  return vec3<f32>(1.0, 0.8, 0.55) * bulge + vec3<f32>(0.75, 0.8, 1.0) * disk;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.zw);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let p1 = u.zoom_params.x;                         // Star Spread
  let p2 = u.zoom_params.y;                         // Star Size
  let diskRotation = u.zoom_params.z;               // Disk Rotation (0.3 = original rate)
  let waveGain = clamp(u.zoom_params.w, 0.0, 1.0) * 2.0; // Wave Density (0.5 = original amplitude)

  // 3D viewpoint offset from mouse
  var viewOffset = vec2<f32>(0.0, 0.0);
  if (u.zoom_config.w > 0.5) {
    viewOffset = (mouse - 0.5) * 1.5;
  }

  // Galaxy center with rotation from mids
  let rotAngle = time * 0.08 * (diskRotation / 0.3) + mids * TAU * 0.25;
  let cosR = cos(rotAngle);
  let sinR = sin(rotAngle);
  let centered = (uv - 0.5) * 2.0;
  let rotUV = vec2<f32>(centered.x * cosR - centered.y * sinR,
                        centered.x * sinR + centered.y * cosR);
  let sampleUV = rotUV + viewOffset;

  // Click ripples = star-formation shock fronts: a compression ring expands
  // from the click and ignites young blue stars wherever it passes.
  var shock = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 3.0) {
      let rpos = (rp.xy - 0.5) * 2.0;
      let front = length(centered - rpos) - age * 0.55;
      shock += exp(-front * front * 140.0) * exp(-age * 1.1);
    }
  }
  shock = clamp(shock, 0.0, 2.0);

  // Star accumulation
  var accum = vec3<f32>(0.0, 0.0, 0.0);
  var alphaAcc = 0.0;
  var maxDepth = 0.0;
  let starCount = 350;
  let c = 0.012 + p1 * 0.015;
  let densityWaveAmp = (0.15 + bass * 0.25) * waveGain;

  for (var i: i32 = 1; i <= starCount; i = i + 1) {
    let n = f32(i);
    let r = c * sqrt(n);
    // Idea: flat rotation curve — inner florets lap the outer ones. Disk rotation still scales the spin.
    let theta = n * PHI + time * (0.012 + 0.028 / (0.18 + r)) * (diskRotation / 0.3) * (1.0 + hash11(n) * 0.5);

    // Lin-Shu density wave perturbation
    let wave = sin(theta * 2.0 + r * 40.0) * densityWaveAmp;
    let rWave = r + wave * r;

    let pos = vec2<f32>(cos(theta) * rWave, sin(theta) * rWave);
    let delta = sampleUV - pos;
    let dist = length(delta);

    // Perspective depth based on ring radius + hash
    let depth = clamp(1.0 - r * 0.9 + (hash11(n * 3.7) - 0.5) * 0.3, 0.0, 1.0);
    let size = (0.003 + hash11(n * 13.0) * 0.006) * (0.6 + depth * 0.8) * (1.0 + p2);

    let starShape = exp(-dist * dist / (size * size));
    // ── Idea: seed-scale bracts ──
    // A short streak on the outer side of the floret, along the position vector already used to place it.
    let radialDir = pos / max(r, 0.001);
    let outward = dot(delta, radialDir);
    let acrossBract = length(delta - radialDir * outward);
    let bract = exp(-acrossBract * acrossBract / max(size * size * 0.12, 1e-8))
      * smoothstep(0.0, size * 1.6, outward)
      * exp(-outward / max(size * 7.0, 1e-4));
    if (starShape < 0.001 && bract < 0.02) { continue; }

    // Hubble palette: young=blue, old=red, dust=yellow
    let starType = hash11(n * 7.3);
    var starColor: vec3<f32>;
    if (starType < 0.25) {
      starColor = vec3<f32>(0.4, 0.6, 1.0) * (1.0 + shock * 2.5); // young blue (shock-triggered)
    } else if (starType < 0.6) {
      starColor = vec3<f32>(1.0, 0.85, 0.6); // yellow main seq
    } else if (starType < 0.9) {
      starColor = vec3<f32>(1.0, 0.5, 0.3); // old red
    } else {
      starColor = vec3<f32>(1.0, 0.3, 0.5); // supernova candidate
    }

    // Treble triggers supernova flare on rare stars
    let isSupernova = step(0.96, starType) * step(0.7, fract(hash11(n) + time * 0.5 + treble));
    starColor += vec3<f32>(1.0, 0.9, 0.7) * isSupernova * treble * 3.0;
    // ── Idea: meristem rim ──
    // The youngest florets are the outer ring of the capitulum. Inner Hubble colors stay.
    let rimR = c * sqrt(350.0);
    let young = smoothstep(0.62, 0.96, r / max(rimR, 0.001));
    starColor = mix(starColor, vec3<f32>(0.55, 0.78, 1.0), young * (0.35 + treble * 0.4));

    // Depth fade
    let depthFade = smoothstep(0.0, 0.15, depth) * smoothstep(1.0, 0.6, depth);
    let dust = smoothstep(0.3, 0.7, hash11(n * 19.0)) * 0.4;
    let extinction = 1.0 - dust * r * 2.0;

    accum += starColor * starShape * depthFade * extinction;
    accum += starColor * bract * 0.42 * depthFade * extinction;
    alphaAcc += starShape * depthFade * extinction;
    maxDepth = max(maxDepth, depth * starShape);
  }

  // Density-wave arm phase at this pixel (same 2-arm phase as the stars).
  let pr = length(sampleUV);
  let pAng = atan2(sampleUV.y, sampleUV.x);
  let armPhase = pAng * 2.0 + pr * 40.0;
  let armCrest = smoothstep(0.35, 1.0, sin(armPhase));

  // Idea 1: bulge + disk starlight.
  let diffuse = diffuseStarlight(sampleUV, armCrest, waveGain);
  // Idea: parastichy sheen — the two spiral families of the same golden angle, in the unresolved disk.
  let parA = abs(fract(pAng / PHI - pr * 7.0) - 0.5);
  let parB = abs(fract(pAng / PHI * 1.618034 - pr * 11.0) - 0.5);
  let parastichy = (exp(-parA * 26.0) + exp(-parB * 34.0) * 0.65) * exp(-pr * 1.15) * smoothstep(0.02, 0.08, pr);
  accum += diffuse * (1.0 + mids * 0.3);
  accum += vec3<f32>(0.55, 0.68, 0.95) * parastichy * (0.035 + p1 * 0.04);

  // Idea 2: trailing dust lane (just upstream of the crest, where gas is
  // shocked) absorbs; HII knots glow pink-red on the crest itself.
  let lane = smoothstep(0.55, 1.0, sin(armPhase + 0.9)) * smoothstep(0.03, 0.2, pr) * exp(-pr * 1.4);
  let absorb = clamp(lane * 0.6 * min(waveGain, 1.5), 0.0, 0.85);
  accum *= 1.0 - absorb;
  let knotCell = vec2<f32>(floor(pr * 34.0), floor((pAng + TAU) * 9.0));
  let knotLocal = vec2<f32>(fract(pr * 34.0), fract((pAng + TAU) * 9.0)) - 0.5;
  let knotOn = step(0.72, hash21(knotCell));
  let knot = exp(-dot(knotLocal, knotLocal) * 22.0) * knotOn * armCrest * smoothstep(0.08, 0.25, pr) * exp(-pr * 1.2);
  let hii = vec3<f32>(1.0, 0.32, 0.5) * knot * 0.35 * min(waveGain, 1.5) * (1.0 + mids * 0.4 + shock * 1.5);
  accum += hii;

  // Chromatic aberration on bright giants
  let caStrength = 0.008 * treble;
  let caR = exp(-pow(length(sampleUV * (1.0 + caStrength) - sampleUV), 2.0) * 200.0);
  accum.r *= 1.0 + caR * 0.2;
  accum.b *= 1.0 - caR * 0.15;

  // Former primary-control twinkle (Star Size sets the pulse rate) + hover glow.
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(time * mix(0.25, 5.0, clamp(p2, 0.0, 1.0))));
  let mouseDistance = length(mouse - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(0.5 * mouseDistance * 2.0, 0.0, 1.0));

  // ACES tone mapping (single pass)
  let display = acesToneMap(accum * 1.1 * speedPulse * mouseInfluence * (1.0 + bass * 0.15));

  // Alpha: star coverage x depth fade x extinction, plus unresolved-light density
  let alpha = clamp(alphaAcc * 0.5 * (1.0 + maxDepth) + length(diffuse) * 0.4 + knot * 0.2 - absorb * 0.2, 0.0, 1.0);
  let out = vec4<f32>(display, alpha);

  // Depth: brightest/nearest stars occlude the background field
  let depthOut = clamp(maxDepth, 0.0, 1.0);
  textureStore(writeTexture, coord, out);
  textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, out);
}
