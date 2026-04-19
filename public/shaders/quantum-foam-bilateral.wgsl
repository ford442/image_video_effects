// ═══════════════════════════════════════════════════════════════════
//  Quantum Foam Bilateral
//  Category: advanced-hybrid
//  Features: advanced-hybrid, quantum-foam, bilateral-filter, edge-preserving
//  Complexity: Very High
//  Chunks From: quantum-foam.wgsl, conv-bilateral-dream.wgsl
//  Created: 2026-04-18
//  By: Agent CB-3 — Convolution Post-Processor
// ═══════════════════════════════════════════════════════════════════
//  Quantum foam chromatic parallax diffusion with edge-preserving
//  bilateral smoothing. Cell boundaries and emissive edges remain
//  crisp while foam interiors are dreamily smoothed.
//
//  RGBA32FLOAT EXPLOITATION:
//    RGB: Bilaterally smoothed quantum foam color
//    Alpha: Edge confidence — 1.0 = sharp edge preserved,
//           0.0 = fully smoothed region
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
  zoom_params: vec4<f32>,  // x=FoamScale, y=FlowSpeed, z=DiffusionRate, w=Detail
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash3 (from quantum-foam.wgsl) ═══
fn hash3(p: vec3<f32>) -> f32 {
  let p3 = fract(p * vec3<f32>(443.897, 441.423, 997.731));
  return fract(p3.x * p3.y * p3.z + dot(p3, p3 + 19.19));
}

// ═══ CHUNK: fbm (from quantum-foam.wgsl) ═══
fn fbm(p: vec2<f32>, time: f32, octaves: i32) -> f32 {
  var value = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    value = value + amp * (hash3(vec3<f32>(p * freq, time * (1.0 + f32(i) * 0.2))) - 0.5);
    freq = freq * 2.15;
    amp = amp * 0.55;
  }
  return value;
}

// ═══ CHUNK: curlNoise (from quantum-foam.wgsl) ═══
fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
  let eps = 0.01;
  let n1 = fbm(p + vec2<f32>(eps, 0.0), time, 4);
  let n2 = fbm(p + vec2<f32>(0.0, eps), time, 4);
  let n3 = fbm(p - vec2<f32>(eps, 0.0), time, 4);
  let n4 = fbm(p - vec2<f32>(0.0, eps), time, 4);
  return vec2<f32>((n2 - n4) / (2.0 * eps), (n1 - n3) / (2.0 * eps));
}

// ═══ CHUNK: voronoi (from quantum-foam.wgsl) ═══
fn voronoi(p: vec2<f32>, time: f32) -> vec3<f32> {
  var i = floor(p);
  var f = fract(p);
  var minDist1 = 1000.0;
  var minDist2 = 1000.0;
  var minPoint = vec2<f32>(0.0);
  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      let seed = hash3(vec3<f32>(i + neighbor, time * 0.1)) * 2.0 - 1.0;
      let point = neighbor + vec2<f32>(seed, seed * 0.7);
      let dist = length(point - f);
      if (dist < minDist1) {
        minDist2 = minDist1;
        minDist1 = dist;
        minPoint = vec2<f32>(seed, seed);
      } else if (dist < minDist2) {
        minDist2 = dist;
      }
    }
  }
  return vec3<f32>(minDist1, minDist2, minPoint.x);
}

