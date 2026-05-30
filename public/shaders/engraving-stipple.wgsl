// ================================================================
//  Engraving Stipple
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, line-art
//  Complexity: Medium
//  Chunks From: engraving-stipple
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
  zoom_params: vec4<f32>,  // x=LineDensity, y=StippleScale, z=Contrast, w=LightRotation
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

  let lineDensity = mix(60.0, 240.0, u.zoom_params.x);
  let stippleScale = mix(4.0, 22.0, u.zoom_params.y);
  let contrast = mix(0.8, 2.8, u.zoom_params.z);
  let lightRotation = u.zoom_params.w * 6.28318 + time * 0.2;

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = pow(clamp(luminance(src.rgb), 0.0, 1.0), contrast);
  let hatchDir = vec2<f32>(cos(lightRotation), sin(lightRotation));
  let hatch = 0.5 + 0.5 * sin(dot(uv * vec2<f32>(aspect, 1.0), hatchDir) * lineDensity);
  let crossHatch = 0.5 + 0.5 * sin(dot(uv * vec2<f32>(aspect, 1.0), vec2<f32>(-hatchDir.y, hatchDir.x)) * lineDensity * 0.7);
  let stipple = fract(sin(dot(floor(uv * stippleScale * 60.0), vec2<f32>(12.9898, 78.233))) * 43758.5453);
  let ink = clamp((1.0 - luma) * 1.2 + hatch * 0.25 + crossHatch * 0.18 - stipple * 0.55, 0.0, 1.0);

  let mouseDelta = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let burnish = 1.0 - smoothstep(0.0, 0.45, length(mouseDelta));
  let warmPaper = mix(vec3<f32>(0.96, 0.93, 0.87), vec3<f32>(0.90, 0.96, 1.0), audio.y * 0.15);
  let inkColor = mix(vec3<f32>(0.12, 0.10, 0.08), vec3<f32>(0.05, 0.10, 0.18), audio.z * 0.25);
  let finalColor = mix(warmPaper, inkColor, clamp(ink + burnish * 0.12, 0.0, 1.0));

  let finalAlpha = clamp(src.a * 0.35 + ink * 0.70 + burnish * 0.08, 0.05, 0.98);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let outDepth = clamp(mix(baseDepth, 0.22 + ink * 0.72, 0.24), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(ink, hatch, burnish, finalAlpha));
}
