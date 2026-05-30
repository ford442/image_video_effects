// ================================================================
//  Sine Wave Distortion
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: sine-wave
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Intensity, y=Speed, z=Scale, w=Detail
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let audio = plasmaBuffer[0].xyz;

  let intensity = u.zoom_params.x * 0.06;
  let speed = 0.15 + u.zoom_params.y * 3.5;
  let scale = 1.5 + u.zoom_params.z * 18.0;
  let detail = u.zoom_params.w;

  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let mouseMask = 1.0 - smoothstep(0.0, 0.75, mouseDist);
  let waveX = sin(uv.y * scale * 6.28318 + time * speed * 2.5);
  let waveY = cos(uv.x * (scale * 0.7) * 6.28318 - time * speed * 1.7);
  let micro = sin((uv.x + uv.y) * scale * 12.0 + time * (2.0 + audio.z * 2.0)) * detail * 0.008;

  let offset = vec2<f32>(
    (waveX + waveY * 0.45) * intensity * (1.0 + audio.x * 0.5) + micro,
    (waveY - waveX * 0.35) * intensity * 0.45 * (1.0 + mouseMask)
  );
  let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
  let split = vec2<f32>(detail * 0.01 * (0.5 + audio.z), 0.0);

  var finalColor = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );
  let crest = clamp(abs(waveX) * 0.6 + abs(waveY) * 0.4, 0.0, 1.0);
  let tint = mix(vec3<f32>(0.0, 0.75, 1.0), vec3<f32>(0.75, 0.30, 1.0), detail * 0.6 + audio.y * 0.2);
  finalColor = finalColor + tint * crest * (0.06 + audio.x * 0.18);

  let finalAlpha = clamp(0.72 + crest * 0.15 + mouseMask * 0.10, 0.45, 0.98);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.25 + crest * 0.60, 0.18 + intensity * 8.0), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(offset.x, offset.y, crest, finalAlpha));
}
