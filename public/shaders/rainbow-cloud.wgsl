// ================================================================
//  Rainbow Cloud
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, atmospheric
//  Complexity: Medium
//  Chunks From: rainbow-cloud
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
  zoom_params: vec4<f32>,  // x=CloudScale, y=DriftSpeed, z=Density, w=RainbowIntensity
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let a = hash12(i);
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var f = p;
  for (var i = 0; i < 4; i = i + 1) {
    v = v + noise(f) * a;
    f = f * 2.0 + 7.13;
    a = a * 0.5;
  }
  return v;
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

  let cloudScale = mix(1.5, 8.0, u.zoom_params.x);
  let driftSpeed = mix(0.02, 0.35, u.zoom_params.y);
  let density = mix(0.1, 0.95, u.zoom_params.z);
  let rainbowIntensity = mix(0.05, 1.0, u.zoom_params.w);

  let cloudUV = uv * vec2<f32>(aspect, 1.0) * cloudScale + vec2<f32>(time * driftSpeed, -time * driftSpeed * 0.4);
  let cloud = fbm(cloudUV + fbm(cloudUV * 0.6) * 1.2);
  let mouseMask = 1.0 - smoothstep(0.0, 0.65, length((uv - mouse) * vec2<f32>(aspect, 1.0)));
  let nebula = smoothstep(0.35, 0.9, cloud) * density;
  let hue = cloud + time * 0.05 + audio.y * 0.18;
  let rainbow = 0.5 + 0.5 * cos(6.28318 * (vec3<f32>(0.0, 0.25, 0.5) + hue));

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var finalColor = src.rgb;
  finalColor = mix(finalColor, finalColor * 0.7 + rainbow * 0.75, nebula * rainbowIntensity);
  finalColor = finalColor + rainbow * mouseMask * (0.06 + audio.x * 0.16);

  let finalAlpha = clamp(src.a * (1.0 - nebula * 0.25) + nebula * 0.30 + mouseMask * 0.06, 0.05, 0.98);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let outDepth = clamp(mix(depth, 0.25 + nebula * 0.55, 0.18), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(nebula, rainbowIntensity, mouseMask, finalAlpha));
}
