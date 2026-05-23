// ═══════════════════════════════════════════════════════════════════
//  Temporal Slit Scan
//  Category: post-processing
//  Features: temporal, history-ring
//  Complexity: Low
//  Requires: binding 13 (historyTexture — HISTORY_DEPTH=8 ring buffer)
//  Created: 2026-05-23
//  By: Copilot
//
//  Classic slit-scan time-smear (Radiohead "Street Spirit" style).
//  Each column (or row) samples a different point in the history ring:
//  one edge = current frame; opposite edge = 7 frames ago.
//  This stretches the temporal axis across the spatial axis, creating
//  a flowing painterly smear on any moving content.
//
//  zoom_params layout:
//    x = axis (0→horizontal scan, >0.5→vertical scan)
//    y = temporal spread (0→1 frame, 1→7 frames, default 1.0→max)
//    z = reverse direction (0→normal, >0.5→reversed L↔R)
//    w = blend with original (0→pure slit, 1→original, default 0.0)
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
  zoom_params: vec4<f32>, // x=axis, y=spread, z=reverse, w=origBlend
  ripples: array<vec4<f32>, 50>,
};

const HISTORY_DEPTH: u32 = 8u;
const MAX_OFFSET: u32    = 7u;  // maximum history age to reach

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res   = vec2<f32>(u.config.z, u.config.w);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;

  // Parameters
  let useVertical  = u.zoom_params.x > 0.5;
  let spread       = clamp(u.zoom_params.y, 0.0, 1.0);   // 0–1 → 0–7 frames
  let doReverse    = u.zoom_params.z > 0.5;
  let origBlend    = u.zoom_params.w;

  // Normalised position along the scan axis [0,1]
  var scanPos = select(uv.x, uv.y, useVertical);
  if (doReverse) { scanPos = 1.0 - scanPos; }

  // Map scan position to temporal offset: left=maxOffset(oldest), right=0(current)
  let maxOffset = u32(spread * f32(MAX_OFFSET) + 0.5);
  // (1-scanPos): scanPos=0(left) → t_offset=maxOffset(oldest); scanPos=1(right) → t_offset=0(current)
  let t_offset = u32((1.0 - scanPos) * f32(maxOffset));

  let historyHead = u32(extraBuffer[4]);
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  var scanColor: vec4<f32>;
  if (t_offset == 0u) {
    // Right edge: live current frame
    scanColor = current;
  } else {
    let layer = (historyHead + HISTORY_DEPTH - t_offset) % HISTORY_DEPTH;
    scanColor = textureSampleLevel(historyTexture, u_sampler, uv, i32(layer), 0.0);
  }

  let output = mix(scanColor, current, origBlend);
  textureStore(writeTexture, coord, vec4<f32>(output.rgb, 1.0));
}
