// ================================================================
//  Zoom Burst
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba, radial-blur
//  Complexity: Medium
//  Chunks From: zoom-burst
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
  zoom_params: vec4<f32>,  // x=BurstLength, y=SampleQuality, z=Spin, w=Chroma
  ripples: array<vec4<f32>, 50>,
};

fn sampleColor(uv: vec2<f32>) -> vec3<f32> {
  return textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
}

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let center = u.zoom_config.yz;
  let audio = plasmaBuffer[0].xyz;

  let burstLength = mix(0.01, 0.20, u.zoom_params.x) * (1.0 + audio.x * 0.5);
  let quality = i32(mix(4.0, 18.0, u.zoom_params.y));
  let spin = (u.zoom_params.z - 0.5) * 1.8;
  let chroma = mix(0.0, 0.03, u.zoom_params.w);

  let offset = uv - center;
  let dist = length(offset);
  let dir = offset / max(dist, 1e-4);

  var accum = vec3<f32>(0.0);
  var weightSum = 0.0;
  for (var i = 0; i < quality; i = i + 1) {
    let t = f32(i) / max(f32(quality - 1), 1.0);
    let stepVec = rotate(dir, spin * t) * burstLength * t * (1.0 + dist * 3.0);
    let sampleUV = clamp(uv - stepVec, vec2<f32>(0.0), vec2<f32>(1.0));
    let split = dir * chroma * t;
    let color = vec3<f32>(
      sampleColor(sampleUV + split).r,
      sampleColor(sampleUV).g,
      sampleColor(sampleUV - split).b
    );
    let w = mix(1.0, 0.2, t);
    accum = accum + color * w;
    weightSum = weightSum + w;
  }

  let burst = accum / max(weightSum, 1e-4);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let flare = pow(max(0.0, 1.0 - dist * 1.8), 3.0) * (0.12 + audio.y * 0.22);
  let tint = mix(vec3<f32>(0.10, 0.8, 1.0), vec3<f32>(1.0, 0.55, 0.75), 0.5 + 0.5 * sin(u.config.x * 0.8));
  let finalColor = burst + tint * flare;
  let finalAlpha = clamp(src.a * 0.35 + 0.58 + flare * 0.16, 0.08, 0.98);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let outDepth = clamp(mix(depth, 0.22 + flare * 0.7, 0.18), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(dist, burstLength * 8.0, flare, finalAlpha));
}
