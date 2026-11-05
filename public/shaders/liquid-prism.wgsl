// ═══════════════════════════════════════════════════════════════════
//  Liquid Prism — Cauchy-Dispersion Ripple Glass
//  Category: distortion
//  Features: mouse-driven, held-drag, bounded-click-ripples, audio-reactive,
//            per-band-fft, cauchy-dispersion, fresnel, caustic-fronts,
//            temporal-afterglow, depth-aware, upgraded-rgba, semantic-alpha, ACES
//  Upgraded: 2026-11-01
//  Ideas: caustic focusing from the refraction Jacobian (1/|det J|); total internal reflection flash beyond the critical angle
//  A packing: display RGBA (unchanged)
//  Complexity: High
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Strength, y=Frequency, z=Speed, w=Aberration

const CAUCHY_A: f32 = 1.62;
const CAUCHY_B: f32 = 0.0132;
const LAMBDA_R: f32 = 0.650;
const LAMBDA_G: f32 = 0.532;
const LAMBDA_B: f32 = 0.450;

fn cauchyIndex(lambdaUm: f32) -> f32 {
  return CAUCHY_A + CAUCHY_B / (lambdaUm * lambdaUm);
}

// FFT band k (0..7): engine FFT bins live in extraBuffer[5 .. 132]. HEAD read plasmaBuffer[k + 1].x, but
// only plasmaBuffer[0] is ever written, so the per-distance band was a constant zero.
fn fftBand(k: u32) -> f32 {
  let idx = 5u + (k % 8u) * 4u;
  return select(0.0, extraBuffer[min(idx, arrayLength(&extraBuffer) - 1u)], arrayLength(&extraBuffer) > idx);
}

fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  let m = clamp(1.0 - cosTheta, 0.0, 1.0);
  let m2 = m * m;
  return F0 + (1.0 - F0) * m2 * m2 * m;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn calculatePrismAlpha(distortionMag: f32, viewDotNormal: f32, baseTransparency: f32) -> f32 {
  let fresnel = schlickFresnel(max(0.0, viewDotNormal), 0.04);
  let thicknessFactor = smoothstep(0.0, 0.1, distortionMag);
  let baseAlpha = mix(0.3, 0.85, baseTransparency);
  return clamp(baseAlpha * (1.0 - thicknessFactor * 0.3) * (1.0 - fresnel * 0.25), 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

  // Critically damped spring cursor in extraBuffer[133..138]
  let isWriter = (global_id.x == 0u && global_id.y == 0u);
  let hasState = (arrayLength(&extraBuffer) > 138u);

  var mouse = rawMouse;
  if (hasState && extraBuffer[138] > 0.5) {
    mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }

  if (isWriter && hasState) {
    let lastTime = extraBuffer[137];
    let dt = clamp(time - lastTime, 0.0, 0.05);
    var sPos = mouse;
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] < 0.5) {
      sPos = rawMouse;
      sVel = vec2<f32>(0.0);
    }
    let stiffness = 42.0;
    let damping = 12.96; // 2 * sqrt(42)
    let accel = (rawMouse - sPos) * stiffness - sVel * damping;
    sVel += accel * dt;
    sPos += sVel * dt;
    extraBuffer[133] = sPos.x;
    extraBuffer[134] = sPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  let diff = uv - mouse;
  let distVec = diff * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);
  let bandIdx = u32(clamp(dist * 8.0, 0.0, 7.999));
  let band = fftBand(bandIdx);

  // Exact parameter contracts
  let strength = u.zoom_params.x * 0.1 * (1.0 + bass * 0.6 + held * 0.35);
  let frequency = (u.zoom_params.y * 20.0 + 5.0) * (1.0 + mids * 0.3 + band * 0.4);
  let speed = u.zoom_params.z * 5.0 * (1.0 + bass * 0.2);
  let aberration = u.zoom_params.w * 0.05 * (1.0 + treble * 0.4);
  let baseTransparency = u.zoom_params.w;

  // Pointer ripple
  let wavePhase = dist * frequency - time * speed;
  let wave = sin(wavePhase);
  let decay = 1.0 / (1.0 + dist * 5.0);
  let dir = normalize(diff + vec2<f32>(0.0001, 0.0001));
  var displace = dir * wave * strength * decay;

  // 2026-11 Idea 1: caustic focusing. The pointer ripple refracts by the radial map r' = r + A(r) with
  // A = strength * decay * sin(phase). Its Jacobian is (1 + A') radially and (1 + A / r) tangentially;
  // light concentrates where the determinant goes to zero, which is what a caustic is. A' is analytic
  // (decay' = -5 decay^2). Brightness x mix(1, clamp(1 / (|det| + 0.25), 0.6, 2.0), 0.6).
  let rippleA = strength * decay * wave;
  let rippleDA = strength * (decay * frequency * cos(wavePhase) - wave * 5.0 * decay * decay);
  let jacDet = (1.0 + rippleDA) * (1.0 + rippleA / max(dist, 0.03));
  let focusGain = clamp(1.0 / (abs(jacDet) + 0.25), 0.6, 2.0);

  // Bounded click caustic fronts
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
      displace += vec2<f32>(rDir.x / aspect, rDir.y) * sin(front * 60.0) * envelope * strength * 2.2;
      causticRidge += envelope * envelope * (1.0 + bass * 0.8);
    }
  }
  causticRidge = min(causticRidge, 2.0);

  // Cauchy dispersion
  let nR = cauchyIndex(LAMBDA_R);
  let nG = cauchyIndex(LAMBDA_G);
  let nB = cauchyIndex(LAMBDA_B);
  let nMid = nG;
  let spread = 1.0 + aberration * 8.0;

  let rUV = clamp(uv + displace * (1.0 + (nR - nMid) * spread), vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = clamp(uv + displace, vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(uv + displace * (1.0 + (nB - nMid) * spread), vec2<f32>(0.0), vec2<f32>(1.0));

  let sR = textureSampleLevel(readTexture, u_sampler, rUV, 0.0);
  let sG = textureSampleLevel(readTexture, u_sampler, gUV, 0.0);
  let sB = textureSampleLevel(readTexture, u_sampler, bUV, 0.0);
  var color = vec3<f32>(sR.r, sG.g, sB.b);

  color = color * mix(1.0, focusGain, 0.6);

  let highlight = smoothstep(0.8, 1.0, wave) * decay * strength * 10.0 * (1.0 + bass);
  color += vec3<f32>(0.15, 0.18, 0.2) * highlight;
  color += vec3<f32>(1.0, 0.92, 0.78) * causticRidge * 0.5;

  let indexSpread = (nB - nR) * spread;
  color += vec3<f32>(0.10, 0.06, 0.22) * indexSpread * length(displace) * 60.0;

  let distortionMag = length(displace);
  let normal = normalize(vec3<f32>(-displace.x * 50.0, -displace.y * 50.0, 1.0));
  let viewDotNormal = normal.z;

  // 2026-11 Idea 2: total internal reflection. On a steep ripple face the ray inside the glass exceeds the
  // critical angle asin(1 / n) and is reflected instead of refracted: cos(critical) = sqrt(1 - 1/n^2).
  // The sample is replaced by a mirrored tap (uv - n.xy * 0.05), lifted slightly, weighted by a soft step.
  let critCos = sqrt(max(1.0 - 1.0 / (nG * nG), 0.0));
  let tirWeight = 1.0 - smoothstep(critCos - 0.06, critCos + 0.06, normal.z);
  let tirUV = clamp(uv - normal.xy * 0.05, vec2<f32>(0.0), vec2<f32>(1.0));
  let tirColor = textureSampleLevel(readTexture, u_sampler, tirUV, 0.0).rgb * 1.15 + vec3<f32>(0.05);
  color = mix(color, tirColor, tirWeight * 0.7);

  // Exact dataTextureC persistence
  let prev = textureLoad(dataTextureC, coord, 0);
  color = max(color, prev.rgb * (0.80 + treble * 0.06));

  color = aces(color);

  let alpha = clamp(calculatePrismAlpha(distortionMag, viewDotNormal, baseTransparency) + causticRidge * 0.2 + held * 0.1, 0.0, 1.0);
  let outColor = vec4<f32>(color, alpha);

  textureStore(writeTexture, coord, outColor);
  textureStore(dataTextureA, coord, outColor);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth * (1.0 - distortionMag * 2.0), 0.0, 1.0), 0.0, 0.0, 0.0));
}
