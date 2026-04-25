// ═══════════════════════════════════════════════════════════════════
//  dimension-slicer-guided
//  Category: advanced-hybrid
//  Features: dimensional-slice, guided-filter, depth-aware, edge-preserving, mouse-driven
//  Complexity: Very High
//  Chunks From: dimension-slicer, conv-guided-filter-depth
//  Created: 2026-04-18
//  By: Agent CB-15 — Visual Effects & Distortion Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Dimensional rift slicer combined with depth-aware guided filtering.
//  The slice uses edge-preserving filtering guided by depth, creating
//  clean dimensional cuts that respect object boundaries. Inside the
//  slice, space is warped with chromatic aberration and depth-aware
//  blur that perfectly follows depth discontinuities.
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

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let c = cos(angle);
  let s = sin(angle);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = u.config.zw;
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / dims;
  let aspect = dims.x / dims.y;
  let time = u.config.x;

  let sliceWidth = mix(0.05, 0.4, u.zoom_params.x);
  let distortion = mix(0.0, 2.0, u.zoom_params.y);
  let angle = u.zoom_params.z * 3.14159 * 2.0;
  let aberration = u.zoom_params.w * 0.05;

  let radiusBase = i32(mix(2.0, 8.0, u.zoom_params.x));
  let epsilonBase = mix(0.0001, 0.05, u.zoom_params.y);
  let depthInfluence = u.zoom_params.z;
  let mouseInfluence = u.zoom_params.w;

  let mouse = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w > 0.5;

  // Coordinate relative to mouse
  var p = uv - mouse;
  p.x *= aspect;
  let pRot = rotate(p, angle);
  let dist = abs(pRot.x);
  let inSlice = 1.0 - smoothstep(sliceWidth - 0.01, sliceWidth, dist);

  // Mouse focus aperture for guided filter
  let mouseDist = length(uv - mouse);
  let mouseFactor = exp(-mouseDist * mouseDist * 6.0) * mouseInfluence;
  let radius = i32(mix(f32(radiusBase), f32(radiusBase) * 0.4, mouseFactor));
  let epsilon = mix(epsilonBase * 3.0, epsilonBase * 0.1, mouseFactor);

  // Ripple depth discontinuities
  var rippleDepth = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rElapsed = time - ripple.z;
    if (rElapsed > 0.0 && rElapsed < 2.5) {
      let rDist = length(uv - ripple.xy);
      let wave = exp(-rDist * rDist * 40.0) * (1.0 - rElapsed / 2.5);
      rippleDepth = rippleDepth + wave;
    }
  }

  var finalColor = vec3<f32>(0.0);
  var finalAlpha = 1.0;

  if (inSlice > 0.0) {
    // Warp UVs inside slice
    let zoom = 1.0 - distortion * 0.5 * cos(dist / sliceWidth * 3.14159);
    let offset = (uv - mouse) * (1.0 / zoom - 1.0);
    let warpedUV = uv + offset * inSlice;

    // ═══ GUIDED FILTER ON WARPED UV ═══
    let pixelSize = 1.0 / dims;
    let maxRadius = min(radius, 7);

    var sumGuide = 0.0;
    var sumInput = vec3<f32>(0.0);
    var sumGuideInput = vec3<f32>(0.0);
    var sumGuide2 = 0.0;
    var count = 0.0;

    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
      for (var dx = -maxRadius; dx <= maxRadius; dx++) {
        let sampleOffset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
        let sampleUV = clamp(warpedUV + sampleOffset, vec2<f32>(0.0), vec2<f32>(1.0));
        let guideVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r + rippleDepth * 0.1;
        let inputVal = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
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

    let guide = textureSampleLevel(readDepthTexture, non_filtering_sampler, warpedUV, 0.0).r + rippleDepth * 0.1;
    let filtered = a * guide + b;

    // Chromatic aberration on filtered result
    let r = textureSampleLevel(readTexture, u_sampler, warpedUV + vec2<f32>(aberration, 0.0) * inSlice, 0.0).r;
    let g = filtered.g;
    let b = textureSampleLevel(readTexture, u_sampler, warpedUV - vec2<f32>(aberration, 0.0) * inSlice, 0.0).b;
    finalColor = vec3<f32>(r, g, b);

    // Mix between guided result and original based on depth influence
    let original = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0).rgb;
    finalColor = mix(original, finalColor, depthInfluence);

    // Glowing edge
    let edge = smoothstep(sliceWidth - 0.02, sliceWidth, dist) * (1.0 - smoothstep(sliceWidth, sliceWidth + 0.01, dist));
    finalColor += vec3<f32>(0.5, 0.8, 1.0) * edge * 2.0;

    // Confidence alpha
    let confidence = length(a) * depthInfluence;
    finalAlpha = mix(0.8, 1.0, confidence);

  } else {
    finalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  }

  // Shadow outside slice
  if (inSlice < 1.0) {
    let shadow = smoothstep(sliceWidth, sliceWidth + 0.1, dist);
    finalColor *= (0.5 + 0.5 * shadow);
  }

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
