// ================================================================
//  Solarize Warp
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: solarize-warp
//  Created: 2026-05-30
//  By: Copilot
// ================================================================

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
  zoom_params: vec4<f32>,  // x=TwistStrength, y=SolarizeThreshold, z=EffectRadius, w=EffectIntensity
  ripples: array<vec4<f32>, 50>,
};

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let aspect = dims.x / dims.y;
  let time = u.config.x;
  let audio = plasmaBuffer[0].xyz;

  let twistStrength = u.zoom_params.x * 4.5;
  let solarizeThreshold = mix(0.15, 0.85, u.zoom_params.y);
  let effectRadius = mix(0.08, 0.80, u.zoom_params.z);
  let effectIntensity = mix(0.05, 1.0, u.zoom_params.w);

  let centered = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(centered);
  let influence = 1.0 - smoothstep(0.0, effectRadius, dist);
  let angle = twistStrength * influence * (1.0 + audio.x * 0.7) + sin(time * 2.0 + dist * 18.0) * 0.15;
  let warpedUV = clamp(rotate(centered, angle) / vec2<f32>(aspect, 1.0) + mouse, vec2<f32>(0.0), vec2<f32>(1.0));

  let source = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0).rgb;
  let luma = dot(source, vec3<f32>(0.299, 0.587, 0.114));
  let threshold = solarizeThreshold + (audio.y - 0.5) * 0.15 * influence;
  let inverted = 1.0 - source;
  let solarized = mix(source, inverted, step(threshold, luma));
  let tint = mix(vec3<f32>(1.0, 0.58, 0.12), vec3<f32>(0.12, 0.78, 1.0), 0.5 + 0.5 * sin(time + dist * 14.0));
  var finalColor = mix(source, solarized + tint * influence * 0.12, influence * effectIntensity);

  let finalAlpha = clamp(0.70 + influence * 0.18 + effectIntensity * 0.08, 0.40, 0.98);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, warpedUV, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.22 + influence * 0.70, 0.28), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(influence, luma, threshold, finalAlpha));
}