// ═══ CHUNK: hsv2rgb (from quantum-foam.wgsl) ═══
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
  var c = v * s;
  let h6 = h * 6.0;
  var x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
  var rgb = vec3<f32>(0.0);
  if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
  else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else               { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + vec3<f32>(v - c);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

  let uv = vec2<f32>(global_id.xy) / res;
  let texel = 1.0 / res;
  let time = u.config.x;

  // ── Parameters ──
  let foamScale = u.zoom_params.x * 3.0 + 1.0;
  let flowSpeed = u.zoom_params.y;
  let diffusionRate = u.zoom_params.z * 0.9;
  let detail = u.zoom_params.w;
  let octaveCount = i32(detail * 4.0 + 3.0);

  let bilateralSpatial = mix(0.5, 3.0, u.zoom_config.x);
  let bilateralColor = mix(0.05, 0.5, u.zoom_config.y);
  let bilateralBlend = u.zoom_config.z;

  // ── Source sampling ──
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let srcColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // ── Quantum foam core ──
  let curl = curlNoise(uv * foamScale * 0.5, time * flowSpeed);

  var totalWarp = vec2<f32>(0.0);
  var parallaxWeight = 0.0;
  for (var layer: i32 = 0; layer < 3; layer = layer + 1) {
    let layerDepth = f32(layer) * 0.33;
    let layerVelocity = 1.0 + f32(layer) * 0.5;
    let layerWeight = 1.0 / (1.0 + abs(depth - layerDepth) * 15.0);
    let advectedCurl = curlNoise(uv * foamScale * 0.5 + curl * layerVelocity, time * flowSpeed);
    let layerAngle = time * flowSpeed * layerVelocity + f32(layer) * 2.094;
    let layerOffset = advectedCurl * 0.1 * layerWeight + vec2<f32>(cos(layerAngle), sin(layerAngle)) * layerWeight * 0.05;
    let layerUV = uv + layerOffset;
    let layerNoise = fbm(layerUV * foamScale, time * layerVelocity, octaveCount);
    totalWarp = totalWarp + vec2<f32>(layerNoise * layerWeight * layerVelocity);
    parallaxWeight = parallaxWeight + layerWeight;
  }
  totalWarp = totalWarp / max(parallaxWeight, 0.001);
  totalWarp = totalWarp + curl * 0.05;

  let cell = voronoi(uv * foamScale + totalWarp * 2.0, time);
  let cellPattern = 1.0 - smoothstep(0.0, 0.08, cell.x);
  let cellBoundary = smoothstep(0.08, 0.12, cell.y - cell.x);
  let cellInterior = fbm(uv * foamScale * 5.0 + cell.z * 2.0, time, max(octaveCount - 2, 2));
  let hybridPattern = mix(cellInterior, cellPattern, cellBoundary);

  let wave1 = sin(length(uv - 0.5) * 25.0 - time * 4.0);
  let wave2 = sin(atan2(uv.y - 0.5, uv.x - 0.5) * 18.0 + time * 3.0);
  let wave3 = sin(dot(uv - 0.5, vec2<f32>(1.0, 1.0)) * 30.0 - time * 5.0);
  let interference = (wave1 * wave2 * wave3 + 1.0) * 0.5;

  let depthWeight = 1.0 + (1.0 - depth) * 2.0;
  let pattern = (hybridPattern * 0.4 + interference * 0.3 + fbm(uv * 4.0, time * 0.3, 3) * 0.3) * depthWeight;

  // Chromatic dispersion
  let dispersion = pattern * texel * 30.0;
  let rUV = clamp(uv + totalWarp * dispersion + depth * dispersion + curl * 0.02, vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = clamp(uv + totalWarp * dispersion * 0.9 + curl * 0.01, vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(uv + totalWarp * dispersion * 1.1 - depth * dispersion - curl * 0.015, vec2<f32>(0.0), vec2<f32>(1.0));

  let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
  let dispersedColor = vec3<f32>(r, g, b);

  // Emissive foam
  let luminance = dot(srcColor, vec3<f32>(0.2126, 0.7152, 0.0722));
  let emission = smoothstep(0.5, 1.0, cellBoundary * pattern * luminance);
  let plasmaColor = hsv2rgb(fract(time * 0.05 + pattern + cell.z), 0.9, 1.0);
  let emissiveColor = mix(dispersedColor, plasmaColor, emission * 0.5);

  let foamColor = mix(srcColor, emissiveColor, detail);

  // ── Bilateral post-processing ──
  let centerColor = foamColor;
  var accumColor = vec3<f32>(0.0);
  var accumWeight = 0.0;
  let radius = i32(ceil(bilateralSpatial));
  let maxRadius = min(radius, 5);

  for (var dy = -maxRadius; dy <= maxRadius; dy = dy + 1) {
    for (var dx = -maxRadius; dx <= maxRadius; dx = dx + 1) {
      let offset = vec2<f32>(f32(dx), f32(dy)) * texel;
      let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
      let neighbor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

      // Re-apply foam warp to neighbor for spatial consistency
      let neighborFoam = mix(neighbor, plasmaColor * 0.5 + neighbor * 0.5, emission * 0.3);

      let spatialDist = length(vec2<f32>(f32(dx), f32(dy)));
      let spatialWeight = exp(-spatialDist * spatialDist / (2.0 * bilateralSpatial * bilateralSpatial + 0.001));

      let colorDist = length(neighborFoam - centerColor);
      let rangeWeight = exp(-colorDist * colorDist / (2.0 * bilateralColor * bilateralColor + 0.001));

      let weight = spatialWeight * rangeWeight;
      accumColor = accumColor + neighborFoam * weight;
      accumWeight = accumWeight + weight;
    }
  }

  var smoothed = vec3<f32>(0.0);
  if (accumWeight > 0.001) {
    smoothed = accumColor / accumWeight;
  } else {
    smoothed = centerColor;
  }

  // Edge confidence: how much the bilateral preserved edges vs smoothed
  let colorShift = length(smoothed - centerColor);
  let edgeConfidence = 1.0 - smoothstep(0.0, 0.2, colorShift);

  let finalColor = mix(foamColor, smoothed, bilateralBlend);

  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, edgeConfidence));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
