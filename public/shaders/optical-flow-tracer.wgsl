// ═══════════════════════════════════════════════════════════════════
//  Optical Flow Tracer
//  Category: post-processing
//  Features: temporal, history-ring, audio-reactive,
//             optical-flow, motion-vectors
//  Complexity: High
//  Upgraded: 2026-09-21, 2026-11-20, 2026-11-22
//  Ideas: Shi-Tomasi confidence; pyramidal (coarse-to-fine) Lucas-Kanade; Gaussian-weighted LK window (§12.1 tactic 1); temporal flow carry through C (§12.1 tactic 6); comet-tail taper with a continuous Trail Age (§12.1 tactic 4)
//  Rescue (2026-11-22): `upgraded-rgba` dropped (output is a passthrough photo composite and A is raw flow — no ACES by design)
//  A packing: raw flow field — A.xy = flow*flowScale (px), A.z = |flow|*flowScale*20, A.w = 1; read back raw via exact textureLoad(C) (Idea 4). Not ACES'd.
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

#include "_prelude.wgsl"
// zoom_params: x=decay, y=flowScale, z=trailAge, w=blend
@group(0) @binding(13) var historyTexture: texture_2d_array<f32>;

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
  var wsum = 0.0;

  // ── Idea 3: Gaussian-weighted LK window (§12.1 tactic 1) ──────────
  // A flat box counts a tap across a motion boundary as much as the centre, so flow leaks
  // past the rim of a moving object. Lucas-Kanade's own refinement is to weight the window
  // by a Gaussian (sigma = 0.8*half, 1.2 floor so the 3x3 coarse level keeps rank).
  let sig2 = max(0.8 * f32(half), 1.2) * max(0.8 * f32(half), 1.2);

  let tapStep = pixSz * stride;
  for (var dy = -half; dy <= half; dy++) {
    for (var dx = -half; dx <= half; dx++) {
      let gw  = exp(-0.5 * f32(dx * dx + dy * dy) / sig2);
      wsum += gw;
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

      Axx += gw * Ix * Ix;
      Ayy += gw * Iy * Iy;
      Axy += gw * Ix * Iy;
      bx  -= gw * Ix * It;
      by  -= gw * Iy * It;
    }
  }
  // Renormalise to the box's tap count so lambda-min (and every threshold below) keeps its calibration.
  let nrm = f32((2 * half + 1) * (2 * half + 1)) / max(wsum, 1e-3);
  Axx *= nrm; Ayy *= nrm; Axy *= nrm; bx *= nrm; by *= nrm;

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
  let ageF       = 1.0 + u.zoom_params.z * 4.0;                // 1–5, continuous (Idea 5)
  let maxAge     = u32(ceil(ageF));
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
    var prior    = clamp(coarse.xy * coarseOk, vec2<f32>(-8.0), vec2<f32>(8.0));

    // ── Idea 4: temporal flow carry through C (§12.1 tactic 6) ───────────────────
    // A already holds this shader's flow field (A.xy = flow*flowScale, A.w = 1) and C returns last
    // frame's copy untouched, yet LK starts from scratch every frame — so it only ever sees what
    // its linearisation can reach, and flickers with sensor noise. A tracker initialises from the
    // previous estimate (KLT): read last frame's flow where this content WAS (semi-Lagrangian,
    // coord - prior), undo the stored flowScale, and use it as the fine level's starting point
    // when it explains the live pixel better than the spatial prior does (+0.01 margin = hysteresis:
    // the carried velocity has to earn the switch). The fine solve still re-measures the residual
    // and the Shi-Tomasi gate below is untouched, so a stopped object's flow dies in a few frames.
    let prevPx   = clamp(coord - vec2<i32>(round(prior)), vec2<i32>(0), vec2<i32>(i32(res.x) - 1, i32(res.y) - 1));
    let prevC    = textureLoad(dataTextureC, prevPx, 0);
    let prevFlow = clamp(prevC.xy / max(flowScale, 0.05), vec2<f32>(-16.0), vec2<f32>(16.0));
    let curL     = luma(textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb);
    let errSpat  = abs(curL - luma(textureSampleLevel(historyTexture, u_sampler, clamp(uv - prior    * pixSz, vec2<f32>(0.0), vec2<f32>(1.0)), prevLayer, 0.0).rgb));
    let errTemp  = abs(curL - luma(textureSampleLevel(historyTexture, u_sampler, clamp(uv - prevFlow * pixSz, vec2<f32>(0.0), vec2<f32>(1.0)), prevLayer, 0.0).rgb));
    prior = select(prior, prevFlow, prevC.w > 0.5 && errTemp + 0.01 < errSpat);

    let fine     = lucasKanade(uv, pixSz, prevLayer, 1.0, 2, prior);
    // Idea 1 applied: damp the flow where the fine tensor is not a corner.
    flow = fine.xy * smoothstep(0.0005, 0.01, fine.z);
    // ... and a Kalman-style 35% inertia on top: only real motion is carried (leak-level flow is not
    // re-fed into the wake) and only while it still explains the live pixel.
    let errMeas  = abs(curL - luma(textureSampleLevel(historyTexture, u_sampler, clamp(uv - flow * pixSz, vec2<f32>(0.0), vec2<f32>(1.0)), prevLayer, 0.0).rgb));
    let explains = 1.0 - smoothstep(0.0, 0.04, errTemp - errMeas);
    flow = mix(flow, prevFlow, 0.35 * step(0.5, prevC.w) * smoothstep(0.5, 1.5, length(prevFlow)) * explains);
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

    // ── Idea 5: comet taper + continuous Trail Age (§12.1 tactic 4) ──────────────
    // `t` was computed here and never read: the taper it implied is now real. The streak thins
    // toward its tip instead of ending in a hard edge, and the last age enters with fractional
    // weight so the Trail Age slider grows the tail smoothly instead of in five stairs
    // (HEAD: maxAge = 1 + u32(z * 4), so z = 0.50 and z = 0.62 drew the same picture).
    let t = f32(age) / (ageF + 1.0);
    let w = pow(decay, f32(age)) * (1.0 - 0.6 * t) * clamp(ageF - f32(age) + 1.0, 0.0, 1.0);
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
