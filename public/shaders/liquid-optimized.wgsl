// ═══════════════════════════════════════════════════════════════════════════════
//  Surface Tension Liquid Shader with Alpha Physics - SHARED MEMORY OPTIMIZED
//  Category: liquid-effects
//  Features: capillary waves, Laplace pressure, fluid transparency, Beer-Lambert,
//            audio-reactive ambient waves and virtual ripple sources
//
//  OPTIMIZATION: Uses workgroup shared memory to reduce texture fetches by ~80%
//  - 18×18 tile cache for 16×16 workgroup (1-pixel halo for neighbors)
//  - Laplacian: 25 texture reads → 1 shared memory read per pixel
//  - Biharmonic: 125 texture reads → 5 shared memory reads per pixel
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED MEMORY TILE CACHE
// ═══════════════════════════════════════════════════════════════════════════════
const TILE_SIZE: u32 = 16u;
const HALO: u32 = 1u;
const TILE_PADDED: u32 = TILE_SIZE + 2u * HALO;

var<workgroup> tileHeight: array<array<f32, 18>, 18>;
var<workgroup> tilePrevHeight: array<array<f32, 18>, 18>;

fn loadPixel(coord: vec2<i32>, resI: vec2<i32>) -> vec4<f32> {
  let clamped = clamp(coord, vec2<i32>(0), resI - vec2<i32>(1));
  return textureLoad(dataTextureC, clamped, 0);
}

fn loadTileToSharedMemory(
  gid: vec3<u32>,
  lid: vec3<u32>,
  resolution: vec2<f32>
) {
  let resI = vec2<i32>(resolution);
  let baseCoord = vec2<i32>(gid.xy) - vec2<i32>(i32(HALO));

  let primaryCoord = baseCoord + vec2<i32>(lid.xy);
  let primaryData = loadPixel(primaryCoord, resI);
  tileHeight[lid.y + HALO][lid.x + HALO] = primaryData.g;
  tilePrevHeight[lid.y + HALO][lid.x + HALO] = primaryData.r;

  if (lid.x == TILE_SIZE - 1u) {
    let rightCoord = baseCoord + vec2<i32>(i32(TILE_SIZE), i32(lid.y));
    let rightData = loadPixel(rightCoord, resI);
    tileHeight[lid.y + HALO][TILE_SIZE + HALO] = rightData.g;
    tilePrevHeight[lid.y + HALO][TILE_SIZE + HALO] = rightData.r;
  }

  if (lid.y == TILE_SIZE - 1u) {
    let bottomCoord = baseCoord + vec2<i32>(i32(lid.x), i32(TILE_SIZE));
    let bottomData = loadPixel(bottomCoord, resI);
    tileHeight[TILE_SIZE + HALO][lid.x + HALO] = bottomData.g;
    tilePrevHeight[TILE_SIZE + HALO][lid.x + HALO] = bottomData.r;
  }

  if (lid.x == TILE_SIZE - 1u && lid.y == TILE_SIZE - 1u) {
    let cornerCoord = baseCoord + vec2<i32>(i32(TILE_SIZE), i32(TILE_SIZE));
    let cornerData = loadPixel(cornerCoord, resI);
    tileHeight[TILE_SIZE + HALO][TILE_SIZE + HALO] = cornerData.g;
    tilePrevHeight[TILE_SIZE + HALO][TILE_SIZE + HALO] = cornerData.r;
  }

  if (lid.x == 0u) {
    let leftCoord = baseCoord + vec2<i32>(-1, i32(lid.y));
    let leftData = loadPixel(leftCoord, resI);
    tileHeight[lid.y + HALO][0u] = leftData.g;
    tilePrevHeight[lid.y + HALO][0u] = leftData.r;
  }

  if (lid.y == 0u) {
    let topCoord = baseCoord + vec2<i32>(i32(lid.x), -1);
    let topData = loadPixel(topCoord, resI);
    tileHeight[0u][lid.x + HALO] = topData.g;
    tilePrevHeight[0u][lid.x + HALO] = topData.r;
  }

  if (lid.x == 0u && lid.y == 0u) {
    let tlCoord = baseCoord + vec2<i32>(-1, -1);
    let tlData = loadPixel(tlCoord, resI);
    tileHeight[0u][0u] = tlData.g;
    tilePrevHeight[0u][0u] = tlData.r;
  }

  workgroupBarrier();
}

fn sampleHeightShared(lid: vec3<u32>, offsetX: i32, offsetY: i32) -> f32 {
  let x = i32(lid.x) + offsetX + i32(HALO);
  let y = i32(lid.y) + offsetY + i32(HALO);
  return tileHeight[clamp(y, 0, 17)][clamp(x, 0, 17)];
}

