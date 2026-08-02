// ═══════════════════════════════════════════════════════════════════
//  Temporal Frequency Decomposition
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, temporal, history-ring, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-08-02 (Algorithmist — swarm b26)
//  Requires: binding 13 (historyTexture — HISTORY_DEPTH=8 ring buffer)
//  Created: 2026-05-23
//  By: Copilot
//
//  Discrete temporal Fourier analysis across the 8-frame history ring.
//  Each pixel accumulates a weighted sum where weights follow
//  sin/cos at the target temporal frequency. Static pixels cancel to
//  zero; pixels flickering or oscillating near the target frequency
//  produce large magnitude responses and glow brightly.
//  The result is overlaid on the current frame.
//
//  Interaction (the 'mouse-driven' tag is now honestly wired):
//    - Sprung analysis lens: the raw cursor is the target of a
//      critically-damped spring; inside the lens the frequency
//      response is sharpened and the glow widened — a Fourier
//      microscope that focuses wherever the pointer roams.
//    - Click tuning-fork pings: each click injects a decaying
//      oscillation at the target frequency into the DFT accumulators,
//      so clicks light up even in perfectly static scenes.
//    - Per-region FFT voices: 8 vertical bands each ride their own
//      spectrum bin, so the glow shimmers spatially with audio.
//
//  zoom_params layout:
//    x = target frequency (0→0.05 cycles/frame, 1→0.5, default 0.25→~0.18)
//    y = glow brightness  (0→dim, 1→blazing, default 0.6)
//    z = glow color hue   (0→red/orange, 0.5→cyan, 1→red again, default 0.17→yellow)
//    w = base blend       (0→glow only, 1→base+glow, default 0.8)
//
//  extraBuffer layout (engine contract — do NOT reinterpret):
//    [0..4]    reserved by engine — [4] = historyHead (READ-ONLY here)
//    [5..132]  engine FFT bins (NOT shader state)
//    [133..255] persistent shader state ONLY:
//      [133]=lensPosX  [134]=lensPosY  [135]=lensVelX  [136]=lensVelY
//      [137]=springInitialized
//  NOTE: extraBuffer[0..2] are NOT bass/mid/treble. Audio lives in
//  plasmaBuffer: [0] = global levels, [1..8] = per-voice FFT bins.
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
  zoom_params: vec4<f32>, // x=freq, y=glowBright, z=glowHue, w=baseBlend
  ripples: array<vec4<f32>, 50>,
};

const HISTORY_DEPTH: u32 = 8u;
const TAU: f32 = 6.28318530718;
const N_FRAMES: f32 = 8.0;  // total frames including current
const SPRING_DT: f32 = 0.0166667;  // fixed 60 Hz integration step
const LENS_RADIUS: f32 = 0.35;     // aspect-corrected lens radius
const PING_RADIUS: f32 = 0.2;      // aspect-corrected click ping radius

