// ═══════════════════════════════════════════════════════════════════
//  PP Sharpen
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-09-06, 2026-09-21, 2026-11-09
//  A packing: pre-tonemap linear RGB + semantic alpha (C history)
//  Motion: interactive clarity lens + traveling sharpness wavefronts
//  Ideas (2026-09-21): anti-halo overshoot clamp; luminance-only sharpening
//         (both on the photographic modes 0/1; mode 2 untouched)
//  Ideas (2026-11-09): clarity band (4x-radius midtone local contrast);
//         tonal protection (no sharpening in deep shadow / clipped highlight)
//  Rescues (2026-11-09): (SDR shoulder replaces ACES re-grade; lens gated on
//         hold; dead extraBuffer spring removed)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Amount, y=Radius, z=EdgeThreshold, w=Mode

// HEAD ran the full ACES fit over an SDR photo: whites landed at 0.80 and
// mids were lifted (0.18 -> 0.27), a re-grade on a utility filter. Keep
// SDR identity below 0.8 and roll only overshoot into a soft shoulder.
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let v = max(x, vec3<f32>(0.0));
  let over = max(v - vec3<f32>(0.8), vec3<f32>(0.0));
  return min(v, vec3<f32>(0.8)) + 0.2 * over / (over + vec3<f32>(0.2));
}

