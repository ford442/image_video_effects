// ═══════════════════════════════════════════════════════════════════
//  Holographic Crystal
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware
//  Complexity: High
//  Created: 2026-05-31
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

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn sat(x: f32) -> f32 {
  return clamp(x, 0.0, 1.0);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz * 2.0 - 1.0;

  let facets = mix(3.0, 16.0, u.zoom_params.x);
  let tilt = mix(0.0, 1.0, u.zoom_params.y);
  let interference = mix(0.1, 2.0, u.zoom_params.z);
  let dispersion = mix(0.1, 1.5, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;

  let tiltAngle = tilt * 0.8 + mouse.x * 0.3;
  let ct = cos(tiltAngle);
  let st = sin(tiltAngle);
  let tp = vec2<f32>(ct * p.x - st * p.y, st * p.x + ct * p.y);

  let crystalR = max(abs(tp.x), abs(tp.y)) * facets;
  let crystalEdge = fract(crystalR);
  let facetId = floor(crystalR);
  let edgeGlow = smoothstep(0.85, 1.0, crystalEdge) + smoothstep(0.0, 0.15, crystalEdge);

  let holoPhase = crystalR * 3.14159 + time * (0.5 + bass * 0.8) + facetId * 1.73;
  let holoR = 0.5 + 0.5 * sin(holoPhase + 0.0 + treble * 0.3);
  let holoG = 0.5 + 0.5 * sin(holoPhase + 2.094 + mids * 0.25);
  let holoB = 0.5 + 0.5 * sin(holoPhase + 4.188 + bass * 0.2);

  let interior = smoothstep(0.5, 0.0, max(abs(tp.x), abs(tp.y)));
  let moire = sin(tp.x * 40.0 + time) * sin(tp.y * 40.0 - time * 0.7) * interior;

  // Chromatic holographic interference
  var color = vec3<f32>(0.01, 0.01, 0.02);
  color = color + vec3<f32>(holoR * 1.1, holoG, holoB * 0.95) * edgeGlow * interference * (1.0 + treble * 0.15);
  color = color + vec3<f32>(0.6, 0.85, 1.0) * moire * dispersion * (1.0 + mids * 0.1);
  color = color + vec3<f32>(0.9, 0.75, 1.0) * interior * 0.15;

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.9, 0.025 + bass * 0.01);

  let presence = sat(edgeGlow * 0.8 + interior * 0.3);
  let alpha = sat(0.08 + presence * 0.92);
  let depth = sat(0.9 - edgeGlow * 0.5 - interior * 0.3);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(edgeGlow, moire, interior, alpha));
}
