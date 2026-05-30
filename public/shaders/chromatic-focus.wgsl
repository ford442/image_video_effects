// ================================================================
//  Chromatic Focus
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, chromatic-aberration
//  Complexity: Medium
//  Chunks From: chromatic-focus
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
  zoom_params: vec4<f32>,  // x=ApertureSize, y=FocusRadius, z=SpectralSpread, w=AnimationSpeed
  ripples: array<vec4<f32>, 50>,
};

fn sampleColor(uv: vec2<f32>) -> vec3<f32> {
  return textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
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

  let aperture = mix(0.002, 0.028, u.zoom_params.x);
  let focusRadius = mix(0.05, 0.42, u.zoom_params.y) + audio.x * 0.035;
  let spectralSpread = mix(0.001, 0.022, u.zoom_params.z);
  let animSpeed = 0.1 + u.zoom_params.w * 2.8;

  let centered = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(centered);
  let focusMask = 1.0 - smoothstep(focusRadius, focusRadius + 0.12, dist);
  let blurMask = 1.0 - focusMask;
  let time = u.config.x * animSpeed;

  let angleStep = 6.28318 / 6.0;
  var blurAccum = vec3<f32>(0.0);
  for (var i = 0; i < 6; i = i + 1) {
    let angle = f32(i) * angleStep + time * 0.7;
    let dir = vec2<f32>(cos(angle), sin(angle));
    blurAccum = blurAccum + sampleColor(uv + dir * aperture * (1.0 + blurMask * 2.0));
  }
  let softColor = blurAccum / 6.0;

  let dispersionDir = normalize(centered + vec2<f32>(0.001, 0.0));
  let chromaOffset = dispersionDir * spectralSpread * blurMask * (1.0 + audio.z * 0.7);
  let chromaColor = vec3<f32>(
    sampleColor(uv + chromaOffset).r,
    sampleColor(uv).g,
    sampleColor(uv - chromaOffset).b
  );

  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let haloColor = mix(vec3<f32>(0.20, 0.85, 1.0), vec3<f32>(1.0, 0.4, 0.95), 0.5 + 0.5 * sin(time + dist * 14.0));
  var finalColor = mix(softColor, source.rgb, focusMask);
  finalColor = mix(finalColor, chromaColor, blurMask * 0.55);
  finalColor = finalColor + haloColor * blurMask * (0.05 + audio.y * 0.16);

  let finalAlpha = clamp(mix(source.a, 0.72 + blurMask * 0.18, blurMask), 0.06, 0.98);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let outDepth = clamp(mix(baseDepth, 0.20 + blurMask * 0.65, 0.24), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(focusMask, blurMask, spectralSpread * 40.0, finalAlpha));
}
