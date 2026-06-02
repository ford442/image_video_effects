// ================================================================
//  Data Slicer
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: data-slicer
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=JitterSpeed, y=SliceThickness, z=ChaosAmount, w=ColorSplit
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  let h = sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453;
  return fract(h);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let audio = plasmaBuffer[0].xyz;

  let jitterSpeed = 0.15 + u.zoom_params.x * 3.5;
  let sliceThickness = mix(0.006, 0.12, u.zoom_params.y);
  let chaosAmount = u.zoom_params.z * 0.12;
  let colorSplit = u.zoom_params.w * 0.03;

  let sliceIndex = floor(uv.y / sliceThickness);
  let localY = fract(uv.y / sliceThickness);
  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let mouseMask = 1.0 - smoothstep(0.0, 0.65, mouseDist);

  let jitterSeed = vec2<f32>(sliceIndex, floor(time * jitterSpeed * 6.0));
  let jitter = (hash12(jitterSeed) - 0.5) * chaosAmount * (1.0 + audio.x * 0.8 + mouseMask * 0.5);
  let wave = sin(sliceIndex * 0.33 + time * jitterSpeed * 5.0 + uv.x * 18.0) * chaosAmount * 0.30;
  let sliceBend = sin(localY * 6.28318 + time * 2.0 + sliceIndex * 0.4) * chaosAmount * 0.18;

  let baseUV = clamp(uv + vec2<f32>(jitter + wave + sliceBend * mouseMask, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let splitDir = vec2<f32>(colorSplit * (0.4 + mouseMask), 0.0);
  let sampleR = clamp(baseUV + splitDir, vec2<f32>(0.0), vec2<f32>(1.0));
  let sampleB = clamp(baseUV - splitDir, vec2<f32>(0.0), vec2<f32>(1.0));

  var finalColor = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, sampleR, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, baseUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, sampleB, 0.0).b
  );

  let scanGlow = (1.0 - smoothstep(0.15, 0.50, abs(localY - 0.5))) * (0.08 + 0.18 * audio.y);
  let glitchTint = mix(vec3<f32>(0.05, 0.65, 1.0), vec3<f32>(1.0, 0.35, 0.85), audio.z * 0.6 + mouseMask * 0.25);
  finalColor = finalColor + glitchTint * scanGlow;

  let finalAlpha = clamp(0.76 + mouseMask * 0.12 + abs(jitter + wave) * 1.4, 0.45, 0.98);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, baseUV, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.25 + scanGlow + mouseMask * 0.25, 0.25 + chaosAmount * 2.0), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(abs(jitter), scanGlow, mouseMask, finalAlpha));
}
