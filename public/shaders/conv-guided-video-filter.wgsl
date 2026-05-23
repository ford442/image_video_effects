// ═══════════════════════════════════════════════════════════════════
//  Guided Video Filter
//  Category: image
//  Features: advanced-convolution, edge-preserving, guided-filter,
//             mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-23
//  By: Copilot
//
//  Guided Image Filtering as described in the Next-Gen Convolutions
//  feature request:
//    Guide  = original crisp video frame (readTexture)
//    Input  = heavily processed / convoluted output from the previous
//             pass in the slot chain (dataTextureC)
//
//  Uses the guide's local linear model (He et al. 2013) to force the
//  smoothed output to respect the guide's edge structure, eliminating
//  the halo artifacts that ordinary bilateral/Gaussian blurs produce
//  when applied after artistic effects.
//
//  RGBA32FLOAT storage:
//    RGB — edge-guided reconstruction of dataTextureC
//    A   — |a| coefficient: high = strong edge guidance,
//           low = smooth region (encodes filter "confidence")
//
//  Mouse interaction:
//    Mouse proximity sharpens the filter (smaller radius, lower eps)
//    to create a live "focus magnifier" over processed content.
//
//  zoom_params layout:
//    x = filter radius  (0→radius 1, 1→radius 8, default 0.4)
//    y = epsilon        (0→very edge-sensitive, 1→smoother, default 0.3)
//    z = guide strength (0→pass-through, 1→fully guided, default 0.85)
//    w = mouse sharpening intensity (default 0.8)
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

// ── Guided filter over an (2r+1)×(2r+1) window ───────────────────────────────
//  Guide I = readTexture (original video luminance)
//  Input P = dataTextureC (processed content from prior pass)
//  Returns: (filtered_rgb, confidence)
fn guidedFilter(
    uv: vec2<f32>,
    pixSz: vec2<f32>,
    radius: i32,
    epsilon: f32
) -> vec4<f32> {
  var sumG   = 0.0;
  var sumP   = vec3<f32>(0.0);
  var sumGP  = vec3<f32>(0.0);
  var sumG2  = 0.0;
  var count  = 0.0;

  let r = min(radius, 8);
  for (var dy = -r; dy <= r; dy++) {
    for (var dx = -r; dx <= r; dx++) {
      let off  = vec2<f32>(f32(dx), f32(dy)) * pixSz;
      let p    = clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0));
      // Guide: luminance of original video
      let gRGB = textureSampleLevel(readTexture, u_sampler, p, 0.0).rgb;
      let g    = dot(gRGB, vec3<f32>(0.2126, 0.7152, 0.0722));
      // Input: processed frame
      let inp  = textureSampleLevel(dataTextureC, u_sampler, p, 0.0).rgb;

      sumG  += g;
      sumP  += inp;
      sumGP += inp * g;
      sumG2 += g * g;
      count += 1.0;
    }
  }

  let meanG  = sumG  / count;
  let meanP  = sumP  / count;
  let meanGP = sumGP / count;
  let meanG2 = sumG2 / count;
  let varG   = meanG2 - meanG * meanG;

  // Linear model: q = a*G + b
  let a = (meanGP - meanG * meanP) / (varG + epsilon);
  let b = meanP - a * meanG;

  // Evaluate at centre pixel
  let gCentre   = dot(textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb,
                      vec3<f32>(0.2126, 0.7152, 0.0722));
  let filtered  = a * gCentre + b;

  // Confidence: magnitude of a coefficient (edge guidance strength)
  let confidence = clamp(length(a) * 2.0, 0.0, 1.0);

  return vec4<f32>(filtered, confidence);
}

// ── Main ─────────────────────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res   = u.config.zw;
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

  let uv      = (vec2<f32>(global_id.xy) + 0.5) / res;
  let pixSz   = 1.0 / res;
  let time    = u.config.x;
  let bass    = plasmaBuffer[0].x;
  let mouse   = u.zoom_config.yz;

  // Parameters
  let radBase   = 1 + i32(u.zoom_params.x * 7.0);
  let epsBase   = mix(0.0002, 0.08, u.zoom_params.y);
  let guideStr  = u.zoom_params.z;
  let mouseStr  = u.zoom_params.w;

  // Mouse proximity sharpens: smaller radius, lower epsilon
  let mDist   = length(uv - mouse);
  let mFactor = exp(-mDist * mDist * 10.0) * mouseStr;
  let radius  = max(1, i32(mix(f32(radBase), 1.0, mFactor)));
  let epsilon = mix(epsBase, epsBase * 0.05, mFactor) * (1.0 - bass * 0.2);

  // Run guided filter
  let result = guidedFilter(uv, pixSz, radius, epsilon);

  // Input (processed) and original
  let processed = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
  let original  = textureSampleLevel(readTexture,  u_sampler, uv, 0.0).rgb;

  // Mix filtered result with processed content based on guide strength
  let finalRGB  = mix(processed, result.rgb, guideStr);
  let confidence = result.a;

  textureStore(writeTexture, coord, vec4<f32>(finalRGB, confidence));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(finalRGB, confidence));
}
