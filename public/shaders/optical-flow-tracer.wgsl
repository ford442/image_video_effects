// ═══════════════════════════════════════════════════════════════════
//  Optical Flow Tracer
//  Category: post-processing
//  Features: temporal, history-ring, audio-reactive, mouse-driven,
//             optical-flow, motion-vectors, upgraded-rgba
//  Complexity: High
//  Requires: binding 13 (historyTexture — HISTORY_DEPTH=8 ring buffer)
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

const HISTORY_DEPTH: u32 = 8u;

// Luminance helper
fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// ── Lucas-Kanade optical flow ─────────────────────────────────────
//  Estimates 2D velocity at `uv` using a 5×5 window comparing
//  readTexture (current) vs the most recent history frame (age=1).
fn lucasKanade(uv: vec2<f32>, pixSz: vec2<f32>, prevLayer: i32) -> vec2<f32> {
  var Axx = 0.0; var Ayy = 0.0; var Axy = 0.0;
  var bx  = 0.0; var by  = 0.0;

  let HALF = 2;
  for (var dy = -HALF; dy <= HALF; dy++) {
    for (var dx = -HALF; dx <= HALF; dx++) {
      let off = vec2<f32>(f32(dx), f32(dy)) * pixSz;
      let p   = clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0));

      let cur  = luma(textureSampleLevel(readTexture, u_sampler, p, 0.0).rgb);
      let prev = luma(textureSampleLevel(historyTexture, u_sampler, p, prevLayer, 0.0).rgb);

      // Spatial gradients from current frame (finite differences)
      let right = luma(textureSampleLevel(readTexture, u_sampler, clamp(p + vec2<f32>(pixSz.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
      let left  = luma(textureSampleLevel(readTexture, u_sampler, clamp(p - vec2<f32>(pixSz.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
      let down  = luma(textureSampleLevel(readTexture, u_sampler, clamp(p + vec2<f32>(0.0, pixSz.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
      let up    = luma(textureSampleLevel(readTexture, u_sampler, clamp(p - vec2<f32>(0.0, pixSz.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);

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

  let det = Axx * Ayy - Axy * Axy;
  if (abs(det) < 1e-6) { return vec2<f32>(0.0); }

  return vec2<f32>(
    (Ayy * bx - Axy * by) / det,
    (Axx * by - Axy * bx) / det
  );
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

  // Most-recent history layer (age 1)
  let prevLayer = i32((historyHead + HISTORY_DEPTH - 1u) % HISTORY_DEPTH);

  // Compute optical flow at this pixel
  let flow = lucasKanade(uv, pixSz, prevLayer);

  // ── Accumulate warped-history trail ────────────────────────────────────────
  var trail     = vec4<f32>(0.0);
  var totalW    = 0.0;
  var warpedUV  = uv;

  for (var age: u32 = 1u; age <= maxAge; age = age + 1u) {
    // Warp UV backward along the flow vector for each additional age
    warpedUV = warpedUV - flow * flowScale * pixSz;
    warpedUV = clamp(warpedUV, vec2<f32>(0.0), vec2<f32>(1.0));

    let layer = i32((historyHead + HISTORY_DEPTH - age) % HISTORY_DEPTH);
    let frame = textureSampleLevel(historyTexture, u_sampler, warpedUV, layer, 0.0);

    let t = f32(age) / f32(maxAge + 1u);
    let w = pow(decay, f32(age));
    trail   += frame * w;
    totalW  += w;
  }

  if (totalW > 0.001) { trail = trail / totalW; }

  // ── Current frame ─────────────────────────────────────────────────────────
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

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
