// ═══════════════════════════════════════════════════════════════════
//  Spectrogram Displace – Pass 2: Displacement & Compositing
//  Category: artistic
//  Features: multi-pass-2, image displacement, color grading,
//            vignette, audio-reactive
//  Complexity: Medium
//  Created: 2026-05-10
//  By: Phase A Upgrade Swarm
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

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let coord = vec2<u32>(gid.xy);
  let dim = textureDimensions(readTexture);
  if (coord.x >= dim.x || coord.y >= dim.y) { return; }

  let uvRaw = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(dim.x), f32(dim.y));
  let uv = clamp(uvRaw, vec2<f32>(0.0), vec2<f32>(1.0));

  let field = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let spectroColor = field.rgb;
  let magnitude = max(field.a, 0.001);

  let effectiveMag = select(u.zoom_params.z, 1.0, u.zoom_params.z < 0.01);

  let bass = plasmaBuffer[0].x;
  let audioBoost = 1.0 + bass * 0.8;

  let src = textureLoad(readTexture, vec2<i32>(i32(coord.x), i32(coord.y)), 0);
  let freqFactor = clamp(1.0 - uv.y, 0.001, 1.0);
  let displacementX = magnitude * (src.r - src.b) * 50.0 * effectiveMag * audioBoost;
  let displacementY = magnitude * (src.g - 0.5) * 30.0 * effectiveMag * freqFactor * audioBoost;
  let waveDisp = sin(uv.y * 20.0 + u.config.x * 3.0) * magnitude * 10.0 * audioBoost;

  var displacedX = i32(coord.x) + i32(displacementX + waveDisp);
  var displacedY = i32(coord.y) + i32(displacementY);
  displacedX = (displacedX + i32(dim.x)) % i32(dim.x);
  displacedY = (displacedY + i32(dim.y)) % i32(dim.y);

  let displacedColor = textureLoad(readTexture, vec2<i32>(displacedX, displacedY), 0);

  let blendFactor = magnitude * 0.3 * audioBoost;
  var finalColor = displacedColor.rgb;
  finalColor = finalColor + spectroColor * magnitude * 0.5 * effectiveMag * audioBoost;

  let lowFreqBoost = select(1.0 + magnitude * 0.2 * audioBoost, 1.0, uv.y > 0.7);
  let highFreqBoost = select(1.0 + magnitude * 0.1 * audioBoost, 1.0, uv.y < 0.3);
  finalColor = finalColor * vec3<f32>(lowFreqBoost, 1.0, highFreqBoost);

  let vignette = clamp(1.0 - magnitude * 0.3, 0.0, 1.0);
  finalColor = finalColor * vignette;
  finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));

  let luma = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(magnitude * 0.6 + luma * 0.3 + 0.1, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(i32(coord.x), i32(coord.y)), vec4<f32>(finalColor, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(i32(coord.x), i32(coord.y)), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
