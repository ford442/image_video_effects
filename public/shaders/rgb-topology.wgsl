// ================================================================
//  RGB Topology
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba, contour
//  Complexity: Medium
//  Chunks From: rgb-topology
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
  zoom_params: vec4<f32>,  // x=ContourDensity, y=LineThickness, z=ChannelSeparation, w=SourceBlend
  ripples: array<vec4<f32>, 50>,
};

fn luminance(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
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

  let contourDensity = mix(8.0, 64.0, u.zoom_params.x);
  let lineThickness = mix(0.01, 0.16, u.zoom_params.y);
  let channelSeparation = mix(0.0, 0.03, u.zoom_params.z);
  let sourceBlend = mix(0.0, 0.85, u.zoom_params.w);

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let topo = luminance(src.rgb) * 0.65 + depth * 0.35;
  let centered = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let tilt = centered * channelSeparation * (0.6 + audio.x * 0.6);

  let topoR = topo + centered.x * 0.35;
  let topoG = topo + centered.y * 0.25;
  let topoB = topo - length(centered) * 0.2;
  let lineR = 1.0 - smoothstep(0.0, lineThickness, abs(sin((topoR + time * 0.03) * contourDensity)));
  let lineG = 1.0 - smoothstep(0.0, lineThickness, abs(sin((topoG + time * 0.04) * contourDensity)));
  let lineB = 1.0 - smoothstep(0.0, lineThickness, abs(sin((topoB - time * 0.05) * contourDensity)));

  let sampleR = textureSampleLevel(readTexture, u_sampler, clamp(uv + tilt, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let sampleG = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
  let sampleB = textureSampleLevel(readTexture, u_sampler, clamp(uv - tilt, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let contourColor = vec3<f32>(lineR * sampleR, lineG * sampleG, lineB * sampleB);
  let glowTint = mix(vec3<f32>(0.08, 0.9, 1.0), vec3<f32>(1.0, 0.35, 0.8), 0.5 + 0.5 * sin(time + topo * 16.0));
  var finalColor = mix(contourColor, src.rgb, sourceBlend);
  finalColor = finalColor + glowTint * max(max(lineR, lineG), lineB) * (0.08 + audio.y * 0.12);

  let contourMask = max(max(lineR, lineG), lineB);
  let finalAlpha = clamp(mix(src.a * sourceBlend, 0.72 + contourMask * 0.18, 1.0 - sourceBlend * 0.3), 0.04, 0.98);
  let outDepth = clamp(mix(depth, 0.20 + contourMask * 0.72, 0.24), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(lineR, lineG, lineB, finalAlpha));
}
