// ═══════════════════════════════════════════════════════════════════
//  Dynamic Halftone
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive
//  Complexity: Medium
//  Phase A Upgrade Swarm
//  Created: 2026-05-10
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Density, y=InfluenceRadius, z=Contrast, w=EdgeSharpness
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let coords = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  var mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let density = max(20.0 + u.zoom_params.x * 100.0, 0.001);
  let influenceRadius = u.zoom_params.y * (1.0 + bass * 0.2);
  let contrast = max(0.5 + u.zoom_params.z * 2.0, 0.001);

  let aspectUV = vec2<f32>(uv.x * aspect, uv.y);
  let scale = vec2<f32>(density, density);

  let gridUV = aspectUV * scale;
  let cellIndex = floor(gridUV);
  let cellLocalUV = fract(gridUV);
  let cellCenter = vec2<f32>(0.5, 0.5);

  let cellCenterUV = (cellIndex + cellCenter) / scale;
  let sampleUV = vec2<f32>(cellCenterUV.x / aspect, cellCenterUV.y);

  let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
  let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

  let distToMouse = length((sampleUV - mouse) * vec2<f32>(aspect, 1.0));
  let influence = smoothstep(influenceRadius, 0.0, distToMouse);

  var radius = luma * 0.5;
  radius = clamp(radius * (1.0 + influence * 0.8), 0.0, 0.6);

  let edgeSharpnessFactor = mix(2.0, 0.1, clamp(u.zoom_params.w, 0.0, 1.0));
  let edgeWidth = 0.05 * (1.0 + influence) * max(edgeSharpnessFactor, 0.001);

  let distToDotCenter = length(cellLocalUV - cellCenter);
  let dot_alpha = 1.0 - smoothstep(radius - edgeWidth, radius + edgeWidth, distToDotCenter);

  var finalColor = mix(vec3<f32>(0.0), color.rgb, dot_alpha);
  finalColor = pow(max(finalColor, vec3<f32>(0.0)), vec3<f32>(contrast));

  // Alpha encodes dot coverage: filled dots = high weight, empty cells = transparent
  let alpha = clamp(dot_alpha * (0.5 + luma * 0.4) + influence * 0.1, 0.0, 1.0);

  textureStore(writeTexture, coords, vec4<f32>(finalColor, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
