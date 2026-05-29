// ═══════════════════════════════════════════════════════════════════
//  Frosty Window
//  Category: artistic
//  Features: upgraded-rgba, depth-aware, interactive, persistence, audio-reactive
//  Complexity: Medium
//  Upgraded: 2026-05-10
//  By: Phase A Upgrade Swarm
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,  // x, y, startTime, unused
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let coord = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(global_id.xy) / resolution;

  // Audio reactivity
  let bass = plasmaBuffer[0].x;

  // Params with randomization guards
  let freezeSpeed = max(0.005 + u.zoom_params.x * 0.05 + bass * 0.01, 0.001);
  let meltRadius = max(0.05 + u.zoom_params.y * 0.2, 0.001);
  let blurStrength = max(u.zoom_params.z * 5.0, 0.001);
  let frostOpacity = clamp(0.5 + u.zoom_params.w * 0.5, 0.0, 1.0);

  // Mouse
  var mouse = u.zoom_config.yz;
  let dist = distance(uv, mouse);

  // Persistence (Frost Level)
  // Read previous state from dataTextureC (r channel)
  var frostLevel = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

  // Grow frost
  frostLevel = clamp(frostLevel + freezeSpeed, 0.0, 1.0);

  // Melt frost with mouse
  if (dist < meltRadius) {
    let melt = smoothstep(meltRadius, meltRadius * 0.5, dist);
    frostLevel = frostLevel * (1.0 - melt);
  }

  // Write frost state to dataTextureA
  textureStore(dataTextureA, coord, vec4<f32>(frostLevel, 0.0, 0.0, frostLevel));

  // Effect
  var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  if (frostLevel > 0.0) {
     let noise = fract(sin(dot(uv + 0.001, vec2<f32>(12.9898, 78.233))) * 43758.5453);
     let angle = noise * 6.28;
     let radius = frostLevel * blurStrength * 0.01;
     let offset = vec2<f32>(cos(angle), sin(angle)) * radius;

     let blurredColor = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
     let frostTint = vec3<f32>(0.1, 0.1, 0.2) * frostLevel;
     color = mix(color, blurredColor + frostTint, frostLevel * frostOpacity);
  }

  // Calculate alpha based on frost level and luminance
  let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let frostAlpha = mix(0.85, 1.0, frostLevel * 0.5 + luma * 0.5);
  let finalAlpha = mix(frostAlpha * 0.8, frostAlpha, depth);

  textureStore(writeTexture, coord, vec4<f32>(color, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
