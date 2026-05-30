// ================================================================
//  Cyber Lens
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba, chromatic-aberration
//  Complexity: Medium
//  Chunks From: cyber-lens
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
  zoom_params: vec4<f32>,  // x=LensRadius, y=ZoomStrength, z=GridIntensity, w=ChromaticAberration
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
  let lenSq = max(dot(v, v), 1e-6);
  return v * inverseSqrt(lenSq);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let aspect = dims.x / dims.y;
  let audio = plasmaBuffer[0].xyz;

  let lensRadius = mix(0.04, 0.42, u.zoom_params.x);
  let zoomStrength = mix(1.0, 5.0, u.zoom_params.y);
  let gridIntensity = u.zoom_params.z;
  let aberration = u.zoom_params.w * 0.05;

  let offset = uv - mouse;
  let delta = vec2<f32>(offset.x * aspect, offset.y);
  let dist = length(delta);
  let lensMask = 1.0 - smoothstep(lensRadius, lensRadius + 0.02, dist);
  let dir = safeNormalize(offset + vec2<f32>(0.0001, 0.0));

  let mag = mix(1.0 / zoomStrength, 1.0, smoothstep(0.0, lensRadius, dist));
  let lensUV = clamp(mouse + offset * mag, vec2<f32>(0.0), vec2<f32>(1.0));

  let split = dir * aberration * lensMask * (1.0 + audio.z * 0.6);
  var lensColor = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(lensUV - split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    textureSampleLevel(readTexture, u_sampler, lensUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, clamp(lensUV + split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );

  let gridUV = lensUV * 42.0;
  let lineX = 1.0 - smoothstep(0.0, 0.06, abs(fract(gridUV.x - time * 0.4) - 0.5));
  let lineY = 1.0 - smoothstep(0.0, 0.06, abs(fract(gridUV.y + time * 0.16) - 0.5));
  let grid = max(lineX, lineY) * gridIntensity * (0.55 + audio.y * 0.8);
  let scan = 0.85 + 0.15 * sin(uv.y * dims.y * 0.45 + time * 7.0);
  let rim = smoothstep(lensRadius - 0.02, lensRadius, dist) - smoothstep(lensRadius, lensRadius + 0.02, dist);
  let borderColor = mix(vec3<f32>(0.05, 0.95, 0.95), vec3<f32>(0.95, 0.35, 1.0), 0.5 + 0.5 * sin(time * 1.5));

  lensColor = lensColor * scan + borderColor * grid + borderColor * rim * (0.2 + audio.x * 0.25);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let finalColor = mix(src.rgb, lensColor, lensMask);
  let finalAlpha = clamp(mix(src.a, 0.72 + grid * 0.35 + rim * 0.18, lensMask), 0.10, 0.98);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, lensUV, 0.0).r;
  let outDepth = clamp(mix(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r, baseDepth, lensMask), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(lensMask, grid, rim, finalAlpha));
}
