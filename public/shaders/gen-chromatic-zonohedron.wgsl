// ═══════════════════════════════════════════════════════════════════
//  Chromatic Zonohedron
//  Category: generative
//  Features: rhombic zonohedron facets, spectral face colors, dual-grid
//            wireframe, mouse warp, audio pulse, domain-warped background
//  Complexity: High
//  Created: 2026-07-12
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

// Rhombic zonohedron in 2D projection: sum of 3 axis rhomb tilings
fn zonoFacet(p: vec2<f32>, axis: vec2<f32>, width: f32) -> f32 {
  let n = vec2<f32>(-axis.y, axis.x);
  let u = dot(p, axis);
  let v = dot(p, n);
  let du = abs(fract(u / width + 0.5) - 0.5) * width;
  let dv = abs(fract(v / width + 0.5) - 0.5) * width;
  return max(du, dv);
}

fn zonoSDF(p: vec2<f32>, scale: f32) -> vec2<f32> {
  let a0 = vec2<f32>(1.0, 0.0);
  let a1 = vec2<f32>(0.5, 0.8660254);
  let a2 = vec2<f32>(-0.5, 0.8660254);
  let w = scale * 0.22;
  let f0 = zonoFacet(p, a0, w);
  let f1 = zonoFacet(p, a1, w);
  let f2 = zonoFacet(p, a2, w);
  let cell = min(min(f0, f1), f2);
  let edge = min(min(abs(f0 - f1), abs(f1 - f2)), abs(f2 - f0));
  return vec2<f32>(cell, edge);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
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
  let facetId = floor(p.x * 3.7 + p.y * 2.3 + time * 0.1);
  let hue = fract(facetId * 0.13 + colorCycle + length(p) * 0.2 + treble * 0.15);

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

  let prev = textureLoad(dataTextureC, pixel, 0);
  color = mix(color, prev.rgb, 0.03);
  color = acesToneMap(color * (1.2 + mids * 0.15));

  let alpha = clamp(facetFill * 0.7 + edgeLine * 0.9 + 0.05, 0.0, 1.0);
  let depthOut = clamp(facetFill * 0.5 + edgeLine * 0.3, 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, pixel, vec4<f32>(z.x, hue, alpha, facetFill));
}
