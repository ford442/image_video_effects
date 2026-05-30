// ================================================================
//  Edge Glow
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: edge-glow-mouse
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
  zoom_params: vec4<f32>,  // x=EdgeThreshold, y=GlowRadius, z=Intensity, w=ColorSpeed
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
  let time = u.config.x;
  let aspect = dims.x / dims.y;
  let audio = plasmaBuffer[0].xyz;

  let edgeThreshold = mix(0.02, 0.35, u.zoom_params.x);
  let glowRadius = mix(0.08, 0.70, u.zoom_params.y);
  let intensity = mix(0.3, 2.5, u.zoom_params.z);
  let colorSpeed = 0.2 + u.zoom_params.w * 4.0;

  let px = vec2<f32>(1.0 / dims.x, 1.0 / dims.y);
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let edgeX = sampleLuma(uv + vec2<f32>(px.x, 0.0)) - sampleLuma(uv - vec2<f32>(px.x, 0.0));
  let edgeY = sampleLuma(uv + vec2<f32>(0.0, px.y)) - sampleLuma(uv - vec2<f32>(0.0, px.y));
  let edge = length(vec2<f32>(edgeX, edgeY));
  let glowMask = smoothstep(edgeThreshold, edgeThreshold + 0.15, edge);

  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let mouseAura = 1.0 - smoothstep(0.0, glowRadius, mouseDist);
  let hue = 0.5 + 0.5 * sin(time * colorSpeed + mouseDist * 18.0);
  let glowColor = mix(vec3<f32>(0.10, 0.85, 1.0), vec3<f32>(1.0, 0.45, 0.75), hue);

  var finalColor = baseColor + glowColor * glowMask * intensity * (0.25 + mouseAura + audio.x * 0.4);
  let finalAlpha = clamp(0.72 + glowMask * 0.18 + mouseAura * 0.08, 0.42, 0.98);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.20 + glowMask * 0.72, 0.26), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(glowMask, mouseAura, intensity, finalAlpha));
}
