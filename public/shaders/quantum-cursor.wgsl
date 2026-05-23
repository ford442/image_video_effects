// ═══════════════════════════════════════════════════════════════════
//  Quantum Cursor
//  Category: interactive-mouse
//  Features: mouse-driven, distortion, audio-reactive, upgraded-rgba
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  var p3  = fract(vec3<f32>(p.xyx) * .1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 0.001);
  var mouse = u.zoom_config.yz;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Params with guards and audio reactivity
  let radius = max(mix(0.05, 0.5, u.zoom_params.x) * (1.0 + bass * 0.3), 0.001);
  let mosaic_scale = mix(50.0, 5.0, clamp(u.zoom_params.y, 0.0, 1.0));
  let aberration = clamp(u.zoom_params.z, 0.0, 1.0) * 0.05;
  let chaos = clamp(u.zoom_params.w * (1.0 + bass * 0.5 + mids * 0.2), 0.0, 1.0);

  let dist_vec = (uv - mouse);
  let dist = length(dist_vec * vec2(aspect, 1.0));

  // Soft edge for the effect
  let mask = smoothstep(radius, radius * 0.8, dist);

  // Sample Original
  let colOrig = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Sample Effect
  let blocks = resolution / max(mosaic_scale, 0.1);
  let blockUV = floor(uv * blocks) / blocks + (0.5 / blocks);

  // Random jitter per block based on chaos
  let blockHash = hash12(blockUV + u.config.x * 0.01 * max(chaos, 0.001));
  let jitter = (blockHash - 0.5) * 0.1 * chaos;
  var activeBlockUV = clamp(blockUV + jitter, vec2<f32>(0.0), vec2<f32>(1.0));

  // Aberration on Block UV with clamped sample coordinates
  let rUV = clamp(activeBlockUV + vec2(aberration, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(activeBlockUV - vec2(aberration, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, activeBlockUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
  var colEffect = vec4<f32>(r, g, b, mask);

  // Branchless color channel shuffle and inversion based on chaos
  let activeChaos = step(0.2, chaos);
  let shuffle1 = step(0.6, blockHash);
  let shuffle2 = step(blockHash, 0.3);
  let doInvert = step(0.7, chaos) * step(0.8, blockHash);

  let shuffled1 = vec4<f32>(colEffect.g, colEffect.b, colEffect.r, mask);
  let shuffled2 = vec4<f32>(colEffect.b, colEffect.r, colEffect.g, mask);
  let anyShuffle = max(shuffle1, shuffle2);
  let chosenShuffle = select(shuffled2, shuffled1, shuffle1 > 0.5);
  let afterShuffle = mix(colEffect, chosenShuffle, activeChaos * anyShuffle);

  let inverted = vec4<f32>(1.0 - afterShuffle.rgb, mask);
  colEffect = mix(afterShuffle, inverted, activeChaos * doInvert);

  let finalRGB = mix(colOrig.rgb, colEffect.rgb, mask);
  let effectStrength = mask * (0.5 + chaos * 0.3 + treble * 0.1);
  let alpha = clamp(effectStrength + dot(finalRGB, vec3<f32>(0.299, 0.587, 0.114)) * 0.3, 0.0, 1.0);
  let finalColor = vec4<f32>(finalRGB, alpha);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
  textureStore(dataTextureA, global_id.xy, finalColor);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
