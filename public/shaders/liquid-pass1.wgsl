// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid – Pass 1: Capillary Wave Physics
//  Category: image
//  Features: multi-pass-1, surface tension, gravity waves, ripple propagation, audio-reactive, mouse-driven
//  Upgraded: 2026-11-22
//  Ideas: Faraday parametric forcing from bass; dispersive capillary precursor ahead of the click train
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
  if (distToSurface < boundaryWidth && depth > 0.5) {
    let t = distToSurface / boundaryWidth;
    return 0.05 * surfaceTension * exp(-t * 8.0);
  }
  return 0.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let pc = vec2<i32>(global_id.xy);
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let currentTime = u.config.x;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let backgroundFactor = 1.0 - smoothstep(0.0, 0.1, depth);

  let surfaceTension = u.zoom_params.x * 0.5 + 0.1;
  let gravityScale = u.zoom_params.y * 2.0 + 0.5;
  let damping = u.zoom_params.z * 0.15 + 0.02;
  let density = 1.0;
  let dt = 0.016;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);

  // One 13-tap neighbourhood feeds the Laplacian, the biharmonic and the crest lean.
  let persistentData = loadC(pc, hi);
  let h_curr = persistentData.g;
  let velocity = persistentData.b;
  let age = persistentData.a;
  let hL = loadC(pc + vec2<i32>(-1, 0), hi).g;
  let hR = loadC(pc + vec2<i32>(1, 0), hi).g;
  let hB = loadC(pc + vec2<i32>(0, -1), hi).g;
  let hT = loadC(pc + vec2<i32>(0, 1), hi).g;
  let hBL = loadC(pc + vec2<i32>(-1, -1), hi).g;
  let hBR = loadC(pc + vec2<i32>(1, -1), hi).g;
  let hTL = loadC(pc + vec2<i32>(-1, 1), hi).g;
  let hTR = loadC(pc + vec2<i32>(1, 1), hi).g;
  let hL2 = loadC(pc + vec2<i32>(-2, 0), hi).g;
  let hR2 = loadC(pc + vec2<i32>(2, 0), hi).g;
  let hB2 = loadC(pc + vec2<i32>(0, -2), hi).g;
  let hT2 = loadC(pc + vec2<i32>(0, 2), hi).g;
  let lapH = hL + hR + hB + hT - 4.0 * h_curr;
  let biLapH = 20.0 * h_curr - 8.0 * (hL + hR + hB + hT) + 2.0 * (hBL + hBR + hTL + hTR) + (hL2 + hR2 + hB2 + hT2);

  // Rescue: a wave equation restores (+c² ∇²h) and surface tension stiffens (−σ ∇⁴h).
  // HEAD had both signs reversed, so every mode grew until the ±0.5 clamp. The constants
  // keep ω·dt < 1.2 at the largest slider values (explicit symplectic step is stable below 2).
  let c2 = gravityScale * 150.0;
  let tensionK = surfaceTension * 40.0;

  // ── Idea 1: Faraday parametric forcing ──────────────────────────────
  // Bass shakes the basin vertically, which modulates the restoring term. The drive sits at
  // twice the natural frequency of the capillary wavelength (dispersion ω² = c²k² + σk⁴),
  // so standing Faraday waves of that wavelength grow while the bass holds.
  let kF = 6.28318530718 / (0.045 * resolution.y);
  let wF = sqrt(c2 * kF * kF + tensionK * kF * kF * kF * kF);
  let drive = 1.0 + 0.6 * bass * cos(2.0 * wF * currentTime);

  var newHeight = h_curr;
  var newVelocity = velocity;

  if (backgroundFactor > 0.01) {
    let acceleration = c2 * drive * lapH - tensionK * biLapH - damping * velocity;
    newVelocity = velocity + acceleration * dt;
    newHeight = h_curr + newVelocity * dt;
    newHeight += meniscusEffect(uv, depth, surfaceTension) * 0.1;
    newHeight = clamp(newHeight, -0.5, 0.5);
    newVelocity = clamp(newVelocity, -1.0, 1.0);
  }

  var sourceHeight = 0.0;
  var sourceVelocity = 0.0;

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rippleData = u.ripples[i];
    let timeSinceClick = currentTime - rippleData.z;
    if (timeSinceClick > 0.0 && timeSinceClick < 3.0) {
      let directionVec = uv - rippleData.xy;
      let dist = length(directionVec);
      if (dist > 0.0001) {
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
        let attenuation = 1.0 - smoothstep(0.0, 1.0, timeSinceClick / 2.5);
        let capillaryAmp = 0.5 * 0.02 * mix(0.3, 1.0, rippleOriginDepth);
        sourceHeight += sin(phase) * envelope * attenuation * capillaryAmp;
        sourceVelocity += cos(phase) * envelope * attenuation * capillaryAmp * capillarySpeed;

        // ── Idea 2: dispersive precursor ────────────────────────────
        // Short capillary waves carry a higher group velocity than the long train above, so a
        // second packet at 2.4× the wavenumber detaches and runs ahead as a travelling shell.
        let k2 = waveNumber * 2.4;
        let speed2 = capillaryWaveSpeed(
          wavelengthBase * (0.5 + rippleOriginDepth * 0.5) / 2.4,
          surfaceTension, gravityScale, density
        );
        let groupFront = timeSinceClick * speed2 * 0.094;
        let shellWidth = 0.03 + timeSinceClick * 0.02;
        let shell = exp(-pow((dist - groupFront) / shellWidth, 2.0));
        let phase2 = dist * k2 - timeSinceClick * speed2 * 3.0;
        sourceHeight += sin(phase2) * shell * attenuation * capillaryAmp * 0.55;
        sourceVelocity += cos(phase2) * shell * attenuation * capillaryAmp * 0.55 * speed2;
      }
    }
  }

  var ambientHeight = 0.0;
  if (backgroundFactor > 0.0) {
    let t = currentTime * 0.5;
    let ambientFreq = 25.0;
    let wave1 = sin(uv.x * ambientFreq + t * 2.0);
    let wave2 = sin(uv.y * ambientFreq * 1.3 + t * 1.7);
    let wave3 = sin((uv.x + uv.y) * ambientFreq * 0.7 + t * 2.3);
    let wave4 = sin(length(uv - vec2<f32>(0.5)) * ambientFreq * 1.5 - t * 3.0);
    ambientHeight = (wave1 + wave2 * 0.5 + wave3 * 0.3 + wave4 * 0.2) * 0.003;
    ambientHeight *= surfaceTension * backgroundFactor;
  }

  newHeight += sourceHeight + ambientHeight;
  newVelocity += sourceVelocity;

  // Crest lean: the front face steepens along the height slope (taps reused from the stencil).
  let slopeX = hR - hL;
  let slopeY = hT - hB;
  newHeight = clamp(newHeight - (slopeX + slopeY) * newVelocity * 0.12, -0.5, 0.5);

  // Capillary fringe. Color Shift (zoom_params.w) sets a short wave that outruns the swell.
  let colorShift = clamp(u.zoom_params.w, 0.0, 1.0);
  let fringePhase = currentTime * (3.5 + colorShift * 7.0);
  let fringe = sin(uv.x * 70.0 + fringePhase) * sin(uv.y * 58.0 - fringePhase * 0.8);
  newHeight = clamp(newHeight + fringe * 0.004 * colorShift * surfaceTension, -0.5, 0.5);

  let newAge = age + dt;
  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  textureStore(writeTexture, global_id.xy, inputColor);
  textureStore(dataTextureA, global_id.xy, vec4<f32>(h_curr, newHeight, newVelocity, newAge));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
