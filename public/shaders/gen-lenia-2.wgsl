// ═══════════════════════════════════════════════════════════════
//  DNA-Encoded Multi-Species Ecosystem
//  Category: generative
//  Description: Advanced 4-species Lenia with DNA-encoded traits,
//               8-sample radial kernels, and predator-prey dynamics.
//  Features: 4-species, dna-encoding, predator-prey, caustics
//  Tags: lenia, multi-species, dna, organic, creature, advanced
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

// Gaussian kernel profile
fn kernel_gaussian(x: f32, sigma: f32) -> f32 {
  let a = x / sigma;
  return exp(-0.5 * a * a);
}

// Mexican hat (Laplacian of Gaussian) kernel profile
fn kernel_mexican_hat(x: f32, sigma: f32) -> f32 {
  let a = x / sigma;
  return (1.0 - a * a) * exp(-0.5 * a * a);
}

// 8-sample radial kernel at 45 degree intervals
fn kernel_sample_8(uv: vec2<f32>, radius: f32, kernel_type: i32) -> vec4<f32> {
  var acc = vec4<f32>(0.0);
  for (var i: i32 = 0; i < 8; i = i + 1) {
    let angle = f32(i) * 0.785398;
    let off = vec2<f32>(cos(angle), sin(angle)) * radius * 0.008;
    let p = clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0));
    let s = textureSampleLevel(readTexture, u_sampler, p, 0.0);
    let dist = f32(i) / 7.0;
    var w: f32;
    if (kernel_type == 0) { w = kernel_gaussian(dist, 0.4); }
    else if (kernel_type == 1) { w = kernel_mexican_hat(dist, 0.4); }
    else if (kernel_type == 2) { w = 1.0 - dist * 0.6; }
    else { w = 1.0 - abs(cos(angle)) * 0.5; }
    acc = acc + s * w;
  }
  return acc / 8.0;
}

// 4x4 predator-prey interaction matrix
fn species_interaction(species_a: f32, species_b: f32) -> f32 {
  let sa = clamp(species_a, 0.0, 1.0);
  let sb = clamp(species_b, 0.0, 1.0);
  let ia = i32(sa * 3.99);
  let ib = i32(sb * 3.99);
  if (ia == ib) { return 0.0; }
  if ((ia == 0 && ib == 1) || (ia == 1 && ib == 2) || (ia == 2 && ib == 3) || (ia == 3 && ib == 0)) {
    return 0.08;
  }
  return -0.04;
}

// DNA-based color mapping from species traits
fn species_to_color(dna: vec4<f32>) -> vec3<f32> {
  let avg = (dna.r + dna.g + dna.b + dna.a) * 0.25;
  let dominance = vec4<f32>(dna.r - avg, dna.g - avg, dna.b - avg, dna.a - avg);
  var c = vec3<f32>(0.0);
  c = c + vec3<f32>(1.0, 0.2, 0.1) * clamp(dominance.r, 0.0, 1.0);
  c = c + vec3<f32>(0.2, 1.0, 0.3) * clamp(dominance.g, 0.0, 1.0);
  c = c + vec3<f32>(0.1, 0.4, 1.0) * clamp(dominance.b, 0.0, 1.0);
  c = c + vec3<f32>(0.8, 0.3, 1.0) * clamp(dominance.a, 0.0, 1.0);
  return clamp(c, vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
  let res = u.config.zw;
  if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }
  var uv = vec2<f32>(id.xy) / res;
  let state = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let time = u.config.x;
  let audioBass = plasmaBuffer[0].x;
  let audioMid = plasmaBuffer[0].y;
  let audioHigh = plasmaBuffer[0].z;
  let audioReactivity = 1.0 + audioBass * 0.5;
  var mouse = u.zoom_config.yz;
  let globalGrowth = u.zoom_params.x;
  let kernelRadius = u.zoom_params.y * 3.6 + 0.4;
  let speed = u.zoom_params.z * 3.0;
  let crossMix = u.zoom_params.w;
  // 4 kernels x 8-sample radial convolution
  var conv = vec4<f32>(0.0);
  for (var i: i32 = 0; i < 4; i = i + 1) {
    let ksample = kernel_sample_8(uv, kernelRadius * (0.8 + f32(i) * 0.15), i);
    let modulate = 0.8 + sin(time + f32(i)) * 0.2 * audioReactivity;
    conv = conv + ksample * modulate;
  }
  conv = conv / 4.0;
  // Species-specific growth with DNA trait inheritance
  var growth = vec4<f32>(
    bell(conv.r, 0.35 + globalGrowth * 0.3, 0.18),
    bell(conv.g, 0.42 + globalGrowth * 0.25, 0.22),
    bell(conv.b, 0.28 + globalGrowth * 0.35, 0.15),
    bell(conv.a, 0.38 + globalGrowth * 0.28, 0.20)
  ) * 2.0 - 1.0;
  // 4-species predator-prey interaction matrix
  var interactions = vec4<f32>(0.0);
  interactions.r = species_interaction(state.r, state.g) + species_interaction(state.r, state.b) + species_interaction(state.r, state.a);
  interactions.g = species_interaction(state.g, state.r) + species_interaction(state.g, state.b) + species_interaction(state.g, state.a);
  interactions.b = species_interaction(state.b, state.r) + species_interaction(state.b, state.g) + species_interaction(state.b, state.a);
  interactions.a = species_interaction(state.a, state.r) + species_interaction(state.a, state.g) + species_interaction(state.a, state.b);
  growth = growth + interactions * 0.5;
  // Update with speed + cross-species DNA mixing
  var newState = state * 0.94 + growth * speed * 0.035;
  newState = mix(newState, newState.gbra, crossMix * 0.12);
  // Mouse food injection
  let md = length(uv - mouse);
  if (md < 0.22) {
    let strength = (1.0 - md * 4.5) * 0.5;
    newState.r = newState.r + strength * 0.3;
    newState.g = newState.g + strength * 0.25;
    newState.b = newState.b + strength * 0.35;
    newState.a = newState.a + strength * 0.2;
  }
  // Audio-reactive global pulse
  let pulse = sin(time * 12.0 * audioReactivity) * 0.3 + sin(time * 28.0 * audioReactivity) * 0.15;
  newState = newState + vec4<f32>(pulse, pulse * 1.3, pulse * 0.8, pulse * 1.1) * 0.015;
  newState = clamp(newState, vec4<f32>(0.0), vec4<f32>(1.0));
  // DNA-based color remapping
  let dnaColor = species_to_color(newState);
  let finalColor = mix(newState.rgb, dnaColor, 0.35);
  textureStore(writeTexture, id.xy, vec4<f32>(finalColor, newState.a));
  textureStore(writeDepthTexture, id.xy, vec4<f32>(newState.r * 0.25 + newState.g * 0.25 + newState.b * 0.25 + newState.a * 0.25, 0.0, 0.0, 0.0));
}
