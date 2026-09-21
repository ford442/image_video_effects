// ═══════════════════════════════════════════════════════════════════
//  Optical Flow Tracer
//  Category: post-processing
//  Features: temporal, history-ring, audio-reactive, mouse-driven,
//             optical-flow, motion-vectors, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-21
//  Ideas: Shi-Tomasi confidence; pyramidal (coarse-to-fine) Lucas-Kanade
//  Floor: history ring wraps at textureNumLayers (8, 4 or 1), not a hardcoded 8
//  Requires: binding 13 (historyTexture — up to 8-layer ring buffer)
//  Created: 2026-05-23
//  By: Copilot
//
//  Implements Lucas-Kanade optical flow between the current frame and
//  the most recent history frame.  The estimated per-pixel motion
//  vector is used to warp the sample position into the history ring,
//  so after-images are physically dragged along the trajectory of
//  moving objects rather than fading in place.
//
//  Static regions: simple, clean frame.
//  Moving regions: ghost trail that follows the actual path of motion,
//                  progressively fading as it ages.
//
//  zoom_params layout:
//    x = trail decay  (0→fast, 1→slow, default 0.6)
//    y = flow scale   (0→subtle, 1→extreme, default 0.4)
//    z = trail age    (0→only age-1, 1→ages up to 5, default 0.5)
//    w = current blend (0→all trail, 1→all current, default 0.35)
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
  zoom_params: vec4<f32>, // x=decay, y=flowScale, z=trailAge, w=blend
  ripples: array<vec4<f32>, 50>,
};

// History ring depth is read at runtime (textureNumLayers) — the renderer
// may allocate 8, 4 or 1 layers and wraps its head at that count.
fn ringLayer(head: u32, age: u32, depth: u32) -> i32 {
  return i32((head + depth - min(age, depth - 1u)) % depth);
}

