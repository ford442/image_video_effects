// ═══════════════════════════════════════════════════════════════════
//  Temporal Phosphor Burn — Motion Adaptive
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, temporal, history-ring, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-07-31 (Batch 19 — mouse lens, click stamps, FFT band drift)
//  Requires: binding 13 (historyTexture — HISTORY_DEPTH=8 ring buffer)
//  Created: 2026-05-23
//  By: Copilot
//
//  Like temporal-phosphor-burn but the per-pixel decay rate adapts
//  to local motion. Fast-moving regions get slow decay (0.99), so
//  they blaze bright trails. Still regions clear quickly (0.85),
//  preventing static burn-in. A green/amber tint is applied to the
//  persistence glow for CRT ambiance.
//
//  Interactions (Batch 19):
//    - Mouse phosphor lens: near the cursor the local decay is biased
//      toward decayMax (longer trails) with an aspect-corrected
//      smoothstep falloff (~0.3 radius) — the pointer "charges" the
//      phosphor. Mouse proximity also feeds the motion term so cursor
//      movement itself leaves a faint trail; pressing (mouseDown)
//      intensifies the charge.
//    - Click burn stamps: each live ripple brands a decaying warm
//      ghost at its click point into the accumulation (~2s fade),
//      like a CRT flash branded into the phosphor.
//    - Per-band decay drift: 8 vertical FFT bands (plasmaBuffer[bin+1].x)
//      subtly modulate decay (±0.005, clamped to [decayMin, 0.999]) so
//      the trails breathe with the spectrum while static areas clear.
//
//  zoom_params layout:
//    x = motion sensitivity (0→gentle, 1→sharp, default 0.5)
//    y = max decay (slow end, 0→0.90, 1→0.999, default 0.5→0.99)
//    z = min decay (fast end, 0→0.70, 1→0.90, default 0.5→0.85)
//    w = warm tint strength (0→none, 1→full green/amber, default 0.6)
//
//  extraBuffer layout (READ-ONLY for this shader — engine owns [0..4]):
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
  zoom_params: vec4<f32>, // x=motionSens, y=maxDecay, z=minDecay, w=warmTint
  ripples: array<vec4<f32>, 50>,
};

const HISTORY_DEPTH: u32 = 8u;
const MOUSE_LENS_RADIUS: f32 = 0.3;  // aspect-corrected lens radius (uv units)
const STAMP_FADE: f32 = 2.0;         // click-stamp lifetime in seconds

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res   = vec2<f32>(u.config.z, u.config.w);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  // Parameters; bass amplifies motion sensitivity for reactive trails
  let motionSens  = (1.0 + u.zoom_params.x * 9.0) * (1.0 + bass * 0.5);
  let decayMax    = clamp(0.90 + u.zoom_params.y * 0.099 + bass * 0.03, 0.0, 0.999);
  let decayMin    = 0.70 + u.zoom_params.z * 0.20;
  let warmStrength = u.zoom_params.w * (1.0 + mids * 0.4);

  let historyHead = u32(extraBuffer[4]);
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // ── Mouse phosphor lens ─────────────────────────────────────────
  // Aspect-corrected distance to cursor; smoothstep falloff ~0.3 radius.
  let mouse     = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let mouseD    = vec2<f32>((uv.x - mouse.x) * aspect, uv.y - mouse.y);
  let mouseMask = smoothstep(MOUSE_LENS_RADIUS, 0.0, length(mouseD));
  // Press-and-hold charges the phosphor harder than a hover.
  let charge = mouseMask * (0.6 + 0.4 * clamp(u.zoom_config.w, 0.0, 1.0));

  // Compute per-pixel motion from most recent history frame
  let layerRecent = (historyHead + HISTORY_DEPTH - 1u) % HISTORY_DEPTH;
  let recent = textureSampleLevel(historyTexture, u_sampler, uv, i32(layerRecent), 0.0);
  // Cursor proximity feeds the motion term, so pointer movement itself
  // leaves a faint trail as it sweeps across the screen.
  var motion = clamp(length(current.rgb - recent.rgb) * motionSens, 0.0, 1.0);
  motion = clamp(motion + charge * 0.18, 0.0, 1.0);

  // Motion-adaptive decay: high motion → decayMax (slow decay → long bright trail)
  //                        no  motion → decayMin (fast decay → static areas clear quickly)
  var decay = mix(decayMin, decayMax, motion);

  // Mouse lens: bias local decay toward decayMax (pointer charges the phosphor)
  decay = mix(decay, decayMax, mouseMask * 0.5);

  // Per-band decay drift: 8 vertical FFT bands make the trails breathe
  // with the spectrum (±0.005 — subtle enough that static areas still clear).
  let bin   = min(u32(clamp(uv.y, 0.0, 0.999) * 8.0), 7u);
  let drift = (plasmaBuffer[bin + 1u].x - 0.5) * 0.01;
  decay = clamp(decay + drift, decayMin, 0.999);

  // Accumulate phosphor burn (max-based; history-ring indexing is an engine contract)
  var burned = current.rgb;
  for (var age: u32 = 1u; age <= 7u; age = age + 1u) {
    let layer   = (historyHead + HISTORY_DEPTH - age) % HISTORY_DEPTH;
    let hist    = textureSampleLevel(historyTexture, u_sampler, uv, i32(layer), 0.0);
    let decayed = hist.rgb * pow(decay, f32(age));
    burned = max(burned, decayed);
  }

  // ── Click burn stamps ───────────────────────────────────────────
  // Each live ripple brands a warm ghost at its click point (~2s fade).
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rp    = u.ripples[i];
    let rpAge = u.config.x - rp.z;
    if (rp.z > 0.0 && rpAge >= 0.0 && rpAge < STAMP_FADE) {
      let rpD   = vec2<f32>((uv.x - rp.x) * aspect, uv.y - rp.y);
      let stamp = smoothstep(0.12, 0.0, length(rpD));
      if (stamp > 0.001) {
        // Warm brand: white-hot core bleeding out to amber at the rim.
        let stampColor = mix(vec3<f32>(1.0, 0.55, 0.2), vec3<f32>(1.0, 0.95, 0.8), stamp * 0.6);
        burned = max(burned, stampColor * exp(-rpAge * 2.0) * stamp);
      }
    }
  }

  // Green/amber warm tint on the phosphor glow (applied proportional to motion)
  // Tint: boost green slightly, reduce blue → classic CRT amber-green
  let warmTint = vec3<f32>(1.0, 1.08, 0.65);
  let glowAmt  = clamp(motion * 1.5, 0.0, 1.0) * warmStrength;
  burned = mix(burned, burned * warmTint, glowAmt);

  let alpha = clamp(motion * 0.5 + current.a * 0.4 + bass * 0.15 + charge * 0.1, 0.0, 1.0);
  let finalOut = vec4<f32>(burned, alpha);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, finalOut);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalOut);
}
