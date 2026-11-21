// ═══════════════════════════════════════════════════════════════════
//  Guided Video Filter
//  Category: image
//  Features: advanced-convolution, edge-preserving, guided-filter,
//             mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-08, 2026-11-21
//  Ideas: depth-augmented guide; exact integer C loads for P; edge-aware ε weighting (weighted guided filter Γ, §12.2A); guide-gated anti-halo envelope (§12.2A)
//  A packing: pre-ACES guided colour state + confidence α (ACES on writeTexture only)
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
//    writeTexture RGB — ACES display of the edge-guided reconstruction
//    dataTextureA RGB — the same reconstruction BEFORE ACES (state read back as
//                       P next frame; storing the tone-mapped value made a
//                       self-fed run contract to flat grey 0.728)
//    A   — |a| coefficient: high = strong edge guidance,
//           low = smooth region (encodes filter "confidence")
//
//  Empty previous pass (dataTextureC all zero: slot 1 / first frame): P falls
//  back to the source frame, i.e. the classic self-guided edge-preserving
//  smoother, instead of the old black-forever output.
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

#include "_prelude.wgsl"

// ── Guided filter over an (2r+1)×(2r+1) window ───────────────────────────────
//  Guide I = readTexture (original video luminance)
//  Input P = dataTextureC (processed content from prior pass)
//  Returns: (filtered_rgb, confidence)
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn guidedFilter(
    uv: vec2<f32>,
    pixSz: vec2<f32>,
    radius: i32,
    epsilon: f32,
    cDims: vec2<i32>
) -> vec4<f32> {
  var sumG   = 0.0;
  var sumP   = vec3<f32>(0.0);
  var sumGP  = vec3<f32>(0.0);
  var sumG2  = 0.0;
  var count  = 0.0;

  // Centre guide, hoisted above the loop: the range envelope (Idea 2) gates on it.
  let gCentreLuma = dot(textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb,
                      vec3<f32>(0.2126, 0.7152, 0.0722));
  let gCentreDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let gCentre = mix(gCentreLuma, gCentreDepth, 0.35);

  // Idea 1 accumulators: the 3×3 sub-window of the SAME taps (no extra fetches).
  var sumG3  = 0.0;
  var sumG32 = 0.0;
  // Idea 2 accumulators: P range over the taps on the centre pixel's side of an edge.
  let tau  = clamp(2.0 * sqrt(epsilon), 0.06, 0.30);
  var minP = vec3<f32>(1e9);
  var maxP = vec3<f32>(-1e9);

  // Rescue: an empty previous pass (C all zero here: slot 1 / first frame) used to give
  // P = 0 → black forever. Decided once per pixel: P falls back to the source frame.
  let cC0 = textureLoad(dataTextureC, clamp(vec2<i32>(uv * vec2<f32>(cDims)), vec2<i32>(0), cDims - vec2<i32>(1)), 0);
  let useSrc = max(max(cC0.r, cC0.g), max(cC0.b, cC0.a)) <= 1e-5;

  let r = min(radius, 8);
  for (var dy = -r; dy <= r; dy++) {
    let rowIn = f32(abs(dy) <= 1);
    for (var dx = -r; dx <= r; dx++) {
      let off  = vec2<f32>(f32(dx), f32(dy)) * pixSz;
      let p    = clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0));
      let gRGB = textureSampleLevel(readTexture, u_sampler, p, 0.0).rgb;
      let gLuma = dot(gRGB, vec3<f32>(0.2126, 0.7152, 0.0722));
      let gDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, p, 0.0).r;
      let g = mix(gLuma, gDepth, 0.35);
      let ic = clamp(vec2<i32>(p * vec2<f32>(cDims)), vec2<i32>(0), cDims - vec2<i32>(1));
      // P = exact integer C load (or the already-fetched source tap when C is empty).
      let inp  = select(textureLoad(dataTextureC, ic, 0).rgb, gRGB, useSrc);

      sumG  += g;
      sumP  += inp;
      sumGP += inp * g;
      sumG2 += g * g;
      count += 1.0;

      // ── Idea 1: 3×3 guide moments for the edge-aware ε (weighted guided filter) ──
      let in3 = rowIn * f32(abs(dx) <= 1);
      sumG3  += g * in3;
      sumG32 += g * g * in3;

      // ── Idea 2: P extrema over the taps whose guide is on the centre's side of the edge ──
      let sameSide = abs(g - gCentre) < tau;
      minP = min(minP, select(vec3<f32>(1e9), inp, sameSide));
      maxP = max(maxP, select(vec3<f32>(-1e9), inp, sameSide));
    }
  }

  let meanG  = sumG  / max(count, 1.0);
  let meanP  = sumP  / max(count, 1.0);
  let meanGP = sumGP / max(count, 1.0);
  let meanG2 = sumG2 / max(count, 1.0);
  let varG   = meanG2 - meanG * meanG;

  // ── Idea 1: edge-aware ε weighting (Li et al. 2015 weighted guided filter) ──
  // Γ = (σ₃·σ_R + λ)/(χ_ref + λ): large on true edges (both the 3×3 and the whole
  // window see contrast), small in flat or noise-only areas. ε_eff = ε/Γ — flats
  // smooth harder (up to ε×2), edges hold (ε/4, a → 1). The eps slider stays the
  // base regulariser. χ_ref is the flat/noise level the paper's image-wide mean
  // reduces to (it is dominated by flat pixels), so Γ ≈ 1 on ordinary flats.
  let meanG3 = sumG3 / 9.0;
  let sd3    = sqrt(max(sumG32 / 9.0 - meanG3 * meanG3, 0.0));
  let sdR    = sqrt(max(varG, 0.0));
  let gammaW = clamp((sd3 * sdR + 1e-5) / (0.0012 + 1e-5), 0.5, 4.0);
  let epsEff = epsilon / gammaW;

  // Linear model: q = a*G + b
  let a = (meanGP - meanG * meanP) / (varG + epsEff);
  let b = meanP - a * meanG;

  // Evaluate at centre pixel
  var filtered = a * gCentre + b;

  // ── Idea 2: guide-gated anti-halo envelope ──
  // q = a·G + b extrapolates past P's own range where guide contrast exceeds the
  // input's — the overshoot ring around strong edges. Bound it by the extrema of P
  // on the pixel's own side of the edge, plus a little headroom that grows with ε.
  let allow = 0.01 + 0.5 * epsilon;
  filtered = clamp(filtered, minP - vec3<f32>(allow), maxP + vec3<f32>(allow));

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
  let mids    = plasmaBuffer[0].y;
  let mouse   = u.zoom_config.yz;
  let cDims   = vec2<i32>(textureDimensions(dataTextureC));

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
  let result = guidedFilter(uv, pixSz, radius, epsilon, cDims);

  let cCentre   = textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), cDims - vec2<i32>(1)), 0);
  let original  = textureSampleLevel(readTexture,  u_sampler, uv, 0.0);
  // Same empty-previous-pass fallback as the filter window (source frame stands in for P).
  let cHas      = max(max(cCentre.r, cCentre.g), max(cCentre.b, cCentre.a)) > 1e-5;
  let processed = select(original.rgb, cCentre.rgb, cHas);

  // Clamp before ACES: a·G+b can dip negative and the catalog ACES fit maps negatives bright.
  let guidedLin = max(result.rgb * (1.0 + mids * 0.15), vec3<f32>(0.0));
  let guidedRGB = acesToneMap(guidedLin);
  let finalRGB  = mix(processed, guidedRGB, guideStr);
  let confidence = clamp(result.a * 0.75 + original.a * 0.25, 0.0, 1.0);

  // Display keeps HEAD's formula. The state fed back as P next frame is the
  // reconstruction BEFORE ACES — re-reading the tone-mapped value contracted a
  // self-fed run to ACES's fixed point (flat grey 0.728).
  let stateRGB = mix(processed, guidedLin, guideStr);

  textureStore(writeTexture, coord, vec4<f32>(finalRGB, confidence));
  textureStore(dataTextureA, coord, vec4<f32>(stateRGB, confidence));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
