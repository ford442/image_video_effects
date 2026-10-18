// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid – Pass 1: Capillary Wave Physics
//  Category: image
//  Features: multi-pass-1, surface tension, gravity waves, ripple propagation
//  Upgraded: 2026-10-17
//  Ideas: crest lean down the height slope; capillary fringe from Color Shift
//  A packing: raw (h_prev, h_curr, velocity, age)
//  Outputs: dataTextureA (h_prev, h_curr, velocity, age)
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn sampleHeight(uv: vec2<f32>) -> f32 {
  return textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).g;
}

fn sampleHeightClamped(uv: vec2<f32>, pixelSize: vec2<f32>) -> f32 {
  let clampedUV = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0));
  return sampleHeight(clampedUV);
}

fn laplacian(uv: vec2<f32>, pixelSize: vec2<f32>) -> f32 {
  let center = sampleHeightClamped(uv, pixelSize);
  let left   = sampleHeightClamped(uv - vec2<f32>(pixelSize.x, 0.0), pixelSize);
  let right  = sampleHeightClamped(uv + vec2<f32>(pixelSize.x, 0.0), pixelSize);
  let bottom = sampleHeightClamped(uv - vec2<f32>(0.0, pixelSize.y), pixelSize);
  let top    = sampleHeightClamped(uv + vec2<f32>(0.0, pixelSize.y), pixelSize);
  return (left + right + bottom + top - 4.0 * center);
}

fn biharmonic(uv: vec2<f32>, pixelSize: vec2<f32>) -> f32 {
  let centerLap = laplacian(uv, pixelSize);
  let leftLap   = laplacian(uv - vec2<f32>(pixelSize.x, 0.0), pixelSize);
  let rightLap  = laplacian(uv + vec2<f32>(pixelSize.x, 0.0), pixelSize);
  let bottomLap = laplacian(uv - vec2<f32>(0.0, pixelSize.y), pixelSize);
  let topLap    = laplacian(uv + vec2<f32>(0.0, pixelSize.y), pixelSize);
  return (leftLap + rightLap + bottomLap + topLap - 4.0 * centerLap);
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
  let uv = vec2<f32>(global_id.xy) / resolution;
  let currentTime = u.config.x;
  let pixelSize = vec2<f32>(1.0) / resolution;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let backgroundFactor = 1.0 - smoothstep(0.0, 0.1, depth);

  let surfaceTension = u.zoom_params.x * 0.5 + 0.1;
  let gravityScale = u.zoom_params.y * 2.0 + 0.5;
  let damping = u.zoom_params.z * 0.15 + 0.02;
  let density = 1.0;
  let dt = 0.016;

  let persistentData = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  let h_prev = persistentData.r;
  let h_curr = persistentData.g;
  let velocity = persistentData.b;
  let age = persistentData.a;

  var newHeight = h_curr;
  var newVelocity = velocity;

  if (backgroundFactor > 0.01) {
    let lapH = laplacian(uv, pixelSize);
    let biLapH = biharmonic(uv, pixelSize);
    let capillaryAcceleration = (surfaceTension / density) * biLapH * 0.001;
    let gravityAcceleration = -gravityScale * lapH * 0.1;
    let acceleration = capillaryAcceleration + gravityAcceleration - damping * velocity;
    newVelocity = velocity + acceleration * dt;
    newHeight = h_curr + newVelocity * dt;
    newHeight += meniscusEffect(uv, depth, surfaceTension) * 0.1;
    newHeight = clamp(newHeight, -0.5, 0.5);
    newVelocity = clamp(newVelocity, -1.0, 1.0);
  }

  var sourceHeight = 0.0;
  var sourceVelocity = 0.0;

  let rippleCount = u32(u.config.y);
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

  // Idea 1 — crest lean: the front face steepens along the height slope.
  let hL = sampleHeightClamped(uv - vec2<f32>(pixelSize.x, 0.0), pixelSize);
  let hR = sampleHeightClamped(uv + vec2<f32>(pixelSize.x, 0.0), pixelSize);
  let hB = sampleHeightClamped(uv - vec2<f32>(0.0, pixelSize.y), pixelSize);
  let hT = sampleHeightClamped(uv + vec2<f32>(0.0, pixelSize.y), pixelSize);
  let slopeX = hR - hL;
  let slopeY = hT - hB;
  newHeight = clamp(newHeight - (slopeX + slopeY) * newVelocity * 0.12, -0.5, 0.5);

  // Idea 2 — capillary fringe. Color Shift (zoom_params.w) was unread here;
  // it sets a short wave that outruns the ambient swell.
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
