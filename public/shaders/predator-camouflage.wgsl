// ================================================================
//  Predator Camouflage
//  Category: distortion
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba, temporal-ghosting, chromatic-aberration
//  Complexity: Medium
//  Chunks From: predator-camouflage
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
  zoom_params: vec4<f32>,  // x=CloakRadius, y=RefractionStrength, z=ShimmerSpeed, w=NoiseScale
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash12(i);
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
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

  let cloakRadius = mix(0.08, 0.70, u.zoom_params.x);
  let refractionStrength = u.zoom_params.y * 0.08;
  let shimmerSpeed = 0.2 + u.zoom_params.z * 5.0;
  let noiseScale = mix(4.0, 26.0, u.zoom_params.w);

  let centered = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(centered);
  let cloakMask = 1.0 - smoothstep(cloakRadius * 0.75, cloakRadius, dist);
  let rim = smoothstep(cloakRadius * 0.55, cloakRadius * 0.92, dist) * cloakMask;

  let shimmerA = noise(uv * noiseScale + vec2<f32>(time * shimmerSpeed, -time * 0.5));
  let shimmerB = noise(uv * (noiseScale * 1.7) - vec2<f32>(time * 0.8, time * shimmerSpeed));
  let shimmer = (shimmerA + shimmerB - 1.0) * (0.5 + audio.x);
  let normal = normalize(centered + vec2<f32>(0.001, 0.0));
  let offset = normal * (refractionStrength * cloakMask * (0.5 + shimmer));
  let refractedUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
  let split = normal * (0.003 + audio.z * 0.01) * rim;

  var finalColor = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(refractedUV + split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    textureSampleLevel(readTexture, u_sampler, refractedUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, clamp(refractedUV - split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );
  let cloakTint = mix(vec3<f32>(0.10, 0.8, 1.0), vec3<f32>(0.65, 0.95, 0.35), shimmerA);
  finalColor = mix(finalColor, finalColor * 0.55 + cloakTint * 0.45, cloakMask * 0.55);
  finalColor = finalColor + cloakTint * rim * (0.10 + audio.y * 0.18);

  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, refractedUV, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.18 + cloakMask * 0.72, 0.30), 0.0, 1.0);
  let finalAlpha = clamp(0.92 - cloakMask * 0.30 + rim * 0.10, 0.35, 0.98);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(cloakMask, rim, shimmerA, finalAlpha));
}
