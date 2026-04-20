// ═══════════════════════════════════════════════════════════════════
//  Quasicrystal Iridescence
//  Category: advanced-hybrid
//  Features: generative, quasicrystal, thin-film-interference, spectral
//  Complexity: Very High
//  Chunks From: gen-quasicrystal.wgsl, spec-iridescence-engine.wgsl
//  Created: 2026-04-18
//  By: Agent CB-23 — Generative Abstract Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Penrose tiling-inspired patterns with 5-fold symmetry enhanced by
//  thin-film iridescence. Quasicrystal depth drives film thickness,
//  producing soap-bubble spectral colors across the aperiodic tiling.
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

// ═══ CHUNK: quasicrystal (from gen-quasicrystal.wgsl) ═══
fn quasicrystal(uv: vec2<f32>, n: i32, t: f32, angle: f32) -> f32 {
  var value = 0.0;
  let pi = 3.14159265359;
  for (var i: i32 = 0; i < n; i++) {
    let theta = angle + pi * 2.0 * f32(i) / f32(n);
    let k = vec2<f32>(cos(theta), sin(theta));
    value += cos(dot(uv, k) * 10.0 + t);
  }
  return value / f32(n);
}

fn rot2(a: f32) -> mat2x2<f32> {
  let s = sin(a);
  let c = cos(a);
  return mat2x2<f32>(c, -s, s, c);
}

// ═══ CHUNK: thin-film functions (from spec-iridescence-engine.wgsl) ═══
fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  let t = clamp((lambda - 380.0) / (700.0 - 380.0), 0.0, 1.0);
  let r = smoothstep(0.5, 0.85, t) + smoothstep(0.0, 0.2, t) * 0.2;
  let g = 1.0 - abs(t - 0.45) * 2.5;
  let b = 1.0 - smoothstep(0.0, 0.45, t);
  return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn thinFilmColor(thicknessNm: f32, cosTheta: f32, filmIOR: f32) -> vec3<f32> {
  let sinTheta_t = sqrt(max(1.0 - cosTheta * cosTheta, 0.0)) / filmIOR;
  let cosTheta_t = sqrt(max(1.0 - sinTheta_t * sinTheta_t, 0.0));
  let opd = 2.0 * filmIOR * thicknessNm * cosTheta_t;
  var color = vec3<f32>(0.0);
  var sampleCount = 0.0;
  for (var lambda = 380.0; lambda <= 700.0; lambda = lambda + 20.0) {
    let phase = opd / lambda;
    let interference = cos(phase * 6.28318530718) * 0.5 + 0.5;
    color += wavelengthToRGB(lambda) * interference;
    sampleCount = sampleCount + 1.0;
  }
  return color / max(sampleCount, 1.0);
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let t = u.config.x;
  let coord = vec2<i32>(global_id.xy);

  let symmetry = i32(mix(5.0, 13.0, u.zoom_params.x));
  let patternDensity = mix(3.0, 15.0, u.zoom_params.y);
  let colorCycle = u.zoom_params.z;
  let projAngle = mix(0.0, 6.28318, u.zoom_params.w);

  let aspect = resolution.x / resolution.y;
  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * patternDensity;
  p = rot2(t * 0.05 + projAngle) * p;

  let qc = quasicrystal(p, symmetry, t * 0.2, projAngle);
  let threshold = 0.2;
  let pattern = smoothstep(-threshold, threshold, qc);

  let qc2 = quasicrystal(p * 1.5 + 0.5, symmetry, t * 0.15, projAngle + 0.1);
  let pattern2 = smoothstep(-threshold * 0.5, threshold * 0.5, qc2);

  // ═══ IRIDESCENCE ENGINE ═══
  let filmThicknessBase = mix(200.0, 800.0, u.zoom_params.x);
  let filmIOR = mix(1.2, 2.4, u.zoom_params.y);
  let intensity = mix(0.3, 1.5, u.zoom_params.z);
  let turbulence = mix(0.0, 1.0, u.zoom_params.w);

  let toCenter = uv - vec2<f32>(0.5);
  let dist = length(toCenter);
  let cosTheta = sqrt(max(1.0 - dist * dist * 0.5, 0.01));

  let noiseVal = hash12(uv * 12.0 + t * 0.1) * 0.5 + hash12(uv * 25.0 - t * 0.15) * 0.25;

  // Quasicrystal pattern drives thickness variation
  let depth = pattern * 0.5 + pattern2 * 0.3;
  var thickness = filmThicknessBase * (0.7 + depth * 0.6 + noiseVal * turbulence);

  // Mouse interaction
  let mousePos = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w > 0.5;
  if (isMouseDown) {
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = exp(-mouseDist * mouseDist * 800.0);
    thickness += mouseInfluence * 300.0 * sin(t * 3.0 + mouseDist * 30.0);
  }

  let iridescent = thinFilmColor(thickness, cosTheta, filmIOR) * intensity;

  // Fresnel-like blend
  let fresnel = pow(1.0 - cosTheta, 3.0);

  // Metallic base from quasicrystal
  let m = fract(qc + qc2 + t * colorCycle * 0.05);
  let gold = vec3<f32>(1.0, 0.84, 0.0);
  let silver = vec3<f32>(0.75, 0.75, 0.75);
  let bronze = vec3<f32>(0.8, 0.5, 0.2);
  var baseCol = vec3<f32>(0.0);
  if (m < 0.33) { baseCol = mix(gold, silver, m * 3.0); }
  else if (m < 0.66) { baseCol = mix(silver, bronze, (m - 0.33) * 3.0); }
  else { baseCol = mix(bronze, gold, (m - 0.66) * 3.0); }

  // Highlight edges
  let edge = abs(qc);
  let edgeMask = smoothstep(0.05, 0.0, edge);
  baseCol = baseCol + vec3<f32>(1.0, 0.95, 0.8) * edgeMask * 0.4;

  // Blend quasicrystal with iridescence
  var outColor = mix(baseCol, iridescent, fresnel * 0.7);

  // Shimmer
  let shimmer = sin(p.x * 20.0 + t) * sin(p.y * 20.0 + t * 1.3);
  outColor = outColor + vec3<f32>(0.1) * shimmer * 0.05;

  // Tone map
  let tonemapped = outColor / (1.0 + outColor * 0.2);
  let vignette = 1.0 - length(uv - 0.5) * 0.5;
  let finalColor = tonemapped * vignette;

  textureStore(dataTextureA, coord, vec4<f32>(iridescent, thickness / 1000.0));
  textureStore(writeTexture, coord, vec4<f32>(finalColor, thickness / 1000.0));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
