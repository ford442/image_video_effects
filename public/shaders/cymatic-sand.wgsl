// ═══════════════════════════════════════════════════════════════════
//  Cymatic Sand
//  Category: simulation
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-12, 2026-11-15
//  Ideas: node piles vs antinode ejection; beat envelope between Chladni modes; acoustic radiation-gradient grain flux (§12.2D); 3D heaped nodal-ridge normals & brushed-brass soundboard
//  A packing: raw (density, radial velocity, resonant energy, strike memory)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn stateAt(p: vec2<i32>, hi: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), hi), 0);
}

fn chladni(p: vec2<f32>, n: f32, m: f32) -> f32 {
  return cos(n * 3.14159265 * p.x) * cos(m * 3.14159265 * p.y)
    - cos(m * 3.14159265 * p.x) * cos(n * 3.14159265 * p.y);
}

fn evalPlateWave(
  plate: vec2<f32>,
  mode: f32,
  harmonic: f32,
  sensitivity: f32,
  audio: vec3<f32>,
  time: f32
) -> vec3<f32> {
  let w0 = chladni(plate, mode + audio.x * sensitivity * 3.0, mode + 2.0 + audio.y * sensitivity * 4.0);
  let w1 = chladni(plate.yx + vec2<f32>(time * 0.012, 0.0), mode + 3.0 + audio.z * 4.0, mode + 5.0);
  let w2 = sin(length(plate) * (18.0 + mode) - time * (1.0 + audio.x * 3.0));
  let wave = mix(w0, w1, harmonic) + w2 * harmonic * 0.22;
  return vec3<f32>(wave, w0, w1);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(91.7, 313.9))) * 43758.5453);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= size.x || gid.y >= size.y) { return; }

  let px = vec2<i32>(gid.xy);
  let hi = vec2<i32>(size) - vec2<i32>(1);
  let res = vec2<f32>(size);
  let uv = (vec2<f32>(px) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));

  var s = stateAt(px, hi);
  if (time < 0.12 || dot(s, s) < 0.000001) {
    let seed = hash21(vec2<f32>(px));
    s = vec4<f32>(0.22 + seed * 0.18, 0.0, 0.0, 0.0);
  }

  let mode = 2.0 + floor(u.zoom_params.x * 15.0);
  let harmonic = u.zoom_params.y;
  let densityControl = u.zoom_params.z;
  let sensitivity = u.zoom_params.w;

  var plate = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
  let mouseOffset = (u.zoom_config.yz - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
  plate -= mouseOffset * (0.12 + select(0.0, 0.32, u.zoom_config.w > 0.5));

  let wCenter = evalPlateWave(plate, mode, harmonic, sensitivity, audio, time);
  let wave = wCenter.x;
  let w0 = wCenter.y;
  let w1 = wCenter.z;
  let node = 1.0 - smoothstep(0.015, 0.12 + audio.x * sensitivity * 0.04, abs(wave));

  let l = stateAt(px + vec2<i32>(-1, 0), hi);
  let r = stateAt(px + vec2<i32>(1, 0), hi);
  let t = stateAt(px + vec2<i32>(0, -1), hi);
  let b = stateAt(px + vec2<i32>(0, 1), hi);
  let lapDensity = l.r + r.r + t.r + b.r - 4.0 * s.r;

  // ── Idea 3: acoustic radiation-gradient transport (-∇W²) & conservative grain flux (§12.2D) ──
  let plateEps = 2.0 / max(res.y, 1.0);
  let wRight = evalPlateWave(plate + vec2<f32>(plateEps, 0.0), mode, harmonic, sensitivity, audio, time).x;
  let wDown = evalPlateWave(plate + vec2<f32>(0.0, plateEps), mode, harmonic, sensitivity, audio, time).x;
  let gradW2 = vec2<f32>(wRight * wRight - wave * wave, wDown * wDown - wave * wave) / plateEps;
  let radForce = clamp(-gradW2 * (0.045 + sensitivity * 0.065 + audio.x * 0.04), vec2<f32>(-0.45), vec2<f32>(0.45));
  let fluxIn = max(radForce.x, 0.0) * l.r + max(-radForce.x, 0.0) * r.r
             + max(radForce.y, 0.0) * t.r + max(-radForce.y, 0.0) * b.r;
  let fluxOut = (abs(radForce.x) + abs(radForce.y)) * s.r;
  let stericCap = clamp(1.08 - s.r, 0.0, 1.0);
  let radiationFlux = fluxIn * stericCap - fluxOut * (1.0 - node * 0.65);

  let drive = (node - s.r) * (0.022 + audio.x * sensitivity * 0.032);
  var velocity = (s.g + drive + lapDensity * 0.035) * (0.91 - audio.y * 0.03);
  var strikes = 0.0;
  let count = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < count; i = i + 1u) {
    let e = u.ripples[i];
    let age = time - e.z;
    let isLive = f32(age >= 0.0 && age < 2.0);
    let safeAge = clamp(age, 0.0, 2.0);
    let d = length((uv - e.xy) * vec2<f32>(aspect, 1.0));
    strikes += isLive * exp(-safeAge * 1.7) * exp(-abs(d - safeAge * (0.24 + audio.x * 0.07)) * 72.0);
  }
  velocity += strikes * 0.18;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  let md = length((uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0));
  let hover = exp(-md * 18.0);
  velocity += hover * (0.004 + held * 0.10);

  let nodePile = node * (0.016 + densityControl * 0.028) * stericCap;
  let antinodeEject = (1.0 - node) * abs(wave) * s.r * 0.015;
  let beatEnv = abs(w0 + w1) / (abs(w0) + abs(w1) + 0.001);
  let newDensity = clamp(s.r + velocity * 0.08 + radiationFlux * 0.22 + nodePile - antinodeEject, 0.0, 1.0);
  let energy = clamp(mix(s.b, abs(wave) * (0.35 + audio.y * sensitivity) * (0.65 + beatEnv * 0.5) + strikes, 0.12), 0.0, 1.0);
  let memory = clamp(max(s.a * 0.94, strikes + hover * held * 0.5), 0.0, 1.0);
  let next = vec4<f32>(newDensity, clamp(velocity, -1.0, 1.0), energy, memory);
  textureStore(dataTextureA, px, next);

  // ── Idea 4: 3D heaped nodal-ridge normals, brushed-brass soundboard & antinode saltation glints ──
  let ridgeSlope = vec2<f32>(l.r - r.r, t.r - b.r) * 5.2;
  let ridgeNormal = normalize(vec3<f32>(ridgeSlope, 0.34));
  let keyDir = normalize(vec3<f32>(-0.46, -0.52, 0.72));
  let ridgeDiff = 0.28 + 0.85 * max(dot(ridgeNormal, keyDir), 0.0);
  let ridgeSpec = pow(max(dot(reflect(-keyDir, ridgeNormal), vec3<f32>(0.0, 0.0, 1.0)), 0.0), 22.0) * newDensity;

  let grainSeed = hash21(vec2<f32>(px));
  let grain = smoothstep(0.06, 0.62, newDensity * (0.45 + densityControl * 0.85) - grainSeed * 0.38);
  let antinodeBounce = (1.0 - node) * energy * step(0.84, hash21(floor(vec2<f32>(px) * 0.5) + floor(radForce * 18.0)));

  let plateRad = length((uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0));
  let latheBrush = 0.5 + 0.5 * sin(plateRad * 210.0 + atan2(uv.y - 0.5, uv.x - 0.5) * 4.0);
  let cornerDist = length(abs(uv - vec2<f32>(0.5)) - vec2<f32>(0.44));
  let clampBolt = exp(-cornerDist * cornerDist * 900.0);
  let brassBoard = vec3<f32>(0.11, 0.085, 0.055) * (0.82 + 0.36 * latheBrush) + vec3<f32>(0.45, 0.36, 0.20) * clampBolt;

  let bronze = vec3<f32>(1.35, 0.58, 0.14);
  let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + wave * 4.0 + time * 0.15);
  var sandCol = bronze * grain * ridgeDiff * (0.52 + newDensity * 1.05 + energy * 0.42);
  sandCol += vec3<f32>(1.85, 1.42, 0.82) * (ridgeSpec * 0.45 + antinodeBounce * 0.65);
  sandCol += spectral * (node * 0.28 + strikes * 0.65 + audio * sensitivity * 0.12);
  sandCol *= 0.72 + beatEnv * 0.48;

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let plateBg = mix(brassBoard, src.rgb * 0.52, 0.58);
  let hdr = mix(plateBg, sandCol, clamp(newDensity * 0.82 + grain * 0.22 + node * 0.18, 0.18, 0.97));
  let alpha = clamp(src.a * 0.15 + newDensity * 0.75 + node * 0.25 + memory * 0.25, 0.0, 1.0);
  let mapped = aces(max(hdr, vec3<f32>(0.0)));
  let sceneDepth = textureLoad(readDepthTexture, px, 0).r;
  textureStore(writeTexture, px, vec4<f32>(mapped * alpha, alpha));
  textureStore(writeDepthTexture, px, vec4<f32>(clamp(mix(sceneDepth, 1.0 - newDensity * 0.65 - node * 0.12, 0.75), 0.0, 1.0), 0.0, 0.0, 0.0));
}
