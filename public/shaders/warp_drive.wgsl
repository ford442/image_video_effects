// ================================================================
//  Warp Drive
//  Category: visual-effects
//  Features: audio-reactive, upgraded-rgba, radial-blur
//  Complexity: Medium
//  Chunks From: warp_drive
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
  zoom_params: vec4<f32>,  // x=WarpSpeed, y=PrismSplit, z=CoreGlow, w=BlurQuality
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
  let center = vec2<f32>(0.5, 0.5);
  let audio = plasmaBuffer[0].xyz;

  let warpSpeed = mix(0.02, 0.18, u.zoom_params.x) * (1.0 + audio.x * 0.6);
  let prismSplit = mix(0.0, 0.03, u.zoom_params.y);
  let coreGlow = mix(0.05, 0.8, u.zoom_params.z);
  let blurQuality = i32(mix(4.0, 14.0, u.zoom_params.w));

  let dir = uv - center;
  let dist = length(dir);
  let dirSafe = dir / max(dist, 1e-4);

  var accum = vec3<f32>(0.0);
  var weightSum = 0.0;
  for (var i = 0; i < blurQuality; i = i + 1) {
    let t = f32(i) / max(f32(blurQuality - 1), 1.0);
    let offset = dir * warpSpeed * t * (1.0 + dist * 2.5);
    let split = dirSafe * prismSplit * t;
    let sampleUV = clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0));
    let color = vec3<f32>(
      sampleColor(sampleUV + split).r,
      sampleColor(sampleUV).g,
      sampleColor(sampleUV - split).b
    );
    let w = mix(1.0, 0.15, t);
    accum = accum + color * w;
    weightSum = weightSum + w;
  }

  var finalColor = accum / max(weightSum, 1e-4);
  let starburst = pow(max(0.0, 1.0 - dist * 1.7), 3.0) * (coreGlow + audio.y * 0.25);
  let tint = mix(vec3<f32>(0.2, 0.7, 1.0), vec3<f32>(1.0, 0.55, 0.9), 0.5 + 0.5 * sin(u.config.x * 0.6));
  finalColor = finalColor + tint * starburst;

  let srcAlpha = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;
  let finalAlpha = clamp(srcAlpha * 0.35 + 0.55 + starburst * 0.2, 0.06, 0.98);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let outDepth = clamp(mix(depth, 0.18 + starburst * 0.72, 0.20), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(dist, warpSpeed * 8.0, starburst, finalAlpha));
}
