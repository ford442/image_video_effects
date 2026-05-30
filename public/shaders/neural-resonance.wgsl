// ================================================================
//  Neural Resonance
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal
//  Complexity: Medium
//  Chunks From: neural-resonance
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
  zoom_params: vec4<f32>,  // x=Amplification, y=CurlStrength, z=FeedbackMix, w=ChromaticDrift
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

fn curlField(p: vec2<f32>, t: f32) -> vec2<f32> {
  let e = 0.01;
  let n1 = noise(p + vec2<f32>(0.0, e) + t);
  let n2 = noise(p - vec2<f32>(0.0, e) + t);
  let n3 = noise(p + vec2<f32>(e, 0.0) - t);
  let n4 = noise(p - vec2<f32>(e, 0.0) - t);
  return vec2<f32>(n1 - n2, -(n3 - n4)) / (2.0 * e);
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

  let amplification = mix(0.15, 1.35, u.zoom_params.x) * (1.0 + audio.x * 0.45);
  let curlStrength = mix(0.005, 0.08, u.zoom_params.y);
  let feedbackMix = mix(0.25, 0.96, u.zoom_params.z);
  let chromaticDrift = mix(0.0, 0.03, u.zoom_params.w);

  let aspectUV = uv * vec2<f32>(aspect, 1.0);
  let mouseDelta = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let mouseMask = 1.0 - smoothstep(0.0, 0.65, length(mouseDelta));
  let curl = curlField(aspectUV * (2.0 + amplification), time * 0.15) * curlStrength;
  let warpedUV = clamp(uv + curl / vec2<f32>(aspect, 1.0) * (0.4 + mouseMask * 1.2), vec2<f32>(0.0), vec2<f32>(1.0));

  let source = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);
  let feedback = textureSampleLevel(dataTextureC, u_sampler, warpedUV, 0.0);
  let split = curl * chromaticDrift * (0.8 + audio.z * 0.6);
  let chroma = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    source.g,
    textureSampleLevel(readTexture, u_sampler, clamp(warpedUV - split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );

  let synapseTint = mix(vec3<f32>(0.10, 0.75, 1.0), vec3<f32>(1.0, 0.35, 0.85), 0.5 + 0.5 * sin(time * 0.7 + noise(aspectUV * 4.0) * 6.28318));
  var finalColor = mix(chroma, feedback.rgb, feedbackMix * (0.4 + mouseMask * 0.6));
  finalColor = mix(finalColor, finalColor + synapseTint * (0.08 + audio.y * 0.18), 0.55);

  let finalAlpha = clamp(mix(source.a, feedback.a, feedbackMix) + mouseMask * 0.12, 0.02, 0.98);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, warpedUV, 0.0).r;
  let outDepth = clamp(mix(baseDepth, 0.24 + mouseMask * 0.58, 0.22), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(mouseMask, feedbackMix, length(curl) * 10.0, finalAlpha));
}