fn getLuma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let invRes = 1.0 / dims;
  let aspect = dims.x / max(dims.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let binA = plasmaBuffer[3].x;

  // HEAD kept a spring cursor in extraBuffer[133..138]; that range is
  // re-uploaded (zeroed) every frame so it never persisted. Use the cursor.
  let spring = mouse;

  // Four saved controls preserved
  let amountParam = u.zoom_params.x;
  let radiusParam = u.zoom_params.y;
  let edgeThreshold = mix(0.02, 0.35, u.zoom_params.z);
  let mode = u.zoom_params.w;

  // Depth sampling
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthScale = mix(0.6, 1.4, depth);

  // Proximity to spring inspection lens
  let distMouse = length((uv - spring) * aspectVec);
  // Idle cursor parks at the centre; the lens only exists while held.
  let lensInfluence = smoothstep(0.40, 0.04, distMouse) * select(0.0, 1.5, held);

  // Click ripple wavefronts that trigger traveling clarity surges
  var rippleSurge = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age > 0.0 && age < 2.2) {
      let d = length((uv - r.xy) * aspectVec);
      let ring = exp(-abs(d - age * 0.48) * 36.0) * exp(-age * 1.5);
      rippleSurge += ring;
    }
  }

  // Effective sharpen amount boosted by lens, ripples, and treble
  let effectiveAmount = mix(0.2, 2.8, amountParam) * (1.0 + lensInfluence * 0.65 + rippleSurge * 0.8 + treble * 0.45);
  let effectiveRadius = (0.5 + radiusParam * 2.0) * invRes * depthScale;

  // Center sample
  let centerCol = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let centerLuma = getLuma(centerCol);

  // 8-tap Gaussian / Bilateral blur kernel
  let offsets = array<vec2<f32>, 8>(
    vec2<f32>(-1.0, -1.0), vec2<f32>(0.0, -1.0), vec2<f32>(1.0, -1.0),
    vec2<f32>(-1.0,  0.0),                       vec2<f32>(1.0,  0.0),
    vec2<f32>(-1.0,  1.0), vec2<f32>(0.0,  1.0), vec2<f32>(1.0,  1.0)
  );
  let spatialWeights = array<f32, 8>(
    0.075, 0.15, 0.075,
    0.15,        0.15,
    0.075, 0.15, 0.075
  );

  var blurCol = vec3<f32>(0.0);
  var totalWeight = 0.0;
  var maxGradient = 0.0;
  var minLuma = centerLuma;
  var maxLuma = centerLuma;

  for (var k = 0; k < 8; k = k + 1) {
    let tapUV = clamp(uv + offsets[k] * effectiveRadius, vec2<f32>(0.0), vec2<f32>(1.0));
    let tapCol = textureSampleLevel(readTexture, u_sampler, tapUV, 0.0).rgb;
    let tapLuma = getLuma(tapCol);
    let diff = abs(centerLuma - tapLuma);
    maxGradient = max(maxGradient, diff);
    minLuma = min(minLuma, tapLuma);
    maxLuma = max(maxLuma, tapLuma);

    // Range weight to prevent haloing around high-contrast edges
    let rangeWeight = exp(-diff * diff / (2.0 * edgeThreshold * edgeThreshold + 0.001));
    let w = spatialWeights[k] * rangeWeight;
    blurCol += tapCol * w;
    totalWeight += w;
  }
  blurCol = blurCol / max(totalWeight, 1e-4);

  // ── Idea 3: clarity band ──────────────────────────────────────────
  // A second, wider (4x radius) ring gives a mid-frequency local-contrast
  // band — Lightroom-style "Clarity". It is weighted to the midtones so it
  // adds punch to texture and form without crunching skies or shadows.
  var wideCol = vec3<f32>(0.0);
  for (var k = 0; k < 8; k = k + 1) {
    let wUV = clamp(uv + offsets[k] * effectiveRadius * 4.0, vec2<f32>(0.0), vec2<f32>(1.0));
    wideCol += textureSampleLevel(readTexture, u_sampler, wUV, 0.0).rgb * spatialWeights[k];
  }
  wideCol = wideCol / 0.9;
  let midWeight = smoothstep(0.08, 0.35, centerLuma) * (1.0 - smoothstep(0.65, 0.92, centerLuma));
  let clarity = getLuma(blurCol - wideCol) * midWeight * amountParam * 0.9 * (1.0 + mids * 0.3);

  // High-pass detail vector
  let highPass = centerCol - blurCol;
  let edgeStrength = maxGradient;
  let edgeMask = smoothstep(edgeThreshold * 0.5, edgeThreshold * 1.5, edgeStrength);

  var sharpened = centerCol;

  if (mode < 0.33) {
    // Mode 0: Film Unsharp Mask with soft-knee coring to suppress noise in flat areas
    let coring = smoothstep(0.005, 0.04, abs(getLuma(highPass)));
    sharpened = centerCol + highPass * effectiveAmount * coring;
  } else if (mode < 0.66) {
    // Mode 1: Anisotropic Edge Enhance - boost edges without flattening midtones
    let boost = edgeMask * effectiveAmount * (1.0 + mids * 0.4);
    sharpened = mix(centerCol, centerCol + highPass * (1.0 + boost), edgeMask);
  } else {
    // Mode 2: High-Frequency Laplacian Detail with holographic edge pop
    let pop = smoothstep(0.0, 0.25, length(highPass)) * highPass;
    let edgeNeon = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + time * 2.0 + binA * 3.0);
    sharpened = centerCol + pop * effectiveAmount * 2.0 + edgeNeon * edgeMask * rippleSurge * 0.35;
  }

  if (mode < 0.66) {
    // ── Idea 2: luminance-only sharpening ─────────────────────────────
    // Sharpening R, G and B independently amplifies colour noise and puts
    // coloured fringes on saturated edges. The detail is re-applied as a
    // luma delta added equally to all three channels, keeping the pixel's
    // own chroma — what "sharpen on luminosity" means to a photographer.
    //
    // ── Idea 1: anti-halo overshoot clamp ─────────────────────────────
    // The tell-tale of bad sharpening is the bright/dark halo either side of
    // an edge, where the result overshoots anything actually in the
    // neighbourhood. That sharpened luma is clamped to the min/max envelope
    // of the 3x3 taps the kernel has already fetched, plus a little room,
    // so edges get crisper without ringing.
    let haloRoom = 0.015 + amountParam * 0.03;
    let clampedLuma = clamp(getLuma(sharpened), minLuma - haloRoom, maxLuma + haloRoom);
    sharpened = centerCol + vec3<f32>(clampedLuma - centerLuma);

    // ── Idea 4: tonal protection ──────────────────────────────────────
    // Noise lives in the deep shadows and detail is gone in clipped
    // highlights; sharpening either only amplifies grain or grey fringes.
    // The luma delta is faded out at both tonal ends.
    let tonalGuard = smoothstep(0.02, 0.12, centerLuma) * (1.0 - smoothstep(0.9, 0.99, centerLuma));
    sharpened = centerCol + (sharpened - centerCol) * tonalGuard + vec3<f32>(clarity);
  }

  // Exact previous frame history load from dataTextureC for temporal anti-jitter
  let hist = textureLoad(dataTextureC, coord, 0);
  let feedbackWeight = mix(0.05, 0.22, clamp(1.0 - edgeMask + bass * 0.2, 0.0, 1.0));
  var hdr = mix(sharpened, hist.rgb, feedbackWeight);

  let finalRGB = acesToneMap(hdr);
  let semanticAlpha = clamp(0.85 + edgeMask * 0.12 + rippleSurge * 0.25, 0.0, 1.0);
  let outCol = vec4<f32>(finalRGB, semanticAlpha);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, vec4<f32>(hdr, semanticAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth + edgeMask * 0.08, 0.0, 1.0), 0.0, 0.0, 0.0));
}
