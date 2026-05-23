// ═══════════════════════════════════════════════════════════════════
//  Liquid (Interactive)
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Created: 2025-11-25
//  Upgraded: 2026-05-23
// ═══════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn sampleHeight(uv: vec2<f32>) -> f32 {
  return textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
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

fn calculateNormal(uv: vec2<f32>, pixelSize: vec2<f32>, heightScale: f32) -> vec3<f32> {
  let left   = sampleHeightClamped(uv - vec2<f32>(pixelSize.x, 0.0), pixelSize);
  let right  = sampleHeightClamped(uv + vec2<f32>(pixelSize.x, 0.0), pixelSize);
  let bottom = sampleHeightClamped(uv - vec2<f32>(0.0, pixelSize.y), pixelSize);
  let top    = sampleHeightClamped(uv + vec2<f32>(0.0, pixelSize.y), pixelSize);
  let dx = (right - left) * heightScale;
  let dy = (top - bottom) * heightScale;
  return normalize(vec3<f32>(-dx, -dy, 2.0));
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

fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

fn calculateFluidAlpha(
    baseColor: vec3<f32>,
    liquidThickness: f32,
    viewDotNormal: f32,
    turbidity: f32,
    isBackground: f32
) -> f32 {
  let F0 = 0.02;
  let fresnel = schlickFresnel(max(0.0, viewDotNormal), F0);
  let effectiveDepth = liquidThickness * (1.0 + turbidity * 2.0);
  let absorption = exp(-effectiveDepth * 2.0);
  let baseAlpha = mix(0.3, 0.95, absorption * isBackground);
  let alpha = baseAlpha * (1.0 - fresnel * 0.5);
  return clamp(alpha, 0.0, 1.0);
}

fn calculateLiquidColor(
    baseColor: vec3<f32>,
    liquidThickness: f32,
    turbidity: f32,
    height: f32
) -> vec3<f32> {
  let absorptionR = exp(-liquidThickness * (1.0 + turbidity));
  let absorptionG = exp(-liquidThickness * (0.8 + turbidity * 0.9));
  let absorptionB = exp(-liquidThickness * (0.6 + turbidity * 0.8));
  let heightTint = vec3<f32>(0.0, 0.1, 0.15) * height * 0.5;
  return vec3<f32>(
      baseColor.r * absorptionR,
      baseColor.g * absorptionG + heightTint.g,
      baseColor.b * absorptionB + heightTint.b
  );
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let currentTime = u.config.x;
  let pixelSize = vec2<f32>(1.0) / resolution;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let backgroundFactor = 1.0 - smoothstep(0.0, 0.1, depth);

  let surfaceTension = u.zoom_params.x * 0.5 + 0.1;
  let gravityScale = (u.zoom_params.y * 2.0 + 0.5) * (1.0 + bass * 0.4);
  let damping = u.zoom_params.z * 0.15 + 0.02;
  let turbidity = u.zoom_params.w;

  let density = 1.0;
  let dt = 0.016;

  let persistentData = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  let h_prev = persistentData.r;
  let h_curr = persistentData.g;
  let velocity = persistentData.b;
  let age = persistentData.a;

  let activeMask = f32(backgroundFactor > 0.01);

  let lapH = laplacian(uv, pixelSize);
  let biLapH = biharmonic(uv, pixelSize);

  let capillaryAcceleration = (surfaceTension / density) * biLapH * 0.001;
  let gravityAcceleration = -gravityScale * lapH * 0.1;
  let acceleration = capillaryAcceleration + gravityAcceleration - damping * velocity;

  var newVelocity = mix(velocity, velocity + acceleration * dt, activeMask);
  var newHeight = mix(h_curr, h_curr + newVelocity * dt, activeMask);

  newHeight += meniscusEffect(uv, depth, surfaceTension) * 0.1 * activeMask;
  newHeight = mix(newHeight, clamp(newHeight, -0.5, 0.5), activeMask);
  newVelocity = mix(newVelocity, clamp(newVelocity, -1.0, 1.0), activeMask);

  var sourceHeight = 0.0;
  var sourceVelocity = 0.0;

  let rippleCount = u32(u.config.y);
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
      surfaceTension,
      gravityScale,
      density
    );

    let waveNumber = 20.0;
    let phase = dist * waveNumber - timeSinceClick * capillarySpeed * 3.0;
    let packetWidth = 0.3 + timeSinceClick * 0.1;
    let envelope = exp(-(dist * dist) / (packetWidth * packetWidth));
    let attenuation = 1.0 - smoothstep(0.0, 1.0, timeSinceClick / 2.5);
    let capillaryAmp = 0.5 * 0.02 * mix(0.3, 1.0, rippleOriginDepth);

    let heightContrib = sin(phase) * envelope * attenuation * capillaryAmp;
    let velocityContrib = cos(phase) * envelope * attenuation * capillaryAmp * capillarySpeed;

    sourceHeight += heightContrib * contribMask;
    sourceVelocity += velocityContrib * contribMask;
  }

  let ambientMask = f32(backgroundFactor > 0.0);
  let time = currentTime * 0.5;
  let ambientFreq = 25.0;

  let wave1 = sin(uv.x * ambientFreq + time * 2.0);
  let wave2 = sin(uv.y * ambientFreq * 1.3 + time * 1.7);
  let wave3 = sin((uv.x + uv.y) * ambientFreq * 0.7 + time * 2.3);
  let wave4 = sin(length(uv - vec2<f32>(0.5)) * ambientFreq * 1.5 - time * 3.0);

  let ambientHeight = (wave1 + wave2 * 0.5 + wave3 * 0.3 + wave4 * 0.2) * 0.003 * surfaceTension * ambientMask;

  newHeight += sourceHeight + ambientHeight;
  newVelocity += sourceVelocity;

  let newAge = age + dt;
  let heightOutput = vec4<f32>(h_curr, newHeight, newVelocity, newAge);
  textureStore(dataTextureA, global_id.xy, heightOutput);

  let normal = calculateNormal(uv, pixelSize, 0.5 * surfaceTension);
  let refractionStrength = 0.02 * surfaceTension;
  let refractDisplacement = normal.xy * refractionStrength * backgroundFactor;
  let totalDisplacement = refractDisplacement + vec2<f32>(newHeight * 0.01);
  let colorUV = clamp(uv + totalDisplacement, vec2<f32>(0.0), vec2<f32>(1.0));
  let baseColor = textureSampleLevel(readTexture, u_sampler, colorUV, 0.0).rgb;

  let curvature = laplacian(uv, pixelSize);
  let laplacePressure = abs(curvature) * surfaceTension * 2.0;
  let specular = pow(max(0.0, normal.z), 20.0) * laplacePressure * 0.3;

  let liquidThickness = abs(newHeight) * 2.0 + 0.1;
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let viewDotNormal = dot(viewDir, normal);

  let liquidColor = calculateLiquidColor(baseColor, liquidThickness, turbidity, newHeight);
  let alpha = calculateFluidAlpha(liquidColor, liquidThickness, viewDotNormal, turbidity, backgroundFactor);

  let finalColor = liquidColor + vec3<f32>(specular);
  let trebleSparkle = treble * 0.1 * backgroundFactor;
  let finalRGB = finalColor + vec3<f32>(trebleSparkle);

  let finalAlpha = clamp(alpha + mids * 0.1 * backgroundFactor, 0.0, 1.0);
  let outColor = vec4<f32>(finalRGB, finalAlpha);

  textureStore(writeTexture, vec2<i32>(global_id.xy), outColor);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
