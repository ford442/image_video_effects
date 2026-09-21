// ═══════════════════════════════════════════════════════════════════
//  Spatio-Temporal 3D Convolution
//  Category: post-processing
//  Features: temporal, history-ring, advanced-convolution, audio-reactive,
//             upgraded-rgba, spatio-temporal
//  Complexity: High
//  Upgraded: 2026-09-21
//  Ideas: motion-adaptive temporal weights (NR mode); variance-driven NR strength
//  Floor: history ring wraps at textureNumLayers (8, 4 or 1), not a hardcoded 8
//  Requires: binding 13 (historyTexture — up to 8-layer ring buffer)
//  Created: 2026-05-23
//  By: Copilot
//
//  Implements 3×3×T spatio-temporal convolution as requested in the
//  Next-Gen Convolutions feature spec.  A 3×3 spatial kernel is
//  evaluated at each of T history frames, and the contributions are
//  blended according to a temporal weighting profile.
//
//  Three modes controlled by Param 3 (mode slider):
//    0.0 – 0.33 : TEMPORAL NOISE REDUCTION
//          Averages nearby frames (weighted by temporal distance).
//          Reduces flickering and sensor noise while preserving motion
//          better than a pure spatial blur.
//    0.33 – 0.67: MOTION BLUR
//          Exponentially accumulates past frames producing a smooth,
//          directional blur effect on fast-moving objects.
//    0.67 – 1.0 : TEMPORAL SHARPENING
//          Computes the temporal mean and subtracts it from the current
//          frame, then boosts the residual.  Emphasises transient
//          flashes, pops, and rapid changes while suppressing static
//          background.
//
//  zoom_params layout:
//    x = spatial kernel sigma (0→sharp 1px, 1→wide 3px, default 0.4)
//    y = temporal depth  (0→2 frames, 1→7 frames, default 0.5)
//    z = mode (0=denoise, 0.5=motion-blur, 1=sharpen, default 0.0)
//    w = effect strength (0→off, 1→full, default 0.7)
//
//  extraBuffer layout:
//    [0]=bass  [1]=mid  [2]=treble  [3]=reserved  [4]=historyHead
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
@group(0) @binding(13) var historyTexture: texture_2d_array<f32>;

struct Uniforms {
  config: vec4<f32>,      // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>, // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>, // x=spatialSigma, y=tempDepth, z=mode, w=strength
  ripples: array<vec4<f32>, 50>,
};


// ── 3×3 Gaussian spatial weights from sigma ──────────────────────────────────
fn gaussWeight(dx: f32, dy: f32, sigma: f32) -> f32 {
  let sig2 = sigma * sigma * 2.0 + 0.0001;
  return exp(-(dx * dx + dy * dy) / sig2);
}

// ── Apply spatial 3×3 convolution on a single history layer ──────────────────
fn spatialConv3x3(uv: vec2<f32>, pixSz: vec2<f32>, layer: i32, sigma: f32) -> vec4<f32> {
  var acc   = vec4<f32>(0.0);
  var totalW = 0.0;
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      let off = vec2<f32>(f32(dx), f32(dy)) * pixSz;
      let p   = clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0));
      let w   = gaussWeight(f32(dx), f32(dy), sigma);
      acc    += textureSampleLevel(historyTexture, u_sampler, p, layer, 0.0) * w;
      totalW += w;
    }
  }
  return acc / max(totalW, 0.001);
}

// ── Same for the current frame (readTexture) ─────────────────────────────────
fn spatialConv3x3Current(uv: vec2<f32>, pixSz: vec2<f32>, sigma: f32) -> vec4<f32> {
  var acc    = vec4<f32>(0.0);
  var totalW = 0.0;
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      let off = vec2<f32>(f32(dx), f32(dy)) * pixSz;
      let p   = clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0));
      let w   = gaussWeight(f32(dx), f32(dy), sigma);
      acc    += textureSampleLevel(readTexture, u_sampler, p, 0.0) * w;
      totalW += w;
    }
  }
  return acc / max(totalW, 0.001);
}

