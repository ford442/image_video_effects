// ================================================================
//  Rain
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, atmospheric
//  Complexity: Medium
//  Chunks From: rain
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
  zoom_params: vec4<f32>,  // x=RainDensity, y=FallSpeed, z=Wind, w=Wetness
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
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

  let rainDensity = mix(8.0, 60.0, u.zoom_params.x);
  let fallSpeed = mix(0.2, 3.5, u.zoom_params.y);
  let wind = mix(-0.08, 0.08, u.zoom_params.z);
  let wetness = mix(0.05, 0.45, u.zoom_params.w);

  let rainUV = vec2<f32>(uv.x * rainDensity * aspect, uv.y * rainDensity + time * fallSpeed);
  let cell = floor(rainUV);
  let dropSeed = hash12(cell);
  let local = fract(rainUV);
  let streak = smoothstep(0.08 + dropSeed * 0.08, 0.0, abs(local.x - 0.5)) * smoothstep(1.0, 0.1, local.y);
  let drops = streak * step(0.72, dropSeed);
  let mouseMask = 1.0 - smoothstep(0.0, 0.55, length((uv - mouse) * vec2<f32>(aspect, 1.0)));
  let displacement = vec2<f32>(wind, 0.02) * drops * (0.6 + wetness * 0.8 + audio.x * 0.5);
  let sampleUV = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));

  let src = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
  let mist = smoothstep(0.55, 1.0, hash12(cell + vec2<f32>(0.0, floor(time * 2.0)))) * wetness * 0.12;
  let rainTint = mix(vec3<f32>(0.65, 0.78, 0.95), vec3<f32>(0.55, 0.95, 1.0), audio.y * 0.35);
  var finalColor = src.rgb + rainTint * drops * (0.18 + audio.z * 0.18);
  finalColor = mix(finalColor, finalColor * 0.75 + rainTint * 0.25, mist + mouseMask * wetness * 0.15);

  let finalAlpha = clamp(src.a * (1.0 - wetness * 0.35) + drops * 0.24 + mist + mouseMask * 0.06, 0.06, 0.98);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
  let outDepth = clamp(mix(depth, 0.22 + drops * 0.65, 0.20), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(drops, mist, mouseMask, finalAlpha));
}
