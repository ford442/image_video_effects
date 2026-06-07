// ═══════════════════════════════════════════════════════════════════
//  Temporal Phosphor Burn
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, temporal, history-ring, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-23
//  Requires: binding 13 (historyTexture — HISTORY_DEPTH=8 ring buffer)
//  Created: 2026-05-23
//  By: Copilot
//
//  Per-channel CRT phosphor persistence. Each channel decays at a
//  different rate (R=fast, B=slow) giving a green/amber afterglow.
//  Uses max(current, decayed_history) as a luminance floor so bright
//  pixels leave long glowing trails.
//
//  zoom_params layout:
//    x = R decay rate (0→0.85, 1→0.99, default 0.50 → 0.92)
//    y = G decay rate (0→0.85, 1→0.99, default 0.79 → 0.96)
//    z = B decay rate (0→0.85, 1→0.99, default 0.93 → 0.98)
//    w = luminance floor lift (0→none, 1→0.1 global floor)
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
  zoom_params: vec4<f32>, // x=R-decay, y=G-decay, z=B-decay, w=lumFloor
  ripples: array<vec4<f32>, 50>,
};

const HISTORY_DEPTH: u32 = 8u;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res   = vec2<f32>(u.config.z, u.config.w);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  // Per-channel CRT decay rates — bass extends phosphor persistence
  let decayR = clamp(0.85 + u.zoom_params.x * 0.14 + bass * 0.04, 0.0, 0.999);
  let decayG = clamp(0.85 + u.zoom_params.y * 0.14 + bass * 0.02, 0.0, 0.999);
  let decayB = clamp(0.85 + u.zoom_params.z * 0.14, 0.0, 0.999);
  let lumFloor = u.zoom_params.w * 0.10 + mids * 0.02;

  // Current input frame
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // historyHead: index of the layer that will be written this frame.
  // Age k = k frames ago → layer (historyHead + HISTORY_DEPTH - k) % HISTORY_DEPTH
  let historyHead = u32(extraBuffer[4]);

  // Accumulate phosphor burn: start from current, raise to history floor
  var burned = current.rgb;

  for (var age: u32 = 1u; age <= 7u; age = age + 1u) {
    let layer  = (historyHead + HISTORY_DEPTH - age) % HISTORY_DEPTH;
    let hist   = textureSampleLevel(historyTexture, u_sampler, uv, i32(layer), 0.0);
    let f      = f32(age);
    let decayed = vec3<f32>(
      hist.r * pow(decayR, f),
      hist.g * pow(decayG, f),
      hist.b * pow(decayB, f),
    );
    // Luminance floor: max keeps the brightest decayed value
    burned = max(burned, decayed);
  }

  // Optional global luminance floor
  burned = max(burned, vec3<f32>(lumFloor));

  // Alpha: luminance of the burn excess above current, boosted by bass
  let burnLuma = dot(max(burned - current.rgb, vec3<f32>(0.0)), vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(current.a * 0.5 + burnLuma * 2.0 + bass * 0.15, 0.0, 1.0);
  let finalOut = vec4<f32>(burned, alpha);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, finalOut);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalOut);
}