// ── Main ─────────────────────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res   = vec2<f32>(u.config.z, u.config.w);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

  let uv     = (vec2<f32>(global_id.xy) + 0.5) / res;
  let pixSz  = 1.0 / res;
  let bass   = plasmaBuffer[0].x;
  let treble = plasmaBuffer[0].z;

  let spatSigma = 0.3 + u.zoom_params.x * 2.7;          // 0.3–3.0
  let tempDepth = 2u + u32(u.zoom_params.y * 5.0);       // 2–7
  let mode      = u.zoom_params.z;                        // [0,1]
  let strength  = u.zoom_params.w * (1.0 + bass * 0.25); // audio-reactive

  let historyHead = u32(extraBuffer[4]);
  // Floor fix: the ring holds 8, 4 or 1 layers (VRAM probe) and the renderer
  // wraps its head at that count; HEAD assumed 8 and read clamped layers.
  let histDepth = max(textureNumLayers(historyTexture), 1u);
  let depthUsed = min(tempDepth, histDepth - 1u);
  let isNR      = mode < 0.33;

  // ── Current frame spatial ─────────────────────────────────────────────────
  let current = spatialConv3x3Current(uv, pixSz, spatSigma);
  let lumaW   = vec3<f32>(0.2126, 0.7152, 0.0722);
  let curLuma = dot(current.rgb, lumaW);

  // ── Accumulate spatio-temporal 3D convolution ─────────────────────────────
  var accumColor = vec4<f32>(0.0);
  var accumW     = 0.0;
  // Similarity-weighted luma moments for the noise estimate (idea 2),
  // seeded with the current frame at full weight.
  var statW  = 1.0;
  var statL  = curLuma;
  var statL2 = curLuma * curLuma;

  for (var age: u32 = 1u; age <= depthUsed; age = age + 1u) {
    let layer = i32((historyHead + histDepth - age) % histDepth);

    // Temporal weight depends on mode
    var tw = 0.0;
    if (mode < 0.33) {
      // Noise reduction: uniform average → decaying Gaussian
      tw = exp(-f32(age - 1u) * 0.4 * (1.0 + treble * 0.5));
    } else if (mode < 0.67) {
      // Motion blur: exponential accumulation favouring older frames slightly
      tw = pow(0.85, f32(age - 1u));
    } else {
      // Temporal sharpening: uniform weight for temporal mean computation
      tw = 1.0;
    }

    let spatialLayer = spatialConv3x3(uv, pixSz, layer, spatSigma);

    // ── Idea 1: motion-adaptive temporal weights (NR mode) ──────────────────
    // The defining failure of temporal noise reduction is ghosting: anything
    // that moved gets averaged with where it used to be. Weighting each frame
    // by its photometric similarity to the current one — a bilateral in
    // time — lets static detail average while moving objects keep only their
    // own recent frames. Motion-blur mode keeps its ghosts (they ARE that
    // effect) and sharpen mode keeps its full mean (it emphasises motion).
    let delta      = length(spatialLayer.rgb - current.rgb);
    let similarity = exp(-delta * delta / (2.0 * 0.07 * 0.07));
    let adaptive   = select(1.0, similarity, isNR);

    accumColor += spatialLayer * tw * adaptive;
    accumW     += tw * adaptive;

    let l = dot(spatialLayer.rgb, lumaW);
    statW  += similarity;
    statL  += l * similarity;
    statL2 += l * l * similarity;
  }
  // HEAD divided only when the weight was non-trivial and otherwise mixed
  // toward black; with similarity weights that can happen on real motion,
  // so fall back to the live frame.
  if (accumW > 0.001) { accumColor = accumColor / accumW; } else { accumColor = current; }

  // ── Idea 2: variance-driven NR strength ───────────────────────────────────
  // A real video denoiser estimates the noise before removing it. The
  // similarity-weighted temporal variance of luma (motion already excluded
  // by idea 1's weights) is that estimate; NR strength follows it, so the
  // averaging works hardest where there is actually noise to remove.
  let statMean = statL / statW;
  let noiseSigma = sqrt(max(statL2 / statW - statMean * statMean, 0.0));
  let nrGain = mix(0.35, 1.0, smoothstep(0.004, 0.03, noiseSigma));

  // ── Apply mode-specific operation ─────────────────────────────────────────
  var result: vec4<f32>;
  if (mode < 0.33) {
    // Temporal noise reduction: blend current with temporal mean
    result = mix(current, accumColor, clamp(strength * nrGain, 0.0, 1.0));
  } else if (mode < 0.67) {
    // Motion blur: blend current with accumulated trail
    result = mix(current, accumColor, strength * 0.8);
  } else {
    // Temporal sharpening: enhance residual (current - temporalMean)
    let residual = current - accumColor;
    result = current + residual * strength * 2.0;
    result = clamp(result, vec4<f32>(0.0), vec4<f32>(1.0));
  }

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, result);
}
