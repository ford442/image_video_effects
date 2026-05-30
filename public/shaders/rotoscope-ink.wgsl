// ================================================================
//  Rotoscope Ink
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, edge-stylization
//  Complexity: Medium
//  Chunks From: rotoscope-ink
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
  zoom_params: vec4<f32>,  // x=EdgeThreshold, y=PosterizeLevels, z=InkDensity, w=ShadeMix
  ripples: array<vec4<f32>, 50>,
};

fn luminance(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn sampleLuma(uv: vec2<f32>) -> f32 {
  return luminance(textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
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

  let edgeThreshold = mix(0.03, 0.28, u.zoom_params.x);
  let levels = mix(2.0, 9.0, u.zoom_params.y);
  let inkDensity = mix(0.3, 1.4, u.zoom_params.z);
  let shadeMix = mix(0.05, 0.95, u.zoom_params.w);

  let px = vec2<f32>(1.0 / dims.x, 1.0 / dims.y);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let l = sampleLuma(uv - px);
  let r = sampleLuma(uv + vec2<f32>(px.x, -px.y));
  let t = sampleLuma(uv + vec2<f32>(-px.x, px.y));
  let b = sampleLuma(uv + px);
  let edge = length(vec2<f32>(r - l, t - b));
  let edgeMask = smoothstep(edgeThreshold, edgeThreshold + 0.16, edge);

  let posterized = floor(src.rgb * levels) / max(levels - 1.0, 1.0);
  let mouseMask = 1.0 - smoothstep(0.0, 0.45, length((uv - mouse) * vec2<f32>(aspect, 1.0)));
  let inkTint = mix(vec3<f32>(0.05, 0.05, 0.06), vec3<f32>(0.12, 0.20, 0.32), audio.z * 0.4);
  let edgeGlow = mix(vec3<f32>(0.9, 0.5, 0.2), vec3<f32>(0.3, 0.9, 1.0), 0.5 + 0.5 * sin(time + uv.y * 12.0));

  var toon = mix(src.rgb, posterized, shadeMix);
  toon = mix(toon, toon * (1.0 - inkDensity * 0.25) + inkTint * 0.15, edgeMask * 0.45);
  let finalColor = mix(toon, inkTint, edgeMask * inkDensity) + edgeGlow * edgeMask * mouseMask * (0.05 + audio.x * 0.18);

  let finalAlpha = clamp(src.a * 0.35 + (1.0 - edgeMask) * 0.40 + edgeMask * 0.55, 0.08, 0.98);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let outDepth = clamp(mix(baseDepth, 0.18 + edgeMask * 0.78, 0.26), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(edgeMask, mouseMask, shadeMix, finalAlpha));
}
