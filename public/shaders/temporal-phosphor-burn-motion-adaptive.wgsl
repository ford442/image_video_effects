// ═══════════════════════════════════════════════════════════════════
//  Temporal Phosphor Burn — Motion Adaptive
//  Category: post-processing
//  Features: temporal, history-ring
//  Complexity: Medium
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
//  zoom_params layout:
//    x = motion sensitivity (0→gentle, 1→sharp, default 0.5)
//    y = max decay (slow end, 0→0.90, 1→0.999, default 0.5→0.99)
//    z = min decay (fast end, 0→0.70, 1→0.90, default 0.5→0.85)
//    w = warm tint strength (0→none, 1→full green/amber, default 0.5)
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
  zoom_params: vec4<f32>, // x=motionSens, y=maxDecay, z=minDecay, w=warmTint
  ripples: array<vec4<f32>, 50>,
};

const HISTORY_DEPTH: u32 = 8u;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res   = vec2<f32>(u.config.z, u.config.w);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;

  // Parameters
  let motionSens = 1.0 + u.zoom_params.x * 9.0;   // multiplier on motion signal
  let decayMax   = 0.90 + u.zoom_params.y * 0.099; // decay when fast-moving (slow decay)
  let decayMin   = 0.70 + u.zoom_params.z * 0.20;  // decay when still (fast decay)
  let warmStrength = u.zoom_params.w;

  let historyHead = u32(extraBuffer[4]);
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Compute per-pixel motion from most recent history frame
  let layerRecent = (historyHead + HISTORY_DEPTH - 1u) % HISTORY_DEPTH;
  let recent = textureSampleLevel(historyTexture, u_sampler, uv, i32(layerRecent), 0.0);
  let motion = clamp(length(current.rgb - recent.rgb) * motionSens, 0.0, 1.0);

  // Motion-adaptive decay: high motion → decayMax (slow decay → long bright trail)
  //                        no  motion → decayMin (fast decay → static areas clear quickly)
  let decay = mix(decayMin, decayMax, motion);

  // Accumulate phosphor burn
  var burned = current.rgb;
  for (var age: u32 = 1u; age <= 7u; age = age + 1u) {
    let layer   = (historyHead + HISTORY_DEPTH - age) % HISTORY_DEPTH;
    let hist    = textureSampleLevel(historyTexture, u_sampler, uv, i32(layer), 0.0);
    let decayed = hist.rgb * pow(decay, f32(age));
    burned = max(burned, decayed);
  }

  // Green/amber warm tint on the phosphor glow (applied proportional to motion)
  // Tint: boost green slightly, reduce blue → classic CRT amber-green
  let warmTint = vec3<f32>(1.0, 1.08, 0.65);
  let glowAmt  = clamp(motion * 1.5, 0.0, 1.0) * warmStrength;
  burned = mix(burned, burned * warmTint, glowAmt);

  textureStore(writeTexture, coord, vec4<f32>(burned, current.a));
}