// Simple hue→RGB conversion
fn hue2rgb(h: f32) -> vec3<f32> {
  let h6 = fract(h) * 6.0;
  let r  = clamp(abs(h6 - 3.0) - 1.0, 0.0, 1.0);
  let g  = clamp(2.0 - abs(h6 - 2.0), 0.0, 1.0);
  let b  = clamp(2.0 - abs(h6 - 4.0), 0.0, 1.0);
  return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res   = vec2<f32>(u.config.z, u.config.w);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

  let uv     = (vec2<f32>(global_id.xy) + 0.5) / res;
  let aspect = res.x / res.y;
  let time   = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  // Parameters; bass boosts glow brightness, mids rotate hue for spectral color
  let freq       = 0.05 + u.zoom_params.x * 0.45;
  let glowBright = u.zoom_params.y * 2.0 * (1.0 + bass * 0.6);
  let glowHue    = fract(u.zoom_params.z + mids * 0.15);
  let baseBlend  = u.zoom_params.w;

  // ── Sprung analysis lens ─────────────────────────────────────────
  // Critically-damped spring chasing the raw mouse; persistent state
  // lives in extraBuffer[133..136] ONLY ([0..4] reserved, [5..132] FFT).
  let mouseRaw = u.zoom_config.yz;             // normalised 0..1
  var lensPos  = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  var lensVel  = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  let springInitialized = extraBuffer[137] > 0.5;
  if (!springInitialized) {                    // cold start: snap to cursor
    lensPos = mouseRaw;
    lensVel = vec2<f32>(0.0, 0.0);
  }
  let omega = 9.0;                             // spring natural frequency
  let stiff = omega * omega;                   // k
  let damp  = 2.0 * omega;                     // critical damping c = 2·√k
  lensVel += ((mouseRaw - lensPos) * stiff - lensVel * damp) * SPRING_DT;
  lensPos += lensVel * SPRING_DT;
  // One invocation persists the shared state; every invocation computes the
  // same local step so this frame's lens remains spatially coherent.
  if (global_id.x == 0u && global_id.y == 0u) {
    extraBuffer[133] = lensPos.x;
    extraBuffer[134] = lensPos.y;
    extraBuffer[135] = lensVel.x;
    extraBuffer[136] = lensVel.y;
    extraBuffer[137] = 1.0;
  }

  // Aspect-corrected lens mask (~0.35 radius, soft edge)
  let lensVec  = (uv - lensPos) * vec2<f32>(aspect, 1.0);
  let lensMask = 1.0 - smoothstep(0.0, LENS_RADIUS, length(lensVec));

  let historyHead = u32(extraBuffer[4]);
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Discrete Fourier bin at target frequency over 8 time samples
  // Real part (cosine weights) and imaginary part (sine weights)
  var realAcc = current.rgb * 1.0;  // cos(0) = 1
  var imagAcc = current.rgb * 0.0;  // sin(0) = 0

  for (var age: u32 = 1u; age <= 7u; age = age + 1u) {
    let layer = (historyHead + HISTORY_DEPTH - age) % HISTORY_DEPTH;
    let hist  = textureSampleLevel(historyTexture, u_sampler, uv, i32(layer), 0.0);
    let t     = f32(age);
    realAcc += hist.rgb * cos(TAU * freq * t);
    imagAcc += hist.rgb * sin(TAU * freq * t);
  }

  // ── Click tuning-fork pings ──────────────────────────────────────
  // Each live ripple injects a decaying oscillation at the target
  // frequency into the DFT accumulators, lighting the click point up
  // at `freq` even when the underlying scene is perfectly static.
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple    = u.ripples[i];
    let rippleAge = time - ripple.z;
    if (rippleAge < 0.0 || rippleAge > 4.0) { continue; }
    let pingVec   = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
    let pingMask  = 1.0 - smoothstep(0.0, PING_RADIUS, length(pingVec));
    let decay     = exp(-rippleAge * 1.5);
    let ageFrames = rippleAge * 60.0;          // seconds → frames
    realAcc += vec3<f32>(cos(TAU * freq * ageFrames)) * pingMask * decay;
    imagAcc += vec3<f32>(sin(TAU * freq * ageFrames)) * pingMask * decay;
  }

  // Frequency magnitude (normalised by sample count)
  let magnitude = sqrt(realAcc * realAcc + imagAcc * imagAcc) / N_FRAMES;

  // Scalar energy level for glow brightness
  let energy = (magnitude.r + magnitude.g + magnitude.b) / 3.0;

  // ── Lens focus: sharpen response, widen glow inside the lens ─────
  var energyFocused = energy * (1.0 + lensMask * 0.8);
  energyFocused = pow(clamp(energyFocused, 0.0, 4.0), 1.0 - lensMask * 0.25);

  // ── Per-region FFT voices: 8 vertical bands ride their own bins ──
  let band       = min(u32(uv.x * 8.0), 7u);
  let voice      = plasmaBuffer[(band % 8u) + 1u].x * 0.4;
  let voiceBoost = 1.0 + bass * 0.6 + voice;   // band voice + global bass

  // Coloured glow: single hue tinted by frequency energy
  let glowColor = hue2rgb(glowHue) * energyFocused * glowBright * voiceBoost;

  // Composite: base + glow
  let base   = current.rgb * baseBlend;
  let output = base + glowColor;
  let alpha = clamp(energy * 2.5 + baseBlend * 0.3 + bass * 0.2, 0.0, 1.0);
  let finalOut = vec4<f32>(output, alpha);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, finalOut);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalOut);
}
