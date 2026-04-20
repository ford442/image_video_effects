// ═══════════════════════════════════════════════════════════════════
//  Gravitational Lensing NLM
//  Category: advanced-hybrid
//  Features: advanced-hybrid, schwarzschild-metric, non-local-means,
//            artistic-overdrive
//  Complexity: Very High
//  Chunks From: gravitational-lensing.wgsl, conv-non-local-means.wgsl
//  Created: 2026-04-18
//  By: Agent CB-3 — Convolution Post-Processor
// ═══════════════════════════════════════════════════════════════════
//  Black hole gravitational lensing with non-local means artistic
//  overdrive. Patch-similarity filtering smooths background starfields
//  while preserving unique features like the event horizon and
//  Einstein ring. Alpha stores an importance map.
//
//  RGBA32FLOAT EXPLOITATION:
//    RGB: NLM-filtered gravitational lensing color
//    Alpha: Self-similarity importance map — low similarity = unique
//           feature (ring, disk) = high alpha. High similarity =
//           repetitive starfield = low alpha.
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=BlackHoleMass, y=DiskBrightness, z=CameraOrbit, w=Redshift
  ripples: array<vec4<f32>, 50>,
};

const MAX_STEPS: i32 = 128;
const MAX_DIST: f32 = 50.0;
const DT: f32 = 0.05;

// ═══ CHUNK: hash12 (from gravitational-lensing.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: schwarzschildFactor (from gravitational-lensing.wgsl) ═══
fn schwarzschildFactor(r: f32, mass: f32) -> f32 {
  let rs = 2.0 * mass;
  return sqrt(max(0.001, 1.0 - rs / max(r, rs * 1.01)));
}

// ═══ CHUNK: renderAccretionDisk (from gravitational-lensing.wgsl) ═══
fn renderAccretionDisk(rayPos: vec3<f32>, rayDir: vec3<f32>, blackHolePos: vec3<f32>, mass: f32) -> vec3<f32> {
  let rs = 2.0 * mass;
  let innerRadius = rs * 3.0;
  let outerRadius = rs * 15.0;
  let toCenter = blackHolePos - rayPos;
  let t = toCenter.y / rayDir.y;
  if (t > 0.0) {
    let hitPos = rayPos + rayDir * t;
    let distFromCenter = length(hitPos.xz - blackHolePos.xz);
    if (distFromCenter > innerRadius && distFromCenter < outerRadius) {
      let temp = 1.0 - (distFromCenter - innerRadius) / (outerRadius - innerRadius);
      let orbitalVel = normalize(vec3<f32>(-(hitPos.z - blackHolePos.z), 0.0, hitPos.x - blackHolePos.x));
      let doppler = dot(rayDir, orbitalVel);
      let beaming = pow(1.0 + doppler, 3.0);
      var color = vec3<f32>(0.0);
      if (temp > 0.8) { color = vec3<f32>(1.0, 0.9, 0.7); }
      else if (temp > 0.5) { color = vec3<f32>(1.0, 0.5, 0.2); }
      else { color = vec3<f32>(0.8, 0.2, 0.1); }
      color = color * beaming * temp * temp;
      return color * smoothstep(outerRadius, innerRadius, distFromCenter);
    }
  }
  return vec3<f32>(0.0);
}

// ═══ CHUNK: gravitationalRedshift (from gravitational-lensing.wgsl) ═══
fn gravitationalRedshift(r: f32, mass: f32) -> vec3<f32> {
  let rs = 2.0 * mass;
  let factor = sqrt(max(0.001, 1.0 - rs / max(r, rs)));
  return vec3<f32>(1.0, factor, factor * 0.8);
}

