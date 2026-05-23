// ═══════════════════════════════════════════════════════════════════
//  Temporal RGB Ghost
//  Category: post-processing
//  Features: temporal, history-ring
//  Complexity: Low
//  Requires: binding 13 (historyTexture — HISTORY_DEPTH=8 ring buffer)
//  Created: 2026-05-23
//  By: Copilot
//
//  Per-channel temporal displacement: R channel = current frame,
//  G = N frames ago, B = M frames ago. Moving objects leave rainbow
//  comet tails as each color channel trails behind a different
//  amount. Static areas look normal (all channels match); motion
//  splits into vivid chromatic echoes.
//
//  zoom_params layout:
//    x = G channel delay (0→age 1, 1→age 7, default 0.17→age 2)
//    y = B channel delay (0→age 1, 1→age 7, default 0.67→age 5)
//    z = ghost blend (0→original only, 1→ghost only, default 0.80)
//    w = luma boost on ghost (0→none, 1→2×, default 0.25)
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
  zoom_params: vec4<f32>, // x=G-delay, y=B-delay, z=blend, w=lumaBoost
  ripples: array<vec4<f32>, 50>,
};

const HISTORY_DEPTH: u32 = 8u;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res   = vec2<f32>(u.config.z, u.config.w);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;

  // Map params [0,1] to history age [1,7]
  let ageG = 1u + u32(clamp(u.zoom_params.x, 0.0, 0.999) * 7.0);
  let ageB = 1u + u32(clamp(u.zoom_params.y, 0.0, 0.999) * 7.0);
  let blendAmt   = u.zoom_params.z;
  let lumaBoost  = 1.0 + u.zoom_params.w;

  let historyHead = u32(extraBuffer[4]);

  // R channel: current frame
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // G channel: ageG frames ago
  let layerG = (historyHead + HISTORY_DEPTH - ageG) % HISTORY_DEPTH;
  let histG  = textureSampleLevel(historyTexture, u_sampler, uv, i32(layerG), 0.0);

  // B channel: ageB frames ago
  let layerB = (historyHead + HISTORY_DEPTH - ageB) % HISTORY_DEPTH;
  let histB  = textureSampleLevel(historyTexture, u_sampler, uv, i32(layerB), 0.0);

  // Assemble RGB ghost: each channel from a different moment in time
  let ghost = vec4<f32>(
    current.r,
    histG.g   * lumaBoost,
    histB.b   * lumaBoost,
    1.0,
  );

  let output = mix(current, ghost, blendAmt);
  textureStore(writeTexture, coord, output);
}
