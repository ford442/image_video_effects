// ═══════════════════════════════════════════════════════════════════════════════
//  Canonical Compute Shader Template
//
//  Start here for every new Pixelocity compute effect. This file is pre-wired
//  to the renderer's immutable bind-group contract and uses the canonical
//  (16, 16, 1) workgroup size.
//
//  DO NOT change the binding numbers, types, or Uniforms struct layout below.
//  Variable names may be flexible, but the contract is not. Run
//    python scripts/wgsl_precommit_gate.py --files this_file.wgsl
//  before committing.
// ═══════════════════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════════════════
//  STUB EFFECT — replace everything below this line with your real algorithm.
// ═══════════════════════════════════════════════════════════════════════════════

@compute @workgroup_size(16, 16, 1)
fn main_compute(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = textureDimensions(writeTexture);
  let coord = vec2<i32>(gid.xy);
  let dimsI = vec2<i32>(dims);

  // Stay inside image bounds.
  if (any(coord >= dimsI)) {
    return;
  }

  // Minimal valid write so naga and the bindgroup gate see a real compute path.
  textureStore(writeTexture, coord, vec4<f32>(u.config.rgb, 1.0));
}
