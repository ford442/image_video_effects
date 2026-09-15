// ═══════════════════════════════════════════════════════════════════
//  Chromatic Zonohedron
//  Category: generative
//  Features: rhombic zonohedron facets, spectral face colors, dual-grid
//            wireframe, mouse warp, audio pulse, upgraded-rgba
//  Complexity: High
//  Created: 2026-07-12
//  Upgraded: 2026-09-15
//  Ideas: fourth golden-ratio generator; generator-axis dichroism; generator-pair face IDs; 3-space vertex stars
//  A packing: ACES display RGBA
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn spectral(t: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(TAU * (t + vec3<f32>(0.0, 0.33, 0.67)));
}

fn rot2(a: f32) -> mat2x2<f32> {
  let s = sin(a); let c = cos(a);
  return mat2x2<f32>(c, -s, s, c);
}

// Rhombic zonohedron in 2D projection: Minkowski sum of generator axes.
fn zonoFacet(p: vec2<f32>, axis: vec2<f32>, width: f32) -> f32 {
  let n = vec2<f32>(-axis.y, axis.x);
  let uu = dot(p, axis);
  let vv = dot(p, n);
  let du = abs(fract(uu / width + 0.5) - 0.5) * width;
  let dv = abs(fract(vv / width + 0.5) - 0.5) * width;
  return max(du, dv);
}

fn zonoSDF(p: vec2<f32>, scale: f32) -> vec4<f32> {
  let a0 = vec2<f32>(1.0, 0.0);
  let a1 = vec2<f32>(0.5, 0.8660254);
  let a2 = vec2<f32>(-0.5, 0.8660254);
  // Idea 1 — fourth generator (golden-ratio direction) → 4-vector zono rhombs.
  let a3 = vec2<f32>(0.80901699, 0.58778525);
  let w = scale * 0.22;
  let f0 = zonoFacet(p, a0, w);
  let f1 = zonoFacet(p, a1, w);
  let f2 = zonoFacet(p, a2, w);
  let f3 = zonoFacet(p, a3, w);
  let cell = min(min(f0, f1), min(f2, f3));
  let d01 = abs(f0 - f1);
  let d02 = abs(f0 - f2);
  let d03 = abs(f0 - f3);
  let d12 = abs(f1 - f2);
  let d13 = abs(f1 - f3);
  let d23 = abs(f2 - f3);
  let edge = min(min(min(d01, d02), min(d03, d12)), min(d13, d23));

  var winner = 0u;
  var best = f0;
  if (f1 < best) { best = f1; winner = 1u; }
  if (f2 < best) { best = f2; winner = 2u; }
  if (f3 < best) { best = f3; winner = 3u; }

  var runner = select(0u, 1u, winner == 0u);
  var second = select(f0, f1, winner == 0u);
  if (winner != 1u && f1 < second) { second = f1; runner = 1u; }
  if (winner != 2u && f2 < second) { second = f2; runner = 2u; }
  if (winner != 3u && f3 < second) { runner = 3u; }

  let lo = min(winner, runner);
  let hi = max(winner, runner);
  let pairId = f32(lo * 4u + hi);
  let star = max(max(max(d01, d02), max(d03, d12)), max(d13, d23));
  return vec4<f32>(cell, edge, f32(winner) + pairId * 0.125, star);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let time = u.config.x;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let mouse = u.zoom_config.yz;

  let facetScale = mix(0.8, 2.2, u.zoom_params.x) * (1.0 + bass * 0.2);
  let spin = time * mix(0.05, 0.4, u.zoom_params.y);
  let edgeWidth = mix(0.01, 0.06, u.zoom_params.z);
  let colorCycle = u.zoom_params.w;

  let aspect = res.x / max(res.y, 1.0);
  var p = (uv01 - 0.5) * vec2<f32>(aspect, 1.0) * 2.5;
  p += (mouse - vec2<f32>(0.5)) * 0.4;
  p = rot2(spin + mids * 0.3) * p;

  let z = zonoSDF(p, facetScale);
  // Idea 1: generator-axis dichroism — hue locked to the winning rhomb family
  let hue = fract(z.z * 0.333 + colorCycle + length(p) * 0.08 + treble * 0.15);

  let facetFill = smoothstep(edgeWidth * 2.0, 0.0, z.x);
  let edgeLine = smoothstep(edgeWidth, 0.0, z.y) * (1.0 - facetFill * 0.3);
  let facetCol = spectral(hue) * facetFill;
  let edgeCol = spectral(hue + 0.5) * edgeLine * (1.5 + bass * 0.5);

  // Prismatic background gradient
  let bg = spectral(length(p) * 0.15 + time * 0.03) * 0.08;
  var color = bg + facetCol * 0.85 + edgeCol;

  // Facet shimmer
  let shimmer = hash21(floor(p * facetScale * 8.0)) * treble * 0.2;
  color += spectral(hue + shimmer) * facetFill * shimmer;

  // Idea 2: 3-space vertex stars — all three generator distances match
  let star = smoothstep(edgeWidth * 2.4, 0.0, z.w) * (1.0 + bass * 0.5);
  color += vec3<f32>(1.0, 0.96, 0.85) * star * 0.85;

  let prev = textureLoad(dataTextureC, pixel, 0);
  color = mix(color, prev.rgb, 0.03);
  color = acesToneMap(color * (1.2 + mids * 0.15));

  let alpha = clamp(facetFill * 0.7 + edgeLine * 0.9 + star * 0.35 + 0.05, 0.0, 1.0);
  let depthOut = clamp(facetFill * 0.5 + edgeLine * 0.3 + star * 0.2, 0.0, 1.0);
  let outCol = vec4<f32>(color, alpha);

  textureStore(writeTexture, pixel, outCol);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, pixel, outCol);
}
