// ═══════════════════════════════════════════════════════════════════
//  Temporal Decay Multiresolution
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, temporal, history-ring, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-23
//  Requires: binding 13 (historyTexture — HISTORY_DEPTH=8 ring buffer)
//  Created: 2026-05-23
//  By: Copilot
//
//  Sibling of sim-decay-system-rgba. Maps the four output channels
//  to four distinct temporal timescales pulled from the history ring:
//    R = fast   (avg of ages 1–2): recent flickers and fast motion
//    G = medium (avg of ages 4–5): medium-speed movement
//    B = slow   (age 7):           slow drift and near-static regions
//    A = ultra  (avg of all 7):    scene-level accumulated luminance
//  Per-channel decay constants let each timescale fade independently.
//  Stacks cleanly behind sim-decay-system-rgba in slot 0 → slot 1.
//
//  zoom_params layout:
//    x = fast-decay  rate (0→0.82, 1→0.97, default 0.5→0.895)
//    y = medium-decay rate (0→0.88, 1→0.98, default 0.5→0.93)
//    z = slow-decay   rate (0→0.93, 1→0.99, default 0.5→0.96)
//    w = blend with original (0→full multiRes, 1→original, default 0.3)
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
  zoom_params: vec4<f32>, // x=fastDecay, y=medDecay, z=slowDecay, w=origBlend
  ripples: array<vec4<f32>, 50>,
};

const HISTORY_DEPTH: u32 = 8u;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res   = vec2<f32>(u.config.z, u.config.w);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Make the advertised mouse interaction real: a critically damped temporal
  // lens follows the pointer using only persistent-safe slots [133..138].
  let rawMouse = u.zoom_config.yz;
  let hasSpringState = arrayLength(&extraBuffer) > 138u;
  var mouse = rawMouse;
  if (hasSpringState && extraBuffer[138] > 0.5) {
    mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (global_id.x == 0u && global_id.y == 0u && hasSpringState) {
    var springPos = mouse;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      springPos = rawMouse;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 7.0;
      let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[133] = springPos.x;
    extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  let aspect = res.x / max(res.y, 0.001);
  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let mouseLens = 1.0 - smoothstep(0.08, 0.42, mouseDist);

  // Clicks launch temporal echo rings that briefly refract the history lookup.
  var clickEcho = 0.0;
  var clickWarp = vec2<f32>(0.0);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri++) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    let safeAge = max(age, 0.0);
    let live = step(0.0, age) * (1.0 - step(1.8, age));
    let rv = (uv - rp.xy) * vec2<f32>(aspect, 1.0);
    let rd = length(rv);
    let ring = 1.0 - smoothstep(0.012, 0.045, abs(rd - safeAge * 0.34));
    let echo = ring * exp(-safeAge * 1.5) * live;
    let radial = select(vec2<f32>(0.0), rv / max(rd, 0.0001), rd > 0.0001);
    clickWarp += vec2<f32>(radial.x / aspect, radial.y) * echo * 0.018;
    clickEcho = max(clickEcho, echo);
  }
  let historyUV = clamp(mouse + (uv - mouse) * (1.0 - mouseLens * 0.035) + clickWarp, vec2<f32>(0.0), vec2<f32>(1.0));

  // Per-channel decay rates; bass lengthens the fast-decay trail on beats
  let regionBin = (u32(floor(uv.x * 4.0)) + u32(floor(uv.y * 4.0)) * 5u) % 8u + 1u;
  let fftRegion = plasmaBuffer[regionBin].x;
  let decayFast   = clamp(0.82 + u.zoom_params.x * 0.15 + bass * 0.05 + fftRegion * 0.01, 0.0, 0.999);
  let decayMedium = clamp(0.88 + u.zoom_params.y * 0.10 + mids * 0.02 + fftRegion * 0.008, 0.0, 0.999);
  let decaySlow   = clamp(0.93 + u.zoom_params.z * 0.06 + treble * 0.006, 0.0, 0.999);
  let origBlend   = u.zoom_params.w;

  let historyHead = u32(extraBuffer[4]);
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // ── Fast timescale (R): average of ages 1–2 ──────────────────────────────
  let l1 = (historyHead + HISTORY_DEPTH - 1u) % HISTORY_DEPTH;
  let l2 = (historyHead + HISTORY_DEPTH - 2u) % HISTORY_DEPTH;
  let h1 = textureSampleLevel(historyTexture, u_sampler, historyUV, i32(l1), 0.0);
  let h2 = textureSampleLevel(historyTexture, u_sampler, historyUV, i32(l2), 0.0);
  let fastAvg = (h1 + h2) * 0.5;

  // ── Medium timescale (G): average of ages 4–5 ────────────────────────────
  let l4 = (historyHead + HISTORY_DEPTH - 4u) % HISTORY_DEPTH;
  let l5 = (historyHead + HISTORY_DEPTH - 5u) % HISTORY_DEPTH;
  let h4 = textureSampleLevel(historyTexture, u_sampler, historyUV, i32(l4), 0.0);
  let h5 = textureSampleLevel(historyTexture, u_sampler, historyUV, i32(l5), 0.0);
  let medAvg = (h4 + h5) * 0.5;

  // ── Slow timescale (B): age 7 (oldest reliable frame) ────────────────────
  let l7 = (historyHead + HISTORY_DEPTH - 7u) % HISTORY_DEPTH;
  let h7 = textureSampleLevel(historyTexture, u_sampler, historyUV, i32(l7), 0.0);

  // ── Ultra-slow timescale: full average of all 7 stored frames ────────────
  var ultraSum = vec4<f32>(0.0);
  for (var age: u32 = 1u; age <= 7u; age = age + 1u) {
    let l = (historyHead + HISTORY_DEPTH - age) % HISTORY_DEPTH;
    ultraSum += textureSampleLevel(historyTexture, u_sampler, historyUV, i32(l), 0.0);
  }
  let ultraAvg = ultraSum / 7.0;

  // ── Per-channel max(current, decayed_history) ─────────────────────────────
  let r = max(current.r, fastAvg.r   * decayFast);
  let g = max(current.g, medAvg.g    * decayMedium);
  let b = max(current.b, h7.b        * decaySlow);
  // Alpha channel encodes ultra-slow luminance (useful for downstream slots)
  let a = (ultraAvg.r + ultraAvg.g + ultraAvg.b) / 3.0;

  let multiRes = vec4<f32>(r, g, b, a);
  let localOrigBlend = clamp(origBlend - mouseLens * 0.15 - clickEcho * 0.25, 0.0, 1.0);
  let output   = mix(multiRes, current, localOrigBlend);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, output);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, output);
}