// Luminance helper
fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// ── Lucas-Kanade optical flow ─────────────────────────────────────
//  Estimates 2D velocity at `uv` comparing readTexture (current) against
//  the most recent history frame (age=1), over a (2·half+1)² window with
//  taps `stride` pixels apart. `prior` (pixels) pre-warps the previous
//  frame so a finer level only has to solve the residual. Returns
//  (flow in pixels, including prior; λmin of the structure tensor).
fn lucasKanade(uv: vec2<f32>, pixSz: vec2<f32>, prevLayer: i32,
               stride: f32, half: i32, prior: vec2<f32>) -> vec3<f32> {
  var Axx = 0.0; var Ayy = 0.0; var Axy = 0.0;
  var bx  = 0.0; var by  = 0.0;

  let tapStep = pixSz * stride;
  for (var dy = -half; dy <= half; dy++) {
    for (var dx = -half; dx <= half; dx++) {
      let off = vec2<f32>(f32(dx), f32(dy)) * tapStep;
      let p   = clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0));

      let cur  = luma(textureSampleLevel(readTexture, u_sampler, p, 0.0).rgb);
      let prev = luma(textureSampleLevel(historyTexture, u_sampler, clamp(p - prior * pixSz, vec2<f32>(0.0), vec2<f32>(1.0)), prevLayer, 0.0).rgb);

      // Spatial gradients from current frame (finite differences)
      let right = luma(textureSampleLevel(readTexture, u_sampler, clamp(p + vec2<f32>(tapStep.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
      let left  = luma(textureSampleLevel(readTexture, u_sampler, clamp(p - vec2<f32>(tapStep.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
      let down  = luma(textureSampleLevel(readTexture, u_sampler, clamp(p + vec2<f32>(0.0, tapStep.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
      let up    = luma(textureSampleLevel(readTexture, u_sampler, clamp(p - vec2<f32>(0.0, tapStep.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);

      let Ix = (right - left) * 0.5;
      let Iy = (down  - up)   * 0.5;
      let It = cur - prev;

      Axx += Ix * Ix;
      Ayy += Iy * Iy;
      Axy += Ix * Iy;
      bx  -= Ix * It;
      by  -= Iy * It;
    }
  }

  // ── Idea 1: Shi-Tomasi confidence ─────────────────────────────────
  // LK is only trustworthy where the structure tensor has TWO strong
  // eigenvalues. In flat regions both are tiny, and along a straight edge
  // one is (the aperture problem): the solve returns noise either way. The
  // smaller eigenvalue is the standard corner/confidence measure.
  let halfTrace = 0.5 * (Axx + Ayy);
  let lambdaMin = halfTrace - sqrt(max(0.25 * (Axx - Ayy) * (Axx - Ayy) + Axy * Axy, 0.0));

  let det = Axx * Ayy - Axy * Axy;
  if (abs(det) < 1e-6) { return vec3<f32>(prior, lambdaMin); }

  let residual = vec2<f32>(
    (Ayy * bx - Axy * by) / det,
    (Axx * by - Axy * bx) / det
  ) * stride;
  return vec3<f32>(prior + residual, lambdaMin);
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

  let decay      = 0.92 + u.zoom_params.x * 0.07;              // 0.92–0.99
  let flowScale  = (0.05 + u.zoom_params.y * 0.95) * (1.0 + bass * 0.3);
  let maxAge     = 1u + u32(u.zoom_params.z * 4.0);            // 1–5
  let blendAmt   = clamp(u.zoom_params.w * (1.0 - treble * 0.2), 0.0, 1.0);

  let historyHead = u32(extraBuffer[4]);
  let histDepth   = max(textureNumLayers(historyTexture), 1u);

  // Most-recent history layer (age 1)
  let prevLayer = ringLayer(historyHead, 1u, histDepth);

  // ── Idea 2: pyramidal (coarse-to-fine) Lucas-Kanade ───────────────
  // Single-level LK linearises the image, so it only sees motion of a
  // pixel or two — anything faster aliases to garbage, which is exactly
  // the motion a flow tracer exists to show. Solve first on a coarse 4px
  // stride (3x3 window, reaches ±4px), then run HEAD's 5x5 solve with the
  // previous frame pre-warped by that estimate, so it only has to find the
  // residual. The coarse prior is trusted only where its own λmin says so.
  var flow = vec2<f32>(0.0);
  if (histDepth > 1u) {
    let coarse   = lucasKanade(uv, pixSz, prevLayer, 4.0, 1, vec2<f32>(0.0));
    let coarseOk = smoothstep(0.002, 0.03, coarse.z);
    let prior    = clamp(coarse.xy * coarseOk, vec2<f32>(-8.0), vec2<f32>(8.0));
    let fine     = lucasKanade(uv, pixSz, prevLayer, 1.0, 2, prior);
    // Idea 1 applied: damp the flow where the fine tensor is not a corner.
    flow = fine.xy * smoothstep(0.0005, 0.01, fine.z);
  }

  // ── Accumulate warped-history trail ────────────────────────────────────────
  var trail     = vec4<f32>(0.0);
  var totalW    = 0.0;
  var warpedUV  = uv;
  let current   = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let trailAge  = min(maxAge, histDepth - 1u);

  for (var age: u32 = 1u; age <= trailAge; age = age + 1u) {
    // Warp UV backward along the flow vector for each additional age
    warpedUV = warpedUV - flow * flowScale * pixSz;
    warpedUV = clamp(warpedUV, vec2<f32>(0.0), vec2<f32>(1.0));

    let layer = ringLayer(historyHead, age, histDepth);
    let frame = textureSampleLevel(historyTexture, u_sampler, warpedUV, layer, 0.0);

    let t = f32(age) / f32(maxAge + 1u);
    let w = pow(decay, f32(age));
    trail   += frame * w;
    totalW  += w;
  }

  // A 1-layer ring has no usable past (the renderer skips its copy), so the
  // trail falls back to the live frame instead of blending toward black.
  if (totalW > 0.001) { trail = trail / totalW; } else { trail = current; }

  // ── Composite: blend trail with current ────────────────────────────────────
  let output   = mix(trail, current, blendAmt);
  let motionMag = length(flow) * flowScale * 20.0;
  let alpha     = clamp(motionMag * 2.0 + current.a * 0.5 + bass * 0.15, 0.0, 1.0);
  let finalOut  = vec4<f32>(output.rgb, alpha);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, finalOut);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(flow * flowScale, motionMag, 1.0));
}
