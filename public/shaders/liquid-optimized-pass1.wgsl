// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Optimized – Pass 1: Physics Simulation
//  Category: liquid-effects
//  Features: multi-pass-1, capillary waves, Laplace pressure, ripple propagation, audio-reactive, mouse-driven
//  Upgraded: 2026-11-22
//  Ideas: bass-forced basin slosh (first seiche mode); scale-selective viscous damping ν∇²v
//  Rescue: restoring terms had the wrong sign (HEAD grew every mode to the clamp); exact C loads
//  A packing: raw (h_prev, h_curr, velocity, age)
//  Outputs: dataTextureA (h_prev, h_curr, velocity, age)
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// Exact, clamped read of the previous frame's state (never a filtering sampler).
fn loadC(p: vec2<i32>, hi: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), hi), 0);
}

fn capillaryWaveSpeed(wavelength: f32, surfaceTension: f32, gravity: f32, density: f32) -> f32 {
  let k = 6.28318530718 / wavelength;
  let tensionTerm = (surfaceTension * k) / density;
  let gravityTerm = gravity / k;
  return sqrt(tensionTerm + gravityTerm);
}

fn meniscusEffect(uv: vec2<f32>, depth: f32, surfaceTension: f32) -> f32 {
  let boundaryWidth = 0.02;
  let distToSurface = 1.0 - depth;
  let inMeniscusRegion = f32(distToSurface < boundaryWidth && depth > 0.5);
  let t = distToSurface / boundaryWidth;
  let meniscusHeight = 0.05 * surfaceTension * exp(-t * 8.0);
  return meniscusHeight * inMeniscusRegion;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let pc = vec2<i32>(global_id.xy);
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let currentTime = u.config.x;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let backgroundFactor = 1.0 - smoothstep(0.0, 0.1, depth);

  let surfaceTension = u.zoom_params.x * 0.5 + 0.1;
  let gravityScale = u.zoom_params.y * 2.0 + 0.5;
  // Turbidity (default 0) adds drag so the slider is live on this pass.
  let turbidity = u.zoom_params.w;
  let damping = (u.zoom_params.z * 0.15 + 0.02) * (1.0 + turbidity * 0.85);
  let density = 1.0;
  let dt = 0.016;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);

  // One 13-tap neighbourhood feeds the Laplacian and the biharmonic; the four velocity
  // neighbours feed the viscous term.
  let persistentData = loadC(pc, hi);
  let h_curr = persistentData.g;
  let velocity = persistentData.b;
  let age = persistentData.a;
  let sL = loadC(pc + vec2<i32>(-1, 0), hi);
  let sR = loadC(pc + vec2<i32>(1, 0), hi);
  let sB = loadC(pc + vec2<i32>(0, -1), hi);
  let sT = loadC(pc + vec2<i32>(0, 1), hi);
  let hBL = loadC(pc + vec2<i32>(-1, -1), hi).g;
  let hBR = loadC(pc + vec2<i32>(1, -1), hi).g;
  let hTL = loadC(pc + vec2<i32>(-1, 1), hi).g;
  let hTR = loadC(pc + vec2<i32>(1, 1), hi).g;
  let hL2 = loadC(pc + vec2<i32>(-2, 0), hi).g;
  let hR2 = loadC(pc + vec2<i32>(2, 0), hi).g;
  let hB2 = loadC(pc + vec2<i32>(0, -2), hi).g;
  let hT2 = loadC(pc + vec2<i32>(0, 2), hi).g;
  let hSum4 = sL.g + sR.g + sB.g + sT.g;
  let lapH = hSum4 - 4.0 * h_curr;
  let biLapH = 20.0 * h_curr - 8.0 * hSum4 + 2.0 * (hBL + hBR + hTL + hTR) + (hL2 + hR2 + hB2 + hT2);

  // Rescue: +c² ∇²h restores, −σ ∇⁴h stiffens. HEAD had both reversed, so every mode grew
  // to the ±0.5 clamp. ω·dt stays below 1.2 at the largest slider values.
  let c2 = gravityScale * 150.0;
  let tensionK = surfaceTension * 40.0;

  // ── Idea 2: scale-selective viscous damping ─────────────────────────
  // Water loses wave energy at a rate ∝ ν k², so grid-scale chop dies long before the broad
  // swell does. Damping sets ν and Turbidity thickens it; this is on top of the drag term.
  let lapV = sL.b + sR.b + sB.b + sT.b - 4.0 * velocity;
  let nu = (0.3 + 2.4 * u.zoom_params.z) * (1.0 + turbidity * 1.5);

  // ── Idea 1: bass-forced slosh ───────────────────────────────────────
  // The basin's first seiche mode is a half-cosine across its length. Bass pushes it (the
  // same basin the seiche beat below breathes), so the whole surface tips and rolls back.
  let slosh = bass * 0.12 * cos(3.14159265 * uv.x) * sin(1.9 * currentTime);

  let activeMask = f32(backgroundFactor > 0.01);
  let acceleration = c2 * lapH - tensionK * biLapH - damping * velocity + nu * lapV + slosh;

  var newVelocity = mix(velocity, velocity + acceleration * dt, activeMask);
  var newHeight = mix(h_curr, h_curr + newVelocity * dt, activeMask);
  newHeight += meniscusEffect(uv, depth, surfaceTension) * 0.1 * activeMask;
  newHeight = mix(newHeight, clamp(newHeight, -0.5, 0.5), activeMask);
  newVelocity = mix(newVelocity, clamp(newVelocity, -1.0, 1.0), activeMask);

  var sourceHeight = 0.0;
  var sourceVelocity = 0.0;

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rippleData = u.ripples[i];
    let timeSinceClick = currentTime - rippleData.z;
    let rippleActive = f32(timeSinceClick > 0.0 && timeSinceClick < 3.0);
    let directionVec = uv - rippleData.xy;
    let dist = length(directionVec);
    let validDist = f32(dist > 0.0001);
    let contribMask = rippleActive * validDist;

    let rippleOriginDepth = 1.0 - textureSampleLevel(
      readDepthTexture, non_filtering_sampler, rippleData.xy, 0.0
    ).r;

    let wavelengthBase = 0.1;
    let capillarySpeed = capillaryWaveSpeed(
      wavelengthBase * (0.5 + rippleOriginDepth * 0.5),
      surfaceTension, gravityScale, density
    );
    let waveNumber = 20.0;
    let phase = dist * waveNumber - timeSinceClick * capillarySpeed * 3.0;
    let packetWidth = 0.3 + timeSinceClick * 0.1;
    let envelope = exp(-(dist * dist) / (packetWidth * packetWidth));
    let attenuation = (1.0 - smoothstep(0.0, 1.0, timeSinceClick / 2.5)) * (1.0 - turbidity * 0.4);
    let capillaryAmp = 0.5 * 0.02 * mix(0.3, 1.0, rippleOriginDepth);

    sourceHeight += sin(phase) * envelope * attenuation * capillaryAmp * contribMask;
    sourceVelocity += cos(phase) * envelope * attenuation * capillaryAmp * capillarySpeed * contribMask;
  }

  let ambientMask = f32(backgroundFactor > 0.0);
  let t = currentTime * 0.5;
  let ambientFreq = 25.0;
  let wave1 = sin(uv.x * ambientFreq + t * 2.0);
  let wave2 = sin(uv.y * ambientFreq * 0.8 + t * 1.7);
  let wave3 = sin((uv.x + uv.y) * ambientFreq * 0.5 + t * 1.3);
  let microRipple = (wave1 + wave2 + wave3) / 3.0;
  let microEnvelope = smoothstep(0.0, 0.3, backgroundFactor);
  // Seiche beat. The basin amplitude breathes instead of a fixed shimmer.
  let seiche = 0.62 + 0.38 * sin(currentTime * 0.31);
  let ambientHeight = microRipple * 0.003 * microEnvelope * surfaceTension * ambientMask * seiche;

  newHeight += sourceHeight + ambientHeight;
  newVelocity += sourceVelocity;
  // Shore set-down. Radiation stress lowers the waterline on the depth contact band.
  let shore = smoothstep(0.0, 0.08, depth) * (1.0 - smoothstep(0.08, 0.22, depth));
  newHeight -= shore * newVelocity * newVelocity * (0.12 + turbidity * 0.05);

  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  textureStore(writeTexture, global_id.xy, inputColor);
  textureStore(dataTextureA, global_id.xy, vec4<f32>(h_curr, newHeight, newVelocity, age + dt));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
