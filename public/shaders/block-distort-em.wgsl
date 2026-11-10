// ═══════════════════════════════════════════════════════════════════
//  Block Distort EM
//  Category: advanced-hybrid
//  Features: mouse-driven, field-simulation, chromatic, temporal, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-11, 2026-11-09
//  Ideas: block hinge shear; row phase stagger; magnetic block rotation (B twists each block about its centre); hinge facet shading (lit/dark halves of a tilted block)
//  A packing: ACES display RGBA; texels (0,0)/(1,0) hold the cursor-track state [mouse, fract(time), 0.7371]/[velocity, 0, 0.7371] (C is read only there)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const FACET_GAIN: f32 = 0.35;

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Streamline speckle for one time step (tq = quantised seconds). Position-only hash: HEAD also mixed
// fieldMag*10 and a fieldDir-displaced lookup into the hash, but hash12 is chaotic, so ANY smooth change of the
// field (a decaying click, a moving cursor) re-randomised every pixel each frame. A displaced white-noise lookup
// is still white noise, so nothing visible is lost; direction still colours the speckle (fieldColor).
fn streamSpeckle(uv: vec2<f32>, tq: f32) -> f32 {
  return smoothstep(0.4, 0.6, hash12(uv * 200.0 + vec2<f32>(tq * 37.0, tq * 17.0)));
}

fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
  let k = vec3<f32>(0.57735, 0.57735, 0.57735);
  let cosAngle = cos(hue);
  return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn electricField(pos: vec2<f32>, chargePos: vec2<f32>, charge: f32) -> vec2<f32> {
  let r = pos - chargePos;
  let dist = max(length(r), 0.001);
  // r / dist^3 == normalize(r) / dist^2, but finite when pos sits exactly on the charge.
  return charge * r / (dist * dist * dist);
}

fn magneticField(pos: vec2<f32>, chargePos: vec2<f32>, velocity: vec2<f32>, charge: f32) -> f32 {
  let r = pos - chargePos;
  let dist = max(length(r), 0.001);
  return charge * (velocity.x * r.y - velocity.y * r.x) / (dist * dist * dist);
}