// ═══ CHUNK: patchDistance (from conv-non-local-means.wgsl) ═══
fn patchDistance(uv1: vec2<f32>, uv2: vec2<f32>, patchRadius: i32, pixelSize: vec2<f32>) -> f32 {
  var dist = 0.0;
  for (var dy = -patchRadius; dy <= patchRadius; dy = dy + 1) {
    for (var dx = -patchRadius; dx <= patchRadius; dx = dx + 1) {
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let p1 = textureSampleLevel(readTexture, u_sampler, uv1 + offset, 0.0).rgb;
      let p2 = textureSampleLevel(readTexture, u_sampler, uv2 + offset, 0.0).rgb;
      let diff = p1 - p2;
      dist = dist + dot(diff, diff);
    }
  }
  return dist;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

  let uvRaw = (vec2<f32>(global_id.xy) / resolution - 0.5) * 2.0;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;
  let id = vec2<i32>(global_id.xy);

  // Parameters
  let blackHoleMass = mix(1.0, 5.0, u.zoom_params.x);
  let diskBrightness = mix(0.5, 3.0, u.zoom_params.y);
  let cameraOrbit = u.zoom_params.z * 6.28;
  let redshiftIntensity = u.zoom_params.w;

  let patchRadius = i32(mix(1.0, 2.0, u.zoom_config.x));
  let searchRadius = i32(mix(2.0, 6.0, u.zoom_config.y));
  let hParam = mix(0.001, 0.05, u.zoom_config.z);
  let overdrive = u.zoom_config.w;

  // ── Gravitational lensing core ──
  let blackHolePos = vec3<f32>(0.0, 0.0, 0.0);
  let rs = 2.0 * blackHoleMass;
  let eventHorizon = rs * 1.05;

  let camDist = 20.0;
  let camAngle = time * 0.1 + cameraOrbit;
  let ro = vec3<f32>(cos(camAngle) * camDist, sin(camAngle * 0.3) * 5.0, sin(camAngle) * camDist);

  let forward = normalize(blackHolePos - ro);
  let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
  let up = cross(forward, right);
  let rd = normalize(forward + right * uvRaw.x * aspect * 0.5 + up * uvRaw.y * 0.5);

  var rayPos = ro;
  var rayDir = rd;
  var color = vec3<f32>(0.0);
  var depth = 1.0;

  for (var i: i32 = 0; i < MAX_STEPS; i = i + 1) {
    let toCenter = rayPos - blackHolePos;
    let r = length(toCenter);
    if (r < eventHorizon) {
      color = vec3<f32>(0.0);
      depth = 0.0;
      break;
    }
    if (r > MAX_DIST) {
      let bgUV = vec2<f32>(atan2(rayDir.z, rayDir.x) / 6.28 + 0.5, rayDir.y * 0.5 + 0.5);
      color = textureSampleLevel(readTexture, u_sampler, bgUV, 0.0).rgb;
      let redshift = gravitationalRedshift(r, blackHoleMass);
      color = color * mix(vec3<f32>(1.0), redshift, redshiftIntensity);
      depth = 0.5 + r / MAX_DIST * 0.5;
      break;
    }
    let accel = -normalize(toCenter) * blackHoleMass / (r * r);
    rayDir = normalize(rayDir + accel * DT);
    rayPos = rayPos + rayDir * DT * r * 0.5;
  }

  let diskColor = renderAccretionDisk(ro, rd, blackHolePos, blackHoleMass) * diskBrightness;
  color = color + diskColor;

  let closestApproach = length(ro - blackHolePos);
  let einsteinRadius = sqrt(rs * closestApproach);
  let toCenter2D = length(uvRaw);
  let ringGlow = smoothstep(0.5, 0.0, abs(toCenter2D - 0.3)) * 0.5;
  color = color + vec3<f32>(0.9, 0.8, 0.6) * ringGlow;

  let lensingColor = color;

  // ── Non-local means artistic overdrive ──
  let uv = vec2<f32>(global_id.xy) / resolution;
  let pixelSize = 1.0 / resolution;

  let center = lensingColor;
  var accumColor = vec3<f32>(0.0);
  var accumWeight = 0.0;
  var similaritySum = 0.0;
  var maxSimilarity = 0.0;

  let maxSearch = min(searchRadius, 5);

  for (var dy = -maxSearch; dy <= maxSearch; dy = dy + 1) {
    for (var dx = -maxSearch; dx <= maxSearch; dx = dx + 1) {
      if (dx == 0 && dy == 0) { continue; }
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let neighborUV = uv + offset;
      let pd = patchDistance(uv, neighborUV, patchRadius, pixelSize);
      let weight = exp(-pd / max(hParam, 0.0001));

      // Sample from the raymarched result by re-mapping neighborUV to the background
      let neighborRaw = (neighborUV - 0.5) * 2.0;
      let nAspect = resolution.x / resolution.y;
      let nRo = ro;
      let nForward = normalize(blackHolePos - nRo);
      let nRight = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), nForward));
      let nUp = cross(nForward, nRight);
      let nRd = normalize(nForward + nRight * neighborRaw.x * nAspect * 0.5 + nUp * neighborRaw.y * 0.5);

      // Approximate neighbor color from readTexture for performance
      let neighborColor = textureSampleLevel(readTexture, u_sampler, neighborUV, 0.0).rgb;
      accumColor = accumColor + neighborColor * weight;
      accumWeight = accumWeight + weight;
      similaritySum = similaritySum + weight;
      maxSimilarity = max(maxSimilarity, weight);
    }
  }

  accumColor = accumColor + center;
  accumWeight = accumWeight + 1.0;
  similaritySum = similaritySum + 1.0;
  maxSimilarity = max(maxSimilarity, 1.0);

  var result = vec3<f32>(0.0);
  if (accumWeight > 0.001) {
    result = accumColor / accumWeight;
  }

  // Artistic overdrive: blend with original based on similarity
  let avgSimilarity = similaritySum / (f32(maxSearch * maxSearch * 4) + 1.0);
  let overdriveBlend = overdrive * (1.0 - avgSimilarity);
  result = mix(result, center, overdriveBlend);

  // Self-similarity importance map: low similarity = unique = high alpha
  let importance = 1.0 - avgSimilarity;

  let alpha = mix(0.9, 1.0, diskBrightness * 0.3);

  textureStore(writeTexture, id, vec4<f32>(result, importance));
  textureStore(writeDepthTexture, id, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
