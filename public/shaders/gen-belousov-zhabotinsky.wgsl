// ═══════════════════════════════════════════════════════════════════
//  Belousov-Zhabotinsky Reaction - Chemical spiral wave oscillator
//  Category: generative
//  Features: upgraded-rgba, aces-tone-map, depth-aware, audio-reactive, temporal, mouse-driven, hue-preserve-clamp, ign-dither
//  Complexity: Medium
//  Created: 2026-05-30
//  Upgraded: 2026-06-07, 2026-09-15
//  Ideas: refractory-tail shading behind the wavefront; pacemaker excitability gradient forming target-wave zones
//  A packing: raw sim (newA, newB, waveFront, alpha) + B detail (lapA, lapB, oxidized, waveFront^2)
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

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: hue-preserve-clamp (from AGENTS.md) ═══
fn huePreserveClamp(c: vec3<f32>, maxLum: f32) -> vec3<f32> {
  let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
  return c * min(1.0, maxLum / max(l, 1e-4));
}

// ═══ CHUNK: ign-dither (from AGENTS.md) ═══
fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let time = u.config.x;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let coord = vec2<i32>(global_id.xy);
  let bass = plasmaBuffer[0].x;
  let mouseUV = u.zoom_config.yz;
  let mouseDown = step(0.5, u.zoom_config.w);

  let epsilon = mix(0.08, 0.25, u.zoom_params.x) * (1.0 - bass * 0.3);
  let Da = mix(0.8, 2.0, u.zoom_params.y);
  let Db = mix(0.2, 0.8, u.zoom_params.z);
  let feed = mix(0.01, 0.05, u.zoom_params.w);

  let resI = vec2<i32>(resolution);
  let lo = vec2<i32>(0);
  let hi = resI - vec2<i32>(1);

  // Exact loads: C is rgba32float history, never filtered.
  let c = textureLoad(dataTextureC, coord, 0);
  var a = c.r;
  var b = c.g;

  // Spiral seed, branchless: dead medium reseeds instead of branching.
  let needsSeed = (a + b) < 0.01;
  let cx = uv.x - 0.5;
  let cy = uv.y - 0.5;
  let ang = atan2(cy, cx);
  let spiral = sin(ang * 3.0 + length(vec2<f32>(cx, cy)) * 20.0);
  let seedA = 0.3 + spiral * 0.2 + hash12(uv * 100.0) * 0.1;
  let seedB = 0.2 - spiral * 0.1;
  a = select(a, seedA, needsSeed);
  b = select(b, seedB, needsSeed);

  let n = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, 1), lo, hi), 0);
  let s = textureLoad(dataTextureC, clamp(coord - vec2<i32>(0, 1), lo, hi), 0);
  let e = textureLoad(dataTextureC, clamp(coord + vec2<i32>(1, 0), lo, hi), 0);
  let w = textureLoad(dataTextureC, clamp(coord - vec2<i32>(1, 0), lo, hi), 0);

  let lapA = (n.r + s.r + e.r + w.r) * 0.25 - a;
  let lapB = (n.g + s.g + e.g + w.g) * 0.25 - b;

  // Idea 2 — pacemaker excitability gradient: a slow concentric gradient on
  // epsilon forms target-wave pacemaker zones where waves originate, the way
  // real BZ dishes are paced by heterogeneities.
  let paceR = length((uv - 0.5) * 2.0);
  let epsilonField = epsilon * (1.0 + 0.35 * cos(paceR * 5.0 - time * 0.4));

  var newA = a + epsilonField * (Da * lapA + a * (1.0 - a * a) - b + feed);
  var newB = b + epsilonField * (Db * lapB + (a - b) * 0.5);

  let mouseDist = length(uv - mouseUV);
  let seed = mouseDown * exp(-mouseDist * mouseDist * 800.0) * 0.5;
  newA = newA + seed;
  newB = newB + seed * 0.3;

  newA = clamp(newA, 0.0, 1.0);
  newB = clamp(newB, 0.0, 1.0);

  let waveFront = abs(newA - a) * 15.0;
  let oxidized = newA * 0.7 + newB * 0.3;

  let blue = vec3<f32>(0.05, 0.1, 0.5);
  let violet = vec3<f32>(0.4, 0.1, 0.6);
  let red = vec3<f32>(0.9, 0.1, 0.1);
  let orange = vec3<f32>(1.0, 0.5, 0.05);

  // ═══ CHUNK: branchless-color-ramp (from AGENTS.md) — replaces if/else branches ═══
  let t0 = smoothstep(0.0, 0.33, oxidized);
  let t1 = smoothstep(0.33, 0.66, oxidized);
  let t2 = smoothstep(0.66, 1.0, oxidized);
  var col = mix(blue, violet, t0);
  col = mix(col, red, t1);
  col = mix(col, orange, t2);

  col = col + vec3<f32>(1.0, 0.7, 0.4) * waveFront * waveFront * 0.5;

  // Idea 1 — refractory-tail shading: excitable media go refractory behind the
  // front. Where inhibitor is high but the front already passed, lay a dark
  // recovery band trailing the wave instead of flat color.
  let refractory = clamp(newB * 0.85 - waveFront * 0.12, 0.0, 1.0);
  col = mix(col, vec3<f32>(0.02, 0.03, 0.10), refractory * 0.55);

  let tipDist = length(uv - vec2<f32>(0.5 + 0.2 * cos(time * 0.3), 0.5 + 0.2 * sin(time * 0.4)));
  let spiralTip = 0.002 / (tipDist * tipDist + 0.001);
  col = col + vec3<f32>(0.3, 0.6, 1.0) * spiralTip * newA;

  var outCol = acesToneMapping(huePreserveClamp(col * 1.3, 2.0));
  outCol += (ign(vec2<f32>(coord)) - 0.5) / 255.0;

  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depth = mix(0.3, 1.0, inputDepth);

  var alpha = newA * waveFront * depth * 0.8 + newA * 0.2;
  alpha = clamp(alpha, 0.0, 0.95);

  var finalColor = mix(inputColor.rgb, outCol, alpha);
  let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
  finalColor = vec3<f32>(finalColor.r + caStr, finalColor.g, finalColor.b - caStr * 0.5);
  let finalAlpha = max(inputColor.a, alpha);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(newA * depth, 0.0, 0.0, 0.0));
  // Primary simulation state: activator(r), inhibitor(g), wavefront(b), alpha(a)
  textureStore(dataTextureA, coord, vec4<f32>(newA, newB, waveFront, alpha));
  // Detail channel: per-Laplacian for multi-scale read
  textureStore(dataTextureB, coord, vec4<f32>(lapA, lapB, oxidized, waveFront * waveFront));
}
