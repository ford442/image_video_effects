// ═══════════════════════════════════════════════════════════════════
//  Cyber Ripples
//  Category: interactive-mouse
//  Features: mouse-driven, wave, neon, audio-reactive
//  Complexity: Medium
//  Created: 2026-05-10
//  By: Phase A Upgrade Agent
// ═══════════════════════════════════════════════════════════════════

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
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  var uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  // Audio reactivity: bass drives ripple intensity
  let bass = plasmaBuffer[0].x;
  let audioBoost = 1.0 + bass * 0.5;

  // Params
  let speed = u.zoom_params.x * 5.0 + 1.0;         // 1.0 to 6.0
  let blockSize = u.zoom_params.y * 0.1;           // 0.0 to 0.1
  let aberration = u.zoom_params.z * 0.05;         // 0.0 to 0.05
  let frequency = u.zoom_params.w * 50.0 + 10.0;   // 10.0 to 60.0

  var mousePos = u.zoom_config.yz;

  // Aspect ratio correction for distance
  let aspect = resolution.x / resolution.y;
  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(mousePos.x * aspect, mousePos.y);

  let dist = distance(uvCorrected, mouseCorrected);

  // Digital Ripple
  // Use a step function or quantization on distance to make it look "digital"
  let quantizedDist = floor(dist * 20.0) / 20.0;
  let wave = sin(quantizedDist * frequency - time * speed);

  // Attenuate wave with distance; audio-reactive boost
  let strength = 1.0 / (dist * 5.0 + 0.5);
  let displacement = vec2<f32>(wave) * strength * 0.01 * audioBoost;

  var displacedUV = uv + displacement;

  // Pixelate / Blocky effect
  if (blockSize > 0.001) {
    let blocks = 1.0 / blockSize;
    displacedUV = floor(displacedUV * blocks) / blocks;
  }

  // Chromatic Aberration
  let redUV = displacedUV + vec2<f32>(aberration, 0.0);
  let blueUV = displacedUV - vec2<f32>(aberration, 0.0);

  let r = textureSampleLevel(readTexture, u_sampler, redUV, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, blueUV, 0.0).b;

  // Meaningful alpha based on ripple intensity and luminance
  let luminance = 0.299 * r + 0.587 * g + 0.114 * b;
  let rippleIntensity = clamp(abs(wave) * strength * 2.0, 0.0, 1.0);
  let alpha = clamp(0.5 + rippleIntensity * 0.4 + luminance * 0.1, 0.5, 1.0);

  let color = vec4<f32>(r, g, b, alpha);

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, vec2<i32>(global_id.xy), color);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
