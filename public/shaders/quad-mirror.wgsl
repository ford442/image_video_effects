// ═══════════════════════════════════════════════════════════════════
//  Quad Mirror
//  Category: image
//  Features: mouse-driven, geometry
//  Complexity: Low
//  Created: 2026-05-03
//  By: Optimizer
// ═══════════════════════════════════════════════════════════════════
// 4-way kaleidoscope mirror centered on mouse with rotation and zoom.
// Pipeline-ready: HDR preserved, single texture sample, slot-chainable.

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

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;
const MIN_ZOOM: f32 = 0.1;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  let px = vec2<i32>(global_id.xy);
  if (any(global_id.xy >= vec2<u32>(res))) {
    return;
  }

  let uv = vec2<f32>(global_id.xy) / res;
  let mouse = u.zoom_config.yz;

  // --- Mirror transform ---
  let rel = uv - mouse;
  let rot = u.zoom_params.z * TAU;
  let c = cos(rot);
  let s = sin(rot);
  let rx = rel.x * c - rel.y * s;
  let ry = rel.x * s + rel.y * c;

  let zoom = max(MIN_ZOOM, u.zoom_params.y);
  let sample_uv = mouse - vec2<f32>(abs(rx), abs(ry)) / zoom;

  // Single texture sample — minimal cost for 3-slot chaining
  var color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0);

  // --- Edge softness (branchless) ---
  let edgeAmt = u.zoom_params.w;
  let edgeMask = smoothstep(0.0, 0.1, min(abs(rx), abs(ry)));
  color = color * mix(1.0, edgeMask, edgeAmt);

  // HDR-ready output (no clamp)
  textureStore(writeTexture, px, color);

  // --- Depth pass-through ---
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, px, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
