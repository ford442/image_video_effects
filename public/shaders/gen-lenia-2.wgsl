// ═══════════════════════════════════════════════════════════════════
//  Lenia 2.0 - Multi-Species
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: growth-field membranes — the zero crossing of each species' Lenia growth mapping G(U) is rendered as a glowing cell wall, brighter on the advancing (dM/dt>0) front; mass-field gel relief — per-species mass gradient gives creature normals for diffuse/specular shading with Beer-Lambert absorption through thick bodies
//  A packing: raw sim state (species R mass, species G mass, species B mass, species A mass) — C feeds back as Lenia state; ACES display RGBA on writeTexture only
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
  config: vec4<f32>,       // x=time, y=rippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Global Growth, y=Kernel Radius, z=Evolution Speed, w=Cross-Species Mix
  ripples: array<vec4<f32>, 50>,
};

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

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

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn load_state(pixel: vec2<i32>, size: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), size - vec2<i32>(1)), 0);
}

// 8-sample radial kernel at 45 degree intervals
fn kernel_sample_8(pixel: vec2<i32>, size: vec2<i32>, radius: f32, kernel_type: i32) -> vec4<f32> {
  var acc = vec4<f32>(0.0);
  var weightSum = 0.0;
  for (var i: i32 = 0; i < 8; i = i + 1) {
    let angle = f32(i) * 0.785398;
    let off = vec2<i32>(round(vec2<f32>(cos(angle), sin(angle)) * radius));
    let s = load_state(pixel + off, size);
    let dist = f32(i) / 7.0;
    var w: f32;
    if (kernel_type == 0) { w = kernel_gaussian(dist, 0.4); }
    else if (kernel_type == 1) { w = kernel_mexican_hat(dist, 0.4); }
    else if (kernel_type == 2) { w = 1.0 - dist * 0.6; }
    else { w = 1.0 - abs(cos(angle)) * 0.5; }
    acc = acc + s * w;
    weightSum = weightSum + abs(w);
  }
  return acc / max(weightSum, 0.001);
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
  let coord = vec2<i32>(id.xy);
  let size = vec2<i32>(i32(res.x), i32(res.y));
  let uv = (vec2<f32>(id.xy) + vec2<f32>(0.5)) / res;
  var state = load_state(coord, size);
  let stateEnergy = dot(state, vec4<f32>(1.0));
  if (stateEnergy < 0.00001) {
    let cell = floor(vec2<f32>(id.xy) / 7.0);
    let seed = hash21(cell);
    let seedMask = step(0.975, seed);
    state = vec4<f32>(
      seedMask * fract(seed * 7.31),
      seedMask * fract(seed * 13.17),
      seedMask * fract(seed * 19.73),
      seedMask * fract(seed * 29.41)
    ) * 0.65;
  }
  let time = u.config.x;
  let audioBass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let audioMid = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let audioHigh = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let audioReactivity = 1.0 + audioBass * 0.5;
  var mouse = u.zoom_config.yz;
  let globalGrowth = u.zoom_params.x;
  let kernelRadius = 2.0 + u.zoom_params.y * 24.0;
  let speed = u.zoom_params.z * 3.0;
  let crossMix = u.zoom_params.w;
  // 4 kernels x 8-sample radial convolution
  var conv = vec4<f32>(0.0);
  for (var i: i32 = 0; i < 4; i = i + 1) {
    let ksample = kernel_sample_8(coord, size, kernelRadius * (0.8 + f32(i) * 0.15), i);
    let modulate = 0.8 + sin(time + f32(i)) * 0.2 * audioReactivity;
    conv = conv + ksample * modulate;
  }
  conv = conv / 4.0;
  // Species-specific growth with DNA trait inheritance.
  // Bass nudges the growth centre mu upward a little (denser creatures on the beat).
  let muKick = audioBass * 0.03;
  var growth = vec4<f32>(
    bell(conv.r, 0.35 + globalGrowth * 0.3 + muKick, 0.18),
    bell(conv.g, 0.42 + globalGrowth * 0.25 + muKick, 0.22),
    bell(conv.b, 0.28 + globalGrowth * 0.35 + muKick, 0.15),
    bell(conv.a, 0.38 + globalGrowth * 0.28 + muKick, 0.20)
  ) * 2.0 - 1.0;
  let growthField = growth; // G(U) before predator-prey coupling, used by the membrane render
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
  // Pressed mouse food injection; hover alone does not continuously overwrite state.
  let md = length(uv - mouse);
  if (u.zoom_config.w > 0.5 && md < 0.22) {
    let strength = (1.0 - md * 4.5) * 0.5;
    newState.r = newState.r + strength * 0.3;
    newState.g = newState.g + strength * 0.25;
    newState.b = newState.b + strength * 0.35;
    newState.a = newState.a + strength * 0.2;
  }
  let aspect = res.x / res.y;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 1.6) {
      let radius = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
      let inoculation = smoothstep(0.12, 0.0, radius) * exp(-age * 3.0);
      let species = i % 4u;
      let seedSpecies = select(
        select(vec4<f32>(0.0, 0.0, 1.0, 0.0), vec4<f32>(0.0, 0.0, 0.0, 1.0), species == 3u),
        select(vec4<f32>(1.0, 0.0, 0.0, 0.0), vec4<f32>(0.0, 1.0, 0.0, 0.0), species == 1u),
        species < 2u
      );
      newState = newState + seedSpecies * inoculation * 0.22;
    }
  }
  // Audio-reactive global pulse (fixed frequency; bass scales amplitude, no phase jumps)
  let pulse = (sin(time * 12.0) * 0.3 + sin(time * 28.0) * 0.15) * audioReactivity;
  newState = newState + vec4<f32>(pulse, pulse * 1.3, pulse * 0.8, pulse * 1.1) * 0.015;
  newState = clamp(newState, vec4<f32>(0.0), vec4<f32>(1.0));
  // DNA-based color remapping
  let dnaColor = species_to_color(newState);
  var finalColor = mix(newState.rgb, dnaColor, 0.35);

  // Chromatic dispersion samples neighboring simulation state, not source media.
  let chrStrength = 0.004 + audioBass * 0.008;
  let chrPx = max(1, i32(chrStrength * res.y));
  let chrR = load_state(coord + vec2<i32>(chrPx, 0), size).r;
  let chrG = load_state(coord + vec2<i32>(0, chrPx), size).g;
  let chrB = load_state(coord + vec2<i32>(-chrPx, chrPx / 2), size).b;
  let chrColor = vec3<f32>(chrR, chrG, chrB);
  finalColor = mix(finalColor, chrColor, 0.2 + audioBass * 0.15);

  // ── Idea 1: growth-field membranes ──
  // Where a species' growth mapping G(U) crosses zero the creature is at its wall:
  // inside grows, outside decays. Brighter on the advancing front (dM/dt > 0).
  let speciesHue = array<vec3<f32>, 4>(
    vec3<f32>(1.0, 0.25, 0.12), vec3<f32>(0.25, 1.0, 0.35),
    vec3<f32>(0.15, 0.45, 1.0), vec3<f32>(0.85, 0.35, 1.0)
  );
  let dM = newState - state;
  var membrane = vec3<f32>(0.0);
  var membraneCov = 0.0;
  let wallWidth = 0.10 + crossMix * 0.08;
  for (var s: i32 = 0; s < 4; s = s + 1) {
    let g = growthField[s];
    let present = smoothstep(0.03, 0.18, conv[s]);
    let wall = exp(-(g / wallWidth) * (g / wallWidth)) * present;
    let front = 0.55 + 0.45 * smoothstep(0.0, 0.01, dM[s]);
    membrane = membrane + speciesHue[s] * wall * front;
    membraneCov = max(membraneCov, wall);
  }

  // ── Idea 2: mass-field gel relief ──
  // Total mass gradient from 4 exact neighbour loads gives a creature normal;
  // thick bodies absorb light per Beer-Lambert through their DNA colour.
  let reliefPx = max(1, i32(kernelRadius * 0.35));
  let mL = dot(load_state(coord - vec2<i32>(reliefPx, 0), size), vec4<f32>(0.25));
  let mR = dot(load_state(coord + vec2<i32>(reliefPx, 0), size), vec4<f32>(0.25));
  let mD = dot(load_state(coord - vec2<i32>(0, reliefPx), size), vec4<f32>(0.25));
  let mU = dot(load_state(coord + vec2<i32>(0, reliefPx), size), vec4<f32>(0.25));
  let normal = normalize(vec3<f32>((mL - mR) * 6.0, (mD - mU) * 6.0, 1.0));
  let lightDir = normalize(vec3<f32>((mouse - vec2<f32>(0.5)) * 1.5 + vec2<f32>(-0.35, -0.45), 0.8));
  let diffuse = max(dot(normal, lightDir), 0.0);
  let halfV = normalize(lightDir + vec3<f32>(0.0, 0.0, 1.0));
  let spec = pow(max(dot(normal, halfV), 0.0), 48.0) * (0.25 + audioHigh * 0.9);

  let density = dot(newState, vec4<f32>(0.25));
  let thickness = density * 3.0;
  let absorb = exp(-thickness * (vec3<f32>(1.0) - dnaColor) * 1.2);
  var litColor = finalColor * (0.7 + 0.5 * diffuse) * mix(vec3<f32>(1.0), absorb, 0.5);
  litColor = litColor + vec3<f32>(spec) * smoothstep(0.02, 0.12, density);
  litColor = litColor + membrane * (0.45 + audioMid * 0.5);

  let display = acesToneMap(litColor * 1.25);
  let alpha = clamp(density * 1.35 + membraneCov * 0.35, 0.0, 0.96);
  let depth = clamp(density + membraneCov * 0.05, 0.0, 1.0);
  textureStore(writeTexture, id.xy, vec4<f32>(display, alpha));
  textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
  // A payload is deliberately the raw four-species state (see header "A packing"); host copies A -> C.
  textureStore(dataTextureA, id.xy, newState);
}