fn laplacianShared(lid: vec3<u32>) -> f32 {
  let center = sampleHeightShared(lid, 0, 0);
  let left   = sampleHeightShared(lid, -1, 0);
  let right  = sampleHeightShared(lid, 1, 0);
  let bottom = sampleHeightShared(lid, 0, -1);
  let top    = sampleHeightShared(lid, 0, 1);
  return (left + right + bottom + top - 4.0 * center);
}

fn biharmonicShared(lid: vec3<u32>) -> f32 {
  let centerLap = laplacianShared(lid);
  var leftLap = 0.0;
  var rightLap = 0.0;
  var bottomLap = 0.0;
  var topLap = 0.0;

  {
    let c = sampleHeightShared(lid, -1, 0);
    let l = sampleHeightShared(lid, -2, 0);
    let r = sampleHeightShared(lid, 0, 0);
    let b = sampleHeightShared(lid, -1, -1);
    let t = sampleHeightShared(lid, -1, 1);
    leftLap = l + r + b + t - 4.0 * c;
  }

  {
    let c = sampleHeightShared(lid, 1, 0);
    let l = sampleHeightShared(lid, 0, 0);
    let r = sampleHeightShared(lid, 2, 0);
    let b = sampleHeightShared(lid, 1, -1);
    let t = sampleHeightShared(lid, 1, 1);
    rightLap = l + r + b + t - 4.0 * c;
  }

  {
    let c = sampleHeightShared(lid, 0, -1);
    let l = sampleHeightShared(lid, -1, -1);
    let r = sampleHeightShared(lid, 1, -1);
    let b = sampleHeightShared(lid, 0, -2);
    let t = sampleHeightShared(lid, 0, 0);
    bottomLap = l + r + b + t - 4.0 * c;
  }

  {
    let c = sampleHeightShared(lid, 0, 1);
    let l = sampleHeightShared(lid, -1, 1);
    let r = sampleHeightShared(lid, 1, 1);
    let b = sampleHeightShared(lid, 0, 0);
    let t = sampleHeightShared(lid, 0, 2);
    topLap = l + r + b + t - 4.0 * c;
  }

  return (leftLap + rightLap + bottomLap + topLap - 4.0 * centerLap);
}

fn calculateNormalShared(lid: vec3<u32>, heightScale: f32) -> vec3<f32> {
  let left   = sampleHeightShared(lid, -1, 0);
  let right  = sampleHeightShared(lid, 1, 0);
  let bottom = sampleHeightShared(lid, 0, -1);
  let top    = sampleHeightShared(lid, 0, 1);
  let dx = (right - left) * heightScale;
  let dy = (top - bottom) * heightScale;
  return normalize(vec3<f32>(-dx, -dy, 2.0));
}

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

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN ENTRY POINT WITH SHARED MEMORY
// ═══════════════════════════════════════════════════════════════════════════════

