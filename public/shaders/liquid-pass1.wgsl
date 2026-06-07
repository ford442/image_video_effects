// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid – Pass 1: Capillary Wave Physics
//  Category: image
//  Features: multi-pass-1, surface tension, gravity waves, ripple propagation
//  Outputs: dataTextureA (h_prev, h_curr, velocity, age)
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

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

  let newAge = age + dt;
  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  textureStore(writeTexture, global_id.xy, inputColor);
  textureStore(dataTextureA, global_id.xy, vec4<f32>(h_curr, newHeight, newVelocity, newAge));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
