// ================================================================
//  Optical Illusion Spin
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: optical-illusion-spin
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
  zoom_params: vec4<f32>,  // x=RingCount, y=Speed, z=TwistForce, w=Alternating
  ripples: array<vec4<f32>, 50>,
};

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / resolution;
  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;
  let audio = plasmaBuffer[0].xyz;

  let ringCount = 4.0 + u.zoom_params.x * 44.0;
  let speed = 0.15 + u.zoom_params.y * 5.0;
  let twistForce = u.zoom_params.z * 4.5;
  let alternating = u.zoom_params.w;

  let centered = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let radius = length(centered);
  let angle = atan2(centered.y, centered.x);
  let ring = floor(radius * ringCount);
  let altDir = mix(1.0, select(-1.0, 1.0, fract(ring * 0.5) >= 0.5), alternating);
  let twist = (1.0 - smoothstep(0.0, 1.1, radius)) * twistForce * altDir;
  let pulse = sin(time * speed * 2.0 + ring * 0.7) * (0.35 + 0.65 * audio.x);
  let spun = rotate(centered, twist + pulse * 0.18);
  let sampleUV = clamp(spun / vec2<f32>(aspect, 1.0) + mouse, vec2<f32>(0.0), vec2<f32>(1.0));

  var finalColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
  let ringPhase = fract(radius * ringCount);
  let ringMask = 1.0 - smoothstep(0.42, 0.50, abs(ringPhase - 0.5));
  let halo = ringMask * (0.08 + 0.24 * audio.z);
  let illusionTint = mix(vec3<f32>(0.10, 0.85, 1.0), vec3<f32>(1.0, 0.55, 0.20), 0.5 + 0.5 * sin(angle * 3.0 + time * speed));
  finalColor = finalColor + illusionTint * halo;

  let finalAlpha = clamp(0.74 + halo * 0.8 + (1.0 - smoothstep(0.0, 1.0, radius)) * 0.12, 0.42, 0.98);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.30 + halo * 0.7, 0.22), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(ringMask, halo, radius, finalAlpha));
}
