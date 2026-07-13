// ═══════════════════════════════════════════════════════════════════
//  Bioluminescent Reaction-Diffusion
//  Category: generative
//  Features: mouse-driven, audio-reactive, simulation, upgraded-rgba,
//            chromatic-species, temporal-mutation, depth-scaled-glow,
//            dual-laplacian, multi-scale-rd, curl-advection,
//            domain-warped-fbm, strange-attractor, plankton-sdf
//  Complexity: High
//  Created: 2026-05-10
//  Upgraded: 2026-07-13
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(acesToneMap(controlled * 1.1), color.a);
}

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, vec3<f32>(p3.y, p3.z, p3.x) + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i = 0; i < 4; i = i + 1) {
    value += amplitude * noise2(p * frequency);
    amplitude *= 0.5;
    frequency *= 2.0;
  }
  return value;
}

fn curl2(p: vec2<f32>) -> vec2<f32> {
  let eps = 0.01;
  let dx = noise2(p + vec2<f32>(eps, 0.0)) - noise2(p - vec2<f32>(eps, 0.0));
  let dy = noise2(p + vec2<f32>(0.0, eps)) - noise2(p - vec2<f32>(0.0, eps));
  return vec2<f32>(-dy, dx) / (2.0 * eps);
}

fn domainWarp(uv: vec2<f32>, t: f32, scale: f32) -> f32 {
  let q = vec2<f32>(fbm(uv * scale + t * 0.1), fbm(uv * scale + vec2<f32>(5.2, 1.3) + t * 0.08));
  let r = vec2<f32>(
    fbm(uv * scale * 2.0 + 4.0 * q + t * 0.05),
    fbm(uv * scale * 2.0 + vec2<f32>(8.3, 2.7) * q + t * 0.04)
  );
  return fbm(uv * scale * 4.0 + r);
}

fn laplacianDual(coord: vec2<i32>, ch: i32, wideMix: f32) -> f32 {
  let center = textureLoad(dataTextureC, coord, 0)[ch];

  // 3x3 Moore neighbor-weight set
  var moore = center * -1.0;
  moore += textureLoad(dataTextureC, coord + vec2<i32>(1, 0), 0)[ch] * 0.2;
  moore += textureLoad(dataTextureC, coord + vec2<i32>(-1, 0), 0)[ch] * 0.2;
  moore += textureLoad(dataTextureC, coord + vec2<i32>(0, 1), 0)[ch] * 0.2;
  moore += textureLoad(dataTextureC, coord + vec2<i32>(0, -1), 0)[ch] * 0.2;
  moore += textureLoad(dataTextureC, coord + vec2<i32>(1, 1), 0)[ch] * 0.05;
  moore += textureLoad(dataTextureC, coord + vec2<i32>(-1, -1), 0)[ch] * 0.05;
  moore += textureLoad(dataTextureC, coord + vec2<i32>(1, -1), 0)[ch] * 0.05;
  moore += textureLoad(dataTextureC, coord + vec2<i32>(-1, 1), 0)[ch] * 0.05;

  // 5x5 high-order cross neighbor-weight set
  var cross = center * -0.625;
  cross += textureLoad(dataTextureC, coord + vec2<i32>(1, 0), 0)[ch] * 0.1666667;
  cross += textureLoad(dataTextureC, coord + vec2<i32>(-1, 0), 0)[ch] * 0.1666667;
  cross += textureLoad(dataTextureC, coord + vec2<i32>(0, 1), 0)[ch] * 0.1666667;
  cross += textureLoad(dataTextureC, coord + vec2<i32>(0, -1), 0)[ch] * 0.1666667;
  cross += textureLoad(dataTextureC, coord + vec2<i32>(2, 0), 0)[ch] * -0.01041667;
  cross += textureLoad(dataTextureC, coord + vec2<i32>(-2, 0), 0)[ch] * -0.01041667;
  cross += textureLoad(dataTextureC, coord + vec2<i32>(0, 2), 0)[ch] * -0.01041667;
  cross += textureLoad(dataTextureC, coord + vec2<i32>(0, -2), 0)[ch] * -0.01041667;

  return mix(moore, cross, wideMix);
}

fn strangeAttractorOrbit(uv: vec2<f32>, t: f32) -> f32 {
  var p = uv * 6.0 - 3.0;
  var orbit = 1e10;
  for (var i = 0; i < 30; i = i + 1) {
    let nx = sin(p.y * 1.1 + t * 0.3) * 1.8 - 0.5 * p.x;
    let ny = sin(p.x * 1.2 - t * 0.2) * 1.8 - 0.5 * p.y;
    p = vec2<f32>(nx, ny);
    orbit = min(orbit, length(p - uv * 6.0 + 3.0));
  }
  return smoothstep(0.8, 0.0, orbit);
}

fn planktonSDF(uv: vec2<f32>, t: f32) -> f32 {
  let cells = floor(uv * 16.0);
  let rnd = hash21(cells + t * 0.05);
  let center = cells + 0.5 + 0.3 * vec2<f32>(cos(t + rnd * 6.2831853), sin(t * 0.7 + rnd * 6.2831853));
  let d = length(uv * 16.0 - center);
  let radius = 0.15 + 0.1 * rnd;
  return smoothstep(radius, radius * 0.3, d);
}

