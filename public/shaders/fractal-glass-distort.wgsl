// ═══════════════════════════════════════════════════════════════════
//  IFS Attractor Glass — Iterated Function System + Chromatic Glass
//  Category: distortion
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba,
//            fractal-attractor, chromatic-aberration, semantic-alpha, ACES
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: 1) stained-glass cells (base-4 map address → per-cell tint, pane tilt, lead lines) 2) thick glass (Beer-Lambert absorption + Fresnel rim) 3) wavelength IFS (R/G/B gradients at shifted contraction = true dispersion)
//  A packing: ACES display RGBA (alpha = glass coverage); C feedback mixed post-ACES
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Contraction, y=Rotation, z=Refraction, w=Aberration

const FD_STEP: f32 = 0.008;

fn ifsAffine(p: vec2<f32>, angle: f32, scale: f32, tx: f32, ty: f32) -> vec2<f32> {
  let c = cos(angle);
  let s = sin(angle);
  return vec2<f32>(scale * (c * p.x - s * p.y) + tx, scale * (s * p.x + c * p.y) + ty);
}

// Returns (density, address). Idea 1: address = base-4 index of the winning maps at the
// first three levels (0..63), i.e. which stained-glass pane of the attractor this pixel is in.
fn ifsAttractorDensity(p: vec2<f32>, contraction: f32, rotation: f32) -> vec2<f32> {
  let s  = contraction * 0.55;
  let s2 = contraction * 0.45;
  let r1 = rotation;
  let r2 = rotation + 2.094395;
  let r3 = rotation - 2.094395;

  var q = p;
  var density = 0.0;
  var address = 0.0;
  for (var i = 0; i < 8; i = i + 1) {
    let q1 = ifsAffine(q, r1, 1.0 / s,  0.0, 0.5);
    let q2 = ifsAffine(q, r2, 1.0 / s2, 0.5, -0.4);
    let q3 = ifsAffine(q, r3, 1.0 / s2,-0.5, -0.4);
    let q4 = (q - vec2<f32>(0.0, -0.3)) * (1.0 / (s * 0.3));

    let d1 = length(q1);
    let d2 = length(q2);
    let d3 = length(q3);
    let d4 = length(q4);

    var k = 3.0;
    if (d1 <= d2 && d1 <= d3 && d1 <= d4) { q = q1; k = 0.0; }
    else if (d2 <= d3 && d2 <= d4)        { q = q2; k = 1.0; }
    else if (d3 <= d4)                     { q = q3; k = 2.0; }
    else                                   { q = q4; }

    if (i < 3) { address = address * 4.0 + k; }
    density += exp(-length(q) * 3.0);
  }
  return vec2<f32>(clamp(density / 8.0, 0.0, 1.0), address);
}

// Density gradient per unit of p (finite difference divided by its step).
fn densityGrad(p: vec2<f32>, d0: f32, contraction: f32, rotation: f32) -> vec2<f32> {
  let dx = ifsAttractorDensity(p + vec2<f32>(FD_STEP, 0.0), contraction, rotation).x;
  let dy = ifsAttractorDensity(p + vec2<f32>(0.0, FD_STEP), contraction, rotation).x;
  return vec2<f32>(dx - d0, dy - d0) / FD_STEP;
}

// Soft cap so the true gradient (spiky at attractor edges) never tears the frame apart.
fn softCap(v: vec2<f32>, cap: f32) -> vec2<f32> {
  return v / (1.0 + length(v) / cap);
}

