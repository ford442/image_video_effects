// ═══════════════════════════════════════════════════════════════════
//  Sine Wave
//  Category: distortion
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: sine-wave
//  Created: 2026-05-30
//  By: 4-Agent Upgrade Swarm
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51, 2.51, 2.51);
  let b = vec3<f32>(0.03, 0.03, 0.03);
  let c = vec3<f32>(2.43, 2.43, 2.43);
  let d = vec3<f32>(0.59, 0.59, 0.59);
  let e = vec3<f32>(0.14, 0.14, 0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  let f = fract(p * vec2<f32>(123.34, 456.21));
  return fract(dot(f, vec2<f32>(1.0, 1.0)) * 78.233);
}

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
  let bass = audio.x;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let intensity = u.zoom_params.x * 0.06 * (1.0 + bass * 0.6);
  let speed = 0.15 + u.zoom_params.y * 3.5;
  let scale = 1.5 + u.zoom_params.z * 18.0;
  let detail = u.zoom_params.w;

  // Mouse creates wave sources
  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let mouseMask = 1.0 - smoothstep(0.0, 0.75, mouseDist);

  // Multi-frequency sine wave interference with traveling wave packets
  let phase = uv.y * scale * 6.28318 + time * speed * 2.5;
  let phase2 = uv.x * (scale * 0.7) * 6.28318 - time * speed * 1.7;
  let groupVel = sin(phase * 0.5 + time * speed * 0.8) * 0.5 + 0.5;
  let waveX = sin(phase) * groupVel;
  let waveY = cos(phase2) * (1.0 - groupVel * 0.3);

  // Amplitude modulation from audio + mouse
  let am = 1.0 + bass * 0.5 + mouseMask * 0.8;
  let micro = sin((uv.x + uv.y) * scale * 12.0 + time * (2.0 + audio.z * 2.0)) * detail * 0.008;

  // Depth controls wave attenuation
  let depthAtten = mix(1.0, 0.2, depth);

  let offset = vec2<f32>(
    (waveX + waveY * 0.45) * intensity * am + micro,
    (waveY - waveX * 0.35) * intensity * 0.45 * (1.0 + mouseMask)
  ) * depthAtten;

  let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));

  // Chromatic dispersion on wave crests
  let crest = clamp(abs(waveX) * 0.6 + abs(waveY) * 0.4, 0.0, 1.0);
  let dispersion = detail * 0.01 * (0.5 + audio.z) * (1.0 + crest * 2.0);
  let split = vec2<f32>(dispersion, 0.0);

  var finalColor = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );

  // Water surface caustics from wave interference
  let interference = abs(waveX * waveY) * 2.0;
  let causticTint = mix(vec3<f32>(0.0, 0.55, 0.95), vec3<f32>(0.75, 0.25, 1.0), detail * 0.6 + audio.y * 0.2);
  finalColor = finalColor + causticTint * interference * (0.04 + bass * 0.12);

  // HDR specular highlights on crests
  let specular = pow(crest, 8.0) * (0.3 + bass * 0.4);
  finalColor = finalColor + vec3<f32>(1.0, 0.95, 0.85) * specular;

  // ACES tone mapping
  finalColor = acesToneMap(finalColor * 1.15);

  // Semantic alpha: wave_amplitude * interference_intensity * depth
  let interferenceIntensity = interference + crest * 0.5;
  let finalAlpha = clamp(intensity * 12.0 * interferenceIntensity * depth * 2.5, 0.15, 0.95);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.25 + crest * 0.60, 0.18 + intensity * 8.0), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(offset.x, offset.y, crest, finalAlpha));
}
