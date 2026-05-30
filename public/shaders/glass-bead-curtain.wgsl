// ================================================================
//  Glass Bead Curtain
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Chunks From: glass-bead-curtain
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
  zoom_params: vec4<f32>,  // x=BeadSize, y=Refraction, z=InteractTension, w=GlassDensity
  ripples: array<vec4<f32>, 50>,
};

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

  let beadCount = mix(8.0, 36.0, 1.0 - u.zoom_params.x);
  let refraction = u.zoom_params.y * 0.06;
  let interactTension = mix(0.05, 0.35, u.zoom_params.z);
  let density = mix(0.35, 1.0, u.zoom_params.w);

  let curtainUV = vec2<f32>(uv.x * beadCount * aspect, uv.y * beadCount);
  let beadId = floor(curtainUV);
  let beadCenter = beadId + 0.5;
  let sway = sin(time * (1.5 + audio.x * 3.0) + beadId.y * 0.4) * 0.12;
  let beadLocal = curtainUV - beadCenter + vec2<f32>(sway, 0.0);
  let beadDist = length(beadLocal);
  let beadMask = 1.0 - smoothstep(0.34, 0.50, beadDist);

  let beadCenterUV = vec2<f32>((beadCenter.x - sway) / (beadCount * aspect), beadCenter.y / beadCount);
  let pullDelta = (beadCenterUV - mouse) * vec2<f32>(aspect, 1.0);
  let pull = (1.0 - smoothstep(0.0, 0.45, length(pullDelta))) * interactTension;
  let normal = safeNormalize(beadLocal + safeNormalize(pullDelta + vec2<f32>(0.001, 0.0)) * pull);
  let refractOffset = normal * refraction * beadMask * (1.0 + audio.z * 0.8);
  let sampleUV = clamp(uv + refractOffset, vec2<f32>(0.0), vec2<f32>(1.0));

  var finalColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
  let iridescence = mix(vec3<f32>(0.25, 0.85, 1.0), vec3<f32>(1.0, 0.55, 0.85), 0.5 + 0.5 * normal.x);
  let sparkle = pow(max(0.0, 1.0 - beadDist * 1.9), 4.0) * (0.3 + audio.y * 0.7);
  finalColor = mix(finalColor, finalColor * density + iridescence * 0.30, beadMask * density);
  finalColor = finalColor + iridescence * sparkle;

  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
  let transmission = mix(0.42, 0.88, beadMask * density);
  let finalAlpha = clamp(0.42 + transmission * 0.45 + sparkle * 0.12, 0.25, 0.97);
  let depthOut = clamp(mix(baseDepth, baseDepth * 0.35 + beadMask * 0.65, 0.38), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(beadMask, transmission, sparkle, finalAlpha));
}
