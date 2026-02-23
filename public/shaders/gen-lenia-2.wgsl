// ═══════════════════════════════════════════════════════════════
//  Lenia 2.0 - Multi-Species Smooth Life with 4 Kernels
//  Category: generative
//  Description: Advanced 4-species Lenia with 4 distinct kernels.
//               Creatures evolve, compete, and merge in real-time.
//  Features: 4-species, mouse-quadrant-food, cross-feeding
//  Tags: lenia, multi-species, 4-kernels, organic, creature, advanced
//  Author: ford442
// ═══════════════════════════════════════════════════════════════

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
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Bell growth function (species-specific peak & width)
fn bell(x: f32, peak: f32, width: f32) -> f32 {
  return exp(-pow((x - peak) / width, 2.0));
}

// Sample neighborhood with one of 4 kernels
fn kernelSample(uv: vec2<f32>, offset: vec2<f32>, kernelType: f32, kernelRadius: f32) -> vec4<f32> {
  let p = clamp(uv + offset * kernelRadius * 0.008, vec2<f32>(0.0), vec2<f32>(1.0));
  let s = textureSampleLevel(readTexture, u_sampler, p, 0.0);
  if (kernelType < 0.25) { return s * 1.2; }
  if (kernelType < 0.5)  { return s * 0.9; }
  if (kernelType < 0.75) { return s * (1.0 - length(offset) * 0.6); }
  return s * (1.0 - abs(offset.x) - abs(offset.y)) * 1.5;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
  let res = u.config.zw;
  if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }

  let uv = vec2<f32>(id.xy) / res;
  let state = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;

  // Parameters
  let globalGrowth = u.zoom_params.x;
  let kernelRadius = u.zoom_params.y * 3.6 + 0.4;
  let speed = u.zoom_params.z * 3.0;
  let crossMix = u.zoom_params.w;

  // 4 kernels × 4 species convolution
  var conv = vec4<f32>(0.0);
  for (var i: i32 = 0; i < 4; i++) {
    let off = vec2<f32>(sin(f32(i) * 1.57), cos(f32(i) * 1.57));
    let kType = f32(i) * 0.25;
    conv += kernelSample(uv, off, kType, kernelRadius) * (0.8 + sin(time + f32(i)) * 0.2);
  }
  conv /= 6.0;

  // Species-specific growth
  var growth = vec4<f32>(
    bell(conv.r, 0.35 + globalGrowth * 0.3, 0.18),
    bell(conv.g, 0.42 + globalGrowth * 0.25, 0.22),
    bell(conv.b, 0.28 + globalGrowth * 0.35, 0.15),
    bell(conv.a, 0.38 + globalGrowth * 0.28, 0.20)
  ) * 2.0 - 1.0;

  // Update with speed + cross-species mixing
  var newState = state * 0.94 + growth * speed * 0.035;
  newState = mix(newState, newState.gbra, crossMix * 0.12);

  // Mouse food injection
  let md = length(uv - mouse);
  if (md < 0.22) {
    let strength = (1.0 - md * 4.5) * 0.5;
    newState.r += strength * 0.3;
    newState.g += strength * 0.25;
    newState.b += strength * 0.35;
    newState.a += strength * 0.2;
  }

  // Audio-reactive global pulse
  let pulse = sin(time * 12.0) * 0.3 + sin(time * 28.0) * 0.15;
  newState += vec4<f32>(pulse, pulse * 1.3, pulse * 0.8, pulse * 1.1) * 0.015;

  newState = clamp(newState, vec4<f32>(0.0), vec4<f32>(1.0));

  textureStore(writeTexture, id.xy, newState);
  textureStore(writeDepthTexture, id.xy, vec4<f32>(newState.r * 0.25 + newState.g * 0.25 + newState.b * 0.25 + newState.a * 0.25, 0.0, 0.0, 0.0));
}
