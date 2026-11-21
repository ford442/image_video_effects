// ═══════════════════════════════════════════════════════════════════
//  Dimension Slicer Guided
//  Category: advanced-hybrid
//  Features: dimensional-slice, guided-filter, depth-aware, edge-preserving, mouse-driven, upgraded-rgba
//  Complexity: Very High
//  Upgraded: 2026-11-21
//  Ideas: depth-snapped rift edge; aberration along the rift normal
//  A packing: ACES display RGBA
//  Chunks From: dimension-slicer, conv-guided-filter-depth
//  Created: 2026-04-18
// ═══════════════════════════════════════════════════════════════════
//  Dimensional rift slicer combined with depth-aware guided filtering.
//  The slice uses edge-preserving filtering guided by depth, creating
//  clean dimensional cuts that respect object boundaries. Inside the
//  slice, space is warped with chromatic aberration and depth-aware
//  blur that perfectly follows depth discontinuities.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let c = cos(angle);
  let s = sin(angle);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
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

  // Coordinate relative to mouse
  var p = uv - mouse;
  p.x *= aspect;
  let pRot = rotate(p, angle);
  let dist = abs(pRot.x);
  // ── Idea 1: depth-snapped rift edge ──────────────────────────────
  // The slab is still the rotated cut. Where the depth the guide
  // already trusts changes fast, the lip steps out onto that silhouette.
  // Flat depth leaves snap at zero, so the geometric cut is unchanged.
  let px = 1.0 / dims;
  let depthC = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthDx = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv + vec2<f32>(px.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r
              - textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv - vec2<f32>(px.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let depthDy = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv + vec2<f32>(0.0, px.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r
              - textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv - vec2<f32>(0.0, px.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let snap = smoothstep(0.015, 0.12, length(vec2<f32>(depthDx, depthDy))) * sliceWidth * 0.7;
  let cutDist = max(dist - snap, 0.0);
  let inSlice = 1.0 - smoothstep(sliceWidth - 0.01, sliceWidth, cutDist);

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
  var confidence = 0.0;
  let srcPx = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let edge = smoothstep(sliceWidth - 0.02, sliceWidth, cutDist) * (1.0 - smoothstep(sliceWidth, sliceWidth + 0.01, cutDist));

  if (inSlice > 0.0) {
    // Warp UVs inside slice. cutDist equals dist wherever the snap is zero.
    let zoom = 1.0 - distortion * 0.5 * cos(cutDist / max(sliceWidth, 1e-3) * 3.14159);
    let offset = (uv - mouse) * (1.0 / max(zoom, 1e-3) - 1.0);
    let warpedUV = clamp(uv + offset * inSlice, vec2<f32>(0.0), vec2<f32>(1.0));

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

    let meanGuide = sumGuide / max(count, 1.0);
    let meanInput = sumInput / max(count, 1.0);
    let meanGI = sumGuideInput / max(count, 1.0);
    let meanGuide2 = sumGuide2 / max(count, 1.0);
    let varGuide = meanGuide2 - meanGuide * meanGuide;

    let a = (meanGI - meanGuide * meanInput) / (varGuide + epsilon);
    let b = meanInput - a * meanGuide;

    let guide = textureSampleLevel(readDepthTexture, non_filtering_sampler, warpedUV, 0.0).r + rippleDepth * 0.1;
    let filtered = a * guide + b;

    // ── Idea 2: aberration along the rift normal ─────────────────────
    // The offset length is still Aberration. Its direction is the slab
    // axis Angle already builds, not screen X.
    let rift = vec2<f32>(cos(angle) / max(aspect, 1e-3), sin(angle));
    let riftDir = rift / max(length(rift), 1e-4);
    let aberrStep = riftDir * aberration * inSlice;
    let r = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + aberrStep, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = filtered.g;
    let bChan = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV - aberrStep, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    finalColor = vec3<f32>(r, g, bChan);

    // Mix between guided result and original based on depth influence
    let original = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0).rgb;
    finalColor = mix(original, finalColor, depthInfluence);

    // Glowing edge — follows the snapped lip
    finalColor += vec3<f32>(0.5, 0.8, 1.0) * edge * 2.0;

    confidence = length(a) * depthInfluence;

  } else {
    finalColor = srcPx.rgb;
  }

  // Shadow outside slice, on the snapped lip
  if (inSlice < 1.0) {
    let shadow = smoothstep(sliceWidth, sliceWidth + 0.1, cutDist);
    finalColor *= (0.5 + 0.5 * shadow);
  }

  let display = aces(max(finalColor, vec3<f32>(0.0)));
  let alpha = clamp(srcPx.a * mix(0.92, 1.0, inSlice) + clamp(confidence, 0.0, 1.0) * inSlice * 0.08 + edge * 0.25, 0.0, 1.0);
  let outColor = vec4<f32>(display, alpha);
  textureStore(writeTexture, vec2<i32>(global_id.xy), outColor);
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthC, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), outColor);
}
