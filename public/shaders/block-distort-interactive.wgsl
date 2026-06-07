// ================================================================
//  Block Distort
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: block-distort-interactive
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
  zoom_params: vec4<f32>,  // x=BlockSize, y=PushStrength, z=RGBSplit, w=Radius
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

  let blockScale = mix(8.0, 72.0, u.zoom_params.x);
  let pushStrength = u.zoom_params.y * 0.20;
  let rgbSplit = u.zoom_params.z * 0.03;
  let radius = mix(0.05, 0.75, u.zoom_params.w);

  let grid = floor(uv * blockScale);
  let cellCenter = (grid + 0.5) / blockScale;
  let delta = (cellCenter - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(delta);
  let influence = 1.0 - smoothstep(0.0, radius, dist);
  let direction = safeNormalize(delta + vec2<f32>(0.0005, 0.0));
  let shove = direction * pushStrength * influence * (1.0 + audio.x * 0.8);
  let wobble = vec2<f32>(sin(time * 2.0 + grid.y), cos(time * 1.7 + grid.x)) * 0.01 * audio.z;
  let sampleUV = clamp(uv + shove + wobble, vec2<f32>(0.0), vec2<f32>(1.0));

  let splitVec = safeNormalize(direction + vec2<f32>(0.0005, 0.0005)) * rgbSplit * influence;
  var finalColor = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + splitVec, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - splitVec, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );

  let gridLine = 1.0 - smoothstep(0.46, 0.50, max(abs(fract(uv * blockScale) - 0.5).x, abs(fract(uv * blockScale) - 0.5).y));
  let prismTint = mix(vec3<f32>(0.10, 0.9, 1.0), vec3<f32>(1.0, 0.30, 0.8), 0.5 + 0.5 * sin(time + grid.x * 0.3));
  finalColor = finalColor + prismTint * (gridLine * 0.10 + influence * 0.12 * audio.y);

  let finalAlpha = clamp(0.70 + influence * 0.18 + gridLine * 0.08, 0.42, 0.98);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.22 + influence * 0.68, 0.30), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(influence, gridLine, abs(shove.x) + abs(shove.y), finalAlpha));
}