fn stepSpecies(
  a: f32, b: f32,
  lapA: f32, lapB: f32,
  feed: f32, kill: f32,
  diffA: f32, diffB: f32,
  dt: f32
) -> vec2<f32> {
  let reaction = a * b * b;
  let newA = a + dt * (diffA * lapA - reaction + feed * (1.0 - a));
  let newB = b + dt * (diffB * lapB + reaction - (kill + feed) * b);
  return clamp(vec2<f32>(newA, newB), vec2<f32>(0.0), vec2<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let center = textureLoad(dataTextureC, coord, 0);

  // Branchless initialization: both species start as (A=1, B=0)
  let initMask = select(0.0, 1.0, time < 0.1);
  var a1 = mix(center.x, 1.0, initMask);
  var b1 = mix(center.y, 0.0, initMask);
  var a2 = mix(center.z, 1.0, initMask);
  var b2 = mix(center.w, 0.0, initMask);

  // Spatial feed/kill modulation via domain-warped FBM
  let warp = domainWarp(uv, time, mix(2.0, 8.0, u.zoom_params.z));
  let luma = dot(textureLoad(readTexture, coord, 0).rgb, vec3<f32>(0.299, 0.587, 0.114));

  // Audio-driven temporal drift for feed/kill rates
  let feedBase = mix(0.01, 0.08, luma);
  let killBase = mix(0.045, 0.065, luma);
  let feedDrift = 0.015 * sin(time * 0.2 + mids * 3.0);
  let killDrift = 0.008 * cos(time * 0.15 + bass * 3.0);

  // Species 1: fast, fine-scale, audio-tight
  let lapA1 = laplacianDual(coord, 0, 0.25 + treble * 0.25);
  let lapB1 = laplacianDual(coord, 1, 0.25 + treble * 0.25);
  let feed1 = clamp(feedBase + feedDrift + warp * 0.01, 0.0, 0.15);
  let kill1 = clamp(killBase + killDrift + warp * 0.005, 0.0, 0.1);
  let diffA1 = mix(1.0, 0.4, bass);
  let diffB1 = mix(0.5, 0.15, bass);
  let s1 = stepSpecies(a1, b1, lapA1, lapB1, feed1, kill1, diffA1, diffB1, 1.0);

  // Species 2: slow, large-scale, inhibited by species 1
  let lapA2 = laplacianDual(coord, 2, 0.6 + bass * 0.3);
  let lapB2 = laplacianDual(coord, 3, 0.6 + bass * 0.3);
  let feed2 = clamp(feedBase * 0.7 - s1.y * 0.01 + warp * 0.008, 0.0, 0.12);
  let kill2 = clamp(killBase * 0.85 + feedDrift * 0.5, 0.0, 0.09);
  let diffA2 = mix(0.6, 0.2, bass);
  let diffB2 = mix(0.3, 0.1, bass);
  let s2 = stepSpecies(a2, b2, lapA2, lapB2, feed2, kill2, diffA2, diffB2, 0.7);

  // Curl-noise advection sampled from neighboring pixels
  let advect = curl2(uv * mix(3.0, 9.0, u.zoom_params.z) + time * 0.1) * (0.5 + bass) * 0.02;
  let advectCoord = coord + vec2<i32>(advect * resolution);
  let advectA = textureLoad(dataTextureC, advectCoord, 0).x;
  let advectB = textureLoad(dataTextureC, advectCoord, 0).w;

  // Blend advected samples into species 1 for organic flow
  var finalA1 = mix(s1.x, advectA, 0.15 + mids * 0.1);
  var finalB1 = mix(s1.y, advectB, 0.1 + treble * 0.05);
  let finalA2 = s2.x;
  let finalB2 = s2.y;

  // Procedural complexity layers injected as branchless seed sources
  let attractor = strangeAttractorOrbit(uv, time) * 0.06;
  let plankton = planktonSDF(uv, time) * 0.04 * (0.5 + treble);
  finalA1 = clamp(finalA1 + attractor * (1.0 - finalA1) + plankton * (1.0 - finalA1), 0.0, 1.0);
  finalB1 = clamp(finalB1 + plankton * (1.0 - finalB1) - attractor * finalB1 * 0.3, 0.0, 1.0);

  // Mouse seeding via smooth branchless falloff
  let mouse = u.zoom_config.yz;
  let distToMouse = distance(vec2<f32>(coord), mouse * resolution);
  let mouseSeed = 1.0 - smoothstep(0.0, mix(20.0, 70.0, u.zoom_params.w), distToMouse);
  let seededB1 = mix(finalB1, 1.0, mouseSeed);

  // State write: species 1 -> xy, species 2 -> zw
  let state = vec4<f32>(finalA1, seededB1, finalA2, finalB2);
  textureStore(dataTextureA, coord, state);

  // Bioluminescent color mapping
  let concDiff = clamp(finalA1 - seededB1 + finalA2 * 0.3, 0.0, 1.0);
  let plasmaIndex = u32(concDiff * 255.0);
  let color = plasmaBuffer[plasmaIndex % 256u];

  // Chromatic species separation: A = green/cyan, B = magenta/purple
  let speciesA = vec3<f32>(0.2, 0.9, 0.6) * finalA1 * (1.0 + treble * 0.35);
  let speciesB = vec3<f32>(0.9, 0.3, 0.75) * seededB1 * (1.0 + mids * 0.35);
  let speciesDeep = vec3<f32>(0.1, 0.4, 0.9) * finalA2 * (1.0 + bass * 0.25);
  let mixedSpecies = mix(color.rgb, speciesA + speciesB + speciesDeep * 0.5, 0.5 + bass * 0.25);

  let glow = clamp(seededB1 * 2.2 + finalA1 * 0.3 + finalB2 * 0.4, 0.0, 1.0);

  // Depth-scaled glow intensity
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthScale = 0.5 + depth * 0.5;

  let video_color = textureLoad(readTexture, coord, 0);
  let alpha = mix(video_color.a, 1.0, glow * 0.75 * depthScale);
  let finalRGB = mixedSpecies * glow * depthScale;

  textureStore(writeTexture, coord, applyGenerativePrimaryControls(vec4<f32>(finalRGB, alpha)));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
