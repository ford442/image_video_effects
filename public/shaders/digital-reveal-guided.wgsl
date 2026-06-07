// ═══════════════════════════════════════════════════════════════════
//  digital-reveal-guided
//  Category: advanced-hybrid
//  Features: mouse-driven, digital-reveal, guided-filter, depth-aware
//  Complexity: High
//  Chunks From: digital-reveal.wgsl, conv-guided-filter-depth.wgsl
//  Created: 2026-04-18
//  By: Agent CB-18
// ═══════════════════════════════════════════════════════════════════
//  Digital rain reveals the image through a depth-guided filter.
//  Revealed areas get smooth edge-aware filtering while rain areas
//  remain sharp/crisp. Mouse focus aperture controls filter radius.
//  Alpha stores filtering confidence.
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx+p3.yz)*p3.zy);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

  let uv = vec2<f32>(global_id.xy) / res;
  let pixelSize = 1.0 / res;
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;

  let density = u.zoom_params.x;
  let revealSize = u.zoom_params.y;
  let trailFade = u.zoom_params.z;
  let depthInfluence = u.zoom_params.w;

  // --- Trail mask ---
  let prevVal = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
  let aspect = res.x / res.y;
  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(mousePos.x * aspect, mousePos.y);
  let dist = distance(uvCorrected, mouseCorrected);
  let brushRadius = revealSize * 0.3 + 0.05;
  let brush = smoothstep(brushRadius, brushRadius * 0.5, dist);
  let fadeFactor = 0.8 + trailFade * 0.19;
  let newVal = max(prevVal * fadeFactor, brush);

  // --- Guided filter on revealed area ---
  let radiusBase = i32(mix(2.0, 6.0, revealSize));
  let epsilonBase = mix(0.0001, 0.05, depthInfluence);

  let mouseDist = length(uv - mousePos);
  let mouseFactor = exp(-mouseDist * mouseDist * 6.0);
  let radius = i32(mix(f32(radiusBase), f32(radiusBase) * 0.4, mouseFactor));
  let epsilon = mix(epsilonBase * 3.0, epsilonBase * 0.1, mouseFactor);

  let maxRadius = min(radius, 5);
  var sumGuide = 0.0;
  var sumInput = vec3<f32>(0.0);
  var sumGuideInput = vec3<f32>(0.0);
  var sumGuide2 = 0.0;
  var count = 0.0;

  for (var dy = -maxRadius; dy <= maxRadius; dy++) {
    for (var dx = -maxRadius; dx <= maxRadius; dx++) {
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let guideVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + offset, 0.0).r;
      let inputVal = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
      sumGuide += guideVal;
      sumInput += inputVal;
      sumGuideInput += inputVal * guideVal;
      sumGuide2 += guideVal * guideVal;
      count += 1.0;
    }
  }

  let meanGuide = sumGuide / count;
  let meanInput = sumInput / count;
  let meanGI = sumGuideInput / count;
  let meanGuide2 = sumGuide2 / count;
  let varGuide = meanGuide2 - meanGuide * meanGuide;

  let a = (meanGI - meanGuide * meanInput) / (varGuide + epsilon);
  let b = meanInput - a * meanGuide;
  let guide = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let filtered = a * guide + b;
  let confidence = length(a) * depthInfluence;

  let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let filteredResult = mix(original, filtered, depthInfluence * newVal);

  // --- Digital rain for unrevealed ---
  let gridSize = vec2<f32>(20.0, 20.0 * aspect) * (1.0 + density * 2.0);
  let cellUV = fract(uv * gridSize);
  let cellID = floor(uv * gridSize);
  let colSpeed = hash22(vec2<f32>(cellID.x, 0.0)).y * 3.0;
  let verticalPos = cellID.y + time * colSpeed;
  let charID = floor(verticalPos);
  let dropVal = fract(verticalPos);
  let charBright = smoothstep(0.0, 0.2, dropVal) * smoothstep(1.0, 0.8, dropVal);
  let flicker = step(0.1, hash22(vec2<f32>(cellID.x, charID)).x);
  var rainColor = vec3<f32>(0.0, 1.0, 0.2) * charBright * flicker;
  if (hash22(vec2<f32>(cellID.x, charID)).y > 0.98 - density * 0.1) {
    rainColor = vec3<f32>(0.8, 1.0, 0.8);
  }

  let finalColor = mix(rainColor, filteredResult, clamp(newVal, 0.0, 1.0));

  textureStore(dataTextureA, global_id.xy, vec4<f32>(newVal, 0.0, 0.0, 1.0));
  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, confidence));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
