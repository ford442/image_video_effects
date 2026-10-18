// ═══════════════════════════════════════════════════════════════════
//  Electromagnetic Aurora
//  Category: interactive-mouse
//  Features: mouse-driven, field-simulation, chromatic, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: LIC field lines over a stable hash; aurora curtains hanging from |B|, coloured by sign of B; click counter-charges anchored at the click
//  A packing: ACES display RGBA; texel (0,0) = (prevMouse.xy, prevTime, 1), texel (1,0) = (smoothed velocity.xy, 0, 1) — exact C loads
// ═══════════════════════════════════════════════════════════════════
//  The mouse acts as a moving electric charge generating EM fields.
//  Electric field distorts UVs; magnetic field (from cursor motion) rotates hue.
//  Clicks drop opposite-polarity counter-charges at the click point.
//  Alpha channel stores magnetic flux (signed, 0.5 = none).
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const MAX_CHARGES: i32 = 8;

// Per-invocation charge set (cursor + up to 8 click counter-charges), aspect space
var<private> gAspect: f32 = 1.0;
var<private> gChargePos: array<vec2<f32>, 8>;
var<private> gChargeQ: array<f32, 8>;
var<private> gChargeN: i32 = 0;

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: hueShift (from stellar-plasma.wgsl) ═══
fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
  let k = vec3<f32>(0.57735, 0.57735, 0.57735);
  let cosAngle = cos(hue);
  return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn toAspect(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(p.x * gAspect, p.y);
}

// pos / chargePos in aspect space (floor fix: HEAD measured distance in raw uv)
fn electricField(pos: vec2<f32>, chargePos: vec2<f32>, charge: f32) -> vec2<f32> {
  let r = pos - chargePos;
  let dist = max(length(r), 0.001);
  return charge * (r / dist) / (dist * dist);
}

fn magneticField(pos: vec2<f32>, chargePos: vec2<f32>, velocity: vec2<f32>, charge: f32) -> f32 {
  let r = pos - chargePos;
  let dist = max(length(r), 0.001);
  return charge * (velocity.x * r.y - velocity.y * r.x) / (dist * dist * dist);
}

// Cursor charge + click counter-charges, aspect space
fn totalE(posA: vec2<f32>, mouseA: vec2<f32>, q: f32) -> vec2<f32> {
  var e = electricField(posA, mouseA, q);
  for (var i: i32 = 0; i < gChargeN; i = i + 1) {
    e = e + electricField(posA, gChargePos[i], gChargeQ[i]);
  }
  return e;
}

