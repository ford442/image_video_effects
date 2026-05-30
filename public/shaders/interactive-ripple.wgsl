// ================================================================
//  Interactive Ripple
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, wave
//  Complexity: Medium
//  Chunks From: interactive-ripple
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
  zoom_params: vec4<f32>,  // x=WaveHeight, y=WaveCount, z=WaveSpeed, w=Damping
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let time = u.config.x;
  let aspect = dims.x / dims.y;
  let audio = plasmaBuffer[0].xyz;

  let waveHeight = u.zoom_params.x * 0.035;
  let waveCount = mix(4.0, 26.0, u.zoom_params.y);
  let waveSpeed = 0.2 + u.zoom_params.z * 4.0;
  let damping = mix(0.35, 2.2, u.zoom_params.w);
  let rippleCount = min(u32(u.config.y), 50u);

  var totalOffset = vec2<f32>(0.0);
  var rippleEnergy = 0.0;

  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let center = ripple.xy;
    let delta = (uv - center) * vec2<f32>(aspect, 1.0);
    let dist = length(delta);
    let age = max(0.0, time - ripple.z);
    let envelope = exp(-age * damping) * exp(-dist * (3.5 + damping));
    let phase = dist * waveCount * 10.0 - age * waveSpeed * 8.0;
    let wave = sin(phase) * envelope;
    let dir = delta / max(dist, 1e-4);
    totalOffset = totalOffset + dir * wave * waveHeight * (1.0 + audio.x * 0.8);
    rippleEnergy = rippleEnergy + abs(wave);
  }

  let sampleUV = clamp(uv + totalOffset, vec2<f32>(0.0), vec2<f32>(1.0));
  var finalColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
  let wetSpec = pow(clamp(rippleEnergy * 0.25, 0.0, 1.0), 2.0) * (0.20 + audio.z * 0.45);
  let tint = mix(vec3<f32>(0.08, 0.55, 1.0), vec3<f32>(0.95, 0.80, 1.0), audio.y * 0.5);
  finalColor = finalColor + tint * wetSpec;

  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
  let finalAlpha = clamp(0.68 + wetSpec * 0.35 + rippleEnergy * 0.03, 0.40, 0.98);
  let depthOut = clamp(mix(baseDepth, 0.18 + rippleEnergy * 0.08, 0.28), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(totalOffset.x, totalOffset.y, rippleEnergy, finalAlpha));
}
