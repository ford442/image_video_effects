// ═══════════════════════════════════════════════════════════════════
//  Holographic Interferometry Bilateral
//  Category: advanced-hybrid
//  Features: advanced-hybrid, holography, bilateral-filter,
//            interference-patterns, speckle-reduction
//  Complexity: High
//  Chunks From: holographic-interferometry.wgsl, conv-bilateral-dream.wgsl
//  Created: 2026-04-18
//  By: Agent CB-3 — Convolution Post-Processor
// ═══════════════════════════════════════════════════════════════════
//  Simulated hologram with interference fringes and edge-preserving
//  bilateral smoothing. Speckle noise is softly reduced while
//  sharp interference fringe edges remain crisp.
//
//  RGBA32FLOAT EXPLOITATION:
//    RGB: Bilaterally smoothed holographic reconstruction
//    Alpha: Fringe edge confidence — 1.0 = sharp fringe edge,
//           0.0 = smooth region between fringes
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
  zoom_params: vec4<f32>,  // x=FringeDensity, y=Coherence, z=ReconAngle, w=Saturation
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash12 (from holographic-interferometry.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: speckleNoise (from holographic-interferometry.wgsl) ═══
fn speckleNoise(uv: vec2<f32>, coherence: f32) -> f32 {
  let scale = mix(50.0, 500.0, coherence);
  var s = 0.0;
  for (var i = 0; i < 4; i = i + 1) {
    let fi = f32(i);
    s = s + hash12(uv * scale + vec2<f32>(fi * 13.7, fi * 42.3));
  }
  return s / 4.0;
}

// ═══ CHUNK: interferencePattern (from holographic-interferometry.wgsl) ═══
fn interferencePattern(uv: vec2<f32>, depth: f32, fringeDensity: f32, angle: f32) -> f32 {
  let objectPhase = depth * fringeDensity * 10.0;
  let refPhase = (uv.x * cos(angle) + uv.y * sin(angle)) * fringeDensity * 50.0;
  let phaseDiff = objectPhase + refPhase;
  return 0.5 + 0.5 * cos(phaseDiff);
}

// ═══ CHUNK: reconstructHologram (from holographic-interferometry.wgsl) ═══
fn reconstructHologram(uv: vec2<f32>, depth: f32, intensity: f32, phase: f32, angle: f32) -> vec3<f32> {
  let reconPhase = (uv.x * cos(angle + 0.5) + uv.y * sin(angle + 0.5)) * 20.0;
  let totalPhase = phase + reconPhase;
  let hue = fract(totalPhase / 6.28);
  let sat = 0.7 + intensity * 0.3;
  let val = 0.5 + intensity * 0.5;
  let c = val * sat;
  let h = hue * 6.0;
  let x = c * (1.0 - abs(h % 2.0 - 1.0));
  var rgb = vec3<f32>(0.0);
  if (h < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
  else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + vec3<f32>(val - c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let pixelSize = 1.0 / resolution;
  let time = u.config.x;
  let id = vec2<i32>(global_id.xy);

  // Parameters
  let fringeDensity = mix(10.0, 100.0, u.zoom_params.x);
  let coherence = u.zoom_params.y;
  let reconAngle = u.zoom_params.z * 3.14;
  let saturation = mix(0.5, 1.5, u.zoom_params.w);

  let bilateralSpatial = mix(0.5, 2.5, u.zoom_config.x);
  let bilateralColor = mix(0.05, 0.4, u.zoom_config.y);
  let bilateralBlend = u.zoom_config.z;

  // ── Holographic interferometry core ──
  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let luma = dot(sourceColor, vec3<f32>(0.299, 0.587, 0.114));

  let interference = interferencePattern(uv, depth, fringeDensity, reconAngle);
  let phase = acos(interference * 2.0 - 1.0);

  var holoColor = reconstructHologram(uv, depth, luma, phase, reconAngle);

  let speckle = speckleNoise(uv + time * 0.01, coherence);
  let specklePattern = mix(0.8, 1.2, speckle * coherence);

  let hologram = holoColor * luma * specklePattern * saturation;

  let fringes = sin(phase * fringeDensity) * 0.5 + 0.5;
  let fringeColor = vec3<f32>(fringes * 0.5, fringes * 0.3, fringes * 0.7);

  var color = mix(sourceColor * 0.3, hologram + fringeColor * 0.2, 0.8);

  let parallax = depth * 0.02;
  let parallaxUV = uv + vec2<f32>(cos(reconAngle), sin(reconAngle)) * parallax;
  let parallaxColor = textureSampleLevel(readTexture, u_sampler, clamp(parallaxUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;

  color = mix(color, parallaxColor * holoColor, depth * 0.3);

  let holographicColor = color;

  // ── Bilateral speckle reduction ──
  let center = holographicColor;
  var accumColor = vec3<f32>(0.0);
  var accumWeight = 0.0;
  let radius = i32(ceil(bilateralSpatial));
  let maxRadius = min(radius, 4);

  for (var dy = -maxRadius; dy <= maxRadius; dy = dy + 1) {
    for (var dx = -maxRadius; dx <= maxRadius; dx = dx + 1) {
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
      let neighbor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
      // Reconstruct hologram at neighbor for consistency
      let nDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
      let nLuma = dot(neighbor, vec3<f32>(0.299, 0.587, 0.114));
      let nInterference = interferencePattern(sampleUV, nDepth, fringeDensity, reconAngle);
      let nPhase = acos(clamp(nInterference * 2.0 - 1.0, -1.0, 1.0));
      let nHolo = reconstructHologram(sampleUV, nDepth, nLuma, nPhase, reconAngle);
      let nSpeckle = speckleNoise(sampleUV + time * 0.01, coherence);
      let nSpecklePattern = mix(0.8, 1.2, nSpeckle * coherence);
      let nHologram = nHolo * nLuma * nSpecklePattern * saturation;
      let nFringes = sin(nPhase * fringeDensity) * 0.5 + 0.5;
      let nFringeColor = vec3<f32>(nFringes * 0.5, nFringes * 0.3, nFringes * 0.7);
      let neighborHolo = mix(neighbor * 0.3, nHologram + nFringeColor * 0.2, 0.8);

      let spatialDist = length(vec2<f32>(f32(dx), f32(dy)));
      let spatialWeight = exp(-spatialDist * spatialDist / (2.0 * bilateralSpatial * bilateralSpatial + 0.001));

      let colorDist = length(neighborHolo - center);
      let rangeWeight = exp(-colorDist * colorDist / (2.0 * bilateralColor * bilateralColor + 0.001));

      let weight = spatialWeight * rangeWeight;
      accumColor = accumColor + neighborHolo * weight;
      accumWeight = accumWeight + weight;
    }
  }

  var smoothed = vec3<f32>(0.0);
  if (accumWeight > 0.001) {
    smoothed = accumColor / accumWeight;
  } else {
    smoothed = center;
  }

  // Fringe edge confidence
  let colorShift = length(smoothed - center);
  let edgeConfidence = 1.0 - smoothstep(0.0, 0.15, colorShift);

  let finalColor = mix(holographicColor, smoothed, bilateralBlend);

  let alpha = mix(0.75, 0.95, luma);

  textureStore(writeTexture, id, vec4<f32>(finalColor, edgeConfidence));
  textureStore(writeDepthTexture, id, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
