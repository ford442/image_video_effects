// ================================================================
//  Infinite Zoom Lens
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal
//  Complexity: Medium
//  Chunks From: infinite-zoom-lens
//  Created: 2026-05-31
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
  zoom_params: vec4<f32>,  // x=ZoomStrength, y=LensRadius, z=FeedbackPersistence, w=Twist
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
  let audio = plasmaBuffer[0].xyz;

  let zoomStrength = mix(0.84, 1.18, u.zoom_params.x + audio.x * 0.08);
  let radius = mix(0.05, 0.52, u.zoom_params.y);
  let persistence = mix(0.50, 0.98, u.zoom_params.z);
  let twist = (u.zoom_params.w - 0.5) * 1.3 + audio.y * 0.25;

  let centered = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(centered);
  let lensMask = 1.0 - smoothstep(radius, radius + 0.025, dist);
  let swirl = twist * lensMask * (1.0 + audio.z * 0.4);
  let rotated = rotate(centered, swirl);
  let zoomedUV = clamp(mouse + rotated / vec2<f32>(aspect, 1.0) * zoomStrength, vec2<f32>(0.0), vec2<f32>(1.0));

  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let history = textureSampleLevel(dataTextureC, u_sampler, zoomedUV, 0.0);
  let historyDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, zoomedUV, 0.0).r;

  let chromaShift = (zoomedUV - mouse) * 0.03 * audio.z * lensMask;
  let historyRGB = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(zoomedUV + chromaShift, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    history.g,
    textureSampleLevel(readTexture, u_sampler, clamp(zoomedUV - chromaShift, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );

  let tunnelTint = mix(vec3<f32>(0.08, 0.6, 1.0), vec3<f32>(1.0, 0.45, 0.95), 0.5 + 0.5 * sin(u.config.x * 0.8 + dist * 18.0));
  let mixedHistory = mix(history.rgb, historyRGB, 0.45);
  let insideColor = mix(current.rgb, mixedHistory, persistence) + tunnelTint * lensMask * (0.06 + audio.x * 0.18);
  let finalColor = mix(current.rgb, insideColor, lensMask);

  let finalAlpha = clamp(mix(current.a, mix(current.a, history.a, persistence) + lensMask * 0.16, lensMask), 0.0, 0.98);
  let outDepth = clamp(mix(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r, historyDepth, lensMask), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(lensMask, zoomStrength, persistence, finalAlpha));
}