fn hash11(n: f32) -> f32 {
  return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

// Idea 1: stained-glass pane colours (ruby, cobalt, amber, emerald, violet, clear).
fn paneTint(address: f32) -> vec3<f32> {
  let h = hash11(address);
  let idx = u32(h * 6.0) % 6u;
  var tint = vec3<f32>(0.92, 0.94, 0.96);
  if (idx == 0u) { tint = vec3<f32>(0.95, 0.35, 0.35); }
  else if (idx == 1u) { tint = vec3<f32>(0.35, 0.5, 0.95); }
  else if (idx == 2u) { tint = vec3<f32>(0.98, 0.75, 0.35); }
  else if (idx == 3u) { tint = vec3<f32>(0.4, 0.85, 0.5); }
  else if (idx == 4u) { tint = vec3<f32>(0.7, 0.45, 0.9); }
  return tint;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  let c = max(x, vec3<f32>(0.0));
  return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
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

  // Exact parameter contracts
  let mousePinch = exp(-dot((uv - mouse) * vec2<f32>(aspect, 1.0), (uv - mouse) * vec2<f32>(aspect, 1.0)) * 12.0) * held;
  let contraction = mix(0.4, 0.75, u.zoom_params.x) * mix(1.0, 0.82, mousePinch * 0.5);
  let rotation = u.zoom_params.y * 6.2831853 + time * 0.2;
  let refrStr = mix(0.01, 0.12, u.zoom_params.z) * (1.0 + bass * 0.4);
  let aberration = mix(0.005, 0.06, u.zoom_params.w) * (1.0 + treble * 0.5);

  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 1.5;

  let dG = ifsAttractorDensity(p, contraction, rotation);
  let d0 = dG.x;
  let address = dG.y;
  let dGx = ifsAttractorDensity(p + vec2<f32>(FD_STEP, 0.0), contraction, rotation);
  let dGy = ifsAttractorDensity(p + vec2<f32>(0.0, FD_STEP), contraction, rotation);
  let gradG = vec2<f32>(dGx.x - d0, dGy.x - d0) / FD_STEP;

  // Idea 3: wavelength IFS — red and blue see a slightly different contraction, so each
  // channel refracts off its own attractor gradient (true dispersion, not a scaled copy).
  let spread = aberration * 0.5;
  let conR = contraction * (1.0 - spread);
  let conB = contraction * (1.0 + spread);
  let gradR = densityGrad(p, ifsAttractorDensity(p, conR, rotation).x, conR, rotation);
  let gradB = densityGrad(p, ifsAttractorDensity(p, conB, rotation).x, conB, rotation);

  // Refraction: true gradient (÷ step) rescaled ×0.2 so the default sits at ~0.02 UV on
  // attractor edges (HEAD's un-normalised difference was ~0.001 UV, i.e. invisible).
  let refrScale = refrStr * 0.2;
  let grad = gradG * refrScale;

  let branchRunner = pow(max(0.0, sin(atan2(grad.y, grad.x) * 6.0 - time * (14.0 + mids * 6.0))), 12.0);
  let attractorRunner = pow(max(0.0, sin(d0 * 24.0 - time * (18.0 + bass * 8.0))), 14.0);

  var clickRing = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.0) {
      let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      clickRing += smoothstep(0.02, 0.0, abs(length(delta) - age * 0.45)) * exp(-age * 1.6);
    }
  }

  let boost = 1.0 + branchRunner * 0.25 + clickRing * 0.3;

  // Idea 1: each pane is a slightly tilted sheet — a constant per-cell offset.
  let paneTilt = (vec2<f32>(hash11(address + 7.0), hash11(address + 19.0)) - 0.5) * 0.006 * u.zoom_params.z;

  // Idea 3: blue bends a little more than red (Cauchy-style), on top of its own gradient.
  let toUV = vec2<f32>(1.0 / aspect, 1.0) / 1.5;
  let offR = softCap(gradR * refrScale * boost * (1.0 - aberration * 6.0), 0.08) * toUV + paneTilt;
  let offG = softCap(grad * boost, 0.08) * toUV + paneTilt;
  let offB = softCap(gradB * refrScale * boost * (1.0 + aberration * 6.0), 0.08) * toUV + paneTilt;

  let uvR = clamp(uv + offR, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvG = clamp(uv + offG, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvB = clamp(uv + offB, vec2<f32>(0.0), vec2<f32>(1.0));

  let sR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0);
  let sG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0);
  let sB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0);
  var color = vec3<f32>(sR.r, sG.g, sB.b);

  // Idea 1: pane tint + lead came where the base-4 address changes between neighbours.
  let tint = paneTint(address);
  color = color * mix(vec3<f32>(1.0), tint, 0.18);
  let lead = select(0.0, 1.0, dGx.y != address || dGy.y != address);

  // Idea 2: thick glass — Beer-Lambert absorption through the attractor body, coloured by
  // the pane (light of the tint colour passes), plus a Fresnel rim from the gradient normal.
  let thickness = d0 * 4.0;
  let absorb = exp(-thickness * (vec3<f32>(1.0) - tint));
  color = color * absorb;
  let nrm = normalize(vec3<f32>(-gradG * 0.3, 1.0));
  let oneMinusCos = clamp(1.0 - nrm.z, 0.0, 1.0);
  let om2 = oneMinusCos * oneMinusCos;
  let fresnel = 0.96 * om2 * om2 * oneMinusCos;   // Schlick term above the F0 = 0.04 base
  color += vec3<f32>(0.92, 0.96, 1.0) * fresnel * 0.8;

  let glow = d0 * d0 * 0.6 * (1.0 + attractorRunner * 0.35);
  let angle = atan2(grad.y, grad.x) / 6.2831853 + 0.5 + treble * 0.15;
  let iridR = 0.5 + 0.5 * sin(angle * 6.2831853 + 0.0);
  let iridG = 0.5 + 0.5 * sin(angle * 6.2831853 + 2.094395);
  let iridB = 0.5 + 0.5 * sin(angle * 6.2831853 + 4.18879);
  color = mix(color, vec3<f32>(iridR, iridG, iridB), glow * 0.4);

  color += vec3<f32>(0.9, 0.95, 1.0) * smoothstep(0.7, 1.0, d0) * 0.5;
  color += vec3<f32>(0.4, 0.6, 1.0) * clickRing * 0.25;

  // Idea 1: lead line — dark came with a faint metallic sheen.
  color = mix(color, vec3<f32>(0.08, 0.08, 0.09) + fresnel * 0.2, lead * 0.6);

  // ACES on display RGB; C holds last frame's ACES display, so persistence mixes post-ACES.
  let prevC = textureLoad(dataTextureC, coord, 0).rgb;
  let finalRGB = mix(aces(color), prevC, 0.08);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let luminance = dot(finalRGB, vec3<f32>(0.299, 0.587, 0.114));
  // Semantic alpha: glass coverage (body density, bend, rim, lead) over the image.
  let alpha = clamp(d0 * 0.5 + length(offG) * 5.0 + glow * 0.5 + fresnel * 0.4 + lead * 0.3
                    + luminance * 0.2 + mousePinch * 0.2, 0.2, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, coord, finalPixel);
  textureStore(dataTextureA, coord, finalPixel);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