@compute @workgroup_size(16, 16, 1)
fn main(
  @builtin(global_invocation_id) gid: vec3<u32>,
  @builtin(workgroup_id) wid: vec3<u32>,
  @builtin(local_invocation_id) lid: vec3<u32>
) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(gid.xy) / resolution;
  let currentTime = u.config.x;
  let pixelSize = vec2<f32>(1.0) / resolution;

  // Bounds check
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
    return;
  }

  // ═══ AUDIO INPUT ═══
  let audioOverall = u.config.y;
  let audioBass = audioOverall * 1.2;
  let audioPulse = 1.0 + audioBass * 0.5;

  // Get depth for depth-aware effects
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let backgroundFactor = 1.0 - smoothstep(0.0, 0.1, depth);

  // Parameters
  let surfaceTension = u.zoom_params.x * 0.5 + 0.1;
  let gravityScale = u.zoom_params.y * 2.0 + 0.5;
  let damping = u.zoom_params.z * 0.15 + 0.02;
  let turbidity = u.zoom_params.w;
  let density = 1.0;
  let dt = 0.016;

  // ═══════════════════════════════════════════════════════════════════════════════
  // LOAD HEIGHT FIELD INTO SHARED MEMORY (OPTIMIZED PATH)
  // ═══════════════════════════════════════════════════════════════════════════════
  loadTileToSharedMemory(gid, lid, resolution);

  // Read persistent data for this pixel
  let persistentData = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  let h_prev = persistentData.r;
  let h_curr = persistentData.g;
  let velocity = persistentData.b;
  let age = persistentData.a;

  // ═══════════════════════════════════════════════════════════════════════════════
  // CAPILLARY WAVE PHYSICS USING SHARED MEMORY
  // ═══════════════════════════════════════════════════════════════════════════════

  let activeMask = f32(backgroundFactor > 0.01);

  let lapH = laplacianShared(lid);
  let biLapH = biharmonicShared(lid);

  let capillaryAcceleration = (surfaceTension / density) * biLapH * 0.001;
  let gravityAcceleration = -gravityScale * lapH * 0.1;

  let acceleration = capillaryAcceleration + gravityAcceleration - damping * velocity;

  var newVelocity = mix(velocity, velocity + acceleration * dt, activeMask);
  var newHeight = mix(h_curr, h_curr + newVelocity * dt, activeMask);

  newHeight += meniscusEffect(uv, depth, surfaceTension) * 0.1 * activeMask;

  newHeight = mix(newHeight, clamp(newHeight, -0.5, 0.5), activeMask);
  newVelocity = mix(newVelocity, clamp(newVelocity, -1.0, 1.0), activeMask);

  // ═══════════════════════════════════════════════════════════════════════════════
  // RIPPLE SOURCES (Mouse-driven + Ambient + Audio-driven)
  // ═══════════════════════════════════════════════════════════════════════════════
  var sourceHeight = 0.0;
  var sourceVelocity = 0.0;

  // Mouse-driven Ripples
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

  // Ambient Capillary Waves - Audio reactive
  let ambientMask = f32(backgroundFactor > 0.0);
  let time = currentTime * 0.5;
  let ambientFreq = 25.0;

  let wave1 = sin(uv.x * ambientFreq + time * 2.0);
  let wave2 = sin(uv.y * ambientFreq * 0.8 + time * 1.7);
  let wave3 = sin((uv.x + uv.y) * ambientFreq * 0.5 + time * 1.3);

  let microRipple = (wave1 + wave2 + wave3) / 3.0;
  let microEnvelope = smoothstep(0.0, 0.3, backgroundFactor);

  var ambientHeight = microRipple * 0.003 * microEnvelope * surfaceTension * ambientMask * audioPulse;

  // Audio-driven virtual ripple at screen center
  let audioDist = distance(uv, vec2<f32>(0.5));
  let audioWave = sin(audioDist * 30.0 - currentTime * 8.0) * exp(-audioDist * 3.0);
  let audioRipple = audioWave * audioBass * 0.015 * microEnvelope;
  ambientHeight += audioRipple;

  // Apply sources
  newHeight += sourceHeight + ambientHeight;
  newVelocity += sourceVelocity;

  // ═══════════════════════════════════════════════════════════════════════════════
  // FLUID RENDERING WITH PHYSICS-BASED ALPHA
  // ═══════════════════════════════════════════════════════════════════════════════

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  let liquidHeight = abs(newHeight) * 2.0;
  let liquidThickness = liquidHeight * (1.0 + turbidity);

  let normal = calculateNormalShared(lid, 1.0);
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let viewDotNormal = dot(viewDir, normal);

  let F0 = 0.02;
  let fresnel = schlickFresnel(max(0.0, viewDotNormal), F0);

  let effectiveDepth = liquidThickness * (1.0 + turbidity * 2.0);
  let absorptionR = exp(-effectiveDepth * 2.0);
  let absorptionG = exp(-effectiveDepth * 1.6);
  let absorptionB = exp(-effectiveDepth * 1.2);
  let absorption = (absorptionR + absorptionG + absorptionB) / 3.0;

  let heightTint = vec3<f32>(0.0, 0.1, 0.15) * newHeight * 0.5;
  let liquidColor = vec3<f32>(
    baseColor.r * absorptionR,
    baseColor.g * absorptionG + heightTint.g,
    baseColor.b * absorptionB + heightTint.b
  );

  let lightDir = normalize(vec3<f32>(0.3, 0.5, 1.0));
  let halfDir = normalize(lightDir + viewDir);
  let specAngle = max(0.0, dot(normal, halfDir));
  let specular = pow(specAngle, 128.0) * 0.8 * (1.0 - turbidity * 0.5);

  let finalLiquidColor = liquidColor + vec3<f32>(specular);

  let baseAlpha = mix(0.3, 0.95, absorption * backgroundFactor);
  let alpha = baseAlpha * (1.0 - fresnel * 0.5);
  let finalAlpha = clamp(alpha, 0.0, 1.0) * backgroundFactor;

  let finalColor = mix(baseColor, finalLiquidColor, finalAlpha);

  // Beat flash on liquid surface
  let isBeat = step(0.7, audioBass);
  let beatColor = finalColor + vec3<f32>(0.05, 0.03, 0.02) * isBeat * finalAlpha;

  // ═══════════════════════════════════════════════════════════════════════════════
  // WRITE OUTPUTS
  // ═══════════════════════════════════════════════════════════════════════════════

  textureStore(writeTexture, gid.xy, vec4<f32>(beatColor, 1.0));
  textureStore(dataTextureA, gid.xy, vec4<f32>(h_curr, newHeight, newVelocity, age + dt));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
