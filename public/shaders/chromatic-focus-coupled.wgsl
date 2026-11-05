// ═══════════════════════════════════════════════════════════════════
//  chromatic-focus-coupled — Fluid-Coupled Chromatic DOF
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            fluid-simulation, chromatic-aberration, semantic-alpha, ACES
//  Complexity: High
//  Upgraded: 2026-11-01
//  Ideas: vorticity confinement from the true curl of C.xy (12.2D); meniscus lens at the dye edge (density-gradient rim + refraction)
//  A packing: RAW sim state in A = (vel.x, vel.y, vel.x - vel.y, density); C read as fields; ACES only on writeTexture
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Strength, y=Blur, z=FocusRad, w=Viscosity

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Idea 1 helpers: velocity from the exact C history (xy), clamped to the texture.
fn velAt(c: vec2<i32>, hi: vec2<i32>) -> vec2<f32> {
  return textureLoad(dataTextureC, clamp(c, vec2<i32>(0), hi), 0).xy;
}

// True curl: d(vy)/dx - d(vx)/dy by central differences (y grows downward).
fn curlAt(c: vec2<i32>, hi: vec2<i32>) -> f32 {
  let r = velAt(c + vec2<i32>(1, 0), hi).y;
  let l = velAt(c + vec2<i32>(-1, 0), hi).y;
  let t = velAt(c + vec2<i32>(0, -1), hi).x;
  let b = velAt(c + vec2<i32>(0, 1), hi).x;
  return 0.5 * ((r - l) - (b - t));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
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
  let mouseDown = u.zoom_config.w > 0.5;
  let held = select(0.0, 1.0, mouseDown);

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
  let strength = u.zoom_params.x * 0.06 * (1.0 + bass * 0.3);
  let blurAmt = u.zoom_params.y;
  let focusRad = u.zoom_params.z;
  let viscosity = mix(0.92, 0.99, u.zoom_params.w);

  // Exact fluid simulation state loaded from dataTextureC
  let prevFluid = textureLoad(dataTextureC, coord, 0);
  let prevVel = prevFluid.xy;
  let prevDens = prevFluid.a;

  let backCoord = clamp(coord - vec2<i32>(prevVel * 3.0), vec2<i32>(0), vec2<i32>(i32(resolution.x) - 1, i32(resolution.y) - 1));
  let advected = textureLoad(dataTextureC, backCoord, 0);
  var vel = advected.xy * viscosity;
  var dens = advected.a * viscosity;

  let toMouse = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(toMouse);
  let mouseRadius = mix(0.04, 0.18, u.zoom_params.w);
  let influence = smoothstep(mouseRadius, 0.0, dist) * (0.6 + held * 0.4);

  let mouseVel = (rawMouse - mouse) * 40.0;
  vel += mouseVel * influence * 0.5;

  let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
  vel += vortexDir * influence * 1.5;

  // Click ripple bursts
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed >= 0.0 && elapsed < 2.0) {
      let rToMouse = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      let rDist = length(rToMouse);
      let rInfluence = smoothstep(0.2, 0.0, rDist) * exp(-elapsed * 1.5);
      let outward = select(vec2<f32>(0.0), normalize(rToMouse / vec2<f32>(aspect, 1.0)), rDist > 0.001);
      vel += outward * rInfluence * 0.35;
      dens += rInfluence * 0.5;
    }
  }

  // ── Idea 1: vorticity confinement (12.2D) ─────────────────────────────
  // Viscosity damps the small swirls the grid solver makes. Confinement re-injects them:
  // N = grad|w| / |grad|w||, force = eps * (N.y, -N.x) * w. eps = 2*(1 - viscosity) scales
  // with exactly the energy viscosity removes, and clamp(dens) keeps it inside the dye, so
  // an idle frame stays still. Curl comes from C (last frame), like the advection.
  let hiC = vec2<i32>(resolution) - vec2<i32>(1);
  let curlHere = curlAt(coord, hiC);
  let curlGx = 0.5 * (abs(curlAt(coord + vec2<i32>(1, 0), hiC)) - abs(curlAt(coord - vec2<i32>(1, 0), hiC)));
  let curlGy = 0.5 * (abs(curlAt(coord + vec2<i32>(0, 1), hiC)) - abs(curlAt(coord - vec2<i32>(0, 1), hiC)));
  let curlN = vec2<f32>(curlGx, curlGy) / max(length(vec2<f32>(curlGx, curlGy)), 1e-5);
  let confineEps = 2.0 * (1.0 - viscosity) * clamp(dens, 0.0, 1.0);
  vel += vec2<f32>(curlN.y, -curlN.x) * curlHere * confineEps;

  let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  vel = vel * smoothstep(0.02, 0.08, edgeDist);
  vel = clamp(vel, vec2<f32>(-0.5), vec2<f32>(0.5));
  dens = clamp(dens, 0.0, 2.0);

  // Pseudo-vorticity kept as HEAD had it: it feeds `twist` and A.z (nothing reads C.z).
  let vorticity = vel.x - vel.y;
  textureStore(dataTextureA, coord, vec4<f32>(vel, vorticity, dens));

  // Chromatic focus calculation
  let center = mouse + vel * 0.02;
  let distVec = (uv - center) * vec2<f32>(aspect, 1.0);
  let focusDist = length(distVec);

  let fluidBlur = dens * blurAmt * 0.5;
  var amount = smoothstep(focusRad, focusRad + 0.5, focusDist);
  amount = pow(amount, 1.0 / (1.0 + fluidBlur * 5.0)) + fluidBlur;

  var dir = normalize(distVec + vec2<f32>(1e-5));
  let twist = vorticity * 0.5 + mids * 0.3;
  let cosT = cos(twist);
  let sinT = sin(twist);
  dir = vec2<f32>(dir.x * cosT - dir.y * sinT, dir.x * sinT + dir.y * cosT);

  // ── Idea 2: meniscus lens ─────────────────────────────────────────────
  // The dye boundary is where density changes: grad(dens) from the same C neighbours.
  // It refracts the three channel taps a little along the gradient, and the lit side of
  // the edge (light from the upper left) catches a thin highlight.
  let denGrad = 0.5 * vec2<f32>(
    textureLoad(dataTextureC, clamp(coord + vec2<i32>(1, 0), vec2<i32>(0), hiC), 0).a - textureLoad(dataTextureC, clamp(coord - vec2<i32>(1, 0), vec2<i32>(0), hiC), 0).a,
    textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, 1), vec2<i32>(0), hiC), 0).a - textureLoad(dataTextureC, clamp(coord - vec2<i32>(0, 1), vec2<i32>(0), hiC), 0).a
  );
  let denGradLen = length(denGrad);
  let meniscusRefract = denGrad * 0.04;
  let meniscusLit = max(dot(-denGrad / max(denGradLen, 1e-5), normalize(vec2<f32>(-0.6, -0.8))), 0.0);
  let meniscusRim = smoothstep(0.01, 0.12, denGradLen) * meniscusLit * meniscusLit;

  let rOffset = dir * amount * strength * (1.0 + dens * 0.3);
  let bOffset = -dir * amount * strength * (1.0 + dens * 0.3);
  let blurVec = vel * dens * 0.01;

  let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + rOffset + blurVec + meniscusRefract, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, clamp(uv + blurVec * 0.5 + meniscusRefract, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(uv + bOffset - blurVec + meniscusRefract, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).b;

  var color = vec3<f32>(r, g, b);
  let vig = 1.0 - amount * 0.3;
  color *= vig;

  if (held > 0.5) {
    let ring = abs(focusDist - focusRad);
    if (ring < 0.006) {
      color += vec3<f32>(0.5, 0.6, 0.8);
    }
  }

  let fluidTint = mix(vec3<f32>(1.0), vec3<f32>(1.0, 0.85, 0.6), dens * blurAmt);
  color *= fluidTint;

  let specNoise = hash12(uv * 300.0 + time * 2.0);
  let specular = pow(specNoise, 20.0) * influence * dens * 3.0;
  color += vec3<f32>(0.9, 0.95, 1.0) * specular;
  color += vec3<f32>(0.9, 0.95, 1.0) * meniscusRim * 0.35;

  let blurThickness = amount * 5.0 + blurAmt * 2.0;
  let alphaR = exp(-blurThickness * 0.5625);
  let alphaG = exp(-blurThickness * 0.7375);
  let alphaB = exp(-blurThickness * 0.9125);
  let finalAlpha = clamp(dot(vec3<f32>(alphaR, alphaG, alphaB), vec3<f32>(0.299, 0.587, 0.114)) + held * 0.1, 0.1, 1.0);

  let finalRGB = aces(color);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let finalPixel = vec4<f32>(finalRGB, finalAlpha);

  textureStore(writeTexture, coord, finalPixel);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