// Idea 1: short LIC trace along the E-field direction over a hash that is fixed
// to the pixel grid (no time term), so streaks are stable iron filings rather
// than per-frame static. A travelling weight pulse makes them flow outward.
fn licFieldLines(uv: vec2<f32>, mouseA: vec2<f32>, q: f32, resolution: vec2<f32>, time: f32) -> f32 {
  let stepA = 1.25 / resolution.y;       // ~1.25 px per step in aspect space
  var pF = toAspect(uv);
  var pB = pF;
  var acc = hash12(floor(uv * resolution));
  var wsum = 1.0;
  for (var i: i32 = 1; i <= 9; i = i + 1) {
    let eF = totalE(pF, mouseA, q);
    let eB = totalE(pB, mouseA, q);
    pF = pF + eF / max(length(eF), 1e-6) * stepA;
    pB = pB - eB / max(length(eB), 1e-6) * stepA;
    let fi = f32(i);
    let wF = 0.6 + 0.4 * sin(fi * 0.7 - time * 5.0);
    let wB = 0.6 + 0.4 * sin(-fi * 0.7 - time * 5.0);
    let uvF = vec2<f32>(pF.x / gAspect, pF.y);
    let uvB = vec2<f32>(pB.x / gAspect, pB.y);
    acc = acc + wF * hash12(floor(uvF * resolution)) + wB * hash12(floor(uvB * resolution));
    wsum = wsum + wF + wB;
  }
  return acc / wsum;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  gAspect = aspect;
  let time = u.config.x;

  let chargeStrength = u.zoom_params.x * 2.0;
  let fieldVis = u.zoom_params.y;
  let distortionStrength = u.zoom_params.z * 0.15;
  let colorRotation = u.zoom_params.w * 3.14159;

  // Floor fix: velocity from real dt (HEAD assumed 60 fps) and EMA-smoothed.
  // State lives in A texels (0,0)/(1,0) and is read back with exact C loads.
  let mousePos = u.zoom_config.yz;
  let s0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let s1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
  let dtRaw = time - s0.z;
  let stateOk = s0.w > 0.5 && s1.w > 0.5 && dtRaw > 0.0 && dtRaw < 0.5;
  let dt = max(dtRaw, 1.0 / 240.0);
  var rawVel = (mousePos - s0.xy) / dt;
  rawVel = rawVel * min(1.0, 6.0 / max(length(rawVel), 1e-6));
  let prevSmooth = select(vec2<f32>(0.0), s1.xy, stateOk && s1.x == s1.x && s1.y == s1.y);
  let mouseVel = select(vec2<f32>(0.0), mix(prevSmooth, rawVel, 1.0 - exp(-dt * 12.0)), stateOk);
  let mouseVelA = vec2<f32>(mouseVel.x * aspect, mouseVel.y);

  // Idea 3: click counter-charges anchored at the click point itself (HEAD
  // orbited them around the cursor). With the cursor they form a dipole.
  let rippleCount = min(u32(u.config.y), 50u);
  var n: i32 = 0;
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 3.0 && n < MAX_CHARGES) {
      gChargePos[n] = toAspect(ripple.xy);
      gChargeQ[n] = -chargeStrength * exp(-elapsed * 0.8) * smoothstep(0.0, 0.15, elapsed);
      n = n + 1;
    }
  }
  gChargeN = n;

  let uvA = toAspect(uv);
  let mouseA = toAspect(mousePos);

  // Primary charge = mouse (moving → B); counter-charges are static (E only)
  let totalEv = totalE(uvA, mouseA, chargeStrength);
  let totalB = magneticField(uvA, mouseA, mouseVelA, chargeStrength);

  // Field magnitude for visualization
  let fieldMag = length(totalEv);
  let fieldDirA = select(vec2<f32>(0.0), totalEv / max(fieldMag, 1e-6), fieldMag > 0.0001);
  let fieldDir = vec2<f32>(fieldDirA.x / aspect, fieldDirA.y);

  // Idea 1: field lines (LIC) replace the per-pixel hash static
  let lic = licFieldLines(uv, mouseA, chargeStrength, resolution, time);
  let licC = clamp((lic - 0.5) * 5.0 + 0.5, 0.0, 1.0);
  let streamline = licC * fieldVis * smoothstep(0.0, 0.5, fieldMag);

  // UV displacement along electric field
  let displacedUV = clamp(uv + fieldDir * distortionStrength * smoothstep(0.0, 2.0, fieldMag), vec2<f32>(0.0), vec2<f32>(1.0));

  // Sample image
  let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

  // Hue rotation from magnetic field
  let hueRot = totalB * colorRotation * 0.5;
  let color = hueShift(baseColor, hueRot);

  // Field line overlay: cyan/gold based on field direction
  let fieldColor = mix(vec3<f32>(0.0, 0.6, 1.0), vec3<f32>(1.0, 0.8, 0.0), atan2(fieldDirA.y, fieldDirA.x) * 0.159 + 0.5);
  var finalColor = mix(color, fieldColor, streamline * 0.4);

  // Idea 2: aurora curtains — |B| sampled above the pixel so glow hangs down
  // from wherever the moving charge induces a strong B, broken into vertical
  // rays; green where B > 0, violet where B < 0.
  var curtain = 0.0;
  var signAcc = 0.0;
  for (var k: i32 = 0; k < 5; k = k + 1) {
    let fk = f32(k);
    let probe = uvA - vec2<f32>(0.0, fk * 0.045);
    let bk = magneticField(probe, mouseA, mouseVelA, chargeStrength);
    let bSoft = abs(bk) / (abs(bk) + 10.0);
    let fall = 1.0 - fk * 0.17;
    curtain = max(curtain, bSoft * fall);
    signAcc = signAcc + bk * fall;
  }
  let xa = uv.x * aspect;
  let rays = 0.5 + 0.5 * sin(xa * 55.0 + 2.5 * sin(xa * 6.0 + time * 0.6) + time * 0.4);
  let ribbon = smoothstep(0.25, 1.0, rays) * (0.65 + 0.35 * sin(xa * 9.0 - time * 0.9));
  let auroraCol = select(vec3<f32>(0.75, 0.3, 1.0), vec3<f32>(0.25, 1.0, 0.55), signAcc >= 0.0);
  finalColor = finalColor + auroraCol * curtain * ribbon * fieldVis * 0.9;

  // Boost near mouse
  let mouseDist = length(uvA - mouseA);
  let coreGlow = exp(-mouseDist * mouseDist * 400.0) * chargeStrength;
  let glowColor = vec3<f32>(0.6, 0.9, 1.0);
  var outColor = finalColor + glowColor * coreGlow * fieldVis;
  // Idea 3: small opposite-polarity glow marks each anchored counter-charge
  for (var i: i32 = 0; i < gChargeN; i = i + 1) {
    let dc = length(uvA - gChargePos[i]);
    outColor = outColor + vec3<f32>(1.0, 0.45, 0.3) * exp(-dc * dc * 600.0) * abs(gChargeQ[i]) * fieldVis;
  }

  let display = aces_tonemap(max(outColor, vec3<f32>(0.0)));

  // Alpha = magnetic flux (signed, clamped for storage)
  let alpha = clamp(totalB * 0.5 + 0.5, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(display, alpha));

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(d, 0.0, 0.0, 0.0));

  // A: display everywhere, pointer state in texels (0,0) and (1,0)
  var aOut = vec4<f32>(display, alpha);
  if (global_id.y == 0u && global_id.x == 0u) {
    aOut = vec4<f32>(mousePos, time, 1.0);
  } else if (global_id.y == 0u && global_id.x == 1u) {
    aOut = vec4<f32>(mouseVel, 0.0, 1.0);
  }
  textureStore(dataTextureA, coord, aOut);
}