// Total field at a point: xy = E, z = B. Cursor charge + the orbiting secondary charges of live clicks.
fn fieldsAt(pos: vec2<f32>, mousePos: vec2<f32>, mouseVel: vec2<f32>, fieldStrength: f32, time: f32) -> vec3<f32> {
  var totalE = electricField(pos, mousePos, fieldStrength);
  var totalB = magneticField(pos, mousePos, mouseVel, fieldStrength);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 3.0) {
      let orbitAngle = elapsed * 2.0 + f32(i) * 1.256;
      let orbitRadius = 0.05 + 0.1 * smoothstep(0.0, 1.0, elapsed);
      let orbitPos = mousePos + vec2<f32>(cos(orbitAngle), sin(orbitAngle)) * orbitRadius;
      // the charge is faded to exactly 0 across 2..3 s so the click's field does not pop out at the cutoff
      let secondaryCharge = -fieldStrength * exp(-elapsed * 0.8) * (1.0 - smoothstep(2.0, 3.0, elapsed));
      let secVel = vec2<f32>(-sin(orbitAngle), cos(orbitAngle)) * 2.0;
      totalE = totalE + electricField(pos, orbitPos, secondaryCharge);
      totalB = totalB + magneticField(pos, orbitPos, secVel, secondaryCharge);
    }
  }
  return vec3<f32>(totalE, totalB);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let pixel = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let blockSize = mix(10.0, 100.0, u.zoom_params.x);
  let pushStrength = u.zoom_params.y * 2.0;
  let rgbSplit = u.zoom_params.z * 0.1;
  let fieldStrength = u.zoom_params.w * 2.0;

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // Rescue R1: HEAD kept the previous cursor in extraBuffer[133..134], which the host re-uploads as 0
  // every frame, so mouseVel was mousePos*60 (cursor POSITION, not motion) and the magnetic term spun the
  // hue even with a parked cursor. The previous cursor now rides texels (0,0)/(1,0) of A (read back as C):
  // (0,0) = [mouse.xy, fract(time), 0.7371], (1,0) = [smoothed velocity.xy, 0, 0.7371]. Those two display
  // pixels of history are sacrificed (this shader reads C nowhere else).
  let trackA = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let trackB = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
  let trackOk = abs(trackA.w - 0.7371) < 0.001 && abs(trackB.w - 0.7371) < 0.001;
  let trackDt = fract(time - trackA.z);
  let trackLive = trackOk && trackDt > 0.0005 && trackDt < 0.25;
  // Dead-band on the per-frame DISPLACEMENT (an f16 A texel quantises the stored cursor by up to ~2.4e-4 per axis,
  // so |Δ| < 4e-4 is storage noise, not motion; fully passed at 9e-4), then the smoothed velocity fades to an
  // exact 0 below 0.02 uv/s: a parked cursor gives exactly zero B at any frame rate.
  let trackMove = mousePos - trackA.xy;
  let instVel = trackMove / max(trackDt, 0.0005) * smoothstep(4.0e-4, 9.0e-4, length(trackMove));
  var sVel = select(vec2<f32>(0.0), mix(trackB.xy, instVel, 0.25), trackLive);
  sVel = sVel * min(1.0, 6.0 / max(length(sVel), 1e-4));
  let mouseVel = sVel * smoothstep(0.02, 0.08, length(sVel));

  let fld = fieldsAt(uv, mousePos, mouseVel, fieldStrength, time);
  let totalE = fld.xy;
  let totalB = fld.z;

  let fieldMag = length(totalE);
  let fieldDir = select(vec2<f32>(0.0), normalize(totalE), fieldMag > 0.0001);
  let fieldTangent = vec2<f32>(-fieldDir.y, fieldDir.x);

  let gridUV = uv * vec2<f32>(resolution.x / blockSize, resolution.y / blockSize);
  let cellID = floor(gridUV);
  let cellCenterGrid = cellID + 0.5;
  let cellCenterUV = cellCenterGrid / vec2<f32>(resolution.x / blockSize, resolution.y / blockSize);

  let distVec = (cellCenterUV - mousePos) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);
  let radius = 0.5;

  // Idea 2 (2026-09-11) — row phase stagger: alternating rows offset push phase by π
  let rowParity = fract(cellID.y * 0.5);
  let rowPhase = select(0.0, 3.14159265, rowParity > 0.25);
  let phasePush = 0.55 + 0.45 * sin(time * 3.0 + rowPhase + dist * 8.0);

  let pushMask = smoothstep(radius, 0.0, dist) * phasePush;
  let pushDir = distVec / max(dist, 1e-4);   // rescue R2: finite when a cell centre sits on the cursor
  let blockDisplacement = pushDir * pushMask * pushStrength * 0.1;

  let emDisplacement = fieldDir * smoothstep(0.0, 2.0, fieldMag) * 0.05;

  // Idea 1 (2026-09-11) — block hinge shear along local E-field tangent
  let cellUV = fract(gridUV) - 0.5;
  let hingeTilt = smoothstep(0.0, 2.0, fieldMag) * pushMask;
  let hingeShear = fieldTangent * cellUV.x * hingeTilt * 0.04;

  // ── Idea 3: magnetic block rotation (native: B was only ever a hue angle) ──
  // B sampled at the block CENTRE so every block turns rigidly about its own middle. The angle saturates at
  // ±0.5 rad and rides the push-radius envelope only (NOT the row-stagger phase, which averaged the turn down to
  // ~2°), so the twist is visible. B is the cursor's real velocity term (rescue R1): blocks twist while the cursor
  // moves and settle (exactly 0) when it parks.
  let cellB = fieldsAt(cellCenterUV, mousePos, mouseVel, fieldStrength, time).z;
  let nearField = smoothstep(radius, radius * 0.35, dist);   // plateau near the cursor, gone by the push radius
  let rotAngle = 0.5 * clamp(cellB * 0.2, -1.0, 1.0) * nearField;
  let rotCs = cos(rotAngle);
  let rotSn = sin(rotAngle);
  let rotatedLocal = vec2<f32>(cellUV.x * rotCs - cellUV.y * rotSn, cellUV.x * rotSn + cellUV.y * rotCs);
  let rotDisp = (rotatedLocal - cellUV) * (blockSize / resolution);   // cell units → uv

  let totalDisplacement = blockDisplacement + emDisplacement + hingeShear - rotDisp;
  let split = totalDisplacement * rgbSplit * 5.0 + fieldDir * rgbSplit * 0.05;

  let uvR = clamp(uv - totalDisplacement + split, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvG = clamp(uv - totalDisplacement, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvB = clamp(uv - totalDisplacement - split, vec2<f32>(0.0), vec2<f32>(1.0));

  let sampleR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0);
  let sampleG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0);
  let sampleB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0);

  var finalColor = vec3<f32>(sampleR.r, sampleG.g, sampleB.b);
  var finalAlpha = (sampleR.a + sampleG.a + sampleB.a) / 3.0;
  finalAlpha = mix(finalAlpha, finalAlpha * 0.9, pushMask);

  // B diverges as 1/r² at the cursor; bound the hue spin so the core is a flat rotation, not aliased rings.
  let hueRot = clamp(totalB, -10.0, 10.0) * 0.5;
  finalColor = hueShift(finalColor, hueRot * pushMask);

  // ── Idea 4: hinge facet shading (native: extends the hinge shear, no new motif) ──
  // A block hinged along the field tangent is a tilted facet: the half leaning toward the (fixed, upper-left)
  // light is lit, the other half dark. Tilt vector = hingeShear direction, so the shading flips with the hinge.
  // (tilt rides the field and the push radius, not the row-stagger phase, so the shading is steady and legible)
  let facet = 2.0 * cellUV.x * dot(fieldTangent, vec2<f32>(-0.7071, -0.7071)) * smoothstep(0.0, 2.0, fieldMag) * nearField;
  finalColor = finalColor * (1.0 + FACET_GAIN * facet);

  let cellUVEdge = fract(gridUV);
  let edgeDist = min(min(cellUVEdge.x, 1.0 - cellUVEdge.x), min(cellUVEdge.y, 1.0 - cellUVEdge.y));
  let edge = (1.0 - smoothstep(0.0, 0.05, edgeDist)) * pushMask;
  finalColor = finalColor + vec3<f32>(edge * 0.5);
  finalAlpha = mix(finalAlpha, 1.0, edge * 0.2);

  // HEAD re-hashed this speckle every frame (a strobe at a parked cursor). It is now re-randomised at 6 Hz and
  // cross-faded between the two steps, same look, no frame-rate flicker.
  let tPh = time * 6.0;
  let tq0 = floor(tPh) / 6.0;
  let streamSp = mix(streamSpeckle(uv, tq0), streamSpeckle(uv, tq0 + 1.0 / 6.0), smoothstep(0.0, 1.0, fract(tPh)));
  let streamline = streamSp * smoothstep(0.0, 0.5, fieldMag);
  let fieldColor = mix(vec3<f32>(0.0, 0.6, 1.0), vec3<f32>(1.0, 0.8, 0.0), atan2(fieldDir.y, fieldDir.x) * 0.159 + 0.5);
  finalColor = mix(finalColor, fieldColor, streamline * 0.3);

  let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let coreGlow = exp(-mouseDist * mouseDist * 400.0) * fieldStrength;
  finalColor = finalColor + vec3<f32>(0.6, 0.9, 1.0) * coreGlow;

  finalColor = finalColor * (1.0 + mouseDown * 0.3);
  finalAlpha = clamp(finalAlpha + pushMask * 0.12 + fieldMag * 0.08, 0.0, 1.0);

  let displayRgb = acesToneMap(max(finalColor, vec3<f32>(0.0)));
  textureStore(writeTexture, pixel, vec4<f32>(displayRgb, finalAlpha));
  var aOut = vec4<f32>(displayRgb, finalAlpha);
  if (pixel.y == 0 && pixel.x == 0) { aOut = vec4<f32>(mousePos, fract(time), 0.7371); }
  if (pixel.y == 0 && pixel.x == 1) { aOut = vec4<f32>(sVel, 0.0, 0.7371); }
  textureStore(dataTextureA, pixel, aOut);

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
