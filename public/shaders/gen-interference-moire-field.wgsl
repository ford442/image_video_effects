// ═══════════════════════════════════════════════════════════════════
//  Interference Moire Field
//  Category: generative
//  Features: analytic-lines, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10, 2026-11-15
//  Ideas: 6.8% density detune beat; two-source Young path-difference; polarization color banding; sub-wavelength micro-fringes; Fabry-Perot Airy finesse & stationary-phase saddle caustics; spectral diffraction-order dispersion (§12.2F)
//  A packing: raw HDR display RGBA (ACES on writeTexture)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;

fn rotate2(p: vec2<f32>, a: f32) -> vec2<f32> {
  let c = cos(a); let s = sin(a);
  return vec2<f32>(c * p.x - s * p.y, s * p.x + c * p.y);
}
fn palette(t: f32) -> vec3<f32> {
  return vec3<f32>(0.52) + vec3<f32>(0.48) * cos(TAU * (vec3<f32>(t) + vec3<f32>(0.0, 0.27, 0.61)));
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = (vec2<f32>(pixel) + vec2<f32>(0.5)) / res;
  let aspect = res.x / max(res.y, 1.0);
  let p = (uv01 - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let densParam = clamp(u.zoom_params.x, 0.0, 1.0);
  let density = mix(12.0, 72.0, densParam);
  let crossing = mix(0.08, 1.48, clamp(u.zoom_params.y, 0.0, 1.0));
  let warpStrength = mix(0.0, 0.42, clamp(u.zoom_params.z, 0.0, 1.0));
  let colorPhase = u.zoom_params.w;
  let mouse = (u.zoom_config.yz - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
  let held = clamp(u.zoom_config.w, 0.0, 1.0);
  let pointerWarp = exp(-distance(p, mouse) * 7.0) * held;
  let phaseWarp = warpStrength * (sin(p.y * 7.0 + time * 0.7 + mids) + cos(p.x * 9.0 - time * 0.5 + bass));
  let ang1 = crossing * 0.5 + pointerWarp * 0.18;
  let ang2 = -crossing * 0.5 - pointerWarp * 0.18;
  let q1 = rotate2(p, ang1);
  let q2 = rotate2(p, ang2);
  let densB = density * 1.068;

  let phaseA = q1.x * density + phaseWarp * density + time * (0.4 + bass * 0.25);
  let phaseB = q2.x * density - phaseWarp * density * 0.8 - time * (0.32 + mids * 0.2);
  let lineA = sin(phaseA);
  let lineB = sin(phaseB);
  let lineA2 = sin(q1.x * densB + phaseWarp * densB + time * (0.4 + bass * 0.25));
  let lineB2 = sin(q2.x * densB - phaseWarp * densB * 0.8 - time * (0.32 + mids * 0.2));
  let crossed = lineA * lineB;
  let detuneBeat = lineA * lineA2 * 0.5 + lineB * lineB2 * 0.5;
  let ridges = pow(max(abs(crossed), 1e-5), mix(0.35, 1.4, densParam));
  let beat = 0.5 + 0.5 * cos((lineA - lineB) * 4.0 + treble * 2.0);
  let srcB = mix(vec2<f32>(0.18, 0.0), mouse, held);
  let young = 0.5 + 0.5 * cos((length(p) - length(p - srcB)) * density * 0.32);

  // Idea 1 (2026-10-10): polarization color banding
  let phaseDiff = abs(lineA - lineB);
  let polarization = palette(phaseDiff * 2.5 + colorPhase);

  // Idea 2 (2026-10-10): sub-wavelength micro-fringes
  let microFringes = sin(q1.x * density * 5.0) * sin(q2.x * density * 5.0) * smoothstep(0.7, 1.0, abs(crossed));

  // ── Idea 3: Fabry-Perot multi-beam Airy finesse & stationary-phase saddle caustics ──
  let finesse = mix(2.5, 18.0, densParam) * (1.0 + bass * 0.38);
  let halfDiff = sin((phaseA - phaseB) * 0.5);
  let airyFinesse = 1.0 / (1.0 + finesse * halfDiff * halfDiff);
  let dWarp = warpStrength * vec2<f32>(
    -9.0 * sin(p.x * 9.0 - time * 0.5 + bass),
     7.0 * cos(p.y * 7.0 + time * 0.7 + mids)
  );
  let kVecA = vec2<f32>(cos(ang1), -sin(ang1)) + dWarp;
  let kVecB = vec2<f32>(cos(ang2), -sin(ang2)) - dWarp * 0.8;
  let moireWavevec = length(kVecA - kVecB);
  let saddleCaustic = exp(-moireWavevec * 2.4) * airyFinesse;

  // ── Idea 4: spectral diffraction-order dispersion (§12.2F Cauchy / grating dispersion) ──
  let lam2 = vec3<f32>(0.650 * 0.650, 0.550 * 0.550, 0.450 * 0.450);
  let cauchyRel = (vec3<f32>(1.0) + 0.022 / lam2) / (1.0 + 0.022 / (0.550 * 0.550)) - vec3<f32>(1.0);
  let dispDrive = (0.32 + warpStrength * 2.6 + pointerWarp * 1.8 + mids * 0.35) * (0.4 + densParam * 0.85);
  let diffOrder = 0.5 + 0.5 * cos(vec3<f32>(phaseA - phaseB) + cauchyRel * dispDrive * 14.0);
  let spectralFringe = diffOrder * diffOrder * diffOrder * (0.22 + airyFinesse * 0.42);

  var pulse = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var ri = 0u; ri < rippleCount; ri++) {
    let ripple = u.ripples[ri];
    let age = time - ripple.z;
    let isLive = f32(age > 0.0 && age < 3.0);
    let safeAge = clamp(age, 0.0, 3.0);
    let center = (ripple.xy - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
    pulse += isLive * exp(-abs(distance(p, center) - safeAge * 0.28) * 74.0) * exp(-safeAge * 1.25);
  }

  let circular = sin(length(p - mouse * held) * density * 0.55 - time * 1.2) * pointerWarp;
  var raw = polarization * (0.14 + ridges * 1.05 + airyFinesse * 0.36);
  raw += spectralFringe * mix(vec3<f32>(1.15, 0.95, 0.82), polarization + vec3<f32>(0.25), 0.45);
  raw += palette(colorPhase + 0.19) * saddleCaustic * (0.55 + bass * 0.28);
  raw += palette(beat * 0.2 + colorPhase + 0.32) * beat * (0.18 + treble * 0.22);
  raw += palette(colorPhase + 0.55) * abs(detuneBeat) * 0.42;
  raw += palette(colorPhase + 0.08) * young * (0.16 + held * 0.12 + treble * 0.08);
  raw += vec3<f32>(1.0, 1.5, 2.0) * max(microFringes, 0.0) * 0.35;
  raw += vec3<f32>(1.3 + bass * 0.3, 0.55 + mids * 0.25, 1.6 + treble * 0.45) * (pulse + abs(circular) * 0.28);

  let prev = textureLoad(dataTextureC, pixel, 0);
  raw = clamp(mix(prev.rgb * 0.93, max(raw, vec3<f32>(0.0)), 0.31 + warpStrength * 0.08), vec3<f32>(0.0), vec3<f32>(7.0));
  let alpha = clamp(0.04 + ridges * 0.54 + airyFinesse * 0.14 + saddleCaustic * 0.12 + beat * 0.10 + abs(detuneBeat) * 0.08 + young * 0.08 + pulse * 0.2, 0.04, 0.98);
  let depth = clamp(ridges * 0.50 + airyFinesse * 0.18 + saddleCaustic * 0.16 + abs(lineA - lineB) * 0.10 + young * 0.08 + pulse * 0.2, 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(raw, alpha));
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(raw * 1.06), alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
