// ═══════════════════════════════════════════════════════════════════
//  Quantum Cursor
//  Category: interactive-mouse
//  Features: mouse-driven, distortion, audio-reactive
//  Complexity: Medium
//  Created: 2026-05-10
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
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  var p3  = fract(vec3<f32>(p.xyx) * .1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  var uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  var mouse = u.zoom_config.yz;

  // Audio reactivity
  let bass = plasmaBuffer[0].x;

  // Params with guards and audio reactivity
  let radius = max(mix(0.05, 0.5, u.zoom_params.x) * (1.0 + bass * 0.3), 0.001);
  let mosaic_scale = mix(50.0, 5.0, clamp(u.zoom_params.y, 0.0, 1.0));
  let aberration = clamp(u.zoom_params.z, 0.0, 1.0) * 0.05;
  let chaos = clamp(u.zoom_params.w * (1.0 + bass * 0.5), 0.0, 1.0);

  let dist_vec = (uv - mouse);
  let dist = length(dist_vec * vec2(aspect, 1.0));

  // Soft edge for the effect
  let mask = smoothstep(radius, radius * 0.8, dist);

  // Sample Original
  let colOrig = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Sample Effect
  // 1. Mosaic UV
  let blocks = resolution / max(mosaic_scale, 0.1);
  let blockUV = floor(uv * blocks) / blocks + (0.5 / blocks);

  // Random jitter per block based on chaos
  let blockHash = hash12(blockUV + u.config.x * 0.01 * max(chaos, 0.001));
  let jitter = (blockHash - 0.5) * 0.1 * chaos;
  var activeBlockUV = clamp(blockUV + jitter, vec2(0.0), vec2(1.0));

  // Aberration on Block UV with clamped sample coordinates
  let rUV = clamp(activeBlockUV + vec2(aberration, 0.0), vec2(0.0), vec2(1.0));
  let bUV = clamp(activeBlockUV - vec2(aberration, 0.0), vec2(0.0), vec2(1.0));
  let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, activeBlockUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
  var colEffect = vec4<f32>(r, g, b, mask);

  if (chaos > 0.2) {
    // Color channel shuffle based on hash
    if (blockHash > 0.6) {
      colEffect = vec4(colEffect.g, colEffect.b, colEffect.r, mask);
    } else if (blockHash < 0.3) {
      colEffect = vec4(colEffect.b, colEffect.r, colEffect.g, mask);
    }

    // Inversion
    if (chaos > 0.7 && blockHash > 0.8) {
      colEffect = vec4(1.0 - colEffect.rgb, mask);
    }
  }

  let finalRGB = mix(colOrig.rgb, colEffect.rgb, mask);
  let finalAlpha = max(colOrig.a, mask);
  let finalColor = vec4<f32>(finalRGB, finalAlpha);

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);

  // Depth pass-through
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 1.0));
}
