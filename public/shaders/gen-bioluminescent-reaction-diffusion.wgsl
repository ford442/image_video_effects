// ═══════════════════════════════════════════════════════════════════
//  Bioluminescent Reaction-Diffusion
//  Category: generative
//  Features: mouse-driven, audio-reactive, simulation, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  // Audio reactivity
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Ping-pong reading from dataTextureC
  let center = textureLoad(dataTextureC, coord, 0).xy;
  var a = center.x;
  var b = center.y;

  if (time < 0.1) {
    a = 1.0;
    b = 0.0;
  }

  // Laplacian
  var lapl = vec2<f32>(0.0);
  let weightAdj = 0.2;
  let weightDiag = 0.05;
  let weightCenter = -1.0;

  lapl += center * weightCenter;
  lapl += textureLoad(dataTextureC, coord + vec2<i32>(1, 0), 0).xy * weightAdj;
  lapl += textureLoad(dataTextureC, coord + vec2<i32>(-1, 0), 0).xy * weightAdj;
  lapl += textureLoad(dataTextureC, coord + vec2<i32>(0, 1), 0).xy * weightAdj;
  lapl += textureLoad(dataTextureC, coord + vec2<i32>(0, -1), 0).xy * weightAdj;
  lapl += textureLoad(dataTextureC, coord + vec2<i32>(1, 1), 0).xy * weightDiag;
  lapl += textureLoad(dataTextureC, coord + vec2<i32>(-1, -1), 0).xy * weightDiag;
  lapl += textureLoad(dataTextureC, coord + vec2<i32>(1, -1), 0).xy * weightDiag;
  lapl += textureLoad(dataTextureC, coord + vec2<i32>(-1, 1), 0).xy * weightDiag;

  // Video luminance controls feed/kill rates
  let video_color = textureLoad(readTexture, coord, 0);
  let luma = dot(video_color.rgb, vec3<f32>(0.299, 0.587, 0.114));

  let feed = mix(0.01, 0.08, luma);
  let kill = mix(0.045, 0.065, luma);

  let diffA = mix(1.0, 0.5, bass) * 1.0;
  let diffB = mix(0.5, 0.2, bass) * 0.5;

  let reaction = a * b * b;
  let newA = a + (diffA * lapl.x - reaction + feed * (1.0 - a));
  let newB = b + (diffB * lapl.y + reaction - (kill + feed) * b);

  var finalA = clamp(newA, 0.0, 1.0);
  var finalB = clamp(newB, 0.0, 1.0);

  // Mouse injection
  let mouse = u.zoom_config.yz;
  let dist_to_mouse = distance(vec2<f32>(coord), mouse * resolution);
  let isNearMouse = dist_to_mouse < 20.0;
  finalB = select(finalB, 1.0, isNearMouse);

  // Output simulation state (temporal persistence required)
  let state = vec4<f32>(finalA, finalB, 0.0, 1.0);
  textureStore(dataTextureA, coord, state);

  // Map chemical concentration to bioluminescent color
  let concDiff = clamp(finalA - finalB, 0.0, 1.0);
  let plasmaIndex = u32(concDiff * 255.0);
  let color = plasmaBuffer[plasmaIndex % 256u];

  // Alpha: bioluminescence intensity blended with input alpha
  let glow = clamp(finalB * 2.0, 0.0, 1.0);
  let alpha = mix(video_color.a, 1.0, glow * 0.7);
  let finalRGB = color.rgb * glow;

  textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));

  // Depth pass-through
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
