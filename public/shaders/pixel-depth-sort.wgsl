// ═══════════════════════════════════════════════════════════════════
//  Pixel Depth Sort — Batch D Upgraded
//  Category: post-processing
//  Features: upgraded-rgba, mouse-driven, audio-reactive, depth-aware
//  Complexity: Medium
//  Chunks From: pixel-depth-sort
//  Created: 2026-05-02
//  Upgraded: 2026-05-10
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;

  let mousePos = u.zoom_config.yz;
  let depthThreshold = u.zoom_params.x;
  let sortLengthBase = u.zoom_params.y * 40.0;
  let sortAngle = u.zoom_params.z * 6.283185307;
  let aberration = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let sortLength = sortLengthBase * (1.0 + bass * 2.0);

  let centerDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Sort direction follows mouse position
  let angleFromMouse = atan2(mousePos.y - 0.5, mousePos.x - 0.5);
  let angle = angleFromMouse + sortAngle;
  let dir = vec2<f32>(cos(angle), sin(angle));

  // Sample 9 pixels forward along sort direction
  var colors: array<vec4<f32>, 9>;
  var depths: array<f32, 9>;

  for (var i: u32 = 0u; i < 9u; i = i + 1u) {
    let offset = dir * f32(i) * sortLength / resolution;
    let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
    colors[i] = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    depths[i] = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
  }

  // Sort by depth (ascending: near to far)
  for (var i: u32 = 0u; i < 9u; i = i + 1u) {
    for (var j: u32 = 0u; j < 8u - i; j = j + 1u) {
      if (depths[j] > depths[j + 1u]) {
        let td = depths[j];
        depths[j] = depths[j + 1u];
        depths[j + 1u] = td;
        let tc = colors[j];
        colors[j] = colors[j + 1u];
        colors[j + 1u] = tc;
      }
    }
  }

  // Find where centerDepth fits in sorted depths
  var rank: u32 = 0u;
  for (var i: u32 = 0u; i < 9u; i = i + 1u) {
    if (centerDepth > depths[i]) {
      rank = rank + 1u;
    }
  }
  rank = clamp(rank, 0u, 8u);

  let sortedColor = colors[rank];

  // Chromatic aberration at sort boundaries
  let depthRange = abs(depths[8] - depths[0]);
  let boundaryStrength = smoothstep(0.05, 0.3, depthRange);
  let caOffset = dir * aberration * boundaryStrength * 4.0 / resolution;

  let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + caOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = sortedColor.g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - caOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

  let finalColor = vec3<f32>(r, g, b);

  // Alpha: near pixels more opaque
  let alpha = clamp(centerDepth, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(centerDepth, 0.0, 0.0, 0.0));
}
