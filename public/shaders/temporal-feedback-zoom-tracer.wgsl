// ═══════════════════════════════════════════════════════════════════
//  Temporal Feedback Zoom Tracer
//  Category: post-processing
//  Features: temporal, history-ring
//  Complexity: Medium
//  Requires: binding 13 (historyTexture — HISTORY_DEPTH=8 ring buffer)
//  Created: 2026-05-23
//  By: Copilot
//
//  Reads the most recent history frame through an affine warp
//  (zoom + rotation centred on canvas centre) then blends it with
//  the current frame:  mix(warped_history * decay, current, blend)
//  The slight magnification + rotation compound across frames,
//  producing infinite psychedelic zoom tunnels from live content.
//
//  zoom_params layout:
//    x = zoom power  (0→1.0×, 1→1.01×, default 0.5→1.002×)
//    y = rotation    (0→-0.002rad, 1→+0.002rad, default 0.625→+0.001rad)
//    z = history persistence (0→0.92, 1→0.99, default 0.714→0.97)
//    w = current-frame blend (0→0.05, 1→0.40, default 0.286→0.15)
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
  zoom_params: vec4<f32>, // x=zoom, y=rotation, z=persistence, w=blend
  ripples: array<vec4<f32>, 50>,
};

const HISTORY_DEPTH: u32 = 8u;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res   = vec2<f32>(u.config.z, u.config.w);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;

  // Map params to affine warp values
  let zoomFactor  = 1.0 + u.zoom_params.x * 0.01;             // 1.0 – 1.01
  let rotAngle    = (u.zoom_params.y - 0.5) * 0.004;           // -0.002 – +0.002 rad
  let persistence = 0.92 + u.zoom_params.z * 0.07;             // 0.92 – 0.99
  let blendAmt    = 0.05 + u.zoom_params.w * 0.35;             // 0.05 – 0.40

  // Affine warp: zoom + rotation about canvas centre
  let uvC = uv - 0.5;
  let cosR = cos(rotAngle);
  let sinR = sin(rotAngle);
  let rotated = vec2<f32>(
    cosR * uvC.x - sinR * uvC.y,
    sinR * uvC.x + cosR * uvC.y,
  );
  // Divide by zoom to reverse-map (so the warped history looks zoomed-in)
  let warpedUV = clamp(rotated / zoomFactor + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));

  let historyHead = u32(extraBuffer[4]);

  // Most recent history frame, sampled through the warp
  let layerPrev = (historyHead + HISTORY_DEPTH - 1u) % HISTORY_DEPTH;
  let histWarp  = textureSampleLevel(historyTexture, u_sampler, warpedUV, i32(layerPrev), 0.0);

  // Current input frame (straight UV)
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Blend: weighted history + current  (matches: mix(history*decay, current, blend))
  let output = mix(histWarp * persistence, current, blendAmt);

  textureStore(writeTexture, coord, vec4<f32>(output.rgb, 1.0));
}
