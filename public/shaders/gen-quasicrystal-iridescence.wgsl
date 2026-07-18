// ═══════════════════════════════════════════════════════════════════
//  Quasicrystal Iridescence
//  Category: advanced-hybrid
//  Features: generative, quasicrystal, thin-film-interference, spectral,
//            audio-reactive, aces-tone-map, ign-dither
//  Complexity: Very High
//  Chunks From: gen-quasicrystal.wgsl, spec-iridescence-engine.wgsl
//  Created: 2026-07-17
//  By: Agent CB-23 — Generative Abstract Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Penrose tiling-inspired patterns with 5-fold symmetry enhanced by
//  thin-film iridescence. Quasicrystal depth drives film thickness,
//  producing soap-bubble spectral colors across the aperiodic tiling.
//  Audio: bass rotates/thickens the film, mids shift the color cycle,
//  treble adds metallic edge shimmer. Alpha encodes density+thickness.
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
  config: vec4<f32>,       // x=Time, y=delta_time, zw=resolution
  zoom_config: vec4<f32>,  // x=zoom, yz=mouse_uv, w=mouse_down
  zoom_params: vec4<f32>,  // xyzw = user params p1…p4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

fn quasicrystal(uv: vec2<f32>, n: i32, t: f32, angle: f32) -> f32 {
  var value = 0.0;
  for (var i: i32 = 0; i < n; i++) {
    let theta = angle + TAU * f32(i) / f32(n);
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
    let interference = cos(phase * TAU) * 0.5 + 0.5;
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let resolution = u.config.zw;
  if (f32(pixel.x) >= resolution.x || f32(pixel.y) >= resolution.y) { return; }
  let uv01 = vec2<f32>(pixel) / resolution;
  let t = u.config.x;
  let coord = pixel;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let symmetry = i32(mix(5.0, 13.0, u.zoom_params.x));
  let patternDensity = mix(3.0, 15.0, u.zoom_params.y);
  let colorCycleBase = u.zoom_params.z;
  let projAngleBase = mix(0.0, TAU, u.zoom_params.w);

  // Audio-driven projection angle and film thickness
  let projAngle = projAngleBase + t * (0.05 + bass * 0.15);
  let filmThicknessBase = mix(200.0, 800.0, u.zoom_params.x) * (1.0 + bass * 0.4);
  let colorCycle = colorCycleBase + mids * 0.5;

  let aspect = resolution.x / resolution.y;
  var p = (uv01 - 0.5) * vec2<f32>(aspect, 1.0) * patternDensity;
  p = rot2(t * 0.05 + projAngle) * p;

  let qc = quasicrystal(p, symmetry, t * 0.2, projAngle);
  let threshold = 0.2;
  let pattern = smoothstep(-threshold, threshold, qc);

  let qc2 = quasicrystal(p * 1.5 + 0.5, symmetry, t * 0.15, projAngle + 0.1);
  let pattern2 = smoothstep(-threshold * 0.5, threshold * 0.5, qc2);

  let filmIOR = mix(1.2, 2.4, u.zoom_params.y);
  let intensity = mix(0.3, 1.5, u.zoom_params.z);
  let turbulence = mix(0.0, 1.0, u.zoom_params.w);

  let toCenter = uv01 - vec2<f32>(0.5);
  let dist = length(toCenter);
  let cosTheta = sqrt(max(1.0 - dist * dist * 0.5, 0.01));

  let noiseVal = hash12(uv01 * 12.0 + t * 0.1) * 0.5 + hash12(uv01 * 25.0 - t * 0.15) * 0.25;

  let depth = pattern * 0.5 + pattern2 * 0.3;
  var thickness = filmThicknessBase * (0.7 + depth * 0.6 + noiseVal * turbulence);

  // Mouse interaction, extra reactive to bass
  let mousePos = u.zoom_config.yz;
  if (u.zoom_config.w > 0.5) {
    let mouseDist = length(uv01 - mousePos);
    let mouseInfluence = exp(-mouseDist * mouseDist * 800.0);
    thickness += mouseInfluence * 300.0 * (1.0 + bass) * sin(t * 3.0 + mouseDist * 30.0);
  }

  let iridescent = thinFilmColor(thickness, cosTheta, filmIOR) * intensity;
  let fresnel = pow(1.0 - cosTheta, 3.0);

  // Metallic base with mids-driven color cycle
  let m = fract(qc + qc2 + t * colorCycle * 0.05 + mids * 0.25);
  let gold = vec3<f32>(1.0, 0.84, 0.0);
  let silver = vec3<f32>(0.75, 0.75, 0.75);
  let bronze = vec3<f32>(0.8, 0.5, 0.2);
  var baseCol = vec3<f32>(0.0);
  if (m < 0.33) { baseCol = mix(gold, silver, m * 3.0); }
  else if (m < 0.66) { baseCol = mix(silver, bronze, (m - 0.33) * 3.0); }
  else { baseCol = mix(bronze, gold, (m - 0.66) * 3.0); }

  // Highlight edges and add treble shimmer
  let edge = abs(qc);
  let edgeMask = smoothstep(0.05, 0.0, edge);
  let sparkle = hash12(uv01 * 350.0 + t * 10.0) * edgeMask * treble * 0.8;
  baseCol = baseCol + vec3<f32>(1.0, 0.95, 0.8) * edgeMask * 0.4;
  baseCol = baseCol + vec3<f32>(sparkle);

  // Blend quasicrystal with iridescence, bass pushes iridescence dominance
  var outColor = mix(baseCol, iridescent, fresnel * 0.7 + bass * 0.15);

  // ACES tone map + IGN dither
  let exposure = 0.9 + mids * 0.2;
  var color = acesToneMap(outColor * exposure);
  let dither = (ign(vec2<f32>(pixel)) - 0.5) / 256.0;
  color = clamp(color + vec3<f32>(dither), vec3<f32>(0.0), vec3<f32>(1.0));

  let vignette = 1.0 - length(uv01 - 0.5) * 0.5;
  let finalColor = color * vignette;

  // Alpha encodes pattern density / film thickness
  let alpha = clamp(depth * 0.8 + thickness / 1200.0, 0.2, 0.95);

  textureStore(dataTextureA, coord, vec4<f32>(iridescent, alpha));
  textureStore(writeTexture, coord, vec4<f32>(finalColor * alpha, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}